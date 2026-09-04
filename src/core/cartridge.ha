// Game Boy cartridge: header parsing and Memory Bank Controller (MBC)
// emulation for the ROM (0x0000-0x7FFF) and external RAM (0xA000-0xBFFF)
// address windows. MBC3's real-time clock registers are modeled as static
// storage only (no wall-clock ticking); see docs/dev/PLAN.md フェーズ5 for
// the rationale.

export type Mbc_Type = enum {
	None,
	Mbc1,
	Mbc2,
	Mbc3,
	Mbc5,
};

export type Cartridge = struct {
	mbc: Mbc_Type,
	battery: bool,
	rom_bank_count: int,
	ram_bank_count: int,
	ram: []u8,
	ram_enabled: bool,
	rom_lo: u8,
	rom_hi: u8,
	ram_sel: u8,
	mode: u8,
	rtc: [5]u8,
	latch_prev: u8,
};

fn cart_type_info(code: u8) (Mbc_Type, bool) = {
	switch (code) {
	case 0x00, 0x08, 0x09 =>
		return (Mbc_Type::None, false);
	case 0x01, 0x02 =>
		return (Mbc_Type::Mbc1, false);
	case 0x03 =>
		return (Mbc_Type::Mbc1, true);
	case 0x05 =>
		return (Mbc_Type::Mbc2, false);
	case 0x06 =>
		return (Mbc_Type::Mbc2, true);
	case 0x0F, 0x10, 0x13 =>
		return (Mbc_Type::Mbc3, true);
	case 0x11, 0x12 =>
		return (Mbc_Type::Mbc3, false);
	case 0x1B, 0x1E =>
		return (Mbc_Type::Mbc5, true);
	case 0x19, 0x1A, 0x1C, 0x1D =>
		return (Mbc_Type::Mbc5, false);
	case =>
		return (Mbc_Type::None, false);
	};
};

fn cart_rom_bank_count(code: u8) int = {
	if (code > 8) return 2;
	return 2 << (code: int);
};

fn cart_ram_size(code: u8) size = {
	switch (code) {
	case 0x02 => return 8 * 1024;
	case 0x03 => return 32 * 1024;
	case 0x04 => return 128 * 1024;
	case 0x05 => return 64 * 1024;
	case => return 0;
	};
};

export fn cartridge_init(bus: *Bus) void = {
	bus.cart = Cartridge { ... };
	bus.cart.rom_lo = 1;
	if (len(bus.rom) < 0x150) {
		bus.cart.rom_bank_count = 2;
		return;
	};

	const type_code = bus.rom[0x147];
	const rom_code = bus.rom[0x148];
	const ram_code = bus.rom[0x149];
	const info = cart_type_info(type_code);
	bus.cart.mbc = info.0;
	bus.cart.battery = info.1;
	bus.cart.rom_bank_count = cart_rom_bank_count(rom_code);
	if (bus.cart.rom_bank_count < 1) bus.cart.rom_bank_count = 1;

	if (bus.cart.mbc == Mbc_Type::Mbc2) {
		bus.cart.ram = alloc([0...], 512)!;
		bus.cart.ram_bank_count = 1;
	} else {
		const ram_bytes = cart_ram_size(ram_code);
		if (ram_bytes > 0) {
			bus.cart.ram = alloc([0...], ram_bytes)!;
			bus.cart.ram_bank_count = (ram_bytes / 0x2000): int;
		};
	};
};

export fn cart_has_battery(bus: *Bus) bool = bus.cart.battery;

// cart_ram_bytes exposes the backing store for battery-backed saves; the
// caller (src/app, once ROM loading lands) owns persisting it to disk.
export fn cart_ram_bytes(bus: *Bus) []u8 = bus.cart.ram;

export fn cart_ram_load(bus: *Bus, data: []u8) void = {
	const n = if (len(data) < len(bus.cart.ram)) len(data) else len(bus.cart.ram);
	for (let i = 0z; i < n; i += 1) bus.cart.ram[i] = data[i];
};

// cart_rom_bank_count は常に2の冪(2<<code、あるいはフォールバックの1)を
// 返すため、剰余の代わりにビットマスクで折り返せる。剰余演算はROMの
// 全バイトアクセス(オペコードフェッチ含む、毎命令複数回発生する)の
// たびに実行されるホットパスなので、これは実測で無視できない差になる。
fn cart_rom_byte(bus: *Bus, bank: int, off: u16) u8 = {
	const b = bank & (bus.cart.rom_bank_count - 1);
	const idx = (b: size) * 0x4000 + (off: size);
	if (idx < len(bus.rom)) return bus.rom[idx];
	return 0xFF;
};

