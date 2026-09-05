// 設定ファイル: 置き場所はOSの習慣(XDG Base Directory)に従う。
// $XDG_CONFIG_HOME/HareGirl/config.ini (未設定時は $HOME/.config/HareGirl/config.ini)
// に "key=value" 形式の単純なテキストとして保存する。

use bufio;
use fmt;
use fs;
use io;
use os;
use strconv;
use strings;

export type Settings = struct {
	// --test-screen のウィンドウ表示倍率(160x144 の何倍か)。
	scale: int,
	// 音量(0-100)。src/app の音声出力(フェーズ9予定)が参照する想定。
	volume: int,
	smooth: bool,
};

export fn settings_default() Settings = Settings {
	scale = 4,
	volume = 100,
	smooth = false,
};

// settings_path は設定ファイルの既定パスを返す。$HOME/$XDG_CONFIG_HOME を
// 解決できない場合は void を返す。
export fn settings_path() (str | void) = {
	const base = match (os::getenv("XDG_CONFIG_HOME")) {
	case let v: str =>
		yield v;
	case void =>
		const home = match (os::getenv("HOME")) {
		case let v: str =>
			yield v;
		case void =>
			return void;
		};
		yield fmt::asprintf("{}/.config", home)!;
	};
	return fmt::asprintf("{}/HareGirl/config.ini", base)!;
};

// settings_load は path の設定ファイルを読み込む。ファイルが存在しない、
// または壊れている場合は既定値を返す(実行不能なエラーにはしない)。
export fn settings_load(path: str) Settings = {
	let s = settings_default();
	const file = match (os::open(path)) {
	case let f: io::file =>
		yield f;
	case fs::error =>
		return s;
	};
	defer io::close(file)!;

	for (true) {
		const line = match (bufio::read_line(file)) {
		case let line: []u8 =>
			yield line;
		case io::EOF =>
			break;
		case =>
			break;
		};
		defer free(line);
		const text = strings::fromutf8(line)!;
		settings_parse_line(&s, text);
	};
	return s;
};

fn settings_parse_line(s: *Settings, line: str) void = {
	const trimmed = strings::trim(line);
	if (len(trimmed) == 0 || strings::hasprefix(trimmed, "#")) return;
	const idx = match (strings::index(trimmed, "=")) {
	case let i: size =>
		yield i;
	case void =>
		return;
	};
	const key = strings::trim(strings::sub(trimmed, 0, idx));
	const value = strings::trim(strings::sub(trimmed, idx + 1, strings::end));
	switch (key) {
	case "scale" =>
		match (strconv::stoi(value)) {
		case let n: int =>
			if (n > 0) s.scale = if (n > 8) 8 else n;
		case => void;
		};
	case "volume" =>
		match (strconv::stoi(value)) {
		case let n: int =>
			if (n >= 0 && n <= 100) s.volume = n;
		case => void;
		};
	case "shader" =>
		if (value == "smooth") s.smooth = true;
		if (value == "nearest") s.smooth = false;
	case => void;
	};
};

// settings_save は path の親ディレクトリを必要に応じて作成し、s の内容を
// "key=value" 形式で書き出す。
export fn settings_save(path: str, s: Settings) (void | fs::error) = {
	const dir = match (strings::rindex(path, "/")) {
	case let i: size =>
		yield strings::sub(path, 0, i);
	case void =>
		yield ".";
	};
	if (dir != "." && !os::exists(dir)) {
		os::mkdirs(dir, 0o755)?;
	};

	const file = os::create(path, 0o644)?;
	defer io::close(file)!;
	fmt::fprintf(file, "scale={}\nvolume={}\nshader={}\n", s.scale, s.volume,
		if (s.smooth) "smooth" else "nearest")!;
};
