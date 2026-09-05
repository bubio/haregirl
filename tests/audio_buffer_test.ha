use core;

fn test_audio_buffer() void = {
	let small = core::Bus { ... };
	let large = core::Bus { ... };
	core::apu_reset(&small.apu);
	core::bus_write(&small, 0xFF26, 0x80);
	core::bus_write(&small, 0xFF24, 0x77);
	core::bus_write(&small, 0xFF25, 0x22);
	core::bus_write(&small, 0xFF16, 0x80);
	core::bus_write(&small, 0xFF17, 0xF0);
	core::bus_write(&small, 0xFF18, 0xE0);
	core::bus_write(&small, 0xFF19, 0x87);
	large = small;
	// Cross many sample boundaries, without crossing a sequencer edge.
	for (let i = 0; i < 1024; i += 1) core::bus_tick(&small, 4);
	core::bus_tick(&large, 4096);
	const a = core::apu_samples(&small);
	const b = core::apu_samples(&large);
	check(len(a) > 0 && len(a) == len(b), "audio sample counts match across chunk sizes");
	for (let i = 0z; i < len(a); i += 1) {
		check(a[i] == b[i], "audio sample boundaries preserved");
	};
	core::apu_clear_samples(&small);
	check(len(core::apu_samples(&small)) == 0, "audio buffer cleared");
	core::bus_tick(&small, 4096);
	check(len(core::apu_samples(&small)) > 0, "audio buffer refilled");
	const owned = core::apu_take_samples(&small);
	check(len(core::apu_samples(&small)) == 0, "audio ownership transfer still clears buffer");
	free(owned);
	free(core::apu_take_samples(&large));
};
