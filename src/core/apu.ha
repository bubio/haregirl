// DMG APU (Audio Processing Unit) emulation: four sound channels (two pulse,
// one wave, one noise), the 512Hz frame sequencer that drives length/envelope/
// sweep, and a simple mixer that resamples the native 4.194304MHz output down
// to SAMPLE_RATE for real-time playback (src/app owns the actual audio
// device). Register read "OR masks" follow the standard DMG sound register
// table (unused bits read back as 1).

export def SAMPLE_RATE: u32 = 44100;

const DUTY_TABLE: [4][8]u8 = [
	[0, 0, 0, 0, 0, 0, 0, 1],
	[1, 0, 0, 0, 0, 0, 0, 1],
	[1, 0, 0, 0, 0, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 1, 0],
];

const NOISE_DIVISORS: [8]u16 = [8, 16, 32, 48, 64, 80, 96, 112];

export type Apu = struct {
	enabled: bool,
	frame_seq_step: u8,

	// Channel 1: pulse with frequency sweep.
	ch1_sweep_pace: u8,
	ch1_sweep_negate: bool,
	ch1_sweep_shift: u8,
	ch1_sweep_timer: u8,
	ch1_sweep_enabled: bool,
	ch1_sweep_neg_calc_done: bool,
	ch1_shadow_freq: u16,
	ch1_duty: u8,
	ch1_length: u16,
	ch1_length_enable: bool,
	ch1_env_initial: u8,
	ch1_env_dir: bool,
	ch1_env_period: u8,
	ch1_env_timer: u8,
	ch1_volume: u8,
	ch1_freq: u16,
	ch1_timer: u16,
	ch1_duty_pos: u8,
	ch1_dac_enabled: bool,
	ch1_enabled: bool,

	// Channel 2: pulse, no sweep.
	ch2_duty: u8,
	ch2_length: u16,
	ch2_length_enable: bool,
	ch2_env_initial: u8,
	ch2_env_dir: bool,
	ch2_env_period: u8,
	ch2_env_timer: u8,
	ch2_volume: u8,
	ch2_freq: u16,
	ch2_timer: u16,
	ch2_duty_pos: u8,
	ch2_dac_enabled: bool,
	ch2_enabled: bool,

	// Channel 3: wave.
	ch3_dac_enabled: bool,
	wave_ram: [16]u8,
	ch3_length: u16,
	ch3_length_enable: bool,
	ch3_volume_code: u8,
	ch3_freq: u16,
	ch3_timer: u16,
	ch3_pos: u8,
	ch3_enabled: bool,

	// Channel 4: noise.
	ch4_length: u16,
	ch4_length_enable: bool,
	ch4_env_initial: u8,
	ch4_env_dir: bool,
	ch4_env_period: u8,
	ch4_env_timer: u8,
	ch4_volume: u8,
	ch4_clock_shift: u8,
	ch4_width_mode: bool,
	ch4_divisor_code: u8,
	ch4_timer: u16,
	ch4_lfsr: u16,
	ch4_dac_enabled: bool,
	ch4_enabled: bool,

	// Mixer (NR50/NR51).
	nr50: u8,
	nr51: u8,

	// Resampling: fractional accumulator driving CPU_HZ -> SAMPLE_RATE
	// decimation (Bresenham-style, exact on average).
	sample_acc: u64,
	samples: []i16,
};

export fn apu_reset(a: *Apu) void = {
	*a = Apu { ... };
	a.ch4_lfsr = 0x7FFF;
};

fn apu_ch1_freq_period(a: *Apu) u16 = (2048 - a.ch1_freq) * 4;
fn apu_ch2_freq_period(a: *Apu) u16 = (2048 - a.ch2_freq) * 4;
fn apu_ch3_freq_period(a: *Apu) u16 = (2048 - a.ch3_freq) * 2;

