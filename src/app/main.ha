use core;
use fmt;
use fs;
use os;
use sdl;
use strconv;
use strings;

const version: str = "1.0.0";

fn print_usage() void = {
	if (!is_japanese()) {
		fmt::println("Usage: HareGirl [options] game.gb|game.gbc")!;
		fmt::println()!;
		fmt::println("  -h, --help        Show command-line help")!;
		fmt::println("  -v, --version     Show version information")!;
		fmt::println("  --test-screen     Display the test screen and exit")!;
		fmt::println("  --test-audio      Play test audio and exit")!;
		fmt::println("  --benchmark       Benchmark a ROM for the specified number of frames")!;
		fmt::println("  --frames N        Frame count for test or benchmark modes")!;
		fmt::println("  --config PATH     Set the configuration file path")!;
		fmt::println("  --scale N         Display scale (1-8; values above 8 use 8; default: 4)")!;
		fmt::println("  --shader KIND     Scaling filter: nearest or smooth (default: nearest)")!;
		fmt::println("  --volume N        Volume (0-100; default: 100)")!;
		fmt::println("  --save-config     Save the active configuration and exit")!;
		fmt::println("  --print-config    Print the active configuration and exit")!;
		fmt::println()!;
		fmt::println("Keyboard shortcuts while running a ROM:")!;
		fmt::println("  Arrow keys        Direction pad")!;
		fmt::println("  Z                 A")!;
		fmt::println("  X                 B")!;
		fmt::println("  Enter             Start")!;
		fmt::println("  Right Shift       Select")!;
		fmt::println("  F5                Save state")!;
		fmt::println("  F7                Load state")!;
		fmt::println("  Esc               Quit")!;
		return;
	};
	fmt::println("使用法: HareGirl [options] game.gb|game.gbc")!;
	fmt::println()!;
	fmt::println("  -h, --help        コマンドラインの使い方を表示")!;
	fmt::println("  -v, --version     バージョンを表示")!;
	fmt::println("  --test-screen     テスト画面を表示して終了")!;
	fmt::println("  --test-audio      テスト音声を再生して終了")!;
	fmt::println("  --benchmark       ROMを指定フレーム数ベンチマーク")!;
	fmt::println("  --frames N        テストまたはベンチマークのフレーム数")!;
	fmt::println("  --config PATH     設定ファイルの場所を指定")!;
	fmt::println("  --scale N         表示倍率 (1-8、9以上は8に丸める、デフォルト 4)")!;
	fmt::println("  --shader KIND     シェーダー: nearest, smooth (デフォルト nearest)")!;
	fmt::println("  --volume N        音量 (0-100、デフォルト 100)")!;
	fmt::println("  --save-config     指定した設定を保存して終了")!;
	fmt::println("  --print-config    現在の設定を表示して終了")!;
	fmt::println()!;
	fmt::println("キーボードショートカット(ROM実行中):")!;
	fmt::println("  矢印キー          十字キー")!;
	fmt::println("  Z                 A")!;
	fmt::println("  X                 B")!;
	fmt::println("  Enter             Start")!;
	fmt::println("  右Shift           Select")!;
	fmt::println("  F5                ステート保存")!;
	fmt::println("  F7                ステート読込")!;
	fmt::println("  Esc               終了")!;
};

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
fn run_test_audio(frames: int) void = {
	if (sdl::init(sdl::INIT_AUDIO) != 0) {
		fmt::fatal(msg("SDL_Init(AUDIO) failed", "SDL_Init(AUDIO) に失敗しました"));
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
		fmt::fatal(msg("SDL_OpenAudioDevice failed", "SDL_OpenAudioDevice に失敗しました"));
	};
	defer sdl::close_audio_device(dev);
	sdl::pause_audio_device(dev, 0);

	let bus: core::Bus = core::Bus { ... };
	core::apu_reset(&bus.apu);
	bus.apu.enabled = true;
	// Comment translated to English.
	core::apu_write(&bus, 0xFF24, 0x77); // Comment translated to English.
	core::apu_write(&bus, 0xFF25, 0xFF); // Comment translated to English.
	core::apu_write(&bus, 0xFF16, 0x80); // Comment translated to English.
	core::apu_write(&bus, 0xFF17, 0x83); // Comment translated to English.
	core::apu_write(&bus, 0xFF18, 0x00); // Comment translated to English.
	core::apu_write(&bus, 0xFF19, 0x87); // Comment translated to English.

	let rendered = 0;
	for (true) {
		core::bus_tick(&bus, core::CYCLES_PER_FRAME: int);
		let samples = core::apu_samples(&bus);
		if (len(samples) > 0) {
			sdl::queue_audio(dev, samples: *[*]i16: *opaque,
				(len(samples) * size(i16)): u32);
		};
		core::apu_clear_samples(&bus);
		// Comment translated to English.
		sdl::delay(16);
		rendered += 1;
		if (frames > 0 && rendered >= frames) break;
	};
};

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
fn run_test_screen(frames: int, scale: int, smooth: bool) void = {
	const v = match (video_init(scale, smooth)) {
	case let v: video =>
		yield v;
	case void =>
		os::exit(1);
	};
	defer video_destroy(&v);

	let fb: []u32 = alloc([0...], (SCREEN_WIDTH * SCREEN_HEIGHT): size)!;
	defer free(fb);
	video_test_pattern(fb);

	let rendered = 0;
	for (true) {
		if (video_should_quit()) {
			break;
		};
		video_present(&v, fb);
		sdl::delay(16);
		rendered += 1;
		if (frames > 0 && rendered >= frames) {
			break;
		};
	};
};

