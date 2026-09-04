// SM83 address bus. Peripheral devices are intentionally represented by
// their backing stores until their respective phases are implemented.
export type Bus = struct {
	mode: Gb_Mode,
	rom: []u8,
	cart: Cartridge,
	vram: [8192]u8,
	wram: [8192]u8,
	oam: [160]u8,
	hram: [127]u8,
	io: [128]u8,
	ie: u8,
	cycles: u64,
	div_counter: u16,
	tima: u8,
	tma: u8,
	tac: u8,
	timer_reload_pending: int,
	timer_reload_just_happened: bool,
	serial_log: []u8,
	ppu: Ppu,
	apu: Apu,
};

export fn bus_load_rom(bus: *Bus, data: []u8) bool = {
	bus.rom = data;
	cartridge_init(bus);
	return len(data) != 0;
};

export fn bus_tick(bus: *Bus, cycles: int) void = {
	if (cycles > 0) {
		bus.cycles += cycles: u64;
		timer_tick(bus, cycles);
		ppu_tick(bus, cycles);
		apu_tick(bus, cycles);
	};
};

export fn bus_read(bus: *Bus, addr: u16) u8 = {
	const a = (addr: size);
	if (addr < 0x8000) {
		return cart_read(bus, addr);
	} else if (addr < 0xA000) {
		return bus.vram[a - 0x8000];
	} else if (addr < 0xC000) {
		return cart_ram_read(bus, addr);
	} else if (addr < 0xE000) {
		return bus.wram[a - 0xC000];
	} else if (addr < 0xFE00) {
		return bus.wram[a - 0xE000];
	} else if (addr < 0xFEA0) {
		return bus.oam[a - 0xFE00];
	} else if (addr < 0xFF00) {
		return 0xFF;
	} else if (addr < 0xFF80) {
		if ((addr >= 0xFF10 && addr <= 0xFF26) || (addr >= 0xFF30 && addr <= 0xFF3F)) {
			return apu_read(bus, addr);
		};
		switch (addr) {
		case 0xFF40 => return bus.ppu.lcdc;
		case 0xFF41 => return bus.ppu.stat | 0x80;
		case 0xFF42 => return bus.ppu.scy;
		case 0xFF43 => return bus.ppu.scx;
		case 0xFF44 => return bus.ppu.ly;
		case 0xFF45 => return bus.ppu.lyc;
		case 0xFF46 => return bus.io[0x46];
		case 0xFF47 => return bus.ppu.bgp;
		case 0xFF48 => return bus.ppu.obp0;
		case 0xFF49 => return bus.ppu.obp1;
		case 0xFF4A => return bus.ppu.wy;
		case 0xFF4B => return bus.ppu.wx;
		case 0xFF04 => return (bus.div_counter >> 8): u8;
		case 0xFF05 => return bus.tima;
		case 0xFF06 => return bus.tma;
		case 0xFF07 => return bus.tac | 0xF8;
		case 0xFF0F => return bus.io[0x0F] | 0xE0;
		case 0xFF01, 0xFF02 => return bus.io[a - 0xFF00];
		case 0xFF50 => return bus.io[0x50];
		case => return 0xFF;
		};
	} else if (addr < 0xFFFF) {
		return bus.hram[a - 0xFF80];
	} else {
		return bus.ie;
	};
};

export fn bus_write(bus: *Bus, addr: u16, value: u8) void = {
	const a = (addr: size);
	if (addr < 0x8000) {
		cart_write(bus, addr, value);
	} else if (addr < 0xA000) {
		bus.vram[a - 0x8000] = value;
	} else if (addr < 0xC000) {
		cart_ram_write(bus, addr, value);
	} else if (addr < 0xE000) {
		bus.wram[a - 0xC000] = value;
	} else if (addr < 0xFE00) {
		bus.wram[a - 0xE000] = value;
	} else if (addr < 0xFEA0) {
		bus.oam[a - 0xFE00] = value;
	} else if (addr < 0xFF00) {
		bus.cycles += 0;
	} else if (addr < 0xFF80) {
		if ((addr >= 0xFF10 && addr <= 0xFF26) || (addr >= 0xFF30 && addr <= 0xFF3F)) {
			apu_write(bus, addr, value);
			return;
		};
		switch (addr) {
		case 0xFF40 =>
			ppu_write_lcdc(bus, value);
		case 0xFF41 =>
			ppu_write_stat(bus, value);
		case 0xFF42 =>
			bus.ppu.scy = value;
		case 0xFF43 =>
			bus.ppu.scx = value;
		case 0xFF44 =>
			ppu_write_ly(bus, value);
		case 0xFF45 =>
			ppu_write_lyc(bus, value);
		case 0xFF46 =>
			oam_dma_start(bus, value);
		case 0xFF47 =>
			bus.ppu.bgp = value;
		case 0xFF48 =>
			bus.ppu.obp0 = value;
		case 0xFF49 =>
			bus.ppu.obp1 = value;
		case 0xFF4A =>
			bus.ppu.wy = value;
		case 0xFF4B =>
			bus.ppu.wx = value;
		case 0xFF04 =>
			timer_write_div(bus);
		case 0xFF05 =>
			timer_write_tima(bus, value);
		case 0xFF06 =>
			timer_write_tma(bus, value);
		case 0xFF07 =>
			timer_write_tac(bus, value);
		case 0xFF0F =>
			bus.io[0x0F] = value & 0x1F;
		case 0xFF01, 0xFF02 =>
			serial_write(bus, addr, value);
		case =>
			bus.io[a - 0xFF00] = value;
		};
	} else if (addr < 0xFFFF) {
		bus.hram[a - 0xFF80] = value;
	} else {
		bus.ie = value;
	};
};

export fn bus_cpu_read8(bus: *Bus, addr: u16) u8 = {
	bus_tick(bus, 4);
	return bus_read(bus, addr);
};

export fn bus_cpu_write8(bus: *Bus, addr: u16, value: u8) void = {
	bus_tick(bus, 4);
	bus_write(bus, addr, value);
};

// CPU accessors keep the CPU argument in the public API so future access
// restrictions can use CPU state without changing callers.
export fn cpu_read8(c: *Cpu, bus: *Bus, addr: u16) u8 = {
	return bus_cpu_read8(bus, addr);
};

export fn cpu_write8(c: *Cpu, bus: *Bus, addr: u16, value: u8) void = {
	bus_cpu_write8(bus, addr, value);
};
