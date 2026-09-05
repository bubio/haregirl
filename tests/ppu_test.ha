use crypto::sha256;
use encoding::hex;
use fmt;
use hash;
use core;

// Rendered by mattcurrie/dmg-acid2 (v1.0) on real DMG hardware; computed
// from img/reference-dmg.png in that repository by mapping each of the
// four grayscale shades to a 0-3 palette id (white=0 .. black=3) in
// row-major order and hashing the resulting 160*144 byte buffer.
const DMG_ACID2_EXPECTED_HASH =
	"f844ea760a6f1fe137f7f992c7ab1c72d34c7fcd3a807b4174a78eb04a32a458";

const DMG_ACID2_PATH = "tests/roms/dmg-acid2/dmg-acid2.gb";

export fn test_dmg_acid2() void = {
	const rom = match (load_rom_file(DMG_ACID2_PATH)) {
	case let rom: []u8 =>
		yield rom;
	case =>
		fmt::println("dmg-acid2 ROM skipped; run ./scripts/fetch-test-roms.sh to enable it")!;
		return;
	};
	defer free(rom);

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&runner, rom, core::Gb_Mode::Dmg),
		"ROM runner accepted dmg-acid2 ROM");

	// dmg-acid2 spends its first frames toggling LCDC per scanline (via
	// STAT interrupts) with the LCD initially off while VRAM is set up,
	// so settling takes noticeably longer than a single frame.
	const frame_cycles = core::CYCLES_PER_FRAME * 40;
	for (runner.bus.cycles < frame_cycles) {
		core::rom_runner_step(&runner);
		if (runner.cpu.stopped) break;
	};

	let sha = sha256::sha256();
	hash::write(&sha, runner.bus.ppu.frame[..]);
	let digest: [sha256::SZ]u8 = [0...];
	hash::sum(&sha, digest[..]);
	const got = hex::encodestr(digest[..])!;
	defer free(got);

	if (got != DMG_ACID2_EXPECTED_HASH) {
		fmt::fatal(fmt::asprintf(
			"dmg-acid2 framebuffer hash mismatch: got {} want {}",
			got, DMG_ACID2_EXPECTED_HASH,
		)!);
	};
};

// Exercise the public scanline path against per-pixel bitplane decoding.
// Include clipped windows, scroll offsets, CGB horizontal flip, and reused
// framebuffer rows when DMG background display is turned off.
fn test_ppu_tile_runs() void = {
	const positions: [6]u8 = [0, 3, 7, 12, 159, 167];
	const colors: [4]u32 = [0, 0xFF0000, 0x00FF00, 0x0000FF];
	for (let setting = 0u16; setting < 192; setting += 1) {
		const cgb = (setting & 1) != 0;
		const flip = (setting & 2) != 0;
		const scroll = ((setting >> 2) & 7): u8;
		const wx = positions[setting / 32];
		const mode = if (cgb) core::Gb_Mode::Cgb else core::Gb_Mode::Dmg;
		let b = core::Bus { mode = mode, ... };
		core::ppu_reset(&b.ppu, mode);
		const p = &b.ppu;
		p.lcdc = 0xF1; // unsigned BG tiles, window at 9C00, sprites off
		p.bgp = 0xE4;
		p.scx = scroll;
		p.wx = wx;
		p.cgb_bg_pal[2] = 31;
		p.cgb_bg_pal[4] = 0xE0; p.cgb_bg_pal[5] = 3;
		p.cgb_bg_pal[7] = 0x7C;
		for (let row = 0z; row < 8; row += 1) {
			b.vram[0][row * 2] = 0x96;
			b.vram[0][row * 2 + 1] = 0x3C;
			b.vram[0][16 + row * 2] = 0x3C;
			b.vram[0][17 + row * 2] = 0xA5;
		};
		for (let tile = 0z; tile < 32; tile += 1) {
			b.vram[0][0x1C00 + tile] = 1;
			b.vram[1][0x1800 + tile] = if (flip) 0x20 else 0;
			b.vram[1][0x1C00 + tile] = if (flip) 0x20 else 0;
		};
		for (let x = 0z; x < 320; x += 1) {
			p.frame[x] = 0xAA;
			p.frame_rgb[x] = 0x123456;
		};
		core::ppu_tick(&b, 332);
		for (let x = 0z; x < 160; x += 1) {
			const window = (x: int) >= (wx: int) - 7;
			const column = (if (window) (x: int) - (wx: int) + 7
				else (x: int) + (scroll: int)) & 7;
			const bit = if (cgb && flip) column else 7 - column;
			const low: u8 = if (window) 0x3C else 0x96;
			const high: u8 = if (window) 0xA5 else 0x3C;
			const id = ((low >> (bit: u8)) & 1) | (((high >> (bit: u8)) & 1) << 1);
			check(if (cgb) p.frame_rgb[x] == colors[id] else p.frame[x] == id,
				"tile run matches per-pixel decoding with scroll/flip/window clipping");
			check(if (cgb) p.frame[x] == 0xAA else p.frame_rgb[x] == 0x123456,
				"render leaves inactive framebuffer unchanged");
			check(p.frame[x + 160] == 0xAA && p.frame_rgb[x + 160] == 0x123456,
				"render stays within destination row");
		};
		check(p.window_line == (if (wx < 167) 1u8 else 0u8), "clipped window line counter");
		p.lcdc &= ~1u8;
		core::ppu_tick(&b, 456);
		for (let x = 0z; x < 160; x += 1) {
			check(if (cgb) p.frame_rgb[x + 160] == p.frame_rgb[x]
				else p.frame[x + 160] == 0,
				"LCDC bit zero clears DMG row but retains CGB background");
		};
	};
};
