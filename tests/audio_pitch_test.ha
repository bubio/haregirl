use core;

fn test_noise_average() void = {
	let b = core::Bus { ... };
	core::apu_reset(&b.apu);
	core::bus_write(&b, 0xFF26, 0x80);
	core::bus_write(&b, 0xFF24, 0x77);
	core::bus_write(&b, 0xFF25, 0x88);
	core::bus_write(&b, 0xFF21, 0xF0);
	core::bus_write(&b, 0xFF22, 0x08); // fastest 7-bit noise
	core::bus_write(&b, 0xFF23, 0x80);
	for (let i = 0; i < 4096; i += 4) core::bus_tick(&b, 4);
	const samples = core::apu_take_samples(&b);
	defer free(samples);
	// Independent per-dot reference, including integration BEFORE the edge.
	let lfsr = 0x7FFFu16;
	let timer = 8;
	let area = 0i64;
	let count = 0i64;
	let acc = 0u64;
	let index = 0z;
	for (let dot = 0; dot < 4096; dot += 1) {
		area += if ((lfsr & 1) == 0) 15 else -15;
		count += 1;
		timer -= 1;
		if (timer == 0) {
			timer = 8;
			const bit = (lfsr & 1) ^ ((lfsr >> 1) & 1);
			lfsr = (lfsr >> 1) | (bit << 14);
			lfsr = (lfsr & ~0x40u16) | (bit << 6);
		};
		acc += core::SAMPLE_RATE;
		if (acc >= core::CPU_HZ) {
			acc -= core::CPU_HZ;
			const expected = ((area * 64 / count) * 8): i16;
			check(samples[index] == expected && samples[index + 1] == expected,
				"noise integration matches per-dot reference");
			index += 2;
			area = 0;
			count = 0;
		};
	};
	check(index == len(samples), "noise reference sample count");
};

fn test_audio_antialias() void = {
	let b = core::Bus { ... };
	core::apu_reset(&b.apu);
	core::bus_write(&b, 0xFF26, 0x80);
	core::bus_write(&b, 0xFF24, 0x77);
	core::bus_write(&b, 0xFF25, 0x44);
	for (let i = 0u16; i < 16; i += 1) {
		core::bus_write(&b, 0xFF30 + i, if (i < 8) 0xFF else 0);
	};
	core::bus_write(&b, 0xFF1A, 0x80);
	core::bus_write(&b, 0xFF1C, 0x20);
	core::bus_write(&b, 0xFF1D, 0xFF);
	core::bus_write(&b, 0xFF1E, 0x87); // 65536 Hz: must not alias into an audible tone
	for (let i = 0; i < 4096; i += 4) core::bus_tick(&b, 4);
	const samples = core::apu_take_samples(&b);
	defer free(samples);
	check(len(samples) > 0, "ultrasonic wave generated PCM");
	for (let i = 0z; i < len(samples); i += 1) {
		check(samples[i] == 0, "ultrasonic balanced wave cannot fold into a low tone");
	};
	// A partially accumulated sample must survive state save/load exactly.
	let rom: [0x150]u8 = [0...];
	core::bus_load_rom(&b, rom[..]);
	core::bus_write(&b, 0xFF1D, 0x80);
	core::bus_tick(&b, 12);
	let c = core::Cpu { ... };
	const saved = core::state_save(&b, &c);
	defer free(saved);
	let restored = core::Bus { ... };
	core::bus_load_rom(&restored, rom[..]);
	check(core::state_load(&restored, &c, saved), "load partial audio sample");
	core::apu_clear_samples(&b);
	for (let i = 0; i < 4096; i += 4) {
		core::bus_tick(&b, 4);
		core::bus_tick(&restored, 4);
	};
	const a = core::apu_take_samples(&b);
	const r = core::apu_take_samples(&restored);
	defer free(a);
	defer free(r);
	check(len(a) == len(r), "restored filtered PCM length");
	for (let i = 0z; i < len(a); i += 1) check(a[i] == r[i], "restored filtered PCM samples");
	// Version 1 has the same prefix and no filter accumulator suffix.
	saved[4] = 1;
	check(core::state_load(&restored, &c, saved[..len(saved) - 24]), "version 1 states remain readable");
};