// apu_periodic_wraps advances a channel's down-counting frequency timer by
// `dots` hardware cycles in one shot and returns how many times it reloaded
// (equivalent to calling the old one-cycle-at-a-time step function `dots`
// times: decrement, and on reaching 0 reload to `period` and count a wrap).
// This turns what used to be an O(cycles-per-frame) loop (the dominant cost
// of apu_tick, since it ran on every single hardware dot of every frame) into
// O(1) math, since `timer` always stays in [1, period] between calls so the
// number of reloads within a span is a plain division.
fn apu_periodic_wraps(timer: *u16, period: u16, dots: u64) u64 = {
	if (dots == 0) return 0;
	if (period == 0) {
		// Pre-existing edge case, not introduced by this closed-form
		// rewrite: high noise divisor*clock-shift combinations overflow the
		// u16 storage used for ch4_timer/period and truncate to 0. The old
		// per-dot code just kept re-assigning timer=0 and shifting the LFSR
		// every single dot in that case; reproduce that instead of dividing
		// by zero.
		*timer = 0;
		return dots;
	};
	if (dots < (*timer: u64)) {
		*timer -= (dots: u16);
		return 0;
	};
	const remaining = dots - (*timer: u64);
	const wraps = 1 + remaining / (period: u64);
	*timer = period - ((remaining % (period: u64)): u16);
	return wraps;
};

fn apu_ch1_advance(a: *Apu, dots: u64) void = {
	if (!a.ch1_enabled) return;
	if (dots < a.ch1_timer: u64) {
		a.ch1_timer -= dots: u16;
		return;
	};
	const wraps = apu_periodic_wraps(&a.ch1_timer, apu_ch1_freq_period(a), dots);
	a.ch1_duty_pos = (((a.ch1_duty_pos: u64) + wraps) % 8): u8;
};

fn apu_ch2_advance(a: *Apu, dots: u64) void = {
	if (!a.ch2_enabled) return;
	if (dots < a.ch2_timer: u64) {
		a.ch2_timer -= dots: u16;
		return;
	};
	const wraps = apu_periodic_wraps(&a.ch2_timer, apu_ch2_freq_period(a), dots);
	a.ch2_duty_pos = (((a.ch2_duty_pos: u64) + wraps) % 8): u8;
};

fn apu_ch3_advance(a: *Apu, dots: u64) void = {
	if (!a.ch3_enabled) return;
	if (dots < a.ch3_timer: u64) {
		a.ch3_timer -= dots: u16;
		return;
	};
	const wraps = apu_periodic_wraps(&a.ch3_timer, apu_ch3_freq_period(a), dots);
	a.ch3_pos = (((a.ch3_pos: u64) + wraps) % 32): u8;
};

// Channel 4's LFSR is a true shift register (each reload depends on the
// previous state), so it cannot be jumped to with closed-form math like the
// other channels' duty/wave position counters; only the reload *count* can
// (via apu_periodic_wraps), and the shift itself still runs once per reload.
// In practice `wraps` is 0 or 1 for the small per-instruction cycle counts
// apu_tick is normally called with, so this is no longer a per-dot loop.
fn apu_ch4_advance(a: *Apu, dots: u64) void = {
	if (!a.ch4_enabled) return;
	const period = NOISE_DIVISORS[a.ch4_divisor_code] << a.ch4_clock_shift;
	// A zero period has special legacy behavior in apu_periodic_wraps;
	// retain it even if a previous register setting left a nonzero timer.
	if (period != 0 && dots < a.ch4_timer: u64) {
		a.ch4_timer -= dots: u16;
		return;
	};
	const wraps = apu_periodic_wraps(&a.ch4_timer, period, dots);
	for (let i = 0u64; i < wraps; i += 1) {
		const bit = (a.ch4_lfsr & 1) ^ ((a.ch4_lfsr >> 1) & 1);
		a.ch4_lfsr = (a.ch4_lfsr >> 1) | (bit << 14);
		if (a.ch4_width_mode) {
			a.ch4_lfsr &= ~(1u16 << 6);
			a.ch4_lfsr |= bit << 6;
		};
	};
};

