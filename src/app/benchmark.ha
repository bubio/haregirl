use core;
use fmt;
use time;

// Run the normal core without SDL, pacing, or battery save I/O. Hash every
// frame and PCM sample, plus the final serialized state, for repeatable
// before/after comparisons. ROMs and existing saves are never modified.
fn run_benchmark(runner: *core::Rom_Runner, frames: int) void = {
	let video_hash = 2166136261u32;
	let audio_hash = 2166136261u32;
	let sample_count = 0u64;
	const start = time::now(time::clock::MONOTONIC);
	for (let frame = 0; frame < frames; frame += 1) {
		const cycles = if (runner.bus.double_speed)
			core::CYCLES_PER_FRAME * 2 else core::CYCLES_PER_FRAME;
		const target = runner.bus.cycles + cycles;
		for (runner.bus.cycles < target) {
			core::rom_runner_step(runner);
			if (runner.cpu.illegal_opcode) fmt::fatal("benchmark: illegal opcode");
		};
		for (let i = 0z; i < len(runner.bus.ppu.frame); i += 1) {
			const pixel = if (runner.bus.mode == core::Gb_Mode::Cgb)
				runner.bus.ppu.frame_rgb[i] else runner.bus.ppu.frame[i]: u32;
			video_hash = (video_hash ^ pixel) * 16777619;
		};
		const samples = core::apu_samples(&runner.bus);
		sample_count += len(samples): u64;
		for (let i = 0z; i < len(samples); i += 1) {
			audio_hash = (audio_hash ^ (samples[i]: u16: u32)) * 16777619;
		};
		core::apu_clear_samples(&runner.bus);
	};
	const elapsed = time::diff(start, time::now(time::clock::MONOTONIC));
	const state = core::state_save(&runner.bus, &runner.cpu);
	defer free(state);
	let state_hash = 2166136261u32;
	for (let i = 0z; i < len(state); i += 1) {
		state_hash = (state_hash ^ state[i]) * 16777619;
	};
	fmt::printfln("frames={} elapsed_ms={} cycles={} steps={}",
		frames, elapsed / time::MILLISECOND, runner.bus.cycles, runner.steps)!;
	fmt::printfln("video={} audio={} samples={} state={}",
		video_hash, audio_hash, sample_count, state_hash)!;
};
