// event.ha: イベントポーリング。SDL_QUIT の検出とキーボードの押下/離す(KEYDOWN/
// KEYUP)のスキャンコード取得(フェーズ9: ゲームパッド入力のキーボード代替)を扱う。

export type event_type = enum u32 {
	QUIT = 0x100,
	KEYDOWN = 0x300,
	KEYUP = 0x301,
};

// よく使うスキャンコード(SDL_Scancode の値)。方向キーと Z/X/Enter/Backspace を
// それぞれ Game Boy の十字キー/A/B/Start/Select に割り当てる。
export def SCANCODE_RETURN: i32 = 40;
export def SCANCODE_BACKSPACE: i32 = 42;
export def SCANCODE_RIGHT: i32 = 79;
export def SCANCODE_LEFT: i32 = 80;
export def SCANCODE_DOWN: i32 = 81;
export def SCANCODE_UP: i32 = 82;
export def SCANCODE_Z: i32 = 29;
export def SCANCODE_X: i32 = 27;
export def SCANCODE_ESCAPE: i32 = 41;

export type keysym = struct {
	scancode: i32,
	sym: i32,
	mod: u16,
	unused: u32,
};

// SDL_KeyboardEvent (SDL2): type/timestamp/windowID/state/repeat/padding2/
// padding3/keysym の順のレイアウト。
export type keyboard_event = struct {
	type_: u32,
	timestamp: u32,
	window_id: u32,
	state: u8,
	repeat: u8,
	padding2: u8,
	padding3: u8,
	keysym: keysym,
};

// SDL_Event は C 側で 56 バイトの共用体(sizeof(SDL_Event) == 56、SDL2 2.26 で確認済み)。
export type event = union {
	type_: u32,
	key: keyboard_event,
	pad: [56]u8,
};

export @symbol("SDL_PollEvent") fn poll_event(ev: *event) int;
