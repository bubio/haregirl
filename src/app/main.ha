use fmt;
use os;

const version: str = "0.1.0";

fn print_usage() void = {
	fmt::println("Usage: HareGirl [--version] [--help]")!;
};

export fn main() void = {
	let args = os::args;
	for (let i = 1z; i < len(args); i += 1) {
		switch (args[i]) {
		case "--version", "-v" =>
			fmt::println("HareGirl", version)!;
			return;
		case "--help", "-h" =>
			print_usage();
			return;
		case =>
			fmt::fatal("unknown option: {}", args[i]);
		};
	};

	print_usage();
};