fn apu_length_clock(a: *Apu) void = {
	if (a.ch1_length_enable && a.ch1_length > 0) {
		a.ch1_length -= 1;
		if (a.ch1_length == 0) a.ch1_enabled = false;
	};
	if (a.ch2_length_enable && a.ch2_length > 0) {
		a.ch2_length -= 1;
		if (a.ch2_length == 0) a.ch2_enabled = false;
	};
	if (a.ch3_length_enable && a.ch3_length > 0) {
		a.ch3_length -= 1;
		if (a.ch3_length == 0) a.ch3_enabled = false;
	};
	if (a.ch4_length_enable && a.ch4_length > 0) {
		a.ch4_length -= 1;
		if (a.ch4_length == 0) a.ch4_enabled = false;
	};
};

fn apu_envelope_clock(a: *Apu) void = {
	if (a.ch1_env_period > 0) {
		if (a.ch1_env_timer > 0) a.ch1_env_timer -= 1;
		if (a.ch1_env_timer == 0) {
			a.ch1_env_timer = a.ch1_env_period;
			if (a.ch1_env_dir && a.ch1_volume < 15) a.ch1_volume += 1
			else if (!a.ch1_env_dir && a.ch1_volume > 0) a.ch1_volume -= 1;
		};
	};
	if (a.ch2_env_period > 0) {
		if (a.ch2_env_timer > 0) a.ch2_env_timer -= 1;
		if (a.ch2_env_timer == 0) {
			a.ch2_env_timer = a.ch2_env_period;
			if (a.ch2_env_dir && a.ch2_volume < 15) a.ch2_volume += 1
			else if (!a.ch2_env_dir && a.ch2_volume > 0) a.ch2_volume -= 1;
		};
	};
	if (a.ch4_env_period > 0) {
		if (a.ch4_env_timer > 0) a.ch4_env_timer -= 1;
		if (a.ch4_env_timer == 0) {
			a.ch4_env_timer = a.ch4_env_period;
			if (a.ch4_env_dir && a.ch4_volume < 15) a.ch4_volume += 1
			else if (!a.ch4_env_dir && a.ch4_volume > 0) a.ch4_volume -= 1;
		};
	};
};

fn apu_sweep_calc(a: *Apu) u16 = {
	let delta = a.ch1_shadow_freq >> a.ch1_sweep_shift;
	if (a.ch1_sweep_negate) {
		a.ch1_sweep_neg_calc_done = true;
		if (delta > a.ch1_shadow_freq) return 0;
		return a.ch1_shadow_freq - delta;
	};
	return a.ch1_shadow_freq + delta;
};

fn apu_sweep_clock(a: *Apu) void = {
	if (!a.ch1_sweep_enabled) return;
	if (a.ch1_sweep_timer > 0) a.ch1_sweep_timer -= 1;
	if (a.ch1_sweep_timer != 0) return;
	a.ch1_sweep_timer = if (a.ch1_sweep_pace > 0) a.ch1_sweep_pace else 8;
	if (a.ch1_sweep_pace == 0) return;
	const new_freq = apu_sweep_calc(a);
	if (new_freq > 2047) {
		a.ch1_enabled = false;
		return;
	};
	if (a.ch1_sweep_shift > 0) {
		a.ch1_shadow_freq = new_freq;
		a.ch1_freq = new_freq;
		if (apu_sweep_calc(a) > 2047) a.ch1_enabled = false;
	};
};

fn apu_frame_sequencer_step(bus: *Bus) void = {
	const a = &bus.apu;
	a.frame_seq_step = (a.frame_seq_step + 1) % 8;
	switch (a.frame_seq_step) {
	case 0, 4 =>
		apu_length_clock(a);
	case 2, 6 =>
		apu_length_clock(a);
		apu_sweep_clock(a);
	case 7 =>
		apu_envelope_clock(a);
	case =>
		void;
	};
};

fn apu_ch1_amplitude(a: *Apu) i16 = {
	if (!a.ch1_enabled || !a.ch1_dac_enabled) return 0;
	const bit = DUTY_TABLE[a.ch1_duty][a.ch1_duty_pos];
	return if (bit != 0) (a.ch1_volume: i16) else -(a.ch1_volume: i16);
};

