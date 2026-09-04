// SM83 address bus. Peripheral devices are intentionally represented by
// their backing stores until their respective phases are implemented.
export type Bus = struct {
	mode: Gb_Mode,
	rom: []u8,
	cart: Cartridge,
	vram: [2][8192]u8,
	vram_bank: u8,
	wram: [8][4096]u8,
	wram_bank: u8,
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
	// CGB double-speed (KEY1, FF4D).
	key1: u8,
	double_speed: bool,
	// CGB VRAM DMA (HDMA1-5, FF51-55). General-purpose transfers are copied
	// immediately; H-Blank transfers copy one 16-byte block per HBlank
	// entry. Neither stalls the CPU for the cycles real hardware would take
	// (known limitation, see phase 7 verification log).
	hdma_src: u16,
	hdma_dst: u16,
	hdma_active: bool,
	hdma_remaining: u8,
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
		// PPU dot timing runs at the fixed hardware rate; it is unaffected
		// by CGB double speed, so it only advances at half the CPU's
		// reported cycle count while double speed is active. The APU
		// derives its own real-rate dot count internally (see apu_tick).
		const dots = if (bus.double_speed) cycles / 2 else cycles;
		ppu_tick(bus, dots);
		apu_tick(bus, cycles);
	};
};

fn hdma_copy_block(bus: *Bus, length: u16) void = {
	for (let i: u16 = 0; i < length; i += 1) {
		const dst = 0x8000 + ((bus.hdma_dst + i) % 0x2000);
		bus_write(bus, dst, bus_read(bus, bus.hdma_src + i));
	};
	bus.hdma_src += length;
	bus.hdma_dst += length;
};

fn hdma_start(bus: *Bus, value: u8) void = {
	if (bus.hdma_active && (value & 0x80) == 0) {
		bus.hdma_active = false;
		return;
	};
	const blocks = (value & 0x7F) + 1;
	if ((value & 0x80) != 0) {
		bus.hdma_active = true;
		bus.hdma_remaining = blocks;
	} else {
		hdma_copy_block(bus, (blocks: u16) * 16);
		bus.hdma_active = false;
	};
};

// Called by the PPU when it enters HBlank; copies one 16-byte block for an
// active H-Blank-mode HDMA transfer.
export fn hdma_hblank_step(bus: *Bus) void = {
	if (bus.mode != Gb_Mode::Cgb || !bus.hdma_active) return;
	hdma_copy_block(bus, 16);
	bus.hdma_remaining -= 1;
	if (bus.hdma_remaining == 0) bus.hdma_active = false;
};

fn wram_bank_index(bus: *Bus) size = {
	let bank = bus.wram_bank & 0x07;
	if (bank == 0) bank = 1;
	return bank: size;
};

export fn vram_at(bus: *Bus, bank: u8, addr: u16) u8 = {
	return bus.vram[bank & 1][(addr: size) - 0x8000];
};

export fn bus_read(bus: *Bus, addr: u16) u8 = {
	const a = (addr: size);
	if (addr < 0x8000) {
		return cart_read(bus, addr);
	} else if (addr < 0xA000) {
		return bus.vram[bus.vram_bank & 1][a - 0x8000];
	} else if (addr < 0xC000) {
		return cart_ram_read(bus, addr);
	} else if (addr < 0xD000) {
		return bus.wram[0][a - 0xC000];
	} else if (addr < 0xE000) {
		return bus.wram[wram_bank_index(bus)][a - 0xD000];
	} else if (addr < 0xF000) {
		return bus.wram[0][a - 0xE000];
	} else if (addr < 0xFE00) {
		return bus.wram[wram_bank_index(bus)][a - 0xF000];
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
		case 0xFF4D =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			let v: u8 = 0x7E;
			if (bus.double_speed) v |= 0x80;
			if ((bus.key1 & 0x01) != 0) v |= 0x01;
			return v;
		case 0xFF4F =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			return (bus.vram_bank & 0x01) | 0xFE;
		case 0xFF55 =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			if (bus.hdma_active) return (bus.hdma_remaining - 1) & 0x7F;
			return 0xFF;
		case 0xFF68 =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			return bus.ppu.bgpi | 0x40;
		case 0xFF69 =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			return bus.ppu.cgb_bg_pal[bus.ppu.bgpi & 0x3F];
		case 0xFF6A =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			return bus.ppu.obpi | 0x40;
		case 0xFF6B =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			return bus.ppu.cgb_obj_pal[bus.ppu.obpi & 0x3F];
		case 0xFF70 =>
			if (bus.mode != Gb_Mode::Cgb) return 0xFF;
			return (bus.wram_bank & 0x07) | 0xF8;
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
		bus.vram[bus.vram_bank & 1][a - 0x8000] = value;
	} else if (addr < 0xC000) {
		cart_ram_write(bus, addr, value);
	} else if (addr < 0xD000) {
		bus.wram[0][a - 0xC000] = value;
	} else if (addr < 0xE000) {
		bus.wram[wram_bank_index(bus)][a - 0xD000] = value;
	} else if (addr < 0xF000) {
		bus.wram[0][a - 0xE000] = value;
	} else if (addr < 0xFE00) {
		bus.wram[wram_bank_index(bus)][a - 0xF000] = value;
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
		case 0xFF4D =>
			if (bus.mode == Gb_Mode::Cgb) bus.key1 = (bus.key1 & 0xFE) | (value & 0x01);
		case 0xFF4F =>
			if (bus.mode == Gb_Mode::Cgb) bus.vram_bank = value & 0x01;
		case 0xFF51 =>
			if (bus.mode == Gb_Mode::Cgb) bus.hdma_src = (bus.hdma_src & 0x00FF) | ((value: u16) << 8);
		case 0xFF52 =>
			if (bus.mode == Gb_Mode::Cgb) bus.hdma_src = (bus.hdma_src & 0xFF00) | ((value & 0xF0): u16);
		case 0xFF53 =>
			if (bus.mode == Gb_Mode::Cgb) bus.hdma_dst = (bus.hdma_dst & 0x00FF) | (((value & 0x1F): u16) << 8);
		case 0xFF54 =>
			if (bus.mode == Gb_Mode::Cgb) bus.hdma_dst = (bus.hdma_dst & 0xFF00) | ((value & 0xF0): u16);
		case 0xFF55 =>
			if (bus.mode == Gb_Mode::Cgb) hdma_start(bus, value);
		case 0xFF68 =>
			if (bus.mode == Gb_Mode::Cgb) bus.ppu.bgpi = value & 0xBF;
		case 0xFF69 =>
			if (bus.mode == Gb_Mode::Cgb) {
				bus.ppu.cgb_bg_pal[bus.ppu.bgpi & 0x3F] = value;
				if ((bus.ppu.bgpi & 0x80) != 0) {
					bus.ppu.bgpi = (bus.ppu.bgpi & 0x80) | ((bus.ppu.bgpi + 1) & 0x3F);
				};
			};
		case 0xFF6A =>
			if (bus.mode == Gb_Mode::Cgb) bus.ppu.obpi = value & 0xBF;
		case 0xFF6B =>
			if (bus.mode == Gb_Mode::Cgb) {
				bus.ppu.cgb_obj_pal[bus.ppu.obpi & 0x3F] = value;
				if ((bus.ppu.obpi & 0x80) != 0) {
					bus.ppu.obpi = (bus.ppu.obpi & 0x80) | ((bus.ppu.obpi + 1) & 0x3F);
				};
			};
		case 0xFF70 =>
			if (bus.mode == Gb_Mode::Cgb) bus.wram_bank = value & 0x07;
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
