// event.ha: イベントポーリング。フェーズ1ではウィンドウを閉じる操作(SDL_QUIT)の
// 検出のみに使う。キー入力の詳細なデコードはフェーズ9(入力・フロントエンド)で扱う。

export type event_type = enum u32 {
	QUIT = 0x100,
};

// SDL_Event は C 側で 56 バイトの共用体(sizeof(SDL_Event) == 56、SDL2 2.26 で確認済み)。
// ここでは先頭の type フィールドだけを見るため、サイズだけ合わせたパディングを持つ
// 最小限の定義にする。
export type event = union {
	type_: u32,
	pad: [56]u8,
};

export @symbol("SDL_PollEvent") fn poll_event(ev: *event) int;