export fn main() void = {
	let args = os::args;
	let test_screen = false;
	let test_audio = false;
	let benchmark = false;
	let frames = 0;
	let save_config = false;
	let print_config = false;
	let config_path: (str | void) = void;
	let scale_override: (int | void) = void;
	let volume_override: (int | void) = void;
	let shader_override: (bool | void) = void;
	let rom_path: (str | void) = void;

	for (let i = 1z; i < len(args); i += 1) {
		switch (args[i]) {
		case "--version", "-v" =>
			fmt::println("HareGirl", version)!;
			return;
		case "--help", "-h" =>
			print_usage();
			return;
		case "--test-screen" =>
			test_screen = true;
		case "--test-audio" =>
			test_audio = true;
		case "--benchmark" =>
			benchmark = true;
		case "--frames" =>
			i += 1;
			if (i >= len(args)) {
				fmt::fatal(msg("--frames requires an argument", "--frames には引数が必要です"));
			};
			frames = match (strconv::stoi(args[i])) {
			case let n: int =>
				yield n;
			case =>
				fmt::fatalf(msg("invalid --frames value: {}", "--frames の値が不正です: {}"), args[i]);
			};
		case "--config" =>
			i += 1;
			if (i >= len(args)) {
				fmt::fatal(msg("--config requires an argument", "--config には引数が必要です"));
			};
			config_path = args[i];
		case "--scale" =>
			i += 1;
			if (i >= len(args)) {
				fmt::fatal(msg("--scale requires an argument", "--scale には引数が必要です"));
			};
			scale_override = match (strconv::stoi(args[i])) {
			case let n: int =>
				if (n <= 0) {
					fmt::fatalf(msg("invalid --scale value: {} (expected 1 or greater)", "--scale の値が不正です: {} (1以上を指定してください)"), args[i]);
				};
				if (n > 8) yield 8;
				yield n;
			case =>
				fmt::fatalf(msg("invalid --scale value: {}", "--scale の値が不正です: {}"), args[i]);
			};
		case "--shader" =>
			i += 1;
			if (i >= len(args)) {
				fmt::fatal(msg("--shader requires an argument", "--shader には引数が必要です"));
			};
			if (args[i] == "smooth") {
				shader_override = true;
			} else if (args[i] != "nearest") {
				fmt::fatalf(msg("invalid --shader value: {} (expected nearest or smooth)", "--shader の値が不正です: {} (nearest または smooth を指定してください)"), args[i]);
			};
			if (args[i] == "nearest") shader_override = false;
		case "--volume" =>
			i += 1;
			if (i >= len(args)) {
				fmt::fatal(msg("--volume requires an argument", "--volume には引数が必要です"));
			};
			volume_override = match (strconv::stoi(args[i])) {
			case let n: int =>
				yield n;
			case =>
				fmt::fatalf(msg("invalid --volume value: {}", "--volume の値が不正です: {}"), args[i]);
			};
		case "--save-config" =>
			save_config = true;
		case "--print-config" =>
			print_config = true;
		case =>
			if (strings::hasprefix(args[i], "-")) {
				fmt::fatalf(msg("unknown option: {}", "不明なオプションです: {}"), args[i]);
			};
			rom_path = args[i];
		};
	};

	if (benchmark && (frames <= 0 || test_screen || test_audio
		|| save_config || print_config || rom_path is void)) {
		fmt::fatal(msg("--benchmark requires a ROM and --frames N (N > 0), without test/config actions", "--benchmark にはROMと --frames N (N > 0) が必要です（テスト/設定操作とは併用できません）"));
	};

	const path = match (config_path) {
	case let p: str =>
		yield p;
	case void =>
		yield match (settings_path()) {
		case let p: str =>
			yield p;
		case void =>
		fmt::fatal(msg("cannot determine configuration path ($HOME is not set)", "設定ファイルの場所を決定できません($HOME が未設定です)"));
		};
	};

	let settings = settings_load(path);
	match (shader_override) {
	case let value: bool =>
		settings.smooth = value;
	case void => void;
	};
	let smooth = settings.smooth;
	match (scale_override) {
	case let n: int =>
		settings.scale = n;
	case void => void;
	};
	match (volume_override) {
	case let n: int =>
		settings.volume = n;
	case void => void;
	};

	if (save_config) {
		match (settings_save(path, settings)) {
		case void =>
			fmt::println(msg("Configuration saved:", "設定を保存しました:"), path)!;
		case let err: fs::error =>
			fmt::fatalf(msg("failed to save configuration: {}", "設定の保存に失敗しました: {}"), fs::strerror(err));
		};
		return;
	};

	if (print_config) {
		fmt::printfln("config: {}", path)!;
		fmt::printfln("scale={}", settings.scale)!;
		fmt::printfln("volume={}", settings.volume)!;
		fmt::printfln("shader={}", if (settings.smooth) "smooth" else "nearest")!;
		return;
	};

	if (test_screen) {
		run_test_screen(frames, settings.scale, smooth);
		return;
	};

	if (test_audio) {
		run_test_audio(frames);
		return;
	};

	match (rom_path) {
	case let p: str =>
		run_rom(p, settings.scale, settings.volume, frames, benchmark, smooth);
		return;
	case void => void;
	};

	print_usage();
};
