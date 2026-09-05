use core;

fn test_rom_mapping_restore() void = {
	let rom = alloc([0u8...], 512 * 0x4000)!;
	defer free(rom);
	for (let bank = 0z; bank < 512; bank += 1) {
		rom[bank * 0x4000] = bank: u8;
		rom[bank * 0x4000 + 1] = (bank >> 8): u8;
	};
	const types: [_]u8 = [0x01, 0x05, 0x11, 0x19];
	const upper: [_]u16 = [65, 15, 127, 257];
	for (let i = 0z; i < len(types); i += 1) {
		rom[0x147] = types[i];
		rom[0x148] = 8;
		let b = core::Bus { ... };
		let c = core::Cpu { ... };
		core::bus_load_rom(&b, rom);
		defer free(b.cart.ram);
		core::bus_write(&b, 0x2100, upper[i]: u8);
		if (i == 0) {
			core::bus_write(&b, 0x4000, 2);
			core::bus_write(&b, 0x6000, 1);
		} else if (i == 3) core::bus_write(&b, 0x3000, 1);
		const saved = core::state_save(&b, &c);
		defer free(saved);
		core::bus_write(&b, 0x2100, 2);
		core::bus_write(&b, 0x3000, 0);
		core::bus_write(&b, 0x4000, 0);
		core::bus_write(&b, 0x6000, 0);
		check(core::state_load(&b, &c, saved), "restore ROM bank registers");
		check(core::bus_read(&b, 0x4000) == upper[i]: u8
			&& core::bus_read(&b, 0x4001) == (upper[i] >> 8): u8,
			"restored upper ROM mapping");
		check(core::bus_read(&b, 0) == (if (i == 0) 64u8 else 0u8),
			"restored lower ROM mapping");
		// Advertised banks beyond the actual file still read as open bus.
		b.rom = rom[..0x8000];
		check(core::bus_read(&b, 0x4000) == 0xFF, "truncated ROM remains bounds checked");
	};
};