fn apu_ch2_amplitude(a: *Apu) i16 = {
	if (!a.ch2_enabled || !a.ch2_dac_enabled) return 0;
	const bit = DUTY_TABLE[a.ch2_duty][a.ch2_duty_pos];
	return if (bit != 0) (a.ch2_volume: i16) else -(a.ch2_volume: i16);
};

fn apu_ch3_amplitude(a: *Apu) i16 = {
	if (!a.ch3_enabled || !a.ch3_dac_enabled) return 0;
	const byte = a.wave_ram[a.ch3_pos / 2];
	const nibble = if (a.ch3_pos % 2 == 0) (byte >> 4) else (byte & 0x0F);
	let sample = (nibble: i16) - 8;
	switch (a.ch3_volume_code) {
	case 0 => sample = 0;
	case 1 => void;
	case 2 => sample >>= 1;
	case => sample >>= 2;
	};
	return sample;
};

fn apu_ch4_amplitude(a: *Apu) i16 = {
	if (!a.ch4_enabled || !a.ch4_dac_enabled) return 0;
	const bit = a.ch4_lfsr & 1;
	return if (bit == 0) (a.ch4_volume: i16) else -(a.ch4_volume: i16);
};

fn apu_mix_sample(bus: *Bus) (i16, i16) = {
	const a = &bus.apu;
	if (!a.enabled) return (0, 0);
	const c1 = apu_ch1_amplitude(a);
	const c2 = apu_ch2_amplitude(a);
	const c3 = apu_ch3_amplitude(a);
	const c4 = apu_ch4_amplitude(a);

	let left = 0i32;
	let right = 0i32;
	if ((a.nr51 & 0x01) != 0) right += c1;
	if ((a.nr51 & 0x10) != 0) left += c1;
	if ((a.nr51 & 0x02) != 0) right += c2;
	if ((a.nr51 & 0x20) != 0) left += c2;
	if ((a.nr51 & 0x04) != 0) right += c3;
	if ((a.nr51 & 0x40) != 0) left += c3;
	if ((a.nr51 & 0x08) != 0) right += c4;
	if ((a.nr51 & 0x80) != 0) left += c4;

	const left_vol = ((a.nr50 >> 4) & 0x07): i32;
	const right_vol = (a.nr50 & 0x07): i32;
	// Scale four -15..15 (ch3 is a narrower -8..7) channels through a 0..7
	// master volume into the i16 range. Worst case |left|/|right| before
	// scaling is about 4*15=60, so at the max master volume multiplier of
	// 8 that's up to 480; a per-step scale of 128 (480*128=61440) overflows
	// i16 (max 32767) and wraps around, which is heard as harsh
	// clipping/distortion at loud mixes. 64 keeps the peak (480*64=30720)
	// safely inside i16 range while still using nearly all of it.
	left = left * (left_vol + 1) * 64;
	right = right * (right_vol + 1) * 64;
	return (left: i16, right: i16);
};

