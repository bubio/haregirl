// sdl は SDL2 の最低限の Hare バインディングを提供する。
//
// 既存のバインディング(hare-sdl2)は現行の Hare でビルドできない(古い Hare の
// エラーハンドリング/free 呼び出しの構文に依存している)ため、docs/BluePrint.md の
// 指示に従い HareGirl が実際に使う分だけを自前で宣言する。SDL2 の C ヘッダの構造体
// レイアウトをそのまま写しているため、命名は Hare の慣習より SDL の元名に合わせている。
use types::c;

// SDL_Init に渡すサブシステムフラグ。
export def INIT_VIDEO: u32 = 0x00000020;

export @symbol("SDL_Init") fn init(flags: u32) int;
export @symbol("SDL_Quit") fn quit() void;
export @symbol("SDL_GetError") fn get_error() *const c::char;
export @symbol("SDL_Delay") fn delay(ms: u32) void;
