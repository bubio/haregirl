// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.

use core;
use fmt;
use fs;
use io;
use os;
use sdl;
use strings;

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
fn apply_apu_power_up(bus: *core::Bus) void = {
	core::bus_write(bus, 0xFF26, 0xF1); // Comment translated to English.
	core::bus_write(bus, 0xFF10, 0x80); // Comment translated to English.
	core::bus_write(bus, 0xFF11, 0xBF); // Comment translated to English.
	core::bus_write(bus, 0xFF12, 0xF3); // Comment translated to English.
	core::bus_write(bus, 0xFF14, 0xBF & 0x7F); // Comment translated to English.
	core::bus_write(bus, 0xFF16, 0x3F); // Comment translated to English.
	core::bus_write(bus, 0xFF17, 0x00); // Comment translated to English.
	core::bus_write(bus, 0xFF19, 0xBF & 0x7F); // Comment translated to English.
	core::bus_write(bus, 0xFF1A, 0x7F); // Comment translated to English.
	core::bus_write(bus, 0xFF1B, 0xFF); // Comment translated to English.
	core::bus_write(bus, 0xFF1C, 0x9F); // Comment translated to English.
	core::bus_write(bus, 0xFF1E, 0xBF & 0x7F); // Comment translated to English.
	core::bus_write(bus, 0xFF20, 0xFF); // Comment translated to English.
	core::bus_write(bus, 0xFF21, 0x00); // Comment translated to English.
	core::bus_write(bus, 0xFF22, 0x00); // Comment translated to English.
	core::bus_write(bus, 0xFF23, 0xBF & 0x7F); // Comment translated to English.
	core::bus_write(bus, 0xFF24, 0x77); // Comment translated to English.
	core::bus_write(bus, 0xFF25, 0xF3); // Comment translated to English.
};

fn save_path_for(rom_path: str) str = {
	const dot = match (strings::rindex(rom_path, ".")) {
	case let i: size =>
		yield i;
	case void =>
		return strings::concat(rom_path, ".sav")!;
	};
	const slash = match (strings::rindex(rom_path, "/")) {
	case let i: size =>
		yield i;
	case void =>
		yield 0z;
	};
	if (dot < slash) return strings::concat(rom_path, ".sav")!;
	return strings::concat(strings::sub(rom_path, 0, dot), ".sav")!;
};

fn load_battery_ram(bus: *core::Bus, path: str) void = {
	if (!core::cart_has_battery(bus)) return;
	const file = match (os::open(path)) {
	case let f: io::file =>
		yield f;
	case fs::error =>
		return;
	};
	defer io::close(file)!;
	const data = match (io::drain(file)) {
	case let d: []u8 =>
		yield d;
	case =>
		return;
	};
	defer free(data);
	core::cart_ram_load(bus, data);
};

fn save_battery_ram(bus: *core::Bus, path: str) void = {
	if (!core::cart_has_battery(bus)) return;
	const file = match (os::create(path, 0o644)) {
	case let f: io::file =>
		yield f;
	case fs::error =>
		fmt::errorfln("電池バックアップRAMの保存に失敗しました: {}", path)!;
		return;
	};
	defer io::close(file)!;
	io::writeall(file, core::cart_ram_bytes(bus))!;
};

// Comment translated to English.
// Comment translated to English.
const DMG_SHADES: [4]u32 = [0xFFFFFFFF, 0xFFAAAAAA, 0xFF555555, 0xFF000000];

