use crypto::sha256;
use encoding::hex;
use fmt;
use hash;
use core;

// Rendered by mattcurrie/cgb-acid2 (v1.1) on real CGB hardware; computed
// from img/reference.png in that repository. The reference PNG's RGB values
// are a plain linear scale of the ROM's RGB555 palette entries (component *
// 255 / 31, rounded, verified against inc/palettes.asm), so the expected
// hash is over the raw 160x144 RGB888 buffer (3 bytes/pixel, row-major, no
// gamma/color-correction curve applied).
const CGB_ACID2_EXPECTED_HASH =
	"df86492849e620d0cd2d421013795997d083ddc2a1ef216b44bf6b9b2f603803";

const CGB_ACID2_PATH = "tests/roms/cgb-acid2/cgb-acid2.gbc";

export fn test_cgb_acid2() void = {
	const rom = match (load_rom_file(CGB_ACID2_PATH)) {
	case let rom: []u8 =>
		yield rom;
	case =>
		fmt::println("cgb-acid2 ROM skipped; run ./scripts/fetch-test-roms.sh to enable it")!;
		return;
	};
	defer free(rom);

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	check(core::rom_runner_init(&runner, rom, core::Gb_Mode::Cgb),
		"ROM runner accepted cgb-acid2 ROM");

	// Mirrors the dmg-acid2 settle budget: give the ROM plenty of frames to
	// finish its VRAM setup and raster-split rendering before sampling the
	// framebuffer. v1.1 additionally halts on a software breakpoint
	// (opcode $40) once the test image is complete, so stop early then too.
	const frame_cycles = core::CYCLES_PER_FRAME * 40;
	for (runner.bus.cycles < frame_cycles) {
		core::rom_runner_step(&runner);
		if (runner.cpu.stopped || runner.breakpoints > 0) break;
	};

	let buf: [69120]u8 = [0...];
	for (let i = 0z; i < 23040; i += 1) {
		const v = runner.bus.ppu.frame_rgb[i];
		buf[i * 3] = (v >> 16): u8;
		buf[i * 3 + 1] = (v >> 8): u8;
		buf[i * 3 + 2] = v: u8;
	};

	let sha = sha256::sha256();
	hash::write(&sha, buf[..]);
	let digest: [sha256::SZ]u8 = [0...];
	hash::sum(&sha, digest[..]);
	const got = hex::encodestr(digest[..])!;
	defer free(got);

	if (got != CGB_ACID2_EXPECTED_HASH) {
		fmt::fatal(fmt::asprintf(
			"cgb-acid2 framebuffer hash mismatch: got {} want {}",
			got, CGB_ACID2_EXPECTED_HASH,
		)!);
	};
};
