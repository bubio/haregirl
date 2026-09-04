use fmt;
use core;

const mbc_cases: [20]rom_case = [
	rom_case { name = "mbc1/bits_bank1", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/bits_bank1.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/bits_bank2", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/bits_bank2.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/bits_mode", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/bits_mode.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/bits_ramg", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/bits_ramg.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/ram_64kb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/ram_64kb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/ram_256kb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/ram_256kb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/rom_512kb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/rom_512kb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/rom_1Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/rom_1Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/rom_2Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/rom_2Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/rom_4Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/rom_4Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/rom_8Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/rom_8Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/rom_16Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/rom_16Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc1/multicart_rom_8Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc1/multicart_rom_8Mb.gb", expectation = rom_expectation::Known_Limitation, limitation = "MBC1M multicart addressing (4-bit bank1 with bank2 also gating the A14 line) is not modeled; only single-cart MBC1 addressing is implemented" },
	rom_case { name = "mbc2/bits_ramg", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/bits_ramg.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc2/bits_romb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/bits_romb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc2/bits_unused", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/bits_unused.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc2/ram", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/ram.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc2/rom_512kb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/rom_512kb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc2/rom_1Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/rom_1Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc2/rom_2Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc2/rom_2Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
];

const mbc5_cases: [8]rom_case = [
	rom_case { name = "mbc5/rom_512kb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_512kb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_1Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_1Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_2Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_2Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_4Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_4Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_8Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_8Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_16Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_16Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_32Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_32Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
	rom_case { name = "mbc5/rom_64Mb", path = "tests/roms/mooneye-test-suite/mts-20221022-1426-a2dac64/emulator-only/mbc5/rom_64Mb.gb", expectation = rom_expectation::Pass, limitation = "" },
];

// MBC ROMs (particularly bits_ramg/bits_bank1/bits_bank2, which sweep all
// 256 register write values) run noticeably longer than the timer/interrupt
// Mooneye ROMs, so this budget is larger than MOONEYE_TIMEOUT_STEPS.
const MBC_TIMEOUT_CYCLES: u64 = 83886080;
const MBC_TIMEOUT_STEPS: u64 = 8000000;

fn run_mbc_case(tc: rom_case) (core::Rom_Run_Result | void) = {
	const rom = match (load_rom_file(tc.path)) {
	case let rom: []u8 =>
		yield rom;
	case =>
		return;
	};
	defer free(rom);

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&runner, rom, core::Gb_Mode::Dmg),
		"ROM runner accepted MBC test ROM");
	const result = core::rom_runner_run(&runner, core::Rom_Run_Options {
		max_steps = MBC_TIMEOUT_STEPS,
		max_cycles = MBC_TIMEOUT_CYCLES,
		stop_on_mooneye = true,
		stop_on_blargg = false,
	});
	return result;
};

fn run_mbc_cases(cases: []rom_case) (int, int, bool) = {
	let ran_any = false;
	let pass_count = 0;
	let limitation_count = 0;
	for (let i = 0z; i < len(cases); i += 1) {
		const tc = cases[i];
		const result = match (run_mbc_case(tc)) {
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
					"MBC limitation resolved: {} now passes; remove its limitation note",
					tc.name,
				)!;
				fmt::fatal(message);
			};
			limitation_count += 1;
			fmt::printfln("MBC limitation: {} -> {} ({})", tc.name,
				rom_status_name(result.status), tc.limitation)!;
		};
	};
	return (pass_count, limitation_count, ran_any);
};

export fn test_mbc_roms() void = {
	const mbc1_mbc2 = run_mbc_cases(mbc_cases[..]);
	const mbc5 = run_mbc_cases(mbc5_cases[..]);
	const pass_count = mbc1_mbc2.0 + mbc5.0;
	const limitation_count = mbc1_mbc2.1 + mbc5.1;
	const ran_any = mbc1_mbc2.2 || mbc5.2;
	if (!ran_any) {
		fmt::println("MBC ROMs skipped; run ./scripts/fetch-test-roms.sh to enable them")!;
	} else if (limitation_count == 0) {
		fmt::printfln("MBC ROMs passed: {}", pass_count)!;
	} else {
		fmt::printfln("MBC ROMs passed: {}, known limitations: {}",
			pass_count, limitation_count)!;
	};
};

// test_cart_ram_save_restore exercises MBC5 battery-RAM persistence at the
// core level: write through the mapped 0xA000-0xBFFF window, snapshot the
// backing store via cart_ram_bytes (the API src/app will use to write a
// .sav file once ROM loading lands in phase 9), and confirm a fresh
// Bus/cartridge restores identical contents via cart_ram_load.
export fn test_cart_ram_save_restore() void = {
	let rom: [0x150]u8 = [0...];
	rom[0x147] = 0x1B; // MBC5+RAM+BATTERY
	rom[0x148] = 0x00; // 32KB ROM (2 banks)
	rom[0x149] = 0x03; // 32KB RAM (4 banks)

	let bus: core::Bus = core::Bus { ... };
	check(core::bus_load_rom(&bus, rom[..]), "cart ram test ROM loaded");
	check(core::cart_has_battery(&bus), "MBC5+RAM+BATTERY reports battery-backed");

	core::bus_write(&bus, 0x0000, 0x0A); // enable RAM
	core::bus_write(&bus, 0x4000, 0x02); // select RAM bank 2
	core::bus_write(&bus, 0xA123, 0x42);
	core::bus_write(&bus, 0x4000, 0x00); // back to RAM bank 0
	core::bus_write(&bus, 0xA000, 0x99);

	let saved: []u8 = alloc(core::cart_ram_bytes(&bus)...)!;
	defer free(saved);

	let restored: core::Bus = core::Bus { ... };
	check(core::bus_load_rom(&restored, rom[..]), "cart ram restore ROM loaded");
	core::cart_ram_load(&restored, saved);
	core::bus_write(&restored, 0x0000, 0x0A); // enable RAM
	core::bus_write(&restored, 0x4000, 0x02);
	check(core::bus_read(&restored, 0xA123) == 0x42,
		"restored save data visible in RAM bank 2");
	core::bus_write(&restored, 0x4000, 0x00);
	check(core::bus_read(&restored, 0xA000) == 0x99,
		"restored save data visible in RAM bank 0");
};
