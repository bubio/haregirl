use fs;
use io;
use os;
use core;

export fn load_rom_file(path: str) ([]u8 | void) = {
	const file = match (os::open(path)) {
	case let file: io::file =>
		yield file;
	case =>
		return;
	};
	defer io::close(file)!;

	const st = match (os::fstat(file)) {
	case let st: fs::filestat =>
		yield st;
	case =>
		return;
	};

	let buf: []u8 = alloc([0...], st.sz: size)!;
	match (io::readall(file, buf)) {
	case let n: size =>
		if (n == len(buf)) return buf;
	case =>
		void;
	};
	free(buf);
};

export fn rom_status_name(status: core::Rom_Status) str = {
	switch (status) {
	case core::Rom_Status::Running =>
		return "running";
	case core::Rom_Status::Passed =>
		return "passed";
	case core::Rom_Status::Failed =>
		return "failed";
	case core::Rom_Status::Timed_Out =>
		return "timed_out";
	case core::Rom_Status::Illegal_Opcode =>
		return "illegal_opcode";
	case core::Rom_Status::Stopped =>
		return "stopped";
	};
};