export fn apu_tick(bus: *Bus, cycles: int) void = {
	if (cycles <= 0) return;

	// The frame sequencer is clocked from the falling edge of a bit of the
	// raw (CPU-rate) DIV counter. In CGB double speed mode DIV advances
	// twice as fast in CPU-cycle terms, so the relevant bit shifts up by
	// one to keep the real-world 512Hz rate unchanged.
	//
	// bus_tick is called once per bus access (a handful of cycles at a
	// time), so apu_tick used to run a cycle-by-cycle loop here and below
	// on every single one of the 70224 hardware dots in a frame, tens of
	// thousands of times a frame - by far the largest cost in the whole
	// emulator (measured: emulation alone could not sustain real-time
	// during gameplay, which is what caused both the audio underruns and
	// the visible slowdown). Since the falling edge of a fixed bit
	// recurs on a fixed period, the number of edges crossed in this call
	// is a plain division instead of a per-cycle scan.
	const edge_bit: u16 = if (bus.double_speed) 0x2000 else 0x1000;
	const period = (edge_bit: u64) * 2;
	const start = (bus.div_counter - (cycles: u16)): u64;
	const edge_shift = if (bus.double_speed) 14u64 else 13u64;
	const edges = ((start & (period - 1)) + (cycles: u64)) >> edge_shift;
	for (let i = 0u64; i < edges; i += 1) {
		apu_frame_sequencer_step(bus);
	};

	// Channel timers and sample generation run at the fixed hardware
	// (real-time) rate, unaffected by CPU double speed.
	const dots = (if (bus.double_speed) cycles / 2 else cycles): u64;
	const a = &bus.apu;
	const rate = (SAMPLE_RATE: u64);

	// Advance the channels in segments bounded by sample points, rather than
	// batching the whole `dots` span in one shot: doing the latter would
	// advance duty/wave/LFSR position once for the *entire* span and then
	// mix every sample in that span from that single frozen snapshot, so any
	// call spanning more than one sample period (routine during a CPU
	// HALT/STOP wait, which can hand apu_tick a very large cycle count at
	// once) would emit runs of identical (or silent) samples instead of a
	// real waveform. Segmenting by sample point keeps each emitted sample
	// exact while still only doing O(1) math between samples instead of a
	// per-dot loop - cost is proportional to samples actually emitted
	// (~738/frame), not to raw hardware dots (70224/frame).
	let remaining = dots;
	for (remaining > 0) {
		// Dots until sample_acc would next cross CPU_HZ (always >= 1, since
		// sample_acc stays below CPU_HZ between samples).
		// Most bus accesses end before the next sample. Avoid a division
		// on that hot path; split only when a sample boundary is reached.
		let step = remaining;
		if (a.sample_acc + remaining * rate >= CPU_HZ) {
			step = (CPU_HZ - a.sample_acc + rate - 1) / rate;
		};
		apu_ch1_advance(a, step);
		apu_ch2_advance(a, step);
		apu_ch3_advance(a, step);
		apu_ch4_advance(a, step);
		a.sample_acc += step * rate;
		remaining -= step;
		if (a.sample_acc >= CPU_HZ) {
			a.sample_acc -= CPU_HZ;
			const s = apu_mix_sample(bus);
			append(bus.apu.samples, s.0)!;
			append(bus.apu.samples, s.1)!;
		};
	};
};

// apu_take_samples hands ownership of the buffered interleaved stereo i16
// samples to the caller (src/app, for queuing to an audio device) and resets
// the internal buffer. The returned slice must be freed by the caller.
export fn apu_take_samples(bus: *Bus) []i16 = {
	const out = bus.apu.samples;
	bus.apu.samples = [];
	return out;
};

// Borrow until the next tick/clear/take. The caller must not free this slice.
export fn apu_samples(bus: *Bus) []i16 = bus.apu.samples;

// Retain the allocation for the next frame after the consumer has copied PCM.
export fn apu_clear_samples(bus: *Bus) void = {
	delete(bus.apu.samples[..]);
};

// apu_length_enable_quirk_* model the DMG "extra length clock" quirk: if a
// write enables the length counter while the frame sequencer's next tick
// will not itself clock length (i.e. we are in the first half of the
// current length period), the counter is clocked once immediately.
fn apu_next_tick_clocks_length(a: *Apu) bool = (a.frame_seq_step % 2) == 0;

fn apu_length_enable_quirk_ch1(a: *Apu, new_enable: bool) void = {
	const enabling = !a.ch1_length_enable && new_enable;
	a.ch1_length_enable = new_enable;
	if (enabling && apu_next_tick_clocks_length(a) && a.ch1_length > 0) {
		a.ch1_length -= 1;
		if (a.ch1_length == 0) a.ch1_enabled = false;
	};
};

fn apu_length_enable_quirk_ch2(a: *Apu, new_enable: bool) void = {
	const enabling = !a.ch2_length_enable && new_enable;
	a.ch2_length_enable = new_enable;
	if (enabling && apu_next_tick_clocks_length(a) && a.ch2_length > 0) {
		a.ch2_length -= 1;
		if (a.ch2_length == 0) a.ch2_enabled = false;
	};
};

