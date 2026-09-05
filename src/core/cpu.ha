// Sharp SM83 CPU core. The decoder uses the regular bit layout of the
// instruction set, keeping the implementation compact while covering the
// complete documented (and CB-prefixed) instruction set.
export type Cpu = struct {
	a: u8, f: u8, b: u8, c: u8, d: u8, e: u8, h: u8, l: u8,
	sp: u16, pc: u16, ime: bool, halted: bool, stopped: bool,
	ime_delay: int, halt_bug: bool, illegal_opcode: bool,
	// last_op はフェッチした最後のオペコード。rom_runner_step が
	// ブレークポイント検出用にオペコードをバス経由で再取得する
	// (毎命令ごとにROMを二重に読む)無駄を避けるためのキャッシュ。
	last_op: u8,
};
// Upper-case spelling is retained for callers that model the hardware name.
export type CPU = Cpu;

export fn cpu_reset(c: *Cpu, mode: Gb_Mode) void = {
	c.a=0;c.f=0;c.b=0;c.c=0;c.d=0;c.e=0;c.h=0;c.l=0;
	c.sp=0xFFFE;c.pc=0x0100;c.ime=false;c.halted=false;c.stopped=false;
	c.ime_delay=0;c.halt_bug=false;c.illegal_opcode=false;
	if (mode == Gb_Mode::Cgb) {
		cpu_set_af(c, 0x1180); cpu_set_bc(c, 0); cpu_set_de(c, 0xFF56); cpu_set_hl(c, 0x000D);
	} else {
		cpu_set_af(c, 0x01B0); cpu_set_bc(c, 0x0013); cpu_set_de(c, 0x00D8); cpu_set_hl(c, 0x014D);
	};
};

export fn cpu_af(c: *Cpu) u16 = (c.a: u16) << 8 | (c.f: u16);
export fn cpu_bc(c: *Cpu) u16 = (c.b: u16) << 8 | (c.c: u16);
export fn cpu_de(c: *Cpu) u16 = (c.d: u16) << 8 | (c.e: u16);
export fn cpu_hl(c: *Cpu) u16 = (c.h: u16) << 8 | (c.l: u16);
export fn cpu_set_af(c: *Cpu, v: u16) void = { c.a = (v >> 8): u8; c.f = (v: u8) & 0xF0; };
export fn cpu_set_bc(c: *Cpu, v: u16) void = { c.b = (v >> 8): u8; c.c = v: u8; };
export fn cpu_set_de(c: *Cpu, v: u16) void = { c.d = (v >> 8): u8; c.e = v: u8; };
export fn cpu_set_hl(c: *Cpu, v: u16) void = { c.h = (v >> 8): u8; c.l = v: u8; };

export fn cpu_set_flags(c: *Cpu, z: bool, n: bool, h: bool, carry: bool) void = {
	c.f = (if (z) FLAG_Z else 0u8) | (if (n) FLAG_N else 0u8)
		| (if (h) FLAG_H else 0u8) | (if (carry) FLAG_C else 0u8);
};
export fn cpu_flag_z(c: *Cpu) bool = c.f & FLAG_Z != 0;
export fn cpu_flag_n(c: *Cpu) bool = c.f & FLAG_N != 0;
export fn cpu_flag_h(c: *Cpu) bool = c.f & FLAG_H != 0;
export fn cpu_flag_c(c: *Cpu) bool = c.f & FLAG_C != 0;

