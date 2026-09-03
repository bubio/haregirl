use fmt;
use os;
use sdl;
use strconv;

const version: str = "0.1.0";

// TEST_SCREEN_SCALE は --test-screen で開くウィンドウの表示倍率(160x144 の何倍か)。
const TEST_SCREEN_SCALE: int = 4;

fn print_usage() void = {
	fmt::println("Usage: HareGirl [--version] [--help] [--test-screen [--frames N]]")!;
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

	print_usage();
};