fn apu_length_enable_quirk_ch3(a: *Apu, new_enable: bool) void = {
	const enabling = !a.ch3_length_enable && new_enable;
	a.ch3_length_enable = new_enable;
	if (enabling && apu_next_tick_clocks_length(a) && a.ch3_length > 0) {
		a.ch3_length -= 1;
		if (a.ch3_length == 0) a.ch3_enabled = false;
	};
};

fn apu_length_enable_quirk_ch4(a: *Apu, new_enable: bool) void = {
	const enabling = !a.ch4_length_enable && new_enable;
	a.ch4_length_enable = new_enable;
	if (enabling && apu_next_tick_clocks_length(a) && a.ch4_length > 0) {
		a.ch4_length -= 1;
		if (a.ch4_length == 0) a.ch4_enabled = false;
	};
};

fn apu_trigger_ch1(bus: *Bus) void = {
	const a = &bus.apu;
	a.ch1_enabled = a.ch1_dac_enabled;
	if (a.ch1_length == 0) {
		a.ch1_length = 64;
		if (a.ch1_length_enable && apu_next_tick_clocks_length(a)) a.ch1_length -= 1;
	};
	a.ch1_timer = apu_ch1_freq_period(a);
	a.ch1_env_timer = a.ch1_env_period;
	a.ch1_volume = a.ch1_env_initial;
	a.ch1_shadow_freq = a.ch1_freq;
	a.ch1_sweep_timer = if (a.ch1_sweep_pace > 0) a.ch1_sweep_pace else 8;
	a.ch1_sweep_enabled = a.ch1_sweep_pace > 0 || a.ch1_sweep_shift > 0;
	a.ch1_sweep_neg_calc_done = false;
	if (a.ch1_sweep_shift > 0 && apu_sweep_calc(a) > 2047) a.ch1_enabled = false;
};

fn apu_trigger_ch2(bus: *Bus) void = {
	const a = &bus.apu;
	a.ch2_enabled = a.ch2_dac_enabled;
	if (a.ch2_length == 0) {
		a.ch2_length = 64;
		if (a.ch2_length_enable && apu_next_tick_clocks_length(a)) a.ch2_length -= 1;
	};
	a.ch2_timer = apu_ch2_freq_period(a);
	a.ch2_env_timer = a.ch2_env_period;
	a.ch2_volume = a.ch2_env_initial;
};

fn apu_trigger_ch3(bus: *Bus) void = {
	const a = &bus.apu;
	a.ch3_enabled = a.ch3_dac_enabled;
	if (a.ch3_length == 0) {
		a.ch3_length = 256;
		if (a.ch3_length_enable && apu_next_tick_clocks_length(a)) a.ch3_length -= 1;
	};
	a.ch3_timer = apu_ch3_freq_period(a);
	a.ch3_pos = 0;
};

fn apu_trigger_ch4(bus: *Bus) void = {
	const a = &bus.apu;
	a.ch4_enabled = a.ch4_dac_enabled;
	if (a.ch4_length == 0) {
		a.ch4_length = 64;
		if (a.ch4_length_enable && apu_next_tick_clocks_length(a)) a.ch4_length -= 1;
	};
	a.ch4_timer = NOISE_DIVISORS[a.ch4_divisor_code] << a.ch4_clock_shift;
	a.ch4_env_timer = a.ch4_env_period;
	a.ch4_volume = a.ch4_env_initial;
	a.ch4_lfsr = 0x7FFF;
};

