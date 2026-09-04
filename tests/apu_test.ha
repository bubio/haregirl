use fmt;
use core;

const apu_cases: [12]rom_case = [
	rom_case { name = "dmg_sound/01-registers", path = "tests/roms/blargg/dmg_sound/rom_singles/01-registers.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/02-len ctr", path = "tests/roms/blargg/dmg_sound/rom_singles/02-len ctr.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/03-trigger", path = "tests/roms/blargg/dmg_sound/rom_singles/03-trigger.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/04-sweep", path = "tests/roms/blargg/dmg_sound/rom_singles/04-sweep.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/05-sweep details", path = "tests/roms/blargg/dmg_sound/rom_singles/05-sweep details.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/06-overflow on trigger", path = "tests/roms/blargg/dmg_sound/rom_singles/06-overflow on trigger.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/07-len sweep period sync", path = "tests/roms/blargg/dmg_sound/rom_singles/07-len sweep period sync.gb", expectation = rom_expectation::Known_Limitation, limitation = "exact frame-sequencer phase alignment immediately after APU power-on/off is not modeled precisely enough to match the ROM's tight cycle-count expectations" },
	rom_case { name = "dmg_sound/08-len ctr during power", path = "tests/roms/blargg/dmg_sound/rom_singles/08-len ctr during power.gb", expectation = rom_expectation::Known_Limitation, limitation = "length-counter values read back through a CRC-checked report after a power-off/power-on cycle don't exactly match; the length-load write-through-while-off quirk is modeled but some other register is not fully ignored while powered off" },
	rom_case { name = "dmg_sound/09-wave read while on", path = "tests/roms/blargg/dmg_sound/rom_singles/09-wave read while on.gb", expectation = rom_expectation::Known_Limitation, limitation = "wave RAM access-while-playing quirk (reads must return the byte currently being played, exactly on the APU cycle it is fetched) is not modeled; wave RAM is treated as plain storage" },
	rom_case { name = "dmg_sound/10-wave trigger while on", path = "tests/roms/blargg/dmg_sound/rom_singles/10-wave trigger while on.gb", expectation = rom_expectation::Known_Limitation, limitation = "wave channel retrigger corruption quirk (the wave position/sample glitch that occurs when retriggering while already enabled) is not modeled" },
	rom_case { name = "dmg_sound/11-regs after power", path = "tests/roms/blargg/dmg_sound/rom_singles/11-regs after power.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "dmg_sound/12-wave write while on", path = "tests/roms/blargg/dmg_sound/rom_singles/12-wave write while on.gb", expectation = rom_expectation::Known_Limitation, limitation = "wave RAM access-while-playing quirk (writes while the channel is active must land on the byte currently being played) is not modeled" },
];

// dmg_sound ROMs run through many register sweeps and length/sweep timing
// sequences at 512Hz; give them the same generous budget as the MBC ROMs.
const APU_TIMEOUT_CYCLES: u64 = 83886080;
const APU_TIMEOUT_STEPS: u64 = 8000000;

// dmg_sound ROMs report pass/fail through cartridge RAM at $A000 rather than
// serial (see tests/roms/blargg/dmg_sound/readme.txt): $A000 holds $80 while
// running and the result code once done, and $A001-$A003 hold the signature
// $DE,$B0,$61 once that result is valid.
fn apu_rom_done(bus: *core::Bus) (u8 | void) = {
	if (core::bus_read(bus, 0xA001) != 0xDE
		|| core::bus_read(bus, 0xA002) != 0xB0
		|| core::bus_read(bus, 0xA003) != 0x61) {
		return;
	};
	const status = core::bus_read(bus, 0xA000);
	if (status == 0x80) return;
	return status;
};

fn run_apu_case(tc: rom_case) ((core::Rom_Run_Result, u8) | void) = {
	const rom = match (load_rom_file(tc.path)) {
	case let rom: []u8 =>
		yield rom;
	case =>
		return;
	};
	defer free(rom);

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&runner, rom, core::Gb_Mode::Dmg),
		"ROM runner accepted APU test ROM");

	const chunk = core::CYCLES_PER_FRAME;
	for (runner.bus.cycles < APU_TIMEOUT_CYCLES && runner.steps < APU_TIMEOUT_STEPS) {
		const result = core::rom_runner_run(&runner, core::Rom_Run_Options {
			max_steps = APU_TIMEOUT_STEPS,
			max_cycles = runner.bus.cycles + chunk,
			stop_on_mooneye = false,
			stop_on_blargg = false,
		});
		match (apu_rom_done(&runner.bus)) {
		case let status: u8 =>
			return (result, status);
		case void =>
			void;
		};
		if (result.status != core::Rom_Status::Timed_Out) {
			return (result, 0xFF);
		};
	};
	return (core::Rom_Run_Result {
		status = core::Rom_Status::Timed_Out,
		mooneye_result = core::Mooneye_Result::None,
		blargg_result = core::Blargg_Result::None,
		steps = runner.steps,
		cycles = runner.bus.cycles,
		last_pc = runner.last_pc,
		last_opcode = runner.last_opcode,
		breakpoints = runner.breakpoints,
	}, 0xFF);
};

export fn test_apu_roms() void = {
	let ran_any = false;
	let pass_count = 0;
	let limitation_count = 0;
	for (let i = 0z; i < len(apu_cases); i += 1) {
		const tc = apu_cases[i];
		const outcome = match (run_apu_case(tc)) {
		case let outcome: (core::Rom_Run_Result, u8) =>
			yield outcome;
		case void =>
			continue;
		};
		const result = outcome.0;
		const status_code = outcome.1;
		ran_any = true;
		const passed = status_code == 0;
		switch (tc.expectation) {
		case rom_expectation::Pass =>
			if (!passed) {
				const message = fmt::asprintf(
					"APU ROM failed: {} status={} result_code={:.2x} steps={} cycles={} pc={:.4x} op={:.2x}",
					tc.name, rom_status_name(result.status), status_code,
					result.steps, result.cycles, result.last_pc,
					result.last_opcode,
				)!;
				fmt::fatal(message);
			};
			pass_count += 1;
		case rom_expectation::Known_Limitation =>
			if (passed) {
				const message = fmt::asprintf(
					"APU ROM {} passed unexpectedly; remove its known-limitation entry ({})",
					tc.name, tc.limitation,
				)!;
				fmt::fatal(message);
			};
			fmt::printfln("APU limitation: {} -> not passed ({})", tc.name,
				tc.limitation)!;
			limitation_count += 1;
		};
	};
	if (!ran_any) {
		fmt::println("APU ROMs skipped; run ./scripts/fetch-test-roms.sh to enable them")!;
	} else {
		fmt::printfln("APU ROMs passed: {}, known limitations: {}", pass_count,
			limitation_count)!;
	};
};
