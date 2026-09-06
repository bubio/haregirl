// event.ha: Event polling, SDL_QUIT detection, and keyboard scan codes for
// KEYDOWN/KEYUP events (phase 9: keyboard alternative for gamepad input).

export type event_type = enum u32 {
	QUIT = 0x100,
	KEYDOWN = 0x300,
	KEYUP = 0x301,
	CONTROLLERAXISMOTION = 0x650,
	CONTROLLERBUTTONDOWN = 0x651,
	CONTROLLERBUTTONUP = 0x652,
	CONTROLLERDEVICEADDED = 0x653,
	CONTROLLERDEVICEREMOVED = 0x654,
};

// Common scan codes (SDL_Scancode values). Map the arrow keys and Z/X/Enter/
// Right Shift to the Game Boy d-pad/A/B/Start/Select respectively.
export def SCANCODE_RETURN: i32 = 40;
export def SCANCODE_RSHIFT: i32 = 229;
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
// Layout order is padding3 followed by keysym.
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

export type controller_axis_event = struct {
	type_: u32, timestamp: u32, which: i32, axis: u8,
	padding1: u8, padding2: u8, padding3: u8, value: i16, padding4: u16,
};
export type controller_button_event = struct {
	type_: u32, timestamp: u32, which: i32, button: u8,
	state: u8, padding1: u8, padding2: u8,
};
export type controller_device_event = struct {
	type_: u32, timestamp: u32, which: i32,
};

// SDL_Event is a 56-byte C union (sizeof(SDL_Event) == 56, verified with SDL2 2.26).
export type event = union {
	type_: u32,
	key: keyboard_event,
	caxis: controller_axis_event,
	cbutton: controller_button_event,
	cdevice: controller_device_event,
	pad: [56]u8,
};

export @symbol("SDL_PollEvent") fn poll_event(ev: *event) int;
