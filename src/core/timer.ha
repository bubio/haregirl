fn timer_selected_bit(tac: u8) int = {
	switch (tac & 0x03) {
	case 0 => return 9;
	case 1 => return 3;
	case 2 => return 5;
	case => return 7;
	};
};

fn timer_signal(divider: u16, tac: u8) bool = {
	if ((tac & 0x04) == 0) return false;
	return divider & ((1: u16) << (timer_selected_bit(tac): u16)) != 0;
};

fn timer_increment_tima(bus: *Bus) void = {
	if (bus.timer_reload_pending > 0) return;
	if (bus.tima == 0xFF) {
		bus.tima = 0;
		bus.timer_reload_pending = 4;
	} else {
		bus.tima += 1;
	};
};

export fn timer_tick(bus: *Bus, cycles: int) void = {
	bus.timer_reload_just_happened = false;
	if (cycles <= 0) return;
	const enabled = (bus.tac & 0x04) != 0;
	const period = 1 << (timer_selected_bit(bus.tac) + 1);
	// Bus accesses usually cannot reach an edge. Skip the event loop when
	// neither TIMA nor its reload state can change in this interval.
	if (bus.timer_reload_pending == 0 && (!enabled
		|| cycles < period - ((bus.div_counter: int) & (period - 1)))) {
		bus.div_counter += cycles: u16;
		return;
	};
	let remaining = cycles;
	for (remaining > 0) {
		// Only falling DIV edges and delayed reloads can change TIMA.
		// Preserve reload-before-edge ordering, including DIV wrapping.
		const edge = if (enabled)
			period - ((bus.div_counter: int) & (period - 1)) else 0;
		let step = remaining;
		if (enabled && edge < step) step = edge;
		if (bus.timer_reload_pending > 0 && bus.timer_reload_pending < step) {
			step = bus.timer_reload_pending;
		};
		if (bus.timer_reload_pending > 0) {
			bus.timer_reload_pending -= step;
			if (bus.timer_reload_pending == 0) {
				bus.tima = bus.tma;
				bus.timer_reload_just_happened = true;
				interrupt_request(bus, INT_TIMER);
			};
		};
		bus.div_counter += step: u16;
		if (enabled && step == edge) timer_increment_tima(bus);
		remaining -= step;
	};
};

fn timer_write_div(bus: *Bus) void = {
	const old_signal = timer_signal(bus.div_counter, bus.tac);
	bus.div_counter = 0;
	if (old_signal) timer_increment_tima(bus);
};

fn timer_write_tima(bus: *Bus, value: u8) void = {
	if (bus.timer_reload_just_happened) return;
	bus.timer_reload_pending = 0;
	bus.tima = value;
};

fn timer_write_tma(bus: *Bus, value: u8) void = {
	bus.tma = value;
	if (bus.timer_reload_just_happened) bus.tima = value;
};

fn timer_write_tac(bus: *Bus, value: u8) void = {
	const old_signal = timer_signal(bus.div_counter, bus.tac);
	bus.tac = value & 0x07;
	const new_signal = timer_signal(bus.div_counter, bus.tac);
	if (old_signal && !new_signal) timer_increment_tima(bus);
};