export fn cart_read(bus: *Bus, addr: u16) u8 = {
	const c = &bus.cart;
	switch (c.mbc) {
	case Mbc_Type::None =>
		const a = addr: size;
		if (a < len(bus.rom)) return bus.rom[a];
		return 0xFF;
	case Mbc_Type::Mbc1 =>
		if (addr < 0x4000) {
			let bank = 0;
			if (c.mode == 1) bank = (c.ram_sel: int) << 5;
			return cart_rom_byte(bus, bank, addr);
		};
		const bank = ((c.ram_sel: int) << 5) | (c.rom_lo: int);
		return cart_rom_byte(bus, bank, addr - 0x4000);
	case Mbc_Type::Mbc2 =>
		if (addr < 0x4000) return cart_rom_byte(bus, 0, addr);
		return cart_rom_byte(bus, c.rom_lo: int, addr - 0x4000);
	case Mbc_Type::Mbc3 =>
		if (addr < 0x4000) return cart_rom_byte(bus, 0, addr);
		return cart_rom_byte(bus, c.rom_lo: int, addr - 0x4000);
	case Mbc_Type::Mbc5 =>
		if (addr < 0x4000) return cart_rom_byte(bus, 0, addr);
		const bank = ((c.rom_hi: int) << 8) | (c.rom_lo: int);
		return cart_rom_byte(bus, bank, addr - 0x4000);
	};
};

export fn cart_write(bus: *Bus, addr: u16, value: u8) void = {
	const c = &bus.cart;
	switch (c.mbc) {
	case Mbc_Type::None => void;
	case Mbc_Type::Mbc1 =>
		if (addr < 0x2000) {
			c.ram_enabled = (value & 0x0F) == 0x0A;
		} else if (addr < 0x4000) {
			let v = value & 0x1F;
			if (v == 0) v = 1;
			c.rom_lo = v;
		} else if (addr < 0x6000) {
			c.ram_sel = value & 0x03;
		} else {
			c.mode = value & 0x01;
		};
	case Mbc_Type::Mbc2 =>
		if (addr < 0x4000) {
			if ((addr & 0x0100) == 0) {
				c.ram_enabled = (value & 0x0F) == 0x0A;
			} else {
				let v = value & 0x0F;
				if (v == 0) v = 1;
				c.rom_lo = v;
			};
		};
	case Mbc_Type::Mbc3 =>
		if (addr < 0x2000) {
			c.ram_enabled = (value & 0x0F) == 0x0A;
		} else if (addr < 0x4000) {
			let v = value & 0x7F;
			if (v == 0) v = 1;
			c.rom_lo = v;
		} else if (addr < 0x6000) {
			c.ram_sel = value;
		} else {
			if (c.latch_prev == 0 && value == 1) {
				// Real-time tracking is not modeled; latching is a no-op
				// beyond acknowledging the write sequence.
				void;
			};
			c.latch_prev = value;
		};
	case Mbc_Type::Mbc5 =>
		if (addr < 0x2000) {
			c.ram_enabled = (value & 0x0F) == 0x0A;
		} else if (addr < 0x3000) {
			c.rom_lo = value;
		} else if (addr < 0x4000) {
			c.rom_hi = value & 0x01;
		} else if (addr < 0x6000) {
			c.ram_sel = value & 0x0F;
		};
	};
};

fn cart_ram_bank_index(bus: *Bus, bank: int, addr: u16) (size | void) = {
	const c = &bus.cart;
	if (len(c.ram) == 0) return void;
	// cart_ram_size (呼び出し元 cartridge_init 経由) は常に2の冪バンク数に
	// なるため、剰余の代わりにビットマスクで折り返せる。
	const b = if (c.ram_bank_count > 0) bank & (c.ram_bank_count - 1) else 0;
	const idx = (b: size) * 0x2000 + ((addr & 0x1FFF): size);
	if (idx >= len(c.ram)) return void;
	return idx;
};

fn cart_ram_bank(c: *Cartridge) int = {
	switch (c.mbc) {
	case Mbc_Type::Mbc1 =>
		return if (c.mode == 1) (c.ram_sel: int) else 0;
	case Mbc_Type::Mbc3 =>
		return c.ram_sel: int;
	case Mbc_Type::Mbc5 =>
		return (c.ram_sel & 0x0F): int;
	case =>
		return 0;
	};
};

export fn cart_ram_read(bus: *Bus, addr: u16) u8 = {
	const c = &bus.cart;
	if (!c.ram_enabled || c.mbc == Mbc_Type::None) return 0xFF;
	if (c.mbc == Mbc_Type::Mbc2) {
		const idx = (addr & 0x01FF): size;
		if (idx >= len(c.ram)) return 0xFF;
		return c.ram[idx] | 0xF0;
	};
	if (c.mbc == Mbc_Type::Mbc3 && c.ram_sel >= 0x08 && c.ram_sel <= 0x0C) {
		return c.rtc[(c.ram_sel - 0x08): size];
	};
	match (cart_ram_bank_index(bus, cart_ram_bank(c), addr)) {
	case let idx: size =>
		return c.ram[idx];
	case void =>
		return 0xFF;
	};
};

export fn cart_ram_write(bus: *Bus, addr: u16, value: u8) void = {
	const c = &bus.cart;
	if (!c.ram_enabled || c.mbc == Mbc_Type::None) return;
	if (c.mbc == Mbc_Type::Mbc2) {
		const idx = (addr & 0x01FF): size;
		if (idx < len(c.ram)) c.ram[idx] = value & 0x0F;
		return;
	};
	if (c.mbc == Mbc_Type::Mbc3 && c.ram_sel >= 0x08 && c.ram_sel <= 0x0C) {
		c.rtc[(c.ram_sel - 0x08): size] = value;
		return;
	};
	match (cart_ram_bank_index(bus, cart_ram_bank(c), addr)) {
	case let idx: size =>
		c.ram[idx] = value;
	case void =>
		void;
	};
};
