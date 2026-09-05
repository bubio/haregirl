use core;
use fmt;
use os;

fn check(ok: bool, message: str) void = {
	if (!ok) fmt::fatal("core test failed: {}", message);
};

fn test_registers() void = {
	let c: core::Cpu = core::Cpu { ... };
	core::cpu_reset(&c, core::Gb_Mode::Dmg);
	check(core::cpu_af(&c) == 0x01B0, "DMG reset AF");
	check(core::cpu_bc(&c) == 0x0013, "DMG reset BC");
	core::cpu_set_af(&c, 0x12FF);
	check(core::cpu_af(&c) == 0x12F0, "AF low nibble mask");
	core::cpu_set_flags(&c, true, false, true, false);
	check(core::cpu_flag_z(&c) && core::cpu_flag_h(&c), "flag helpers");
};

fn test_bus() void = {
	let b: core::Bus = core::Bus { ... };
	core::bus_write(&b, 0xC123, 0x5A);
	check(core::bus_read(&b, 0xC123) == 0x5A, "WRAM read/write");
	check(core::bus_read(&b, 0xE123) == 0x5A, "echo read");
	core::bus_write(&b, 0xE124, 0xA5);
	check(core::bus_read(&b, 0xC124) == 0xA5, "echo write");
	core::bus_write(&b, 0xFF40, 0x91);
	check(core::bus_read(&b, 0xFF40) == 0x91, "LCDC latch readback");
	core::bus_tick(&b, 8);
	check(b.cycles == 8, "bus tick");
};

fn test_cpu_steps() void = {
	let rom: [0x104]u8 = [0...];
	rom[0x100] = 0x3E;
	rom[0x101] = 0x2A;
	rom[0x102] = 0x06;
	rom[0x103] = 0x10;
	let b: core::Bus = core::Bus { ... };
	core::bus_load_rom(&b, rom: []u8);
	let c: core::Cpu = core::Cpu { ... };
	core::cpu_reset(&c, core::Gb_Mode::Dmg);
	core::cpu_step(&c, &b);
	check(c.a == 0x2A && c.pc == 0x0102, "LD A,n");
	core::cpu_step(&c, &b);
	check(c.b == 0x10 && c.pc == 0x0104, "LD B,n");
};

fn test_stack_and_cb() void = {
	let b: core::Bus = core::Bus { ... };
	let c: core::Cpu = core::Cpu { ... };
	core::cpu_reset(&c, core::Gb_Mode::Dmg);
	c.sp = 0xFFFE;
	c.a = 0x80;
	c.pc = 0x0100;
	b.rom = alloc([0...], 0x102)!;
	defer free(b.rom);
	b.rom[0x100] = 0xCB;
	b.rom[0x101] = 0x07;
	core::cpu_step(&c, &b);
	check(c.a == 0x01 && core::cpu_flag_c(&c), "CB RLC A");
	c.pc = 0x0100;
	b.rom[0x100] = 0xC5;
	core::cpu_set_bc(&c, 0x1234);
	core::cpu_step(&c, &b);
	check(c.sp == 0xFFFC && core::bus_read(&b, 0xFFFC) == 0x34, "PUSH BC");
	b.rom[0x100] = 0xC1;
	c.pc = 0x0100;
	core::cpu_set_bc(&c, 0);
	core::cpu_step(&c, &b);
	check(core::cpu_bc(&c) == 0x1234 && c.sp == 0xFFFE, "POP BC");
};

fn test_timer() void = {
	let b: core::Bus = core::Bus { ... };
	core::bus_write(&b, 0xFF06, 0x42);
	core::bus_write(&b, 0xFF05, 0xFF);
	core::bus_write(&b, 0xFF07, 0x05); // enable, divider bit 3
	b.div_counter = 0x000F;
	core::bus_tick(&b, 1);
	check(core::bus_read(&b, 0xFF05) == 0, "TIMA overflow clears during reload delay");
	check(b.timer_reload_pending == 4, "TIMA reload delay starts at four cycles");
	core::bus_tick(&b, 4);
	check(core::bus_read(&b, 0xFF05) == 0x42, "TIMA reloads from TMA");
	check((core::bus_read(&b, 0xFF0F) & core::INT_TIMER) != 0, "timer interrupt requested");
	core::bus_write(&b, 0xFF04, 0xFF);
	check(core::bus_read(&b, 0xFF04) == 0, "DIV write resets divider");
};