export fn apu_read(bus: *Bus, addr: u16) u8 = {
	const a = &bus.apu;
	if (addr >= 0xFF30 && addr <= 0xFF3F) {
		return a.wave_ram[addr - 0xFF30];
	};
	switch (addr) {
	case 0xFF10 =>
		let v: u8 = (a.ch1_sweep_pace << 4) | a.ch1_sweep_shift | 0x80u8;
		if (a.ch1_sweep_negate) v |= 0x08u8;
		return v;
	case 0xFF11 =>
		return (a.ch1_duty << 6) | 0x3Fu8;
	case 0xFF12 =>
		let v: u8 = (a.ch1_env_initial << 4) | a.ch1_env_period;
		if (a.ch1_env_dir) v |= 0x08u8;
		return v;
	case 0xFF13 =>
		return 0xFFu8;
	case 0xFF14 =>
		let v: u8 = 0xBFu8;
		if (a.ch1_length_enable) v |= 0x40u8;
		return v;
	case 0xFF16 =>
		return (a.ch2_duty << 6) | 0x3Fu8;
	case 0xFF17 =>
		let v: u8 = (a.ch2_env_initial << 4) | a.ch2_env_period;
		if (a.ch2_env_dir) v |= 0x08u8;
		return v;
	case 0xFF18 =>
		return 0xFFu8;
	case 0xFF19 =>
		let v: u8 = 0xBFu8;
		if (a.ch2_length_enable) v |= 0x40u8;
		return v;
	case 0xFF1A =>
		let v: u8 = 0x7Fu8;
		if (a.ch3_dac_enabled) v |= 0x80u8;
		return v;
	case 0xFF1B =>
		return 0xFFu8;
	case 0xFF1C =>
		return (a.ch3_volume_code << 5) | 0x9Fu8;
	case 0xFF1D =>
		return 0xFFu8;
	case 0xFF1E =>
		let v: u8 = 0xBFu8;
		if (a.ch3_length_enable) v |= 0x40u8;
		return v;
	case 0xFF20 =>
		return 0xFFu8;
	case 0xFF21 =>
		let v: u8 = (a.ch4_env_initial << 4) | a.ch4_env_period;
		if (a.ch4_env_dir) v |= 0x08u8;
		return v;
	case 0xFF22 =>
		return (a.ch4_clock_shift << 4) | (if (a.ch4_width_mode) 0x08u8 else 0u8)
			| a.ch4_divisor_code;
	case 0xFF23 =>
		let v: u8 = 0xBFu8;
		if (a.ch4_length_enable) v |= 0x40u8;
		return v;
	case 0xFF24 =>
		return a.nr50;
	case 0xFF25 =>
		return a.nr51;
	case 0xFF26 =>
		let status: u8 = if (a.enabled) 0x80u8 else 0u8;
		if (a.ch1_enabled) status |= 0x01u8;
		if (a.ch2_enabled) status |= 0x02u8;
		if (a.ch3_enabled) status |= 0x04u8;
		if (a.ch4_enabled) status |= 0x08u8;
		return status | 0x70u8;
	case =>
		return 0xFF;
	};
};

