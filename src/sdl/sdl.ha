// sdl provides minimal Hare bindings for SDL2.
//
// The existing hare-sdl2 bindings do not build with current Hare because they
// depend on obsolete error-handling/free syntax. Following docs/BluePrint.md,
// declare only the SDL2 surface actually used by HareGirl. Struct layouts mirror
// the SDL2 C headers, so names follow SDL rather than Hare conventions.
use types::c;

// Subsystem flags passed to SDL_Init.
export def INIT_VIDEO: u32 = 0x00000020;
export def INIT_GAMECONTROLLER: u32 = 0x00002000;

export @symbol("SDL_Init") fn init(flags: u32) int;
export @symbol("SDL_Quit") fn quit() void;
export @symbol("SDL_GetError") fn get_error() *const c::char;
export @symbol("SDL_Delay") fn delay(ms: u32) void;