fn test_interrupts() void = {
	let b: core::Bus = core::Bus { ... };
	let c: core::Cpu = core::Cpu { ... };
	core::cpu_reset(&c, core::Gb_Mode::Dmg);
	c.ime = true;
	c.pc = 0x0200;
	c.sp = 0xFFFE;
	core::bus_write(&b, 0xFFFF, core::INT_TIMER | core::INT_VBLANK);
	core::bus_write(&b, 0xFF0F, core::INT_TIMER | core::INT_VBLANK);
	check(core::cpu_step(&c, &b) == 20, "interrupt dispatch timing");
	check(c.pc == 0x0040 && !c.ime, "highest priority interrupt dispatch");
	check((core::bus_read(&b, 0xFF0F) & core::INT_VBLANK) == 0, "dispatched IF bit cleared");
	check((core::bus_read(&b, 0xFF0F) & core::INT_TIMER) != 0, "lower IF bit retained");
};

fn test_serial() void = {
	let b: core::Bus = core::Bus { ... };
	core::bus_write(&b, 0xFF01, 0x48);
	core::bus_write(&b, 0xFF02, 0x81);
	check(core::serial_get_log(&b) == "H", "serial byte captured");
	check((core::bus_read(&b, 0xFF02) & 0x80) == 0, "serial transfer bit cleared");
	check((core::bus_read(&b, 0xFF0F) & core::INT_SERIAL) != 0, "serial interrupt requested");
};

fn test_cgb_extensions() void = {
	let b: core::Bus = core::Bus { mode = core::Gb_Mode::Cgb, ... };

	// VRAM banking (FF4F/VBK): bank 0 and bank 1 are independent stores.
	core::bus_write(&b, 0xFF4F, 0x00);
	core::bus_write(&b, 0x8000, 0x11);
	core::bus_write(&b, 0xFF4F, 0x01);
	core::bus_write(&b, 0x8000, 0x22);
	check(core::bus_read(&b, 0x8000) == 0x22, "VRAM bank 1 write/read");
	core::bus_write(&b, 0xFF4F, 0x00);
	check(core::bus_read(&b, 0x8000) == 0x11, "VRAM bank 0 unaffected by bank 1 write");

	// WRAM banking (FF70/SVBK): bank 0 fixed at C000-CFFF, switchable bank
	// (1-7, 0 treated as 1) at D000-DFFF.
	core::bus_write(&b, 0xFF70, 0x02);
	core::bus_write(&b, 0xD000, 0xAA);
	core::bus_write(&b, 0xFF70, 0x03);
	core::bus_write(&b, 0xD000, 0xBB);
	check(core::bus_read(&b, 0xD000) == 0xBB, "WRAM bank 3 write/read");
	core::bus_write(&b, 0xFF70, 0x02);
	check(core::bus_read(&b, 0xD000) == 0xAA, "WRAM bank 2 unaffected by bank 3 write");
	check(core::bus_read(&b, 0xE000) == core::bus_read(&b, 0xC000), "echo mirrors bank 0");

	// CGB BG palette RAM (FF68/69) with auto-increment.
	core::bus_write(&b, 0xFF68, 0x80);
	core::bus_write(&b, 0xFF69, 0xFF);
	core::bus_write(&b, 0xFF69, 0x7F);
	check((core::bus_read(&b, 0xFF68) & 0x3F) == 0x02, "BCPS auto-increment");
	core::bus_write(&b, 0xFF68, 0x00);
	check(core::bus_read(&b, 0xFF69) == 0xFF, "BCPD readback low byte");

	// KEY1 (FF4D)/STOP: armed speed-switch flips double_speed and resumes
	// execution instead of halting the CPU like a normal STOP.
	let rom: [0x102]u8 = [0...];
	rom[0x100] = 0x10;
	rom[0x101] = 0x00;
	core::bus_load_rom(&b, rom: []u8);
	core::bus_write(&b, 0xFF4D, 0x01);
	let c: core::Cpu = core::Cpu { ... };
	core::cpu_reset(&c, core::Gb_Mode::Cgb);
	core::cpu_step(&c, &b);
	check(b.double_speed, "STOP with armed KEY1 enters double speed");
	check(!c.stopped, "STOP with armed KEY1 does not halt the CPU");
	check((core::bus_read(&b, 0xFF4D) & 0x01) == 0, "KEY1 armed bit cleared after switch");
};