fn next8(c: *Cpu, b: *Bus) u8 = { const v = bus_cpu_read8(b, c.pc); c.pc += 1; return v; };
fn next16(c: *Cpu, b: *Bus) u16 = { const lo = next8(c,b); const hi = next8(c,b); return (hi: u16)<<8 | (lo: u16); };
fn rr(c: *Cpu, b: *Bus, i: u8) u8 = {
	switch (i) { case 0 => return c.b; case 1 => return c.c; case 2 => return c.d; case 3 => return c.e;
	case 4 => return c.h; case 5 => return c.l; case 6 => return bus_cpu_read8(b, cpu_hl(c)); case => return c.a; };
};
fn wr(c: *Cpu, b: *Bus, i: u8, v: u8) void = {
	switch (i) { case 0 => c.b=v; case 1 => c.c=v; case 2 => c.d=v; case 3 => c.e=v;
	case 4 => c.h=v; case 5 => c.l=v; case 6 => bus_cpu_write8(b,cpu_hl(c),v); case => c.a=v; };
};
fn rp(c: *Cpu, i: u8) u16 = { switch (i) { case 0 => return cpu_bc(c); case 1 => return cpu_de(c); case 2 => return cpu_hl(c); case => return c.sp; }; };
fn w_rp(c: *Cpu, i: u8, v: u16) void = { switch (i) { case 0 => cpu_set_bc(c,v); case 1 => cpu_set_de(c,v); case 2 => cpu_set_hl(c,v); case => c.sp=v; }; };
fn cond(c: *Cpu, i: u8) bool = {
	const mask = if (i < 2) FLAG_Z else FLAG_C;
	return ((c.f & mask) != 0) == ((i & 1) != 0);
};
fn pick(ok: bool, yes: u8, no: u8) u8 = { if (ok) return yes; return no; };
fn push(c: *Cpu, b: *Bus, v: u16) void = { c.sp -= 1; bus_cpu_write8(b,c.sp,(v >> 8): u8); c.sp -= 1; bus_cpu_write8(b,c.sp,(v): u8); };
fn pop(c: *Cpu, b: *Bus) u16 = { const lo=bus_cpu_read8(b,c.sp); c.sp+=1; const hi=bus_cpu_read8(b,c.sp); c.sp+=1; return (hi: u16)<<8|(lo: u16); };

fn alu(c: *Cpu, op: u8, v: u8) void = {
	switch (op) {
	case 0, 1, 2, 3, 7 =>
		const left = c.a: u16;
		const right = v: u16;
		// Only ADC/SBC consume the incoming carry flag.
		const ci: u16 = if (op == 1 || op == 3) ((c.f >> 4) & 1): u16 else 0;
		const subtract = op >= 2;
		const result = if (subtract) left - right - ci else left + right + ci;
		// Carry out of bit 3 is bit 4 of operands XOR result; bit 8
		// carries/borrows out of the byte. Map these to H and C directly.
		c.f = (if ((result & 0xFF) == 0) FLAG_Z else 0u8)
			| (if (subtract) FLAG_N else 0u8)
			| (((left ^ right ^ result) & 0x10) << 1): u8
			| ((result >> 4) & 0x10): u8;
		if (op != 7) c.a = result: u8;
	case 4 =>
		c.a &= v;
		c.f = FLAG_H | (if (c.a == 0) FLAG_Z else 0u8);
	case 5 =>
		c.a ^= v;
		c.f = if (c.a == 0) FLAG_Z else 0u8;
	case =>
		c.a |= v;
		c.f = if (c.a == 0) FLAG_Z else 0u8;
	};
};

fn inc(c: *Cpu, v: u8) u8 = {
	const r = v + 1;
	c.f = (c.f & FLAG_C) | (if (r == 0) FLAG_Z else 0u8)
		| (if ((v & 15) == 15) FLAG_H else 0u8);
	return r;
};

fn dec(c: *Cpu, v: u8) u8 = {
	const r = v - 1;
	c.f = (c.f & FLAG_C) | FLAG_N | (if (r == 0) FLAG_Z else 0u8)
		| (if ((v & 15) == 0) FLAG_H else 0u8);
	return r;
};
fn daa(c: *Cpu) void = {
	const n=cpu_flag_n(c); let adj:u8=0; let carry=cpu_flag_c(c);
	if (cpu_flag_h(c) || (!n && (c.a&15)>9)) adj|=6;
	if (carry || (!n && c.a>0x99)) { adj|=0x60; carry=true; };
	if (n) c.a-=adj else c.a+=adj;
	cpu_set_flags(c,c.a==0,n,false,carry);
};

fn cb(c: *Cpu, b: *Bus, op: u8) void = {
	const i=op&7; let v=rr(c,b,i); const group=op>>6; const n=(op>>3)&7;
	if (group==0) {
		const sub=n; let out:u8=0; let carry=false;
		switch (sub) {
		case 0 => carry=v&0x80!=0; out=(v<<1)|pick(carry,1,0);
		case 1 => carry=v&1!=0; out=(v>>1)|pick(carry,0x80,0);
		case 2 => carry=v&0x80!=0; out=(v<<1)|pick(cpu_flag_c(c),1,0);
		case 3 => carry=v&1!=0; out=(v>>1)|pick(cpu_flag_c(c),0x80,0);
		case 4 => carry=v&0x80!=0; out=v<<1;
		case 5 => carry=v&1!=0; out=(v>>1)|(v&0x80);
		case 6 => out=(v<<4)|(v>>4); carry=false;
		case => carry=v&1!=0; out=v>>1;
		};
		wr(c,b,i,out); cpu_set_flags(c,out==0,false,false,carry);
	} else if (group==1) {
		cpu_set_flags(c,v&((1: u8)<<n)==0,false,true,cpu_flag_c(c));
	} else if (group==2) {
		v &= ~((1: u8)<<n); wr(c,b,i,v);
	} else {
		v |= (1: u8)<<n; wr(c,b,i,v);
	};
};

