// input.ha: SDL2 のキーボードイベントを Game Boy ジョイパッド入力へ変換する
// (フェーズ9: ゲームパッド入力のキーボード代替)。
//
// 割り当て: 十字キー = 矢印キー、A = Z、B = X、Start = Enter、Select = 右Shift。
// Escape キーはウィンドウを閉じる操作と同様、終了要求として扱う。

use core;
use sdl;

export type Input_State = struct {
	dpad: u8,
	buttons: u8,
};

fn input_set_key(st: *Input_State, sc: i32, pressed: bool) void = {
	let mask: u8 = 0;
	let is_dpad = false;
	switch (sc) {
	case sdl::SCANCODE_RIGHT =>
		mask = core::JOYPAD_RIGHT; is_dpad = true;
	case sdl::SCANCODE_LEFT =>
		mask = core::JOYPAD_LEFT; is_dpad = true;
	case sdl::SCANCODE_UP =>
		mask = core::JOYPAD_UP; is_dpad = true;
	case sdl::SCANCODE_DOWN =>
		mask = core::JOYPAD_DOWN; is_dpad = true;
	case sdl::SCANCODE_Z =>
		mask = core::JOYPAD_A;
	case sdl::SCANCODE_X =>
		mask = core::JOYPAD_B;
	case sdl::SCANCODE_RETURN =>
		mask = core::JOYPAD_START;
	case sdl::SCANCODE_RSHIFT =>
		mask = core::JOYPAD_SELECT;
	case =>
		return;
	};
	if (is_dpad) {
		if (pressed) st.dpad |= mask else st.dpad &= ~mask;
	} else {
		if (pressed) st.buttons |= mask else st.buttons &= ~mask;
	};
};

// input_poll はイベントキューを排出し、ジョイパッド状態を bus へ反映する。
// 終了要求(SDL_QUIT または Escape キー)があれば true を返す。
export fn input_poll(bus: *core::Bus, st: *Input_State) bool = {
	let ev = sdl::event { pad = [0...] };
	let quit = false;
	for (sdl::poll_event(&ev) != 0) {
		switch (ev.type_) {
		case sdl::event_type::QUIT: u32 =>
			quit = true;
		case sdl::event_type::KEYDOWN: u32 =>
			if (ev.key.keysym.scancode == sdl::SCANCODE_ESCAPE) quit = true;
			input_set_key(st, ev.key.keysym.scancode, true);
		case sdl::event_type::KEYUP: u32 =>
			input_set_key(st, ev.key.keysym.scancode, false);
		case => void;
		};
	};
	core::joypad_set_dpad(bus, st.dpad);
	core::joypad_set_buttons(bus, st.buttons);
	return quit;
};
