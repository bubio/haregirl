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

fn timer_advance_reload(bus: *Bus) void = {
	if (bus.timer_reload_pending <= 0) return;
	if (bus.timer_reload_pending == 1) {
		bus.timer_reload_pending = 0;
		bus.tima = bus.tma;
		bus.timer_reload_just_happened = true;
		interrupt_request(bus, INT_TIMER);
	} else {
		bus.timer_reload_pending -= 1;
	};
};

export fn timer_tick(bus: *Bus, cycles: int) void = {
	bus.timer_reload_just_happened = false;
	for (let i = 0; i < cycles; i += 1) {
		timer_advance_reload(bus);
		const old_signal = timer_signal(bus.div_counter, bus.tac);
		bus.div_counter += 1;
		const new_signal = timer_signal(bus.div_counter, bus.tac);
		if (old_signal && !new_signal) timer_increment_tima(bus);
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
