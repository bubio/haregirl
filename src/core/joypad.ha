// joypad.ha: FF00 (P1/JOYP) register. The d-pad (P14 selected) and buttons
// (P15 selected) are combined as separate 4-bit active-low outputs. When a
// button is pressed, request INT_JOYPAD only if its row is selected, as on hardware.

export const JOYPAD_RIGHT: u8 = 0x01;
export const JOYPAD_LEFT: u8 = 0x02;
export const JOYPAD_UP: u8 = 0x04;
export const JOYPAD_DOWN: u8 = 0x08;
export const JOYPAD_A: u8 = 0x01;
export const JOYPAD_B: u8 = 0x02;
export const JOYPAD_SELECT: u8 = 0x04;
export const JOYPAD_START: u8 = 0x08;

// joypad_read returns the FF00 read value, combining the selection bits stored
// in bus.io[0x00] with the pressed state.
export fn joypad_read(bus: *Bus) u8 = {
	return 0xC0 | (bus.io[0x00] & 0x30) | joypad_output(bus);
};

fn joypad_output(bus: *Bus) u8 = {
	const select = bus.io[0x00] & 0x30;
	let bits: u8 = 0x0F;
	if ((select & 0x10) == 0) bits &= ~bus.btn_dpad & 0x0F;
	if ((select & 0x20) == 0) bits &= ~bus.btn_buttons & 0x0F;
	return bits;
};

fn joypad_request_falling_edges(bus: *Bus, old: u8) void = {
	const current = joypad_output(bus);
	if ((old & ~current & 0x0F) != 0) interrupt_request(bus, INT_JOYPAD);
};

// joypad_write_select applies an FF00 write; only the P14/P15 selection bits are writable.
export fn joypad_write_select(bus: *Bus, value: u8) void = {
	const old = joypad_output(bus);
	bus.io[0x00] = (bus.io[0x00] & 0x0F) | (value & 0x30);
	joypad_request_falling_edges(bus, old);
};

// joypad_set_dpad/joypad_set_buttons set the current pressed state in bulk
// (a corresponding bit of 1 means pressed). Request an interrupt when a newly
// pressed button belongs to the selected row.
export fn joypad_set_dpad(bus: *Bus, state: u8) void = {
	const old = joypad_output(bus);
	bus.btn_dpad = state & 0x0F;
	joypad_request_falling_edges(bus, old);
};

export fn joypad_set_buttons(bus: *Bus, state: u8) void = {
	const old = joypad_output(bus);
	bus.btn_buttons = state & 0x0F;
	joypad_request_falling_edges(bus, old);
};