fn test_save_state() void = {
	let rom: [0x150]u8 = [0...];
	rom[0x147] = 0x1B; // MBC5+RAM+BATTERY
	rom[0x148] = 0x00; // 32KB ROM (2 banks)
	rom[0x149] = 0x03; // 32KB RAM (4 banks)
	rom[0x100] = 0x00; // NOP at the reset vector

	let bus: core::Bus = core::Bus { ... };
	check(core::bus_load_rom(&bus, rom[..]), "save state test ROM loaded");
	let cpu: core::Cpu = core::Cpu { ... };
	core::cpu_reset(&cpu, core::Gb_Mode::Dmg);
	core::ppu_reset(&bus.ppu, core::Gb_Mode::Dmg);
	core::apu_reset(&bus.apu);

	// 状態を「初期値と違う」ことが分かるように変化させる。
	cpu.a = 0x42; cpu.pc = 0x1234; cpu.sp = 0xCAFE;
	core::bus_write(&bus, 0x0000, 0x0A); // RAM enable
	core::bus_write(&bus, 0x4000, 0x02); // RAM bank 2
	core::bus_write(&bus, 0xA100, 0x77);
	core::bus_write(&bus, 0xFF40, 0x91); // LCDC
	core::bus_write(&bus, 0xFF11, 0x80); // NR11 duty
	core::bus_tick(&bus, 12345);

	const snapshot = core::state_save(&bus, &cpu);
	defer free(snapshot);

	// スナップショット後にさらに状態を変えてから復元し、復元後の値が
	// スナップショット時点のものに戻ることを確認する。
	cpu.a = 0x00; cpu.pc = 0x0000;
	core::bus_write(&bus, 0xA100, 0x00);
	core::bus_tick(&bus, 999);

	let restored: core::Bus = core::Bus { ... };
	check(core::bus_load_rom(&restored, rom[..]), "save state restore ROM loaded");
	let restored_cpu: core::Cpu = core::Cpu { ... };
	check(core::state_load(&restored, &restored_cpu, snapshot),
		"state_load accepts a snapshot for the same ROM");

	check(restored_cpu.a == 0x42 && restored_cpu.pc == 0x1234
		&& restored_cpu.sp == 0xCAFE, "CPU registers restored");
	check(core::bus_read(&restored, 0xFF40) == 0x91, "PPU register restored");
	core::bus_write(&restored, 0x4000, 0x02);
	check(core::bus_read(&restored, 0xA100) == 0x77, "cartridge RAM restored");
	check(restored.cycles == bus.cycles - 999, "bus cycle count restored");

	// マジック/バージョンが壊れたデータや ROM 不一致は false を返し、
	// 復元先の状態を変更しない。
	let garbage: [8]u8 = [0...];
	let untouched: core::Bus = core::Bus { ... };
	let untouched_cpu: core::Cpu = core::Cpu { ... };
	check(!core::state_load(&untouched, &untouched_cpu, garbage[..]),
		"state_load rejects invalid data");
};

fn test_joypad() void = {
	let b: core::Bus = core::Bus { ... };
	core::bus_write(&b, 0xFF00, 0x10); // select buttons row (P15=0), dpad row deselected
	check((core::bus_read(&b, 0xFF00) & 0x0F) == 0x0F, "no buttons pressed reads all-1");
	core::joypad_set_buttons(&b, core::JOYPAD_A);
	check((core::bus_read(&b, 0xFF00) & 0x01) == 0, "A press pulls P10 low when buttons row selected");
	check((core::bus_read(&b, 0xFF0F) & core::INT_JOYPAD) != 0, "joypad interrupt requested on press");
	core::bus_write(&b, 0xFF0F, 0);
	core::bus_write(&b, 0xFF00, 0x20); // select dpad row instead
	check((core::bus_read(&b, 0xFF00) & 0x01) != 0, "buttons row no longer visible once deselected");
	core::joypad_set_dpad(&b, core::JOYPAD_DOWN);
	check((core::bus_read(&b, 0xFF00) & 0x08) == 0, "Down press pulls P13 low when dpad row selected");
};

export fn main() void = {
	test_registers();
	test_bus();
	test_cpu_steps();
	test_cpu_alu_exhaustive();
	test_cpu_conditions();
	test_stack_and_cb();
	test_timer();
	test_timer_batched();
	test_audio_buffer();
	test_audio_pitch();
	test_audio_antialias();
	test_noise_average();
	test_audio_spans();
	test_rom_mapping_restore();
	test_interrupts();
	test_serial();
	test_cgb_extensions();
	test_save_state();
	test_joypad();
	test_rom_runner();
	test_blargg_runner();
	test_blargg_roms();
	test_mooneye_roms();
	test_mbc_roms();
	test_cart_ram_save_restore();
	test_ppu_tile_runs();
	test_dmg_acid2();
	test_apu_roms();
	test_cgb_acid2();
	fmt::println("core tests passed")!;
	os::exit(0);
};