export fn cpu_step(c: *Cpu, b: *Bus) int = {
	const start=b.cycles;
	if (c.ime_delay>0) { c.ime_delay-=1; if(c.ime_delay==0)c.ime=true; };
	// Read the pending mask here on the per-instruction hot path.
	const pending = b.ie & b.io[0x0F] & 0x1F;
	if (pending != 0) {
		if (c.halted) c.halted = false;
		if (c.ime) {
			cpu_dispatch_interrupt(c, b);
			return ((b.cycles-start): int);
		};
	};
	if (c.halted) { bus_tick(b,4); return ((b.cycles-start): int); };
	let op=bus_cpu_read8(b,c.pc); if(!c.halt_bug)c.pc+=1 else c.halt_bug=false;
	c.last_op=op;
	if(op==0xCB) { cb(c,b,next8(c,b)); return ((b.cycles-start): int); };
	// Regular register transfers and ALU operations.
	if (op>=0x40 && op<=0x7F) {
		if(op==0x76) { c.halted=true; } else wr(c,b,(op>>3)&7,rr(c,b,op&7));
		return ((b.cycles-start): int);
	};
	if (op>=0x80 && op<=0xBF) { alu(c,(op>>3)&7,rr(c,b,op&7)); return ((b.cycles-start): int); };
	if ((op&7)==6 && op>=0x06 && op<=0x3E) {
		wr(c,b,(op>>3)&7,next8(c,b)); return ((b.cycles-start): int);
	};
	switch (op) {
	case 0x00 => bus_tick(b,0);
	case 0x01,0x11,0x21,0x31 => w_rp(c,(op>>4)&3,next16(c,b));
	case 0x02 => bus_cpu_write8(b,cpu_bc(c),c.a); case 0x12 => bus_cpu_write8(b,cpu_de(c),c.a);
	case 0x0A => c.a=bus_cpu_read8(b,cpu_bc(c)); case 0x1A => c.a=bus_cpu_read8(b,cpu_de(c));
	case 0x22 => const x=cpu_hl(c);bus_cpu_write8(b,x,c.a);cpu_set_hl(c,x+1);
	case 0x32 => const x=cpu_hl(c);bus_cpu_write8(b,x,c.a);cpu_set_hl(c,x-1);
	case 0x2A => const x=cpu_hl(c);c.a=bus_cpu_read8(b,x);cpu_set_hl(c,x+1);
	case 0x3A => const x=cpu_hl(c);c.a=bus_cpu_read8(b,x);cpu_set_hl(c,x-1);
	case 0x03,0x13,0x23,0x33 => const i=(op>>4)&3;w_rp(c,i,rp(c,i)+1);bus_tick(b,4);
	case 0x0B,0x1B,0x2B,0x3B => const i=(op>>4)&3;w_rp(c,i,rp(c,i)-1);bus_tick(b,4);
	case 0x09,0x19,0x29,0x39 => const x=cpu_hl(c);const y=rp(c,(op>>4)&3);const z=(x : int)+(y: int);const fz=cpu_flag_z(c);cpu_set_flags(c,fz,false,(x&0xFFF)+(y&0xFFF)>0xFFF,z>0xFFFF);cpu_set_hl(c,(z: u16));bus_tick(b,4);
	case 0x07,0x17,0x0F,0x1F =>
		const old=c.a; let ca: bool=false; let out: u8=0;
		if (op==0x07) { ca=old&0x80!=0; out=(old<<1)|pick(ca,1,0); }
		else if (op==0x17) { ca=old&0x80!=0; out=(old<<1)|pick(cpu_flag_c(c),1,0); }
		else if (op==0x0F) { ca=old&1!=0; out=(old>>1)|pick(ca,0x80,0); }
		else { ca=old&1!=0; out=(old>>1)|pick(cpu_flag_c(c),0x80,0); };
		c.a=out;cpu_set_flags(c,false,false,false,ca);
	case 0x27 => daa(c);
	case 0x2F => c.a=~c.a;c.f=(c.f&(FLAG_Z|FLAG_C))|FLAG_N|FLAG_H;
	case 0x37 => c.f=(c.f&FLAG_Z)|FLAG_C;
	case 0x3F => c.f=(c.f&FLAG_Z)|pick(!cpu_flag_c(c),FLAG_C,0);
	case 0x04,0x0C,0x14,0x1C,0x24,0x2C,0x34,0x3C => const i=(op>>3)&7;wr(c,b,i,inc(c,rr(c,b,i)));
	case 0x05,0x0D,0x15,0x1D,0x25,0x2D,0x35,0x3D => const i=(op>>3)&7;wr(c,b,i,dec(c,rr(c,b,i)));
	case 0xC6,0xCE,0xD6,0xDE,0xE6,0xEE,0xF6,0xFE => alu(c,(op>>3)&7,next8(c,b));
	case 0xC3 => c.pc=next16(c,b);bus_tick(b,4);
	case 0xC2,0xCA,0xD2,0xDA => const x=next16(c,b);if(cond(c,(op>>3)&3)){c.pc=x;bus_tick(b,4);};
	case 0x18 => const x=next8(c,b): i8;c.pc=((c.pc: int)+(x: int)): u16;bus_tick(b,4);
	case 0x20,0x28,0x30,0x38 => const x=next8(c,b): i8;if(cond(c,(op>>3)&3)){c.pc=((c.pc: int)+(x: int)): u16;bus_tick(b,4);};
	case 0xC9 => c.pc=pop(c,b);bus_tick(b,4);
	case 0xC0,0xC8,0xD0,0xD8 => bus_tick(b,4);if(cond(c,(op>>3)&3)){c.pc=pop(c,b);bus_tick(b,4);};
	case 0xCD => const x=next16(c,b);bus_tick(b,4);push(c,b,c.pc);c.pc=x;
	case 0xC4,0xCC,0xD4,0xDC => const x=next16(c,b);if(cond(c,(op>>3)&3)){bus_tick(b,4);push(c,b,c.pc);c.pc=x;};
	case 0xC7,0xCF,0xD7,0xDF,0xE7,0xEF,0xF7,0xFF => bus_tick(b,4);push(c,b,c.pc);c.pc=(op&0x38 : u16);
	case 0xC1,0xD1,0xE1,0xF1 =>
		const v=pop(c,b);if(op==0xC1)cpu_set_bc(c,v)else if(op==0xD1)cpu_set_de(c,v)else if(op==0xE1)cpu_set_hl(c,v)else cpu_set_af(c,v);
	case 0xC5,0xD5,0xE5,0xF5 =>
		bus_tick(b,4);let v:u16=0;if(op==0xC5)v=cpu_bc(c)else if(op==0xD5)v=cpu_de(c)else if(op==0xE5)v=cpu_hl(c)else v=cpu_af(c);push(c,b,v);
	case 0xE0 => bus_cpu_write8(b,0xFF00+(next8(c,b): u16),c.a); case 0xF0 => c.a=bus_cpu_read8(b,0xFF00+(next8(c,b): u16));
	case 0xE2 => bus_cpu_write8(b,0xFF00+(c.c : u16),c.a); case 0xF2 => c.a=bus_cpu_read8(b,0xFF00+(c.c : u16));
	case 0xEA => bus_cpu_write8(b,next16(c,b),c.a); case 0xFA => c.a=bus_cpu_read8(b,next16(c,b));
	case 0xF3 => c.ime=false;c.ime_delay=0; case 0xFB => c.ime_delay=2;
	case 0x76 => c.halted=true;
	case 0x10 =>
		c.pc+=1;
		if ((b.key1 & 0x01) != 0) {
			b.double_speed = !b.double_speed;
			b.key1 &= 0xFE;
		} else {
			c.stopped=true;
		};
	case 0xE9 => c.pc=cpu_hl(c);
	case 0xF9 => bus_tick(b,4);c.sp=cpu_hl(c);
	case 0xE8,0xF8 =>
		const e=next8(c,b); const old=c.sp; const u=(e: u16);
		const v=((old: int)+(e: i8)): u16;
		cpu_set_flags(c,false,false,(old&15)+(u&15)>15,(old&255)+(u&255)>255);
		bus_tick(b,4);
		if (op == 0xE8) {
			bus_tick(b,4); c.sp=v;
		} else {
			cpu_set_hl(c,v);
		};
	case 0x08 => const x=next16(c,b);bus_cpu_write8(b,x,(c.sp): u8);bus_cpu_write8(b,x+1,(c.sp>>8): u8);
	case 0xD9 => c.pc=pop(c,b);bus_tick(b,4);c.ime=true;
	case => c.illegal_opcode=true;c.stopped=true;
	};
	return ((b.cycles-start): int);
};
