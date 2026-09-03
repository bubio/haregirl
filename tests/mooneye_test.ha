use fmt;
use os;
use core;

type rom_expectation = enum {
	Pass,
	Known_Limitation,
};

type rom_case = struct {
	name: str,
	path: str,
	expectation: rom_expectation,
	limitation: str,
};

const MOONEYE_TIMEOUT_CYCLES: u64 = 20971520;
const MOONEYE_TIMEOUT_STEPS: u64 = 2000000;

const mooneye_cases: [15]rom_case = [
	rom_case { name = "timer/div_write", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/div_write.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/rapid_toggle", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/rapid_toggle.gb", expectation = rom_expectation::Known_Limitation, limitation = "timer interrupt is recognized one loop late (BC reaches $FFD8 instead of the expected $FFD9)" },
	rom_case { name = "timer/tim00", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim00.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim00_div_trigger", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim00_div_trigger.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim01", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim01.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim01_div_trigger", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim01_div_trigger.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim10", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim10.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim10_div_trigger", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim10_div_trigger.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim11", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim11.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tim11_div_trigger", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tim11_div_trigger.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tima_reload", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tima_reload.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tima_write_reloading", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tima_write_reloading.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "timer/tma_write_reloading", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/timer/tma_write_reloading.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "interrupts/ie_push", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/interrupts/ie_push.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "serial/boot_sclk_align-dmgABCmgb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/acceptance/serial/boot_sclk_align-dmgABCmgb.gb", expectation = rom_expectation::Known_Limitation, limitation = "boot-aligned serial clock timing is not modeled yet, so SC=$81 completes immediately instead of on the post-boot clock phase" },
];

fn mooneye_result_name(result: core::Mooneye_Result) str = {
	switch (result) {
	case core::Mooneye_Result::None =>
		return "none";
	case core::Mooneye_Result::Pass =>
		return "pass";
	case core::Mooneye_Result::Fail =>
		return "fail";
	};
};

fn fail_mooneye_case(tc: rom_case, result: core::Rom_Run_Result) never = {
	const message = fmt::asprintf(
		"Mooneye ROM failed: {} status={} result={} steps={} cycles={} pc={:.4x} op={:.2x}",
		tc.name, rom_status_name(result.status),
		mooneye_result_name(result.mooneye_result),
		result.steps, result.cycles, result.last_pc, result.last_opcode,
	)!;
	fmt::fatal(message);
};

fn run_mooneye_case(tc: rom_case) (core::Rom_Run_Result | void) = {
	const rom = match (load_rom_file(tc.path)) {
	case let rom: []u8 =>
		yield rom;
	case =>
		return;
	};
	defer free(rom);

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&runner, rom, core::Gb_Mode::Dmg),
		"ROM runner accepted test ROM");
	const result = core::rom_runner_run(&runner, core::Rom_Run_Options {
		max_steps = MOONEYE_TIMEOUT_STEPS,
		max_cycles = MOONEYE_TIMEOUT_CYCLES,
		stop_on_mooneye = true,
		stop_on_blargg = false,
	});
	return result;
};

