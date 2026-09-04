// rom.ha: ROM ファイルを読み込んで実行する(フェーズ9: 「ROM 起動、入力、終了が
// CLI から完結する」の本体)。SDL2 ウィンドウへ PPU のフレームバッファを描画し、
// SDL2 音声デバイスへ APU のサンプルを流し、キーボード入力をジョイパッドへ渡す。
// 電池バックアップ RAM を持つカートリッジは ROM と同じディレクトリの
// "<rom>.sav" から読み込み、終了時に書き戻す。

use core;
use fmt;
use fs;
use io;
use os;
use sdl;
use strings;

// apply_apu_power_up は実機のブートROMが行うAPUレジスタの初期化を代替する。
// core::apu_reset は全レジスタを0にするが、実機はブートROM実行後
// NR52(電源)・NR50(マスター音量)・NR51(左右振り分)・各チャンネルの
// デフォルト値が設定済みの状態でゲーム本体に処理を渡す。多くの市販ROMは
// 「起動時点で音源は既に有効」という前提でチャンネルのトリガーのみを行い、
// これらのレジスタ自体を書き換えないため、ブートROMを実行しないHareGirlでは
// 明示的に投入しないと常時無音になる(NR52を最初に書いて電源を入れないと、
// 他のレジスタへの書き込みは無視される点に注意)。
// テストROM実行に使われる core::rom_runner_init 自体は変更しない
// (テストROMは自前で全レジスタを設定するため不要かつ、既存の合格テストへの
// 回帰リスクを避けるため)。
fn apply_apu_power_up(bus: *core::Bus) void = {
	core::bus_write(bus, 0xFF26, 0xF1); // NR52: 電源ON(以降のレジスタ書き込みが有効になる)
	core::bus_write(bus, 0xFF10, 0x80); // NR10
	core::bus_write(bus, 0xFF11, 0xBF); // NR11
	core::bus_write(bus, 0xFF12, 0xF3); // NR12
	core::bus_write(bus, 0xFF14, 0xBF); // NR14
	core::bus_write(bus, 0xFF16, 0x3F); // NR21
	core::bus_write(bus, 0xFF17, 0x00); // NR22
	core::bus_write(bus, 0xFF19, 0xBF); // NR24
	core::bus_write(bus, 0xFF1A, 0x7F); // NR30
	core::bus_write(bus, 0xFF1B, 0xFF); // NR31
	core::bus_write(bus, 0xFF1C, 0x9F); // NR32
	core::bus_write(bus, 0xFF1E, 0xBF); // NR34
	core::bus_write(bus, 0xFF20, 0xFF); // NR41
	core::bus_write(bus, 0xFF21, 0x00); // NR42
	core::bus_write(bus, 0xFF22, 0x00); // NR43
	core::bus_write(bus, 0xFF23, 0xBF); // NR44
	core::bus_write(bus, 0xFF24, 0x77); // NR50: マスター音量(左右ともフル)
	core::bus_write(bus, 0xFF25, 0xF3); // NR51: 左右チャンネル振り分け
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

// frame_to_argb は PPU のフレームバッファ(DMG: 0-3 のシェードID、CGB: 0xRRGGBB)を
// video_present が要求する ARGB8888 のピクセル列へ変換する。
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

// run_rom は rom_path のROMを実行し続ける。ウィンドウを閉じるか Escape キーで
// 終了する。frames > 0 の場合はその数のフレーム描画後に自動終了する
// (ヘッドレスCIでのスモークテスト用)。
export fn run_rom(rom_path: str, scale: int, frames: int) void = {
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

	const v = match (video_init(scale)) {
	case let v: video =>
		yield v;
	case void =>
		save_battery_ram(&runner.bus, save_path);
		os::exit(1);
	};
	defer video_destroy(&v);

	let fb: []u32 = alloc([0...], (SCREEN_WIDTH * SCREEN_HEIGHT): size)!;
	defer free(fb);

	let input: Input_State = Input_State { ... };
	let rendered = 0;
	for (true) {
		if (input_poll(&runner.bus, &input)) break;

		const frame_cycles = if (runner.bus.double_speed)
			core::CYCLES_PER_FRAME * 2 else core::CYCLES_PER_FRAME;
		const target = runner.bus.cycles + frame_cycles;
		for (runner.bus.cycles < target) {
			core::rom_runner_step(&runner);
		};

		frame_to_argb(&runner.bus, fb);
		video_present(&v, fb);

		const samples = core::apu_take_samples(&runner.bus);
		defer free(samples);
		if (len(samples) > 0) {
			sdl::queue_audio(dev, samples: *[*]i16: *opaque,
				(len(samples) * size(i16)): u32);
		};

		// run_test_screen/run_test_audio (フェーズ1/6) 同様、実時間の
		// フレーム間隔(約16ms/60fps)に合わせて進行を待つ。これが無いと
		// CPUが許す限りの速度でエミュレーションが進んでしまう(実機の
		// 何倍もの速さでゲームが進行し、音声もキューに溜まり続けて
		// 実時間再生と噛み合わなくなる)。
		sdl::delay(16);

		rendered += 1;
		if (frames > 0 && rendered >= frames) break;
	};

	save_battery_ram(&runner.bus, save_path);
};