export fn apu_write(bus: *Bus, addr: u16, value: u8) void = {
	const a = &bus.apu;
	if (addr >= 0xFF30 && addr <= 0xFF3F) {
		a.wave_ram[addr - 0xFF30] = value;
		return;
	};
	if (addr == 0xFF26) {
		const was_enabled = a.enabled;
		a.enabled = (value & 0x80) != 0;
		if (was_enabled && !a.enabled) {
			apu_power_off(bus);
		} else if (!was_enabled && a.enabled) {
			a.frame_seq_step = 0;
		};
		return;
	};
	// DMG quirk: length-counter load registers stay writable while the APU
	// is powered off; every other register write is ignored.
	if (!a.enabled) {
		switch (addr) {
		case 0xFF11 =>
			a.ch1_length = 64 - (value & 0x3F);
		case 0xFF16 =>
			a.ch2_length = 64 - (value & 0x3F);
		case 0xFF1B =>
			a.ch3_length = 256 - (value: u16);
		case 0xFF20 =>
			a.ch4_length = 64 - (value & 0x3F);
		case =>
			void;
		};
		return;
	};
	switch (addr) {
	case 0xFF10 =>
		a.ch1_sweep_pace = (value >> 4) & 0x07;
		const new_negate = (value & 0x08) != 0;
		// Leaving negate mode after it has performed a subtraction
		// calculation since the last trigger disables the channel (a
		// documented DMG sweep-unit quirk).
		if (a.ch1_sweep_negate && !new_negate && a.ch1_sweep_neg_calc_done) {
			a.ch1_enabled = false;
		};
		a.ch1_sweep_negate = new_negate;
		a.ch1_sweep_shift = value & 0x07;
	case 0xFF11 =>
		a.ch1_duty = (value >> 6) & 0x03;
		a.ch1_length = 64 - (value & 0x3F);
	case 0xFF12 =>
		a.ch1_env_initial = (value >> 4) & 0x0F;
		a.ch1_env_dir = (value & 0x08) != 0;
		a.ch1_env_period = value & 0x07;
		a.ch1_dac_enabled = (value & 0xF8) != 0;
		if (!a.ch1_dac_enabled) a.ch1_enabled = false;
	case 0xFF13 =>
		a.ch1_freq = (a.ch1_freq & 0x0700) | (value: u16);
	case 0xFF14 =>
		a.ch1_freq = (a.ch1_freq & 0x00FF) | (((value & 0x07): u16) << 8);
		apu_length_enable_quirk_ch1(a, (value & 0x40) != 0);
		if ((value & 0x80) != 0) apu_trigger_ch1(bus);
	case 0xFF16 =>
		a.ch2_duty = (value >> 6) & 0x03;
		a.ch2_length = 64 - (value & 0x3F);
	case 0xFF17 =>
		a.ch2_env_initial = (value >> 4) & 0x0F;
		a.ch2_env_dir = (value & 0x08) != 0;
		a.ch2_env_period = value & 0x07;
		a.ch2_dac_enabled = (value & 0xF8) != 0;
		if (!a.ch2_dac_enabled) a.ch2_enabled = false;
	case 0xFF18 =>
		a.ch2_freq = (a.ch2_freq & 0x0700) | (value: u16);
	case 0xFF19 =>
		a.ch2_freq = (a.ch2_freq & 0x00FF) | (((value & 0x07): u16) << 8);
		apu_length_enable_quirk_ch2(a, (value & 0x40) != 0);
		if ((value & 0x80) != 0) apu_trigger_ch2(bus);
	case 0xFF1A =>
		a.ch3_dac_enabled = (value & 0x80) != 0;
		if (!a.ch3_dac_enabled) a.ch3_enabled = false;
	case 0xFF1B =>
		a.ch3_length = 256 - (value: u16);
	case 0xFF1C =>
		a.ch3_volume_code = (value >> 5) & 0x03;
	case 0xFF1D =>
		a.ch3_freq = (a.ch3_freq & 0x0700) | (value: u16);
	case 0xFF1E =>
		a.ch3_freq = (a.ch3_freq & 0x00FF) | (((value & 0x07): u16) << 8);
		apu_length_enable_quirk_ch3(a, (value & 0x40) != 0);
		if ((value & 0x80) != 0) apu_trigger_ch3(bus);
	case 0xFF20 =>
		a.ch4_length = 64 - (value & 0x3F);
	case 0xFF21 =>
		a.ch4_env_initial = (value >> 4) & 0x0F;
		a.ch4_env_dir = (value & 0x08) != 0;
		a.ch4_env_period = value & 0x07;
		a.ch4_dac_enabled = (value & 0xF8) != 0;
		if (!a.ch4_dac_enabled) a.ch4_enabled = false;
	case 0xFF22 =>
		a.ch4_clock_shift = (value >> 4) & 0x0F;
		a.ch4_width_mode = (value & 0x08) != 0;
		a.ch4_divisor_code = value & 0x07;
	case 0xFF23 =>
		apu_length_enable_quirk_ch4(a, (value & 0x40) != 0);
		if ((value & 0x80) != 0) apu_trigger_ch4(bus);
	case 0xFF24 =>
		a.nr50 = value;
	case 0xFF25 =>
		a.nr51 = value;
	case =>
		void;
	};
};

// apu_power_off clears every APU register except wave RAM, matching DMG
// behavior where powering the APU off silences and resets all channels.
fn apu_power_off(bus: *Bus) void = {
	const wave = bus.apu.wave_ram;
	const samples = bus.apu.samples;
	bus.apu = Apu { ... };
	bus.apu.wave_ram = wave;
	bus.apu.samples = samples;
	bus.apu.enabled = false;
};