// Measure output pitch rather than just checking frequency registers. The
// same tone must have the same number of periods per PCM second in CGB
// normal and double speed, for both pulse channels and the wave channel.
fn test_audio_pitch() void = {
	for (let channel = 1; channel <= 3; channel += 1) {
		for (let speed = 0; speed < 2; speed += 1) {
			let b = core::Bus { mode = core::Gb_Mode::Cgb, ... };
			b.double_speed = speed != 0;
			core::apu_reset(&b.apu);
			core::bus_write(&b, 0xFF26, 0x80);
			core::bus_write(&b, 0xFF24, 0x77);
			core::bus_write(&b, 0xFF25, 0x11u8 << ((channel - 1): u8));
			if (channel < 3) {
				const base = if (channel == 1) 0xFF11u16 else 0xFF16u16;
				core::bus_write(&b, base, 0x80);
				core::bus_write(&b, base + 1, 0xF0);
				core::bus_write(&b, base + 2, 0);
				core::bus_write(&b, base + 3, 0x87); // 131072 / 256 = 512 Hz
			} else {
				for (let i = 0u16; i < 16; i += 1) {
					core::bus_write(&b, 0xFF30 + i, if (i < 8) 0xFF else 0);
				};
				core::bus_write(&b, 0xFF1A, 0x80);
				core::bus_write(&b, 0xFF1C, 0x20);
				core::bus_write(&b, 0xFF1D, 0x80);
				core::bus_write(&b, 0xFF1E, 0x87); // 65536 / 128 = 512 Hz
			};
			const ticks = (core::CPU_HZ / 4): int;
			for (let i = 0; i < ticks; i += 1) {
				core::bus_tick(&b, if (speed == 0) 4 else 8);
			};
			const samples = core::apu_take_samples(&b);
			defer free(samples);
			check(len(samples) == (core::SAMPLE_RATE: size) * 2, "one PCM second at either CPU speed");
			let rising = 0;
			for (let i = 2z; i < len(samples); i += 2) {
				if (samples[i - 2] <= 0 && samples[i] > 0) rising += 1;
			};
			check(rising >= 511 && rising <= 512, "pulse/wave output pitch is 512 Hz, not one octave lower");
		};
	};
};

// Compare bus-sized and long spans against one-dot stepping. Cover timer
// edges, all noise settings (including existing u16 overflow behavior),
// muted wave output, and periods on both sides of the sample boundary.
fn test_audio_spans() void = {
	const frequencies: [8]u16 = [0, 1024, 1920, 2000, 2044, 2045, 2046, 2047];
	for (let setting = 0u16; setting < 512; setting += 1) {
		let bulk = core::Bus { ... };
		const a = &bulk.apu;
		a.enabled = true;
		a.nr50 = 0x77;
		a.nr51 = 0xFF;
		a.ch1_enabled = true; a.ch1_dac_enabled = true;
		a.ch2_enabled = true; a.ch2_dac_enabled = true;
		a.ch3_enabled = true; a.ch3_dac_enabled = true;
		a.ch4_enabled = true; a.ch4_dac_enabled = true;
		a.ch1_volume = 9; a.ch2_volume = 7; a.ch4_volume = 15;
		a.ch1_duty = 2; a.ch2_duty = 1;
		a.ch1_freq = frequencies[setting & 7];
		a.ch2_freq = frequencies[(setting >> 3) & 7];
		a.ch3_freq = frequencies[setting & 7];
		a.ch3_volume_code = ((setting >> 3) & 3): u8;
		a.ch4_divisor_code = (setting & 7): u8;
		a.ch4_clock_shift = ((setting >> 3) & 15): u8;
		a.ch4_width_mode = (setting & 128) != 0;
		a.ch4_lfsr = 0x7FFF;
		const initial: u16 = if ((setting & 256) == 0) 0 else 17;
		a.ch1_timer = initial; a.ch2_timer = initial;
		a.ch3_timer = initial; a.ch4_timer = initial;
		for (let i = 0z; i < 16; i += 1) a.wave_ram[i] = (i * 37): u8;
		let single = bulk;
		let elapsed_dots = 0;
		for (elapsed_dots < 4096) {
			let span = if ((setting & 1) == 0) 4 else 257;
			if (span > 4096 - elapsed_dots) span = 4096 - elapsed_dots;
			bulk.div_counter += span: u16;
			core::apu_tick(&bulk, span);
			for (let i = 0; i < span; i += 1) {
				single.div_counter += 1;
				core::apu_tick(&single, 1);
			};
			elapsed_dots += span;
		};
		const b = &single.apu;
		check(a.ch1_timer == b.ch1_timer && a.ch1_duty_pos == b.ch1_duty_pos,
			"pulse 1 span preserves timer and phase");
		check(a.ch2_timer == b.ch2_timer && a.ch2_duty_pos == b.ch2_duty_pos,
			"pulse 2 span preserves timer and phase");
		check(a.ch3_timer == b.ch3_timer && a.ch3_pos == b.ch3_pos,
			"wave span preserves timer and phase");
		check(a.ch4_timer == b.ch4_timer && a.ch4_lfsr == b.ch4_lfsr,
			"noise span preserves timer and LFSR");
		check(a.wave_area == b.wave_area && a.noise_area == b.noise_area,
			"span preserves unfinished sample integrals");
		check(len(a.samples) == len(b.samples), "span preserves sample count");
		for (let i = 0z; i < len(a.samples); i += 1) {
			check(a.samples[i] == b.samples[i], "span PCM matches one-dot stepping");
		};
		free(a.samples);
		free(b.samples);
	};
};
