// DMG picture processing unit. Implements register access, mode timing,
// background/window/sprite rendering and STAT/VBlank interrupt requests.
// CGB-specific behaviour (palette RAM, VRAM banking, priority overrides) is
// out of scope until phase 7.

export const PPU_MODE_HBLANK: u8 = 0;
export const PPU_MODE_VBLANK: u8 = 1;
export const PPU_MODE_OAM: u8 = 2;
export const PPU_MODE_TRANSFER: u8 = 3;

const DOTS_PER_LINE: u16 = 456;
const OAM_DOTS: u16 = 80;
const TRANSFER_DOTS: u16 = 252;
const LINES_PER_FRAME: u8 = 154;

export type Ppu = struct {
	lcdc: u8,
	stat: u8,
	scy: u8,
	scx: u8,
	ly: u8,
	lyc: u8,
	bgp: u8,
	obp0: u8,
	obp1: u8,
	wy: u8,
	wx: u8,
	dot: u16,
	mode: u8,
	window_line: u8,
	stat_line: bool,
	frame: [23040]u8,
};

export fn ppu_lcd_enabled(p: *Ppu) bool = (p.lcdc & 0x80) != 0;
fn ppu_win_tilemap_9c00(p: *Ppu) bool = (p.lcdc & 0x40) != 0;
fn ppu_window_enabled(p: *Ppu) bool = (p.lcdc & 0x20) != 0;
fn ppu_bg_unsigned_tiles(p: *Ppu) bool = (p.lcdc & 0x10) != 0;
fn ppu_bg_tilemap_9c00(p: *Ppu) bool = (p.lcdc & 0x08) != 0;
fn ppu_obj_tall(p: *Ppu) bool = (p.lcdc & 0x04) != 0;
fn ppu_obj_enabled(p: *Ppu) bool = (p.lcdc & 0x02) != 0;
fn ppu_bg_window_enabled(p: *Ppu) bool = (p.lcdc & 0x01) != 0;

export fn ppu_reset(p: *Ppu) void = {
	*p = Ppu { ... };
	p.lcdc = 0x91;
	p.bgp = 0xFC;
	p.obp0 = 0xFF;
	p.obp1 = 0xFF;
};

fn ppu_set_mode(bus: *Bus, mode: u8) void = {
	bus.ppu.mode = mode;
	bus.ppu.stat = (bus.ppu.stat & 0xFC) | mode;
};

fn ppu_stat_signal(bus: *Bus) bool = {
	const p = &bus.ppu;
	if ((p.stat & 0x40) != 0 && p.ly == p.lyc) return true;
	if ((p.stat & 0x20) != 0 && p.mode == PPU_MODE_OAM) return true;
	if ((p.stat & 0x10) != 0 && p.mode == PPU_MODE_VBLANK) return true;
	if ((p.stat & 0x08) != 0 && p.mode == PPU_MODE_HBLANK) return true;
	return false;
};

fn ppu_update_stat_line(bus: *Bus) void = {
	const signal = ppu_stat_signal(bus);
	if (signal && !bus.ppu.stat_line) {
		interrupt_request(bus, INT_STAT);
	};
	bus.ppu.stat_line = signal;
};

fn ppu_update_lyc(bus: *Bus) void = {
	if (bus.ppu.ly == bus.ppu.lyc) {
		bus.ppu.stat |= 0x04;
	} else {
		bus.ppu.stat &= ~0x04u8;
	};
};

