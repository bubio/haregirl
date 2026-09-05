use core;

// Execute real ALU opcodes for all byte operands and both incoming carries.
// The reference uses signed arithmetic and nibble comparisons, independently
// of the core's carry-bit extraction. CP must leave A intact.
fn test_cpu_alu_exhaustive() void = {
	let rom: [2]u8 = [0...];
	let b = core::Bus { rom = rom[..], ... };
	for (let op = 0; op < 8; op += 1) {
		rom[0] = (0x80 + op * 8): u8; // ALU A,B
		for (let carry = 0; carry < 2; carry += 1) {
			for (let left = 0; left < 256; left += 1) {
				for (let right = 0; right < 256; right += 1) {
					let result = 0;
					let half = false;
					let carry_out = false;
					let subtract = false;
					switch (op) {
					case 0, 1 =>
						const ci = if (op == 1) carry else 0;
						result = left + right + ci;
						half = left % 16 + right % 16 + ci >= 16;
						carry_out = result >= 256;
					case 2, 3, 7 =>
						const ci = if (op == 3) carry else 0;
						result = left - right - ci;
						half = left % 16 < right % 16 + ci;
						carry_out = result < 0;
						subtract = true;
					case 4 => result = left & right; half = true;
					case 5 => result = left ^ right;
					case => result = left | right;
					};
					let flags = 0u8;
					if ((result: u8) == 0) flags |= 0x80;
					if (subtract) flags |= 0x40;
					if (half) flags |= 0x20;
					if (carry_out) flags |= 0x10;
					let c = core::Cpu {
						a = left: u8, b = right: u8,
						f = (0xE0 + carry * 16): u8, ...
					};
					const cycles = core::cpu_step(&c, &b);
					check(c.a == ((if (op == 7) left else result): u8), "exhaustive ALU result");
					check(c.f == flags, "exhaustive ALU Z/N/H/C flags");
					check(c.pc == 1 && cycles == 4 && c.b == right: u8,
						"ALU instruction length, cycles and source register");
				};
			};
		};
	};
	for (let decrement = 0; decrement < 2; decrement += 1) {
		rom[0] = if (decrement == 0) 0x04 else 0x05; // INC/DEC B
		for (let flags_in = 0; flags_in < 16; flags_in += 1) {
			for (let value = 0; value < 256; value += 1) {
				const result = (value + (if (decrement == 0) 1 else -1)): u8;
				let flags = ((flags_in * 16): u8) & 0x10;
				if (result == 0) flags |= 0x80;
				if (decrement != 0) flags |= 0x40;
				if (if (decrement == 0) value % 16 == 15 else value % 16 == 0) flags |= 0x20;
				let c = core::Cpu { b = value: u8, f = (flags_in * 16): u8, ... };
				check(core::cpu_step(&c, &b) == 4 && c.b == result && c.f == flags,
					"exhaustive INC/DEC result, carry preservation and flags");
			};
		};
	};
	free(b.apu.samples);
};

fn test_cpu_conditions() void = {
	let rom: [2]u8 = [0, 5]; // JR cc,+5
	let b = core::Bus { rom = rom[..], ... };
	for (let condition = 0u8; condition < 4; condition += 1) {
		rom[0] = 0x20 + condition * 8;
		for (let flags = 0; flags < 16; flags += 1) {
			let c = core::Cpu { f = (flags * 16): u8, ... };
			let taken = false;
			switch (condition) {
			case 0 => taken = (flags & 8) == 0;
			case 1 => taken = (flags & 8) != 0;
			case 2 => taken = (flags & 1) == 0;
			case => taken = (flags & 1) != 0;
			};
			const cycles = core::cpu_step(&c, &b);
			check(c.pc == (if (taken) 7u16 else 2u16)
				&& cycles == (if (taken) 12 else 8)
				&& c.f == (flags * 16): u8,
				"conditional branch checks the selected flag, cycles and target");
		};
	};
	free(b.apu.samples);
};
