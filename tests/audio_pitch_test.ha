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
