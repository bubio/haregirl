// render.ha: SDL_Renderer / SDL_Texture の生成・描画。

export type renderer = opaque;
export type texture = opaque;

export type renderer_flags = enum u32 {
	NONE = 0x00000000,
	SOFTWARE = 0x00000001,
	ACCELERATED = 0x00000002,
	PRESENTVSYNC = 0x00000004,
};

// SDL_PIXELFORMAT_ARGB8888(SDL_pixels.h)。
export def PIXELFORMAT_ARGB8888: u32 = 0x16362004;

export type texture_access = enum int {
	STATIC = 0,
	STREAMING = 1,
	TARGET = 2,
};

export type scale_mode = enum int {
	NEAREST = 0,
	LINEAR = 1,
};

export @symbol("SDL_CreateRenderer") fn create_renderer(
	win: *window,
	index: int,
	flags: u32,
) nullable *renderer;

export @symbol("SDL_DestroyRenderer") fn destroy_renderer(rend: *renderer) void;

export @symbol("SDL_CreateTexture") fn create_texture(
	rend: *renderer,
	format: u32,
	access: int,
	w: int,
	h: int,
) nullable *texture;

export @symbol("SDL_DestroyTexture") fn destroy_texture(tex: *texture) void;

export @symbol("SDL_SetTextureScaleMode") fn set_texture_scale_mode(
	tex: *texture,
	mode: scale_mode,
) int;

export @symbol("SDL_UpdateTexture") fn update_texture(
	tex: *texture,
	rect: nullable *rect,
	pixels: *const opaque,
	pitch: int,
) int;

export @symbol("SDL_SetRenderDrawColor") fn set_render_draw_color(
	rend: *renderer,
	r: u8,
	g: u8,
	b: u8,
	a: u8,
) int;

export @symbol("SDL_RenderClear") fn render_clear(rend: *renderer) int;

export @symbol("SDL_RenderCopy") fn render_copy(
	rend: *renderer,
	tex: *texture,
	srcrect: nullable *rect,
	dstrect: nullable *rect,
) int;

export @symbol("SDL_RenderPresent") fn render_present(rend: *renderer) void;
