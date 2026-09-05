// DMG/CGB picture processing unit. Implements register access, mode timing,
// background/window/sprite rendering and STAT/VBlank interrupt requests.
// In CGB mode, BG map attributes (VRAM bank 1), OBJ CGB palettes/VRAM bank,
// CGB BG/OBJ palette RAM (BCPS/BCPD, OCPS/OCPD) and the BG/OBJ master
// priority bit are additionally modelled; the `frame` byte buffer keeps
// holding DMG 0-3 shade ids (unchanged, still used by the dmg-acid2 test),
// while `frame_rgb` holds packed 0xRRGGBB colors and is only populated in
// CGB mode.

export def PPU_MODE_HBLANK: u8 = 0;
export def PPU_MODE_VBLANK: u8 = 1;
export def PPU_MODE_OAM: u8 = 2;
export def PPU_MODE_TRANSFER: u8 = 3;

def DOTS_PER_LINE: u16 = 456;
def OAM_DOTS: u16 = 80;
def TRANSFER_DOTS: u16 = 252;
def LINES_PER_FRAME: u8 = 154;

export type Ppu = struct {
	mode_gb: Gb_Mode,
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
	// CGB palette RAM (BCPS/BCPD FF68/69, OCPS/OCPD FF6A/6B): 8 palettes of
	// 4 colors, 2 bytes (little-endian RGB555) per color.
	cgb_bg_pal: [64]u8,
	cgb_obj_pal: [64]u8,
	bgpi: u8,
	obpi: u8,
	// Packed 0xRRGGBB colors, populated only in CGB mode.
	frame_rgb: [23040]u32,
};

export fn ppu_lcd_enabled(p: *Ppu) bool = (p.lcdc & 0x80) != 0;
fn ppu_win_tilemap_9c00(p: *Ppu) bool = (p.lcdc & 0x40) != 0;
fn ppu_window_enabled(p: *Ppu) bool = (p.lcdc & 0x20) != 0;
fn ppu_bg_unsigned_tiles(p: *Ppu) bool = (p.lcdc & 0x10) != 0;
fn ppu_bg_tilemap_9c00(p: *Ppu) bool = (p.lcdc & 0x08) != 0;
fn ppu_obj_tall(p: *Ppu) bool = (p.lcdc & 0x04) != 0;
fn ppu_obj_enabled(p: *Ppu) bool = (p.lcdc & 0x02) != 0;
// On DMG, LCDC bit0 disables BG/window display entirely. On CGB it is
// repurposed as the BG/OBJ master priority flag: BG/window keep rendering,
// they merely lose the ability to be drawn above sprites.
fn ppu_bg_window_enabled(p: *Ppu) bool = {
	if (p.mode_gb == Gb_Mode::Cgb) return true;
	return (p.lcdc & 0x01) != 0;
};
fn ppu_master_priority(p: *Ppu) bool = (p.lcdc & 0x01) != 0;

export fn ppu_reset(p: *Ppu, mode: Gb_Mode) void = {
	*p = Ppu { ... };
	p.mode_gb = mode;
	p.lcdc = 0x91;
	p.bgp = 0xFC;
	p.obp0 = 0xFF;
	p.obp1 = 0xFF;
};

fn ppu_rgb555_scale(v: u8) u8 = (((v: uint) * 255 + 15) / 31): u8;

fn ppu_rgb555_unpack(lo: u8, hi: u8) u32 = {
	const v: u16 = (lo: u16) | ((hi: u16) << 8);
	const r = ppu_rgb555_scale((v & 0x1F): u8);
	const g = ppu_rgb555_scale(((v >> 5) & 0x1F): u8);
	const b = ppu_rgb555_scale(((v >> 10) & 0x1F): u8);
	return ((r: u32) << 16) | ((g: u32) << 8) | (b: u32);
};

fn ppu_cgb_bg_color(p: *Ppu, palette: u8, id: u8) u32 = {
	const base = ((palette & 0x07): size) * 8 + (id: size) * 2;
	return ppu_rgb555_unpack(p.cgb_bg_pal[base], p.cgb_bg_pal[base + 1]);
};