// Renders one background/window/sprite scanline into the framebuffer using
// the register values captured at the moment HBlank begins.
fn ppu_render_line(bus: *Bus) void = {
	const p = &bus.ppu;
	const ly = p.ly;
	let row: [160]u8 = [0...];
	let bg_color_id: [160]u8 = [0...];

	if (ppu_bg_window_enabled(p)) {
		const y = ly + p.scy;
		const tile_row = (y / 8): u16;
		const in_row = y % 8;
		const map_base: u16 = if (ppu_bg_tilemap_9c00(p)) 0x9C00 else 0x9800;
		for (let x = 0z; x < 160; x += 1) {
			const sx = (x: u8) + p.scx;
			const tile_col = (sx / 8): u16;
			const in_col = sx % 8;
			const map_addr = map_base + tile_row * 32 + tile_col;
			const tile_id = bus_read(bus, map_addr);
			const addr = ppu_tile_addr(p, tile_id, in_row);
			const lo = bus_read(bus, addr);
			const hi = bus_read(bus, addr + 1);
			const bit = 7 - in_col;
			const id: u8 = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
			bg_color_id[x] = id;
			row[x] = ppu_apply_palette(p.bgp, id);
		};

		if (ppu_window_enabled(p) && ly >= p.wy) {
			const wx = (p.wx: int) - 7;
			if (wx < 160) {
				const win_map_base: u16 = if (ppu_win_tilemap_9c00(p)) 0x9C00 else 0x9800;
				const tile_row = (p.window_line / 8): u16;
				const in_row = p.window_line % 8;
				let drew = false;
				for (let x = 0z; x < 160; x += 1) {
					const wxpos = (x: int) - wx;
					if (wxpos < 0) continue;
					drew = true;
					const tile_col = (wxpos: u16) / 8;
					const in_col = (wxpos: u8) % 8;
					const map_addr = win_map_base + tile_row * 32 + tile_col;
					const tile_id = bus_read(bus, map_addr);
					const addr = ppu_tile_addr(p, tile_id, in_row);
					const lo = bus_read(bus, addr);
					const hi = bus_read(bus, addr + 1);
					const bit: u8 = 7 - in_col;
					const id: u8 = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
					bg_color_id[x] = id;
					row[x] = ppu_apply_palette(p.bgp, id);
				};
				if (drew) p.window_line += 1;
			};
		};
	};

	if (ppu_obj_enabled(p)) {
		ppu_render_sprites(bus, ly, &row, &bg_color_id);
	};

	for (let x = 0z; x < 160; x += 1) {
		p.frame[(ly: size) * 160 + x] = row[x];
	};
};

fn ppu_tile_addr(p: *Ppu, tile_id: u8, in_row: u16) u16 = {
	if (ppu_bg_unsigned_tiles(p)) {
		return 0x8000 + (tile_id: u16) * 16 + in_row * 2;
	};
	const signed_id = (tile_id: i8): int;
	return (0x9000 + signed_id * 16 + (in_row: int) * 2): u16;
};

fn ppu_apply_palette(palette: u8, id: u8) u8 = {
	const shade = (palette >> (id * 2)) & 0x03;
	return shade;
};

type oam_entry = struct {
	y: u8,
	x: u8,
	tile: u8,
	flags: u8,
	index: int,
};