fn frame_to_argb(bus: *core::Bus, fb: []u32) void = {
	if (bus.mode == core::Gb_Mode::Cgb) {
		for (let i = 0z; i < len(fb); i += 1) {
			fb[i] = 0xFF000000 | bus.ppu.frame_rgb[i];
		};
	} else {
		for (let i = 0z; i < len(fb); i += 1) {
			fb[i] = DMG_SHADES[bus.ppu.frame[i] & 0x03];
		};
	};
};

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
fn apply_volume(samples: []i16, volume: int) void = {
	if (volume >= 100) return;
	let v = volume;
	if (v < 0) v = 0;
	for (let i = 0z; i < len(samples); i += 1) {
		samples[i] = (((samples[i]: int) * v) / 100): i16;
	};
};

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
export fn run_rom(rom_path: str, scale: int, volume: int, frames: int, benchmark: bool, smooth: bool) void = {
	const file = match (os::open(rom_path)) {
	case let f: io::file =>
		yield f;
	case fs::error =>
		fmt::fatalf("ROMを開けません: {}", rom_path);
	};
	const data = match (io::drain(file)) {
	case let d: []u8 =>
		yield d;
	case =>
		fmt::fatalf("ROMの読み込みに失敗しました: {}", rom_path);
	};
	io::close(file)!;
	defer free(data);

	if (len(data) < 0x150) {
		fmt::fatal("ROMファイルが小さすぎます");
	};
	const mode = if ((data[0x143] & 0x80) != 0) core::Gb_Mode::Cgb else core::Gb_Mode::Dmg;

	let runner: core::Rom_Runner = core::Rom_Runner { ... };
	if (!core::rom_runner_init(&runner, data, mode)) {
		fmt::fatalf("ROMの読み込みに失敗しました: {}", rom_path);
	};
	apply_apu_power_up(&runner.bus);
	if (benchmark) {
		run_benchmark(&runner, frames);
		return;
	};

	const save_path = save_path_for(rom_path);
	defer free(save_path);
	load_battery_ram(&runner.bus, save_path);

	if (sdl::init(sdl::INIT_AUDIO) != 0) {
		fmt::fatal("SDL_Init(AUDIO) に失敗しました");
	};
	defer sdl::quit();

	let desired = sdl::audio_spec {
		freq = core::SAMPLE_RATE: int,
		format = sdl::AUDIO_S16SYS,
		channels = 2,
		silence = 0,
		samples = 2048,
		padding = 0,
		buf_size = 0,
		callback = null,
		userdata = null,
	};
	let obtained = sdl::audio_spec { ... };
	const dev = sdl::open_audio_device(null, 0, &desired, &obtained, 0);
	if (dev == 0) {
		fmt::fatal("SDL_OpenAudioDevice に失敗しました");
	};
	defer sdl::close_audio_device(dev);
	sdl::pause_audio_device(dev, 0);

	const v = match (video_init(scale, smooth)) {
	case let v: video =>
		yield v;
	case void =>
		save_battery_ram(&runner.bus, save_path);
		os::exit(1);
	};
	defer video_destroy(&v);

	let fb: []u32 = alloc([0...], (SCREEN_WIDTH * SCREEN_HEIGHT): size)!;
	defer free(fb);

	// Comment translated to English.
	// Comment translated to English.
	// Comment translated to English.
	// Comment translated to English.
	// Comment translated to English.
	// Comment translated to English.
	// Comment translated to English.
	const bytes_per_frame = (core::SAMPLE_RATE / 60) * 2 * (size(i16): u32);
	const audio_high_watermark = bytes_per_frame * 4;

	let input: Input_State = Input_State { ... };
	let rendered = 0;
	for (true) {
		if (input_poll(&runner.bus, &input)) {
			// Comment translated to English.
			// Comment translated to English.
			// Comment translated to English.
			// Comment translated to English.
			// Comment translated to English.
			// Comment translated to English.
			sdl::pause_audio_device(dev, 1);
			break;
		};

		const frame_cycles = if (runner.bus.double_speed)
			core::CYCLES_PER_FRAME * 2 else core::CYCLES_PER_FRAME;
		const target = runner.bus.cycles + frame_cycles;
		for (runner.bus.cycles < target) {
			core::rom_runner_step(&runner);
		};

		frame_to_argb(&runner.bus, fb);
		video_present(&v, fb);

		const samples = core::apu_samples(&runner.bus);
		if (len(samples) > 0) {
			apply_volume(samples, volume);
			sdl::queue_audio(dev, samples: *[*]i16: *opaque,
				(len(samples) * size(i16)): u32);
		};
		core::apu_clear_samples(&runner.bus);

		// Comment translated to English.
		// Comment translated to English.
		// Comment translated to English.
		// Comment translated to English.
		// Comment translated to English.
		for (sdl::get_queued_audio_size(dev) > audio_high_watermark) {
			sdl::delay(1);
		};

		rendered += 1;
		if (frames > 0 && rendered >= frames) break;
	};

	save_battery_ram(&runner.bus, save_path);
};
