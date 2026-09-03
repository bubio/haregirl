use fmt;
use core;

type blargg_case = struct {
	name: str,
	path: str,
};

const BLARGG_TIMEOUT_CYCLES: u64 = 120000000;
const BLARGG_TIMEOUT_STEPS: u64 = 30000000;

const blargg_cases: [12]blargg_case = [
	blargg_case { name = "cpu_instrs/individual/01-special", path = "tests/roms/blargg/cpu_instrs/individual/01-special.gb" },
	blargg_case { name = "cpu_instrs/individual/02-interrupts", path = "tests/roms/blargg/cpu_instrs/individual/02-interrupts.gb" },
	blargg_case { name = "cpu_instrs/individual/03-op sp,hl", path = "tests/roms/blargg/cpu_instrs/individual/03-op sp,hl.gb" },
	blargg_case { name = "cpu_instrs/individual/04-op r,imm", path = "tests/roms/blargg/cpu_instrs/individual/04-op r,imm.gb" },
	blargg_case { name = "cpu_instrs/individual/05-op rp", path = "tests/roms/blargg/cpu_instrs/individual/05-op rp.gb" },
	blargg_case { name = "cpu_instrs/individual/06-ld r,r", path = "tests/roms/blargg/cpu_instrs/individual/06-ld r,r.gb" },
	blargg_case { name = "cpu_instrs/individual/07-jr,jp,call,ret,rst", path = "tests/roms/blargg/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb" },
	blargg_case { name = "cpu_instrs/individual/08-misc instrs", path = "tests/roms/blargg/cpu_instrs/individual/08-misc instrs.gb" },
	blargg_case { name = "cpu_instrs/individual/09-op r,r", path = "tests/roms/blargg/cpu_instrs/individual/09-op r,r.gb" },
	blargg_case { name = "cpu_instrs/individual/10-bit ops", path = "tests/roms/blargg/cpu_instrs/individual/10-bit ops.gb" },
	blargg_case { name = "cpu_instrs/individual/11-op a,(hl)", path = "tests/roms/blargg/cpu_instrs/individual/11-op a,(hl).gb" },
	blargg_case { name = "instr_timing/instr_timing", path = "tests/roms/blargg/instr_timing/instr_timing.gb" },
];

fn blargg_result_name(result: core::Blargg_Result) str = {
	switch (result) {
	case core::Blargg_Result::None =>
		return "none";
	case core::Blargg_Result::Pass =>
		return "pass";
	case core::Blargg_Result::Fail =>
		return "fail";
	};
};

fn write_serial_program(rom: []u8, bytes: []u8) void = {
	let pc = 0x100z;
	for (let i = 0z; i < len(bytes); i += 1) {
		rom[pc] = 0x3E; pc += 1; rom[pc] = bytes[i]; pc += 1;
		rom[pc] = 0xE0; pc += 1; rom[pc] = 0x01; pc += 1;
		rom[pc] = 0x3E; pc += 1; rom[pc] = 0x81; pc += 1;
		rom[pc] = 0xE0; pc += 1; rom[pc] = 0x02; pc += 1;
	};
	rom[pc] = 0x18; pc += 1; rom[pc] = 0xFE;
};

fn fail_blargg_case(
	tc: blargg_case,
	result: core::Rom_Run_Result,
	serial_log: str,
) never = {
	const message = fmt::asprintf(
		"Blargg ROM failed: {} status={} result={} steps={} cycles={} pc={:.4x} op={:.2x}\n--- serial log ---\n{}\n------------------",
		tc.name, rom_status_name(result.status),
		blargg_result_name(result.blargg_result),
		result.steps, result.cycles, result.last_pc, result.last_opcode,
		serial_log,
	)!;
	fmt::fatal(message);
};

fn run_blargg_case(tc: blargg_case) bool = {
	const rom = match (load_rom_file(tc.path)) {
	case let rom: []u8 =>
		yield rom;
	case =>
		return false;
	};
	defer free(rom);

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&runner, rom, core::Gb_Mode::Dmg),
		"ROM runner accepted Blargg test ROM");
	const result = core::rom_runner_run(&runner, core::Rom_Run_Options {
		max_steps = BLARGG_TIMEOUT_STEPS,
		max_cycles = BLARGG_TIMEOUT_CYCLES,
		stop_on_mooneye = false,
		stop_on_blargg = true,
	});
	if (result.status != core::Rom_Status::Passed
		|| result.blargg_result != core::Blargg_Result::Pass) {
		fail_blargg_case(tc, result, core::serial_get_log(&runner.bus));
	};
	return true;
};

export fn test_blargg_runner() void = {
	let pass_rom: [0x180]u8 = [0...];
	write_serial_program(pass_rom[..], [0x50, 0x61, 0x73, 0x73, 0x65, 0x64]);
	let pass_runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&pass_runner, pass_rom[..], core::Gb_Mode::Dmg),
		"ROM runner init Blargg pass ROM");
	const pass = core::rom_runner_run(&pass_runner, core::Rom_Run_Options {
		max_steps = 256,
		max_cycles = 16384,
		stop_on_mooneye = false,
		stop_on_blargg = true,
	});
	check(pass.status == core::Rom_Status::Passed,
		"ROM runner detects Blargg pass signature");
	check(pass.blargg_result == core::Blargg_Result::Pass,
		"ROM runner returns Blargg pass result");

	let fail_rom: [0x180]u8 = [0...];
	write_serial_program(fail_rom[..], [0x46, 0x61, 0x69, 0x6C, 0x65, 0x64]);
	let fail_runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&fail_runner, fail_rom[..], core::Gb_Mode::Dmg),
		"ROM runner init Blargg fail ROM");
	const fail = core::rom_runner_run(&fail_runner, core::Rom_Run_Options {
		max_steps = 256,
		max_cycles = 16384,
		stop_on_mooneye = false,
		stop_on_blargg = true,
	});
	check(fail.status == core::Rom_Status::Failed,
		"ROM runner detects Blargg fail signature");
	check(fail.blargg_result == core::Blargg_Result::Fail,
		"ROM runner returns Blargg fail result");
};

export fn test_blargg_roms() void = {
	let ran_any = false;
	let pass_count = 0;
	for (let i = 0z; i < len(blargg_cases); i += 1) {
		if (!run_blargg_case(blargg_cases[i])) continue;
		ran_any = true;
		pass_count += 1;
	};
	if (!ran_any) {
		fmt::println("Blargg CPU ROMs skipped; run ./scripts/fetch-test-roms.sh to enable them")!;
	} else {
		fmt::printfln("Blargg CPU ROMs passed: {}", pass_count)!;
	};
};
