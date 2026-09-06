// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.

use fmt;
use sdl;
use types::c;

export def SCREEN_WIDTH: int = 160;
export def SCREEN_HEIGHT: int = 144;

export type video = struct {
	win:  *sdl::window,
	rend: *sdl::renderer,
	tex:  *sdl::texture,
};

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
export fn video_init(scale: int, smooth: bool) (video | void) = {
	if (sdl::init(sdl::INIT_VIDEO | sdl::INIT_GAMECONTROLLER) != 0) {
		fmt::errorfln("SDL_Init に失敗しました: {}", c::tostr_unsafe(sdl::get_error()))!;
		return;
	};

	const title = match (c::fromstr("HareGirl")) {
	case let t: *c::char =>
		yield t;
	case nomem =>
		fmt::errorln("メモリ不足のためウィンドウタイトルを確保できませんでした")!;
		sdl::quit();
		return;
	};
	defer free(title);

	const w = SCREEN_WIDTH * scale;
	const h = SCREEN_HEIGHT * scale;
	const win = match (sdl::create_window(
		title,
		sdl::WINDOWPOS_CENTERED,
		sdl::WINDOWPOS_CENTERED,
		w, h,
		sdl::window_flags::SHOWN,
	)) {
	case let win: *sdl::window =>
		yield win;
	case null =>
		fmt::errorfln("SDL_CreateWindow に失敗しました: {}", c::tostr_unsafe(sdl::get_error()))!;
		sdl::quit();
		return;
	};

	const rend = match (sdl::create_renderer(win, -1, sdl::renderer_flags::ACCELERATED)) {
	case let rend: *sdl::renderer =>
		yield rend;
	case null =>
		// Comment translated to English.
		// Comment translated to English.
		yield match (sdl::create_renderer(win, -1, sdl::renderer_flags::NONE)) {
		case let rend: *sdl::renderer =>
			yield rend;
		case null =>
			fmt::errorfln("SDL_CreateRenderer に失敗しました: {}", c::tostr_unsafe(sdl::get_error()))!;
			sdl::destroy_window(win);
			sdl::quit();
			return;
		};
	};

	const tex = match (sdl::create_texture(
		rend,
		sdl::PIXELFORMAT_ARGB8888,
		sdl::texture_access::STREAMING: int,
		SCREEN_WIDTH, SCREEN_HEIGHT,
	)) {
	case let tex: *sdl::texture =>
		yield tex;
	case null =>
		fmt::errorfln("SDL_CreateTexture に失敗しました: {}", c::tostr_unsafe(sdl::get_error()))!;
		sdl::destroy_renderer(rend);
		sdl::destroy_window(win);
		sdl::quit();
		return;
	};
	const scale_mode = if (smooth) sdl::scale_mode::LINEAR else sdl::scale_mode::NEAREST;
	sdl::set_texture_scale_mode(tex, scale_mode);

	return video {
		win = win,
		rend = rend,
		tex = tex,
	};
};

// Comment translated to English.
// Comment translated to English.
// Comment translated to English.
export fn video_test_pattern(fb: []u32) void = {
	assert(len(fb) == (SCREEN_WIDTH * SCREEN_HEIGHT): size, "framebuffer size mismatch");
	for (let y = 0; y < SCREEN_HEIGHT; y += 1) {
		for (let x = 0; x < SCREEN_WIDTH; x += 1) {
			// Comment translated to English.
			let color: u32 = 0;
			if (y < SCREEN_HEIGHT / 2) {
				const r = (x * 256 / SCREEN_WIDTH): u32;
				color = 0xFF000000 | (r << 16);
			} else {
				const checker = ((x / 8) + (y / 8)) % 2;
				color = if (checker == 0) 0xFFFFFFFF else 0xFF3050C0;
			};
			fb[y * SCREEN_WIDTH + x] = color;
		};
	};
};

// Comment translated to English.
export fn video_present(v: *video, fb: []u32) void = {
	const pitch = (SCREEN_WIDTH: size * size(u32)): int;
	sdl::update_texture(v.tex, null, fb: *[*]u32: *opaque, pitch);
	sdl::render_clear(v.rend);
	sdl::render_copy(v.rend, v.tex, null, null);
	sdl::render_present(v.rend);
};

// Comment translated to English.
// Comment translated to English.
export fn video_should_quit() bool = {
	let ev = sdl::event { pad = [0...] };
	let quit = false;
	for (sdl::poll_event(&ev) != 0) {
		if (ev.type_ == sdl::event_type::QUIT: u32) {
			quit = true;
		};
	};
	return quit;
};

export fn video_destroy(v: *video) void = {
	sdl::destroy_texture(v.tex);
	sdl::destroy_renderer(v.rend);
	sdl::destroy_window(v.win);
	sdl::quit();
};