export fn test_rom_runner() void = {
	let pass_rom: [0x120]u8 = [0...];
	pass_rom[0x100] = 0x06; pass_rom[0x101] = 3;
	pass_rom[0x102] = 0x0E; pass_rom[0x103] = 5;
	pass_rom[0x104] = 0x16; pass_rom[0x105] = 8;
	pass_rom[0x106] = 0x1E; pass_rom[0x107] = 13;
	pass_rom[0x108] = 0x26; pass_rom[0x109] = 21;
	pass_rom[0x10A] = 0x2E; pass_rom[0x10B] = 34;
	pass_rom[0x10C] = 0x40;
	let pass_runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&pass_runner, pass_rom[..], core::Gb_Mode::Dmg),
		"ROM runner init pass ROM");
	const pass = core::rom_runner_run(&pass_runner, core::Rom_Run_Options {
		max_steps = 64,
		max_cycles = 4096,
		stop_on_mooneye = true,
		stop_on_blargg = false,
	});
	check(pass.status == core::Rom_Status::Passed,
		"ROM runner detects Mooneye pass breakpoint");
	check(pass.mooneye_result == core::Mooneye_Result::Pass,
		"ROM runner returns pass result");

	let fail_rom: [0x120]u8 = [0...];
	fail_rom[0x100] = 0x06; fail_rom[0x101] = 0x42;
	fail_rom[0x102] = 0x0E; fail_rom[0x103] = 0x42;
	fail_rom[0x104] = 0x16; fail_rom[0x105] = 0x42;
	fail_rom[0x106] = 0x1E; fail_rom[0x107] = 0x42;
	fail_rom[0x108] = 0x26; fail_rom[0x109] = 0x42;
	fail_rom[0x10A] = 0x2E; fail_rom[0x10B] = 0x42;
	fail_rom[0x10C] = 0x40;
	let fail_runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&fail_runner, fail_rom[..], core::Gb_Mode::Dmg),
		"ROM runner init fail ROM");
	const fail = core::rom_runner_run(&fail_runner, core::Rom_Run_Options {
		max_steps = 64,
		max_cycles = 4096,
		stop_on_mooneye = true,
		stop_on_blargg = false,
	});
	check(fail.status == core::Rom_Status::Failed,
		"ROM runner detects Mooneye fail breakpoint");
	check(fail.mooneye_result == core::Mooneye_Result::Fail,
		"ROM runner returns fail result");

	let serial_rom: [0x150]u8 = [0...];
	let pc = 0x100z;
	const serial_bytes: [6]u8 = [3, 5, 8, 13, 21, 34];
	for (let i = 0z; i < len(serial_bytes); i += 1) {
		serial_rom[pc] = 0x3E; pc += 1; serial_rom[pc] = serial_bytes[i]; pc += 1;
		serial_rom[pc] = 0xE0; pc += 1; serial_rom[pc] = 0x01; pc += 1;
		serial_rom[pc] = 0x3E; pc += 1; serial_rom[pc] = 0x81; pc += 1;
		serial_rom[pc] = 0xE0; pc += 1; serial_rom[pc] = 0x02; pc += 1;
	};
	serial_rom[pc] = 0x18; pc += 1; serial_rom[pc] = 0xFE;
	let serial_runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&serial_runner, serial_rom[..], core::Gb_Mode::Dmg),
		"ROM runner init serial ROM");
	const serial = core::rom_runner_run(&serial_runner, core::Rom_Run_Options {
		max_steps = 256,
		max_cycles = 16384,
		stop_on_mooneye = true,
		stop_on_blargg = false,
	});
	check(serial.status == core::Rom_Status::Passed,
		"ROM runner detects serial pass signature");
	check(serial.mooneye_result == core::Mooneye_Result::Pass,
		"ROM runner returns serial pass result");
};

export fn test_mooneye_roms() void = {
	let ran_any = false;
	let pass_count = 0;
	let limitation_count = 0;
	for (let i = 0z; i < len(mooneye_cases); i += 1) {
		const tc = mooneye_cases[i];
		const result = match (run_mooneye_case(tc)) {
		case let result: core::Rom_Run_Result =>
			yield result;
		case =>
			continue;
		};
		ran_any = true;
		switch (tc.expectation) {
		case rom_expectation::Pass =>
			if (result.status != core::Rom_Status::Passed
				|| result.mooneye_result != core::Mooneye_Result::Pass) {
				fail_mooneye_case(tc, result);
			};
			pass_count += 1;
		case rom_expectation::Known_Limitation =>
			if (result.status == core::Rom_Status::Passed
				&& result.mooneye_result == core::Mooneye_Result::Pass) {
				const message = fmt::asprintf(
					"Mooneye limitation resolved: {} now passes; remove its limitation note",
					tc.name,
				)!;
				fmt::fatal(message);
			};
			limitation_count += 1;
			fmt::printfln("Mooneye limitation: {} -> {} ({})", tc.name,
				rom_status_name(result.status), tc.limitation)!;
		};
	};
	if (!ran_any) {
		fmt::println("Mooneye ROMs skipped; run ./scripts/fetch-test-roms.sh to enable them")!;
	} else if (limitation_count == 0) {
		fmt::printfln("Mooneye ROMs passed: {}", pass_count)!;
	} else {
		fmt::printfln("Mooneye ROMs passed: {}, known limitations: {}",
			pass_count, limitation_count)!;
	};
};