fn ppu_cgb_obj_color(p: *Ppu, palette: u8, id: u8) u32 = {
	const base = ((palette & 0x07): size) * 8 + (id: size) * 2;
	return ppu_rgb555_unpack(p.cgb_obj_pal[base], p.cgb_obj_pal[base + 1]);
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

// Fetches one background/window tile's two bitplane bytes and CGB attribute
// byte (0 outside CGB mode) at (map_addr, in_row). The result is shared by up
// to 8 consecutive screen pixels within the same tile column, so callers
// should re-fetch only when the tile column changes rather than per pixel.
fn ppu_bg_tile_fetch(bus: *Bus, map_addr: u16, in_row: u8) (u8, u8, u8) = {
	const p = &bus.ppu;
	const cgb = p.mode_gb == Gb_Mode::Cgb;
	const tile_id = vram_at(bus, 0, map_addr);
	const attr: u8 = if (cgb) vram_at(bus, 1, map_addr) else 0;
	const bank: u8 = (attr >> 3) & 1;
	const yflip = (attr & 0x40) != 0;
	const row = if (yflip) 7 - in_row else in_row;
	const addr = ppu_tile_addr(p, tile_id, row: u16);
	const lo = vram_at(bus, bank, addr);
	const hi = vram_at(bus, bank, addr + 1);
	return (lo, hi, attr);
};

// Extracts one pixel's color id from a tile fetched by ppu_bg_tile_fetch.
fn ppu_tile_pixel_id(lo: u8, hi: u8, attr: u8, in_col: u8) u8 = {
	const xflip = (attr & 0x20) != 0;
	const bit: u8 = if (xflip) in_col else 7 - in_col;
	return (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
};

// Renders one background/window/sprite scanline into the framebuffer using
// the register values captured at the moment HBlank begins.
fn ppu_render_line(bus: *Bus) void = {
	const p = &bus.ppu;
	const cgb = p.mode_gb == Gb_Mode::Cgb;
	const ly = p.ly;
	let row: [160]u8 = [0...];
	let row_rgb: [160]u32 = [0...];
	let bg_color_id: [160]u8 = [0...];
	let bg_priority: [160]bool = [false...];

	if (ppu_bg_window_enabled(p)) {
		const y = ly + p.scy;
		const tile_row = (y / 8): u16;
		const in_row = y % 8;
		const map_base: u16 = if (ppu_bg_tilemap_9c00(p)) 0x9C00 else 0x9800;
		let x = 0z;
		for (x < 160) {
			const sx = (x: u8) + p.scx;
			const tile_col = (sx / 8): u16;
			const in_col0 = (sx % 8): size;
			const map_addr = map_base + tile_row * 32 + tile_col;
			const tile = ppu_bg_tile_fetch(bus, map_addr, in_row);
			const run = 8 - in_col0;
			const n = if (run < 160 - x) run else 160 - x;
			for (let k = 0z; k < n; k += 1) {
				const id = ppu_tile_pixel_id(tile.0, tile.1, tile.2, (in_col0 + k): u8);
				bg_color_id[x + k] = id;
				if (cgb) {
					bg_priority[x + k] = (tile.2 & 0x80) != 0;
					row_rgb[x + k] = ppu_cgb_bg_color(p, tile.2 & 0x07, id);
				} else {
					row[x + k] = ppu_apply_palette(p.bgp, id);
				};
			};
			x += n;
		};

		if (ppu_window_enabled(p) && ly >= p.wy) {
			const wx = (p.wx: int) - 7;
			if (wx < 160) {
				const win_map_base: u16 = if (ppu_win_tilemap_9c00(p)) 0x9C00 else 0x9800;
				const tile_row = (p.window_line / 8): u16;
				const in_row = p.window_line % 8;
				let drew = false;
				let x = if (wx > 0) wx: size else 0z;
				for (x < 160) {
					drew = true;
					const wxpos = (x: int) - wx;
					const tile_col = (wxpos: u16) / 8;
					const in_col0 = (wxpos: size) % 8;
					const map_addr = win_map_base + tile_row * 32 + tile_col;
					const tile = ppu_bg_tile_fetch(bus, map_addr, in_row);
					const run = 8 - in_col0;
					const n = if (run < 160 - x) run else 160 - x;
					for (let k = 0z; k < n; k += 1) {
						const id = ppu_tile_pixel_id(tile.0, tile.1, tile.2, (in_col0 + k): u8);
						bg_color_id[x + k] = id;
						if (cgb) {
							bg_priority[x + k] = (tile.2 & 0x80) != 0;
							row_rgb[x + k] = ppu_cgb_bg_color(p, tile.2 & 0x07, id);
						} else {
							row[x + k] = ppu_apply_palette(p.bgp, id);
						};
					};
					x += n;
				};
				if (drew) p.window_line += 1;
			};
		};
	};

	if (ppu_obj_enabled(p)) {
		ppu_render_sprites(bus, ly, &row, &row_rgb, &bg_color_id, &bg_priority);
	};

	for (let x = 0z; x < 160; x += 1) {
		if (cgb) {
			p.frame_rgb[(ly: size) * 160 + x] = row_rgb[x];
		} else {
			p.frame[(ly: size) * 160 + x] = row[x];
		};
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
	row_rgb: *[160]u32,
	bg_color_id: *[160]u8,
	bg_priority: *[160]bool,
) void = {
	const p = &bus.ppu;
	const cgb = p.mode_gb == Gb_Mode::Cgb;
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

	// On DMG, lower OAM index draws on top when X coordinates tie, so a
	// stable insertion sort by (x, index) establishes priority order. On
	// CGB, sprite priority is purely OAM index order (already the order
	// `selected` was built in), so the sort is skipped.
	if (!cgb) {
		for (let i = 1; i < count; i += 1) {
			const key = selected[i];
			let j = i - 1;
			for (j >= 0 && (selected[j].x: int) > (key.x: int); j -= 1) {
				selected[j + 1] = selected[j];
			};
			selected[j + 1] = key;
		};
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
		const bank: u8 = if (cgb) (s.flags >> 3) & 1 else 0;
		const addr = 0x8000 + (tile: u16) * 16 + (line: u16) * 2;
		const lo = vram_at(bus, bank, addr);
		const hi = vram_at(bus, bank, addr + 1);
		const x_flip = (s.flags & 0x20) != 0;
		const behind_bg = (s.flags & 0x80) != 0;
		const palette = if ((s.flags & 0x10) != 0) p.obp1 else p.obp0;
		const cgb_palette = s.flags & 0x07;
		for (let col = 0; col < 8; col += 1) {
			const sx = (s.x: int) - 8 + col;
			if (sx < 0 || sx >= 160) continue;
			const bit: u8 = if (x_flip) (col: u8) else (7 - (col: u8));
			const id: u8 = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
			if (id == 0) continue;
			if (cgb) {
				if (ppu_master_priority(p)
					&& (behind_bg || bg_priority[sx])
					&& bg_color_id[sx] != 0) {
					continue;
				};
				row_rgb[sx] = ppu_cgb_obj_color(p, cgb_palette, id);
			} else {
				if (behind_bg && bg_color_id[sx] != 0) continue;
				row[sx] = ppu_apply_palette(palette, id);
			};
		};
	};
};

// ppu_tick は以前1dotずつループしてppu_update_stat_line(STATの edge
// detection)を毎dot呼んでいたが、モード/LYCが実際に変化するのはOAM/転送/
// 行送りの境界dotだけなので、境界のないdot区間は一気にスキップできる
// (STAT/LYC/LCDCレジスタへの書き込みによる境界外での変化はppu_write_stat/
// ppu_write_lyc/ppu_write_lcdc側で個別にppu_update_stat_lineを呼んで
// 拾うため、ここで毎dot呼ぶ必要はない)。
export fn ppu_tick(bus: *Bus, cycles: int) void = {
	const p = &bus.ppu;
	if (!ppu_lcd_enabled(p)) return;

	let remaining: u16 = cycles: u16;
	for (remaining > 0) {
		let next_boundary = DOTS_PER_LINE;
		if (p.ly < 144) {
			if (p.dot < OAM_DOTS) {
				next_boundary = OAM_DOTS;
			} else if (p.dot < OAM_DOTS + TRANSFER_DOTS) {
				next_boundary = OAM_DOTS + TRANSFER_DOTS;
			};
		};
		const to_boundary = next_boundary - p.dot;
		// Almost every CPU access ends within the current PPU mode.
		// No mode/LY/STAT work is needed until its boundary is reached.
		if (remaining < to_boundary) {
			p.dot += remaining;
			return;
		};
		const step = if (to_boundary < remaining) to_boundary else remaining;
		p.dot += step;
		remaining -= step;

		if (p.ly < 144) {
			if (p.dot == OAM_DOTS) {
				ppu_set_mode(bus, PPU_MODE_TRANSFER);
				ppu_update_stat_line(bus);
			} else if (p.dot == OAM_DOTS + TRANSFER_DOTS) {
				ppu_render_line(bus);
				ppu_set_mode(bus, PPU_MODE_HBLANK);
				hdma_hblank_step(bus);
				ppu_update_stat_line(bus);
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
			ppu_update_stat_line(bus);
		};
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
	} else if (!was_enabled && ppu_lcd_enabled(&bus.ppu)) {
		ppu_update_stat_line(bus);
	};
};

// ppu_tick はモード/LYCの境界dotでしかppu_update_stat_lineを呼ばないため、
// 走査線の途中でSTAT割り込み源を有効にした場合はここで即座に拾う必要がある
// (境界まで待つと実機よりSTAT割り込みが遅れてしまう)。
export fn ppu_write_stat(bus: *Bus, value: u8) void = {
	bus.ppu.stat = (bus.ppu.stat & 0x87) | (value & 0x78);
	ppu_update_stat_line(bus);
};

export fn ppu_write_ly(bus: *Bus, value: u8) void = {
	bus.cycles += 0;
};

export fn ppu_write_lyc(bus: *Bus, value: u8) void = {
	bus.ppu.lyc = value;
	ppu_update_lyc(bus);
	ppu_update_stat_line(bus);
};

export fn oam_dma_start(bus: *Bus, value: u8) void = {
	bus.io[0x46] = value;
	const src = (value: u16) << 8;
	for (let i: u16 = 0; i < 160; i += 1) {
		bus.oam[i] = bus_read(bus, src + i);
	};
};
