use core;
use fmt;
use os;
use sdl;
use strconv;

const version: str = "0.1.0";

// TEST_SCREEN_SCALE は --test-screen で開くウィンドウの表示倍率(160x144 の何倍か)。
const TEST_SCREEN_SCALE: int = 4;

fn print_usage() void = {
	fmt::println("Usage: HareGirl [--version] [--help] [--test-screen [--frames N]] [--test-audio [--frames N]]")!;
};

// run_test_audio は SDL2 の音声デバイスを開き、core::Apu が生成する PCM サンプルを
// 実時間で再生し続ける(フェーズ6 DoD:「実時間再生が成立する」の確認用)。
// APU レジスタを直接叩いてチャンネル2に単純な矩形波トーンを鳴らすだけで、実際の
// ROM 実行(フェーズ9のCLIで実装予定)には依存しない。frames > 0 の場合はその
// フレーム数を再生したら自動終了する(SDL_AUDIODRIVER=dummy と組み合わせたヘッド
// レス CI でのスモークテスト用)。
fn run_test_audio(frames: int) void = {
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

	let bus: core::Bus = core::Bus { ... };
	core::apu_reset(&bus.apu);
	bus.apu.enabled = true;
	// NR52 有効化 + チャンネル2を音量8の矩形波(50%デューティ)で単純に鳴らす。
	core::apu_write(&bus, 0xFF24, 0x77); // NR50: 両chフルボリューム
	core::apu_write(&bus, 0xFF25, 0xFF); // NR51: 全チャンネルを両ch出力
	core::apu_write(&bus, 0xFF16, 0x80); // NR21: duty 50%
	core::apu_write(&bus, 0xFF17, 0x83); // NR22: 音量8, envelope off
	core::apu_write(&bus, 0xFF18, 0x00); // NR23: freq lo
	core::apu_write(&bus, 0xFF19, 0x87); // NR24: freq hi=3, trigger (約440Hz相当)

	let rendered = 0;
	for (true) {
		core::bus_tick(&bus, core::CYCLES_PER_FRAME: int);
		let samples = core::apu_take_samples(&bus);
		defer free(samples);
		if (len(samples) > 0) {
			sdl::queue_audio(dev, samples: *[*]i16: *opaque,
				(len(samples) * size(i16)): u32);
		};
		// キューに溜まりすぎないよう、実時間のフレーム間隔に合わせて待つ。
		sdl::delay(16);
		rendered += 1;
		if (frames > 0 && rendered >= frames) break;
	};
};

// run_test_screen は SDL2 ウィンドウを開き、160x144 のテストパターンを表示し続ける
// (フェーズ1 DoD: 「SDL2 ウィンドウに 160x144 のテスト画面を表示できる」の確認用)。
// frames が 0 より大きい場合はその数のフレームを描画したら自動的に終了する
// (ヘッドレス CI でのスモークテスト用、SDL_VIDEODRIVER=dummy と組み合わせて使う)。
// frames が 0 の場合はウィンドウを閉じる操作(SDL_QUIT)があるまで描画し続ける。
fn run_test_screen(frames: int) void = {
	const v = match (video_init(TEST_SCREEN_SCALE)) {
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
	let frames = 0;

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
		case "--frames" =>
			i += 1;
			if (i >= len(args)) {
				fmt::fatal("--frames requires an argument");
			};
			frames = match (strconv::stoi(args[i])) {
			case let n: int =>
				yield n;
			case =>
				fmt::fatal("invalid --frames value: {}", args[i]);
			};
		case =>
			fmt::fatal("unknown option: {}", args[i]);
		};
	};

	if (test_screen) {
		run_test_screen(frames);
		return;
	};

	if (test_audio) {
		run_test_audio(frames);
		return;
	};

	print_usage();
};