fn ppu_render_sprites(
	bus: *Bus,
	ly: u8,
	row: *[160]u8,
	bg_color_id: *[160]u8,
) void = {
	const p = &bus.ppu;
	const height: int = if (ppu_obj_tall(p)) 16 else 8;
	let selected: [10]oam_entry = [oam_entry { ... }...];
	let count = 0;
	for (let i = 0; i < 40 && count < 10; i += 1) {
		const base = (i: size) * 4;
		const sy = (bus.oam[base]: int) - 16;
		if ((ly: int) < sy || (ly: int) >= sy + height) continue;
		selected[count] = oam_entry {
			y = bus.oam[base],
			x = bus.oam[base + 1],
			tile = bus.oam[base + 2],
			flags = bus.oam[base + 3],
			index = i,
		};
		count += 1;
	};

	// Lower OAM index draws on top when X coordinates tie; stable
	// insertion sort by (x, index) keeps priority correct for DMG.
	for (let i = 1; i < count; i += 1) {
		const key = selected[i];
		let j = i - 1;
		for (j >= 0 && (selected[j].x: int) > (key.x: int); j -= 1) {
			selected[j + 1] = selected[j];
		};
		selected[j + 1] = key;
	};

	// Draw back-to-front so that the earlier (higher priority) sprite in
	// the sorted order ends up visible.
	for (let i = count - 1; i >= 0; i -= 1) {
		const s = selected[i];
		const sy = (s.y: int) - 16;
		let line = (ly: int) - sy;
		if ((s.flags & 0x40) != 0) line = height - 1 - line;
		let tile = s.tile;
		if (height == 16) tile &= 0xFE;
		const addr = 0x8000 + (tile: u16) * 16 + (line: u16) * 2;
		const lo = bus_read(bus, addr);
		const hi = bus_read(bus, addr + 1);
		const x_flip = (s.flags & 0x20) != 0;
		const behind_bg = (s.flags & 0x80) != 0;
		const palette = if ((s.flags & 0x10) != 0) p.obp1 else p.obp0;
		for (let col = 0; col < 8; col += 1) {
			const sx = (s.x: int) - 8 + col;
			if (sx < 0 || sx >= 160) continue;
			const bit: u8 = if (x_flip) (col: u8) else (7 - (col: u8));
			const id: u8 = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
			if (id == 0) continue;
			if (behind_bg && bg_color_id[sx] != 0) continue;
			row[sx] = ppu_apply_palette(palette, id);
		};
	};
};

export fn ppu_tick(bus: *Bus, cycles: int) void = {
	const p = &bus.ppu;
	if (!ppu_lcd_enabled(p)) return;

	let remaining = cycles;
	for (remaining > 0) {
		p.dot += 1;
		remaining -= 1;

		if (p.ly < 144) {
			if (p.dot == OAM_DOTS) {
				ppu_set_mode(bus, PPU_MODE_TRANSFER);
			} else if (p.dot == OAM_DOTS + TRANSFER_DOTS) {
				ppu_render_line(bus);
				ppu_set_mode(bus, PPU_MODE_HBLANK);
			};
		};

		if (p.dot >= DOTS_PER_LINE) {
			p.dot = 0;
			p.ly += 1;
			if (p.ly == 144) {
				ppu_set_mode(bus, PPU_MODE_VBLANK);
				interrupt_request(bus, INT_VBLANK);
			} else if (p.ly >= LINES_PER_FRAME) {
				p.ly = 0;
				p.window_line = 0;
				ppu_set_mode(bus, PPU_MODE_OAM);
			} else if (p.ly < 144) {
				ppu_set_mode(bus, PPU_MODE_OAM);
			};
			ppu_update_lyc(bus);
		};
		ppu_update_stat_line(bus);
	};
};

export fn ppu_write_lcdc(bus: *Bus, value: u8) void = {
	const was_enabled = ppu_lcd_enabled(&bus.ppu);
	bus.ppu.lcdc = value;
	if (was_enabled && !ppu_lcd_enabled(&bus.ppu)) {
		bus.ppu.ly = 0;
		bus.ppu.dot = 0;
		bus.ppu.window_line = 0;
		ppu_set_mode(bus, PPU_MODE_HBLANK);
		bus.ppu.stat_line = false;
	};
};

export fn ppu_write_stat(bus: *Bus, value: u8) void = {
	bus.ppu.stat = (bus.ppu.stat & 0x87) | (value & 0x78);
};

export fn ppu_write_ly(bus: *Bus, value: u8) void = {
	bus.cycles += 0;
};

export fn ppu_write_lyc(bus: *Bus, value: u8) void = {
	bus.ppu.lyc = value;
	ppu_update_lyc(bus);
};

export fn oam_dma_start(bus: *Bus, value: u8) void = {
	bus.io[0x46] = value;
	const src = (value: u16) << 8;
	for (let i: u16 = 0; i < 160; i += 1) {
		bus.oam[i] = bus_read(bus, src + i);
	};
};
