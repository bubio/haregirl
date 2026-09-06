// Minimal SDL2 GameController bindings used by HareGirl.
export type game_controller = opaque;
export type joystick = opaque;

export type controller_axis = enum i32 { LEFTX = 0, LEFTY = 1 };
export type controller_button = enum i32 {
	A = 0, B = 1, BACK = 4, START = 6,
	DPAD_UP = 11, DPAD_DOWN = 12, DPAD_LEFT = 13, DPAD_RIGHT = 14,
};

export @symbol("SDL_NumJoysticks") fn num_joysticks() int;
export @symbol("SDL_IsGameController") fn is_game_controller(index: int) int;
export @symbol("SDL_GameControllerOpen") fn game_controller_open(index: int) nullable *game_controller;
export @symbol("SDL_GameControllerClose") fn game_controller_close(controller: *game_controller) void;
export @symbol("SDL_GameControllerGetJoystick") fn game_controller_get_joystick(controller: *game_controller) *joystick;
export @symbol("SDL_JoystickInstanceID") fn joystick_instance_id(joystick: *joystick) i32;
