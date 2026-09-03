// window.ha: SDL_Window の生成・破棄。
use types::c;

export type window = opaque;

export type window_flags = enum u32 {
	NONE = 0,
	SHOWN = 0x00000004,
	FULLSCREEN_DESKTOP = 0x00001001,
};

export def WINDOWPOS_CENTERED: int = 0x2FFF0000;

export @symbol("SDL_CreateWindow") fn create_window(
	title: *const c::char,
	x: int,
	y: int,
	w: int,
	h: int,
	flags: u32,
) nullable *window;

export @symbol("SDL_DestroyWindow") fn destroy_window(win: *window) void;
