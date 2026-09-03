fn interrupt_request(bus: *Bus, bit: u8) void = {
	bus.io[0x0F] |= bit;
};

fn interrupt_pending(bus: *Bus) u8 = {
	return bus.ie & bus.io[0x0F] & 0x1F;
};

fn interrupt_vector(bit: u8) u16 = {
	switch (bit) {
	case 0x01 => return 0x0040;
	case 0x02 => return 0x0048;
	case 0x04 => return 0x0050;
	case 0x08 => return 0x0058;
	case => return 0x0060;
	};
};

fn cpu_dispatch_interrupt(cpu: *Cpu, bus: *Bus) void = {
	bus_tick(bus, 4);
	bus_tick(bus, 4);
	cpu.ime = false;
	const pc = cpu.pc;
	cpu.sp -= 1;
	bus_cpu_write8(bus, cpu.sp, (pc >> 8): u8);
	let vector: u16 = 0;
	const mask = interrupt_pending(bus);
	const bits: [5]u8 = [INT_VBLANK, INT_STAT, INT_TIMER, INT_SERIAL, INT_JOYPAD];
	for (let i = 0; i < 5; i += 1) {
		const bit = bits[i];
		if ((mask & bit) != 0) {
			vector = interrupt_vector(bit);
			bus.io[0x0F] &= ~bit;
			break;
		};
	};
	cpu.sp -= 1;
	bus_cpu_write8(bus, cpu.sp, pc: u8);
	bus_tick(bus, 4);
	cpu.pc = vector;
};
