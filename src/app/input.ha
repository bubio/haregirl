// Keyboard and SDL2 GameController input. Controller bindings match BubiBoyLite:
// d-pad/left stick, SDL B=GB A, SDL A=GB B, Start=Start, Back=Select.
use core;
use sdl;

export type Input_State = struct {
	key_dpad: u8,
	key_buttons: u8,
	pad_dpad: u8,
	pad_buttons: u8,
	axis_dpad: u8,
	save_state_requested: bool,
	load_state_requested: bool,
};

export type Controller_Manager = struct {
	handle: nullable *sdl::game_controller,
	instance_id: i32,
};

def CONTROLLER_DEADZONE: i16 = 8000;

fn set_mask(value: *u8, mask: u8, pressed: bool) void = {
	if (pressed) *value |= mask else *value &= ~mask;
};

fn input_set_key(st: *Input_State, sc: i32, pressed: bool) void = {
	let mask: u8 = 0;
	let is_dpad = false;
	switch (sc) {
	case sdl::SCANCODE_RIGHT => mask = core::JOYPAD_RIGHT; is_dpad = true;
	case sdl::SCANCODE_LEFT => mask = core::JOYPAD_LEFT; is_dpad = true;
	case sdl::SCANCODE_UP => mask = core::JOYPAD_UP; is_dpad = true;
	case sdl::SCANCODE_DOWN => mask = core::JOYPAD_DOWN; is_dpad = true;
	case sdl::SCANCODE_Z => mask = core::JOYPAD_A;
	case sdl::SCANCODE_X => mask = core::JOYPAD_B;
	case sdl::SCANCODE_RETURN => mask = core::JOYPAD_START;
	case sdl::SCANCODE_RSHIFT => mask = core::JOYPAD_SELECT;
	case => return;
	};
	set_mask(if (is_dpad) &st.key_dpad else &st.key_buttons, mask, pressed);
};

fn input_set_controller_button(st: *Input_State, button: u8, pressed: bool) void = {
	let mask: u8 = 0;
	let is_dpad = false;
	switch (button: i32) {
	case sdl::controller_button::DPAD_RIGHT: i32 => mask = core::JOYPAD_RIGHT; is_dpad = true;
	case sdl::controller_button::DPAD_LEFT: i32 => mask = core::JOYPAD_LEFT; is_dpad = true;
	case sdl::controller_button::DPAD_UP: i32 => mask = core::JOYPAD_UP; is_dpad = true;
	case sdl::controller_button::DPAD_DOWN: i32 => mask = core::JOYPAD_DOWN; is_dpad = true;
	case sdl::controller_button::B: i32 => mask = core::JOYPAD_A;
	case sdl::controller_button::A: i32 => mask = core::JOYPAD_B;
	case sdl::controller_button::START: i32 => mask = core::JOYPAD_START;
	case sdl::controller_button::BACK: i32 => mask = core::JOYPAD_SELECT;
	case => return;
	};
	set_mask(if (is_dpad) &st.pad_dpad else &st.pad_buttons, mask, pressed);
};

fn input_set_controller_axis(st: *Input_State, axis: u8, value: i16) void = {
	let positive: u8 = 0;
	let negative: u8 = 0;
	switch (axis: i32) {
	case sdl::controller_axis::LEFTX: i32 =>
		positive = core::JOYPAD_RIGHT; negative = core::JOYPAD_LEFT;
	case sdl::controller_axis::LEFTY: i32 =>
		positive = core::JOYPAD_DOWN; negative = core::JOYPAD_UP;
	case => return;
	};
	st.axis_dpad &= ~(positive | negative);
	if (value > CONTROLLER_DEADZONE) st.axis_dpad |= positive
	else if (value < -CONTROLLER_DEADZONE) st.axis_dpad |= negative;
};

fn controller_try_open(mgr: *Controller_Manager, device_index: int) void = {
	if (mgr.handle is *sdl::game_controller) return;
	const handle = match (sdl::game_controller_open(device_index)) {
	case let handle: *sdl::game_controller => yield handle;
	case null => return;
	};
	mgr.handle = handle;
	mgr.instance_id = sdl::joystick_instance_id(sdl::game_controller_get_joystick(handle));
};

export fn controller_open_first(mgr: *Controller_Manager) void = {
	const count = sdl::num_joysticks();
	for (let i = 0; i < count; i += 1) {
		if (sdl::is_game_controller(i) != 0) controller_try_open(mgr, i);
		if (mgr.handle is *sdl::game_controller) return;
	};
};

export fn controller_destroy(mgr: *Controller_Manager) void = {
	match (mgr.handle) {
	case let handle: *sdl::game_controller => sdl::game_controller_close(handle);
	case null => void;
	};
	mgr.handle = null;
};

fn controller_removed(mgr: *Controller_Manager, st: *Input_State, instance_id: i32) void = {
	if (mgr.handle is null || mgr.instance_id != instance_id) return;
	controller_destroy(mgr);
	mgr.instance_id = 0;
	st.pad_dpad = 0;
	st.pad_buttons = 0;
	st.axis_dpad = 0;
};

export fn input_poll(bus: *core::Bus, st: *Input_State, mgr: *Controller_Manager) bool = {
	st.save_state_requested = false;
	st.load_state_requested = false;
	let ev = sdl::event { pad = [0...] };
	let quit = false;
	for (sdl::poll_event(&ev) != 0) {
		switch (ev.type_) {
		case sdl::event_type::QUIT: u32 => quit = true;
		case sdl::event_type::KEYDOWN: u32 =>
			if (ev.key.keysym.scancode == sdl::SCANCODE_ESCAPE) quit = true;
			if (ev.key.repeat == 0 && ev.key.keysym.scancode == sdl::SCANCODE_F5)
				st.save_state_requested = true;
			if (ev.key.repeat == 0 && ev.key.keysym.scancode == sdl::SCANCODE_F7)
				st.load_state_requested = true;
			input_set_key(st, ev.key.keysym.scancode, true);
		case sdl::event_type::KEYUP: u32 => input_set_key(st, ev.key.keysym.scancode, false);
		case sdl::event_type::CONTROLLERDEVICEADDED: u32 =>
			if (sdl::is_game_controller(ev.cdevice.which) != 0)
				controller_try_open(mgr, ev.cdevice.which);
		case sdl::event_type::CONTROLLERDEVICEREMOVED: u32 =>
			controller_removed(mgr, st, ev.cdevice.which);
		case sdl::event_type::CONTROLLERBUTTONDOWN: u32 =>
			input_set_controller_button(st, ev.cbutton.button, true);
		case sdl::event_type::CONTROLLERBUTTONUP: u32 =>
			input_set_controller_button(st, ev.cbutton.button, false);
		case sdl::event_type::CONTROLLERAXISMOTION: u32 =>
			input_set_controller_axis(st, ev.caxis.axis, ev.caxis.value);
		case => void;
		};
	};
	core::joypad_set_dpad(bus, st.key_dpad | st.pad_dpad | st.axis_dpad);
	core::joypad_set_buttons(bus, st.key_buttons | st.pad_buttons);
	return quit;
};
