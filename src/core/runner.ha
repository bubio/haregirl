const MOONEYE_PASS: [6]u8 = [3, 5, 8, 13, 21, 34];
const MOONEYE_FAIL: [6]u8 = [0x42, 0x42, 0x42, 0x42, 0x42, 0x42];

export type Mooneye_Result = enum {
	None,
	Pass,
	Fail,
};

export type Rom_Status = enum {
	Running,
	Passed,
	Failed,
	Timed_Out,
	Illegal_Opcode,
	Stopped,
};

export type Rom_Runner = struct {
	bus: Bus,
	cpu: Cpu,
	steps: u64,
	last_pc: u16,
	last_opcode: u8,
	breakpoints: u64,
};

export type Rom_Run_Options = struct {
	max_steps: u64,
	max_cycles: u64,
	stop_on_mooneye: bool,
};

export type Rom_Run_Result = struct {
	status: Rom_Status,
	mooneye_result: Mooneye_Result,
	steps: u64,
	cycles: u64,
	last_pc: u16,
	last_opcode: u8,
	breakpoints: u64,
};

fn mooneye_register_result(cpu: *Cpu) Mooneye_Result = {
	if (cpu.b == MOONEYE_PASS[0] && cpu.c == MOONEYE_PASS[1]
		&& cpu.d == MOONEYE_PASS[2] && cpu.e == MOONEYE_PASS[3]
		&& cpu.h == MOONEYE_PASS[4] && cpu.l == MOONEYE_PASS[5]) {
		return Mooneye_Result::Pass;
	};
	if (cpu.b == MOONEYE_FAIL[0] && cpu.c == MOONEYE_FAIL[1]
		&& cpu.d == MOONEYE_FAIL[2] && cpu.e == MOONEYE_FAIL[3]
		&& cpu.h == MOONEYE_FAIL[4] && cpu.l == MOONEYE_FAIL[5]) {
		return Mooneye_Result::Fail;
	};
	return Mooneye_Result::None;
};

fn mooneye_bytes_match(data: []u8, start: size, expect: []u8) bool = {
	for (let i = 0z; i < len(expect); i += 1) {
		if (data[start + i] != expect[i]) return false;
	};
	return true;
};

fn mooneye_serial_result(bus: *Bus) Mooneye_Result = {
	if (len(bus.serial_log) < len(MOONEYE_PASS)) return Mooneye_Result::None;
	for (let i = 0z; i + len(MOONEYE_PASS) <= len(bus.serial_log); i += 1) {
		if (mooneye_bytes_match(bus.serial_log, i, MOONEYE_PASS[..])) {
			return Mooneye_Result::Pass;
		};
		if (mooneye_bytes_match(bus.serial_log, i, MOONEYE_FAIL[..])) {
			return Mooneye_Result::Fail;
		};
	};
	return Mooneye_Result::None;
};

fn rom_result_status(result: Mooneye_Result) Rom_Status = {
	switch (result) {
	case Mooneye_Result::Pass =>
		return Rom_Status::Passed;
	case Mooneye_Result::Fail =>
		return Rom_Status::Failed;
	case =>
		return Rom_Status::Running;
	};
};

fn rom_runner_snapshot(
	runner: *Rom_Runner,
	status: Rom_Status,
	mooneye_result: Mooneye_Result,
) Rom_Run_Result = {
	return Rom_Run_Result {
		status = status,
		mooneye_result = mooneye_result,
		steps = runner.steps,
		cycles = runner.bus.cycles,
		last_pc = runner.last_pc,
		last_opcode = runner.last_opcode,
		breakpoints = runner.breakpoints,
	};
};

export fn rom_runner_init(runner: *Rom_Runner, rom: []u8, mode: Gb_Mode) bool = {
	runner.bus = Bus { mode = mode, ... };
	runner.cpu = Cpu { ... };
	runner.steps = 0;
	runner.last_pc = 0;
	runner.last_opcode = 0;
	runner.breakpoints = 0;
	const ok = bus_load_rom(&runner.bus, rom);
	cpu_reset(&runner.cpu, mode);
	return ok;
};

export fn rom_runner_step(runner: *Rom_Runner) int = {
	runner.last_pc = runner.cpu.pc;
	runner.last_opcode = bus_read(&runner.bus, runner.cpu.pc);
	const cycles = cpu_step(&runner.cpu, &runner.bus);
	runner.steps += 1;
	if (runner.last_opcode == 0x40 && runner.cpu.pc == runner.last_pc + 1) {
		runner.breakpoints += 1;
	};
	return cycles;
};

export fn rom_runner_run(
	runner: *Rom_Runner,
	options: Rom_Run_Options,
) Rom_Run_Result = {
	let max_steps = options.max_steps;
	if (max_steps == 0) max_steps = 1000000;
	let max_cycles = options.max_cycles;
	if (max_cycles == 0) max_cycles = CPU_HZ * 5;

	for (runner.steps < max_steps && runner.bus.cycles < max_cycles) {
		rom_runner_step(runner);
		if (options.stop_on_mooneye) {
			if (runner.last_opcode == 0x40) {
				const mooneye = mooneye_register_result(&runner.cpu);
				if (mooneye != Mooneye_Result::None) {
					return rom_runner_snapshot(runner,
						rom_result_status(mooneye), mooneye);
				};
			};
			const serial = mooneye_serial_result(&runner.bus);
			if (serial != Mooneye_Result::None) {
				return rom_runner_snapshot(runner,
					rom_result_status(serial), serial);
			};
		};
		if (runner.cpu.illegal_opcode) {
			return rom_runner_snapshot(runner,
				Rom_Status::Illegal_Opcode, Mooneye_Result::None);
		};
		if (runner.cpu.stopped) {
			return rom_runner_snapshot(runner,
				Rom_Status::Stopped, Mooneye_Result::None);
		};
	};
	return rom_runner_snapshot(runner, Rom_Status::Timed_Out,
		Mooneye_Result::None);
};
