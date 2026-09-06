// audio.ha: Minimal SDL2 audio bindings. Audio is pushed by setting callback
// to null and supplying samples through SDL_QueueAudio.
use types::c;

export def INIT_AUDIO: u32 = 0x00000010;
export def AUDIO_S16SYS: u16 = 0x8010; // AUDIO_S16LSB on little-endian hosts

export type audio_spec = struct {
	freq: int,
	format: u16,
	channels: u8,
	silence: u8,
	samples: u16,
	padding: u16,
	buf_size: u32,
	callback: nullable *opaque,
	userdata: nullable *opaque,
};

export @symbol("SDL_OpenAudioDevice") fn open_audio_device(
	device: nullable *const c::char,
	iscapture: int,
	desired: *audio_spec,
	obtained: *audio_spec,
	allowed_changes: int,
) u32;

export @symbol("SDL_CloseAudioDevice") fn close_audio_device(dev: u32) void;
export @symbol("SDL_PauseAudioDevice") fn pause_audio_device(dev: u32, pause_on: int) void;
export @symbol("SDL_QueueAudio") fn queue_audio(dev: u32, data: *opaque, nbytes: u32) int;
export @symbol("SDL_GetQueuedAudioSize") fn get_queued_audio_size(dev: u32) u32;
export @symbol("SDL_ClearQueuedAudio") fn clear_queued_audio(dev: u32) void;
