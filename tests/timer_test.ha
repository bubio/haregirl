use core;

// Independent, cycle-by-cycle oracle for the event-based timer. Keep this
// deliberately simple: exercise edges, wraparound, reloads and writes.
fn timer_reference(b: *core::Bus, cycles: int) void = {
	const bits: [4]u16 = [9, 3, 5, 7];
	const mask = 1u16 << bits[b.tac & 3];
	b.timer_reload_just_happened = false;
	for (let i = 0; i < cycles; i += 1) {
		if (b.timer_reload_pending > 0) {
			b.timer_reload_pending -= 1;
			if (b.timer_reload_pending == 0) {
				b.tima = b.tma;
				b.timer_reload_just_happened = true;
				b.io[0x0F] |= core::INT_TIMER;
			};
		};
		const old = b.div_counter;
		b.div_counter += 1;
		if ((b.tac & 4) != 0 && (old & mask) != 0
			&& (b.div_counter & mask) == 0 && b.timer_reload_pending == 0) {
			if (b.tima == 255) {
				b.tima = 0;
				b.timer_reload_pending = 4;
			} else b.tima += 1;
		};
	};
};

fn test_timer_batched() void = {
	let actual = core::Bus { ... };
	let expected = core::Bus { ... };
	let random = 12345u32;
	const spans: [_]int = [-1, 0, 1, 2, 3, 4, 8, 16, 255, 1024, 65536, 70224];
	for (let tac = 0u8; tac < 8; tac += 1) {
		for (let pending = 0; pending <= 4; pending += 1) {
			actual.tac = tac;
			actual.div_counter = 0xFFFD;
			actual.tima = 255;
			actual.tma = 254;
			actual.timer_reload_pending = pending;
			expected = actual;
			for (let i = 0z; i < 300; i += 1) {
				random = random * 1664525 + 1013904223;
				const cycles = spans[(random >> 16): size % len(spans)];
				core::timer_tick(&actual, cycles);
				timer_reference(&expected, cycles);
				check(actual.div_counter == expected.div_counter
					&& actual.tima == expected.tima
					&& actual.timer_reload_pending == expected.timer_reload_pending
					&& actual.timer_reload_just_happened == expected.timer_reload_just_happened
					&& actual.io[0x0F] == expected.io[0x0F], "batched timer matches cycle oracle");
				const addr = 0xFF04u16 + ((random >> 8): u16 & 3);
				core::bus_write(&actual, addr, random: u8);
				core::bus_write(&expected, addr, random: u8);
			};
		};
	};
};
