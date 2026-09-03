use strings;

fn serial_write(bus: *Bus, addr: u16, value: u8) void = {
	switch (addr) {
	case 0xFF01 =>
		bus.io[0x01] = value;
	case 0xFF02 =>
		if ((value & 0x81) == 0x81) {
			let log = &bus.serial_log;
			append(log, bus.io[0x01])!;
			bus.io[0x02] = value & ~((1: u8) << 7);
			interrupt_request(bus, INT_SERIAL);
		} else {
			bus.io[0x02] = value;
		};
	case => void;
	};
};

export fn serial_get_log(bus: *Bus) str = {
	return strings::fromutf8(bus.serial_log)!;
};
