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
