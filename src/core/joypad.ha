// joypad.ha: FF00 (P1/JOYP) レジスタ。方向キー(P14 選択)とボタン(P15 選択)を
// それぞれ4bitのアクティブロー出力として合成する。ボタンが押された瞬間、対応する
// 行が選択されていれば INT_JOYPAD を要求する(実機同様、選択されていない行の押下は
// 割り込みを発生させない)。

export const JOYPAD_RIGHT: u8 = 0x01;
export const JOYPAD_LEFT: u8 = 0x02;
export const JOYPAD_UP: u8 = 0x04;
export const JOYPAD_DOWN: u8 = 0x08;
export const JOYPAD_A: u8 = 0x01;
export const JOYPAD_B: u8 = 0x02;
export const JOYPAD_SELECT: u8 = 0x04;
export const JOYPAD_START: u8 = 0x08;

// joypad_read は FF00 読み出し時の値を返す(bus.io[0x00] に保持された選択ビットと
// 押下状態から合成する)。
export fn joypad_read(bus: *Bus) u8 = {
	const select = bus.io[0x00] & 0x30;
	let bits: u8 = 0x0F;
	if ((select & 0x10) == 0) bits &= ~bus.btn_dpad & 0x0F;
	if ((select & 0x20) == 0) bits &= ~bus.btn_buttons & 0x0F;
	return 0xC0 | select | bits;
};

// joypad_write_select は FF00 書き込み(P14/P15 選択ビットのみが書き込み可能)を
// 反映する。
export fn joypad_write_select(bus: *Bus, value: u8) void = {
	bus.io[0x00] = (bus.io[0x00] & 0x0F) | (value & 0x30);
};

fn joypad_maybe_interrupt(bus: *Bus) void = {
	const select = bus.io[0x00] & 0x30;
	let bits: u8 = 0x0F;
	if ((select & 0x10) == 0) bits &= ~bus.btn_dpad & 0x0F;
	if ((select & 0x20) == 0) bits &= ~bus.btn_buttons & 0x0F;
	if (bits != 0x0F) interrupt_request(bus, INT_JOYPAD);
};

// joypad_set_dpad/joypad_set_buttons は現在の押下状態(該当ビットが1で押下)を
// まとめて設定する。新たに押されたボタンが選択中の行にあれば割り込みを要求する。
export fn joypad_set_dpad(bus: *Bus, state: u8) void = {
	bus.btn_dpad = state & 0x0F;
	joypad_maybe_interrupt(bus);
};

export fn joypad_set_buttons(bus: *Bus, state: u8) void = {
	bus.btn_buttons = state & 0x0F;
	joypad_maybe_interrupt(bus);
};
