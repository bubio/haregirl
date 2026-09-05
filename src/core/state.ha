// セーブステート(実行状態の完全なスナップショット)。バッテリーバックアップ
// カートリッジRAM(cart_ram_bytes/cart_ram_load、フェーズ5)とは別物で、CPU・
// PPU・APU・タイマー・CGB拡張レジスタを含む実行状態全体を対象にする。
//
// ROM本体・カートリッジ種別(ROM/RAMバンク数・MBC種別・バッテリー有無)は
// ROMヘッダーから決定的に再構築できるため保存しない。state_load は
// bus_load_rom で同一ROMを読み込んだ後の Bus に対して呼び出す前提
// (cart_ram_load と同じ前提)。

const STATE_MAGIC: u32 = 0x47425253; // "SRBG" little-endian
const STATE_VERSION: u32 = 1;

type state_buf = struct { data: []u8 };

fn put_u8(buf: *state_buf, v: u8) void = { append(buf.data, v)!; };
fn put_u16(buf: *state_buf, v: u16) void = { put_u8(buf, (v & 0xFF): u8); put_u8(buf, (v >> 8): u8); };
fn put_u32(buf: *state_buf, v: u32) void = { put_u16(buf, (v & 0xFFFF): u16); put_u16(buf, (v >> 16): u16); };
fn put_u64(buf: *state_buf, v: u64) void = { put_u32(buf, (v & 0xFFFFFFFF): u32); put_u32(buf, (v >> 32): u32); };
fn put_bool(buf: *state_buf, v: bool) void = { put_u8(buf, if (v) 1u8 else 0u8); };
fn put_bytes(buf: *state_buf, data: []u8) void = {
	for (let i = 0z; i < len(data); i += 1) put_u8(buf, data[i]);
};
fn put_u32_array(buf: *state_buf, data: []u32) void = {
	for (let i = 0z; i < len(data); i += 1) put_u32(buf, data[i]);
};

type state_reader = struct { data: []u8, pos: size, ok: bool };

fn get_u8(r: *state_reader) u8 = {
	if (r.pos >= len(r.data)) { r.ok = false; return 0; };
	const v = r.data[r.pos];
	r.pos += 1;
	return v;
};
fn get_u16(r: *state_reader) u16 = {
	const lo = get_u8(r); const hi = get_u8(r);
	return (hi: u16) << 8 | (lo: u16);
};
fn get_u32(r: *state_reader) u32 = {
	const lo = get_u16(r); const hi = get_u16(r);
	return (hi: u32) << 16 | (lo: u32);
};
fn get_u64(r: *state_reader) u64 = {
	const lo = get_u32(r); const hi = get_u32(r);
	return (hi: u64) << 32 | (lo: u64);
};
fn get_bool(r: *state_reader) bool = get_u8(r) != 0;
fn get_bytes(r: *state_reader, out: []u8) void = {
	for (let i = 0z; i < len(out); i += 1) out[i] = get_u8(r);
};
fn get_u32_array(r: *state_reader, out: []u32) void = {
	for (let i = 0z; i < len(out); i += 1) out[i] = get_u32(r);
};

// state_save は Bus/Cpu の実行状態をバイト列へシリアライズする。
export fn state_save(bus: *Bus, cpu: *Cpu) []u8 = {
	let sb = state_buf { data = [] };
	const buf = &sb;
	put_u32(buf, STATE_MAGIC);
	put_u32(buf, STATE_VERSION);

	// CPU
	put_u8(buf, cpu.a); put_u8(buf, cpu.f);
	put_u8(buf, cpu.b); put_u8(buf, cpu.c);
	put_u8(buf, cpu.d); put_u8(buf, cpu.e);
	put_u8(buf, cpu.h); put_u8(buf, cpu.l);
	put_u16(buf, cpu.sp); put_u16(buf, cpu.pc);
	put_bool(buf, cpu.ime); put_bool(buf, cpu.halted); put_bool(buf, cpu.stopped);
	put_u32(buf, cpu.ime_delay: u32);
	put_bool(buf, cpu.halt_bug); put_bool(buf, cpu.illegal_opcode);

	// Bus (ROM本体・serial_log は対象外)
	put_u8(buf, bus.mode: u8);
	for (let bank = 0z; bank < 2; bank += 1) put_bytes(buf, bus.vram[bank][..]);
	put_u8(buf, bus.vram_bank);
	for (let bank = 0z; bank < 8; bank += 1) put_bytes(buf, bus.wram[bank][..]);
	put_u8(buf, bus.wram_bank);
	put_bytes(buf, bus.oam[..]);
	put_bytes(buf, bus.hram[..]);
	put_bytes(buf, bus.io[..]);
	put_u8(buf, bus.ie);
	put_u64(buf, bus.cycles);
	put_u16(buf, bus.div_counter);
	put_u8(buf, bus.tima); put_u8(buf, bus.tma); put_u8(buf, bus.tac);
	put_u32(buf, bus.timer_reload_pending: u32);
	put_bool(buf, bus.timer_reload_just_happened);
	put_u8(buf, bus.key1); put_bool(buf, bus.double_speed);
	put_u16(buf, bus.hdma_src); put_u16(buf, bus.hdma_dst);
	put_bool(buf, bus.hdma_active); put_u8(buf, bus.hdma_remaining);

	// PPU
	const p = &bus.ppu;
	put_u8(buf, p.mode_gb: u8);
	put_u8(buf, p.lcdc); put_u8(buf, p.stat);
	put_u8(buf, p.scy); put_u8(buf, p.scx);
	put_u8(buf, p.ly); put_u8(buf, p.lyc);
	put_u8(buf, p.bgp); put_u8(buf, p.obp0); put_u8(buf, p.obp1);
	put_u8(buf, p.wy); put_u8(buf, p.wx);
	put_u16(buf, p.dot); put_u8(buf, p.mode);
	put_u8(buf, p.window_line); put_bool(buf, p.stat_line);
	put_bytes(buf, p.frame[..]);
	put_bytes(buf, p.cgb_bg_pal[..]);
	put_bytes(buf, p.cgb_obj_pal[..]);
	put_u8(buf, p.bgpi); put_u8(buf, p.obpi);
	put_u32_array(buf, p.frame_rgb[..]);

	// APU (samples キューは対象外。呼び出し側で apu_take_samples 済み前提)
	const a = &bus.apu;
	put_bool(buf, a.enabled); put_u8(buf, a.frame_seq_step);
	put_u8(buf, a.ch1_sweep_pace); put_bool(buf, a.ch1_sweep_negate);
	put_u8(buf, a.ch1_sweep_shift); put_u8(buf, a.ch1_sweep_timer);
	put_bool(buf, a.ch1_sweep_enabled); put_bool(buf, a.ch1_sweep_neg_calc_done);
	put_u16(buf, a.ch1_shadow_freq); put_u8(buf, a.ch1_duty);
	put_u16(buf, a.ch1_length); put_bool(buf, a.ch1_length_enable);
	put_u8(buf, a.ch1_env_initial); put_bool(buf, a.ch1_env_dir);
	put_u8(buf, a.ch1_env_period); put_u8(buf, a.ch1_env_timer);
	put_u8(buf, a.ch1_volume); put_u16(buf, a.ch1_freq);
	put_u16(buf, a.ch1_timer); put_u8(buf, a.ch1_duty_pos);
	put_bool(buf, a.ch1_dac_enabled); put_bool(buf, a.ch1_enabled);

	put_u8(buf, a.ch2_duty); put_u16(buf, a.ch2_length);
	put_bool(buf, a.ch2_length_enable);
	put_u8(buf, a.ch2_env_initial); put_bool(buf, a.ch2_env_dir);
	put_u8(buf, a.ch2_env_period); put_u8(buf, a.ch2_env_timer);
	put_u8(buf, a.ch2_volume); put_u16(buf, a.ch2_freq);
	put_u16(buf, a.ch2_timer); put_u8(buf, a.ch2_duty_pos);
	put_bool(buf, a.ch2_dac_enabled); put_bool(buf, a.ch2_enabled);

	put_bool(buf, a.ch3_dac_enabled); put_bytes(buf, a.wave_ram[..]);
	put_u16(buf, a.ch3_length); put_bool(buf, a.ch3_length_enable);
	put_u8(buf, a.ch3_volume_code); put_u16(buf, a.ch3_freq);
	put_u16(buf, a.ch3_timer); put_u8(buf, a.ch3_pos);
	put_bool(buf, a.ch3_enabled);

	put_u16(buf, a.ch4_length); put_bool(buf, a.ch4_length_enable);
	put_u8(buf, a.ch4_env_initial); put_bool(buf, a.ch4_env_dir);
	put_u8(buf, a.ch4_env_period); put_u8(buf, a.ch4_env_timer);
	put_u8(buf, a.ch4_volume); put_u8(buf, a.ch4_clock_shift);
	put_bool(buf, a.ch4_width_mode); put_u8(buf, a.ch4_divisor_code);
	put_u16(buf, a.ch4_timer); put_u16(buf, a.ch4_lfsr);
	put_bool(buf, a.ch4_dac_enabled); put_bool(buf, a.ch4_enabled);

	put_u8(buf, a.nr50); put_u8(buf, a.nr51);
	put_u64(buf, a.sample_acc);

	// Cartridge (可変部分のみ。ROM/RAM構成は再読込時にヘッダーから復元)
	const cart = &bus.cart;
	put_bool(buf, cart.ram_enabled);
	put_u8(buf, cart.rom_lo); put_u8(buf, cart.rom_hi);
	put_u8(buf, cart.ram_sel); put_u8(buf, cart.mode);
	put_bytes(buf, cart.rtc[..]);
	put_u8(buf, cart.latch_prev);
	put_u32(buf, len(cart.ram): u32);
	put_bytes(buf, cart.ram);

	return sb.data;
};

// state_load は state_save が生成したバイト列を Bus/Cpu へ復元する。
// bus は state_save 時と同一ROMを bus_load_rom 済みでなければならない
// (カートリッジRAM容量が一致しない場合は false を返し、状態を変更しない)。
export fn state_load(bus: *Bus, cpu: *Cpu, data: []u8) bool = {
	let r = state_reader { data = data, pos = 0, ok = true };
	if (get_u32(&r) != STATE_MAGIC) return false;
	if (get_u32(&r) != STATE_VERSION) return false;

	let nc: Cpu = Cpu { ... };
	nc.a = get_u8(&r); nc.f = get_u8(&r);
	nc.b = get_u8(&r); nc.c = get_u8(&r);
	nc.d = get_u8(&r); nc.e = get_u8(&r);
	nc.h = get_u8(&r); nc.l = get_u8(&r);
	nc.sp = get_u16(&r); nc.pc = get_u16(&r);
	nc.ime = get_bool(&r); nc.halted = get_bool(&r); nc.stopped = get_bool(&r);
	nc.ime_delay = get_u32(&r): int;
	nc.halt_bug = get_bool(&r); nc.illegal_opcode = get_bool(&r);

	const mode: Gb_Mode = get_u8(&r): Gb_Mode;
	let vram: [2][8192]u8 = [[0...], [0...]];
	for (let bank = 0z; bank < 2; bank += 1) get_bytes(&r, vram[bank][..]);
	const vram_bank = get_u8(&r);
	let wram: [8][4096]u8 = [[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...]];
	for (let bank = 0z; bank < 8; bank += 1) get_bytes(&r, wram[bank][..]);
	const wram_bank = get_u8(&r);
	let oam: [160]u8 = [0...];
	get_bytes(&r, oam[..]);
	let hram: [127]u8 = [0...];
	get_bytes(&r, hram[..]);
	let io: [128]u8 = [0...];
	get_bytes(&r, io[..]);
	const ie = get_u8(&r);
	const cycles = get_u64(&r);
	const div_counter = get_u16(&r);
	const tima = get_u8(&r); const tma = get_u8(&r); const tac = get_u8(&r);
	const timer_reload_pending = get_u32(&r): int;
	const timer_reload_just_happened = get_bool(&r);
	const key1 = get_u8(&r); const double_speed = get_bool(&r);
	const hdma_src = get_u16(&r); const hdma_dst = get_u16(&r);
	const hdma_active = get_bool(&r); const hdma_remaining = get_u8(&r);

	let np: Ppu = Ppu { ... };
	np.mode_gb = get_u8(&r): Gb_Mode;
	np.lcdc = get_u8(&r); np.stat = get_u8(&r);
	np.scy = get_u8(&r); np.scx = get_u8(&r);
	np.ly = get_u8(&r); np.lyc = get_u8(&r);
	np.bgp = get_u8(&r); np.obp0 = get_u8(&r); np.obp1 = get_u8(&r);
	np.wy = get_u8(&r); np.wx = get_u8(&r);
	np.dot = get_u16(&r); np.mode = get_u8(&r);
	np.window_line = get_u8(&r); np.stat_line = get_bool(&r);
	get_bytes(&r, np.frame[..]);
	get_bytes(&r, np.cgb_bg_pal[..]);
	get_bytes(&r, np.cgb_obj_pal[..]);
	np.bgpi = get_u8(&r); np.obpi = get_u8(&r);
	get_u32_array(&r, np.frame_rgb[..]);

	let na: Apu = Apu { ... };
	na.enabled = get_bool(&r); na.frame_seq_step = get_u8(&r);
	na.ch1_sweep_pace = get_u8(&r); na.ch1_sweep_negate = get_bool(&r);
	na.ch1_sweep_shift = get_u8(&r); na.ch1_sweep_timer = get_u8(&r);
	na.ch1_sweep_enabled = get_bool(&r); na.ch1_sweep_neg_calc_done = get_bool(&r);
	na.ch1_shadow_freq = get_u16(&r); na.ch1_duty = get_u8(&r);
	na.ch1_length = get_u16(&r); na.ch1_length_enable = get_bool(&r);
	na.ch1_env_initial = get_u8(&r); na.ch1_env_dir = get_bool(&r);
	na.ch1_env_period = get_u8(&r); na.ch1_env_timer = get_u8(&r);
	na.ch1_volume = get_u8(&r); na.ch1_freq = get_u16(&r);
	na.ch1_timer = get_u16(&r); na.ch1_duty_pos = get_u8(&r);
	na.ch1_dac_enabled = get_bool(&r); na.ch1_enabled = get_bool(&r);

	na.ch2_duty = get_u8(&r); na.ch2_length = get_u16(&r);
	na.ch2_length_enable = get_bool(&r);
	na.ch2_env_initial = get_u8(&r); na.ch2_env_dir = get_bool(&r);
	na.ch2_env_period = get_u8(&r); na.ch2_env_timer = get_u8(&r);
	na.ch2_volume = get_u8(&r); na.ch2_freq = get_u16(&r);
	na.ch2_timer = get_u16(&r); na.ch2_duty_pos = get_u8(&r);
	na.ch2_dac_enabled = get_bool(&r); na.ch2_enabled = get_bool(&r);

	na.ch3_dac_enabled = get_bool(&r);
	get_bytes(&r, na.wave_ram[..]);
	na.ch3_length = get_u16(&r); na.ch3_length_enable = get_bool(&r);
	na.ch3_volume_code = get_u8(&r); na.ch3_freq = get_u16(&r);
	na.ch3_timer = get_u16(&r); na.ch3_pos = get_u8(&r);
	na.ch3_enabled = get_bool(&r);

	na.ch4_length = get_u16(&r); na.ch4_length_enable = get_bool(&r);
	na.ch4_env_initial = get_u8(&r); na.ch4_env_dir = get_bool(&r);
	na.ch4_env_period = get_u8(&r); na.ch4_env_timer = get_u8(&r);
	na.ch4_volume = get_u8(&r); na.ch4_clock_shift = get_u8(&r);
	na.ch4_width_mode = get_bool(&r); na.ch4_divisor_code = get_u8(&r);
	na.ch4_timer = get_u16(&r); na.ch4_lfsr = get_u16(&r);
	na.ch4_dac_enabled = get_bool(&r); na.ch4_enabled = get_bool(&r);

	na.nr50 = get_u8(&r); na.nr51 = get_u8(&r);
	na.sample_acc = get_u64(&r);

	const cart_ram_enabled = get_bool(&r);
	const cart_rom_lo = get_u8(&r); const cart_rom_hi = get_u8(&r);
	const cart_ram_sel = get_u8(&r); const cart_mode = get_u8(&r);
	let rtc: [5]u8 = [0...];
	get_bytes(&r, rtc[..]);
	const cart_latch_prev = get_u8(&r);
	const ram_len = get_u32(&r): size;

	if (!r.ok) return false;
	if (ram_len != len(bus.cart.ram)) return false;
	let ram: []u8 = [];
	if (ram_len > 0) ram = alloc([0...], ram_len)!;
	get_bytes(&r, ram);
	if (!r.ok) {
		free(ram);
		return false;
	};
	if (bus.mode != mode) {
		free(ram);
		return false;
	};

	// ここまで読み取りが全て成功したので、実際の状態を書き換える。
	*cpu = nc;
	bus.vram = vram; bus.vram_bank = vram_bank;
	bus.wram = wram; bus.wram_bank = wram_bank;
	bus.oam = oam; bus.hram = hram; bus.io = io;
	bus.ie = ie; bus.cycles = cycles; bus.div_counter = div_counter;
	bus.tima = tima; bus.tma = tma; bus.tac = tac;
	bus.timer_reload_pending = timer_reload_pending;
	bus.timer_reload_just_happened = timer_reload_just_happened;
	bus.key1 = key1; bus.double_speed = double_speed;
	bus.hdma_src = hdma_src; bus.hdma_dst = hdma_dst;
	bus.hdma_active = hdma_active; bus.hdma_remaining = hdma_remaining;
	bus.ppu = np;
	free(bus.apu.samples);
	na.samples = [];
	bus.apu = na;
	bus.cart.ram_enabled = cart_ram_enabled;
	bus.cart.rom_lo = cart_rom_lo; bus.cart.rom_hi = cart_rom_hi;
	bus.cart.ram_sel = cart_ram_sel; bus.cart.mode = cart_mode;
	cart_refresh_rom_mapping(bus);
	bus.cart.rtc = rtc; bus.cart.latch_prev = cart_latch_prev;
	for (let i = 0z; i < ram_len; i += 1) bus.cart.ram[i] = ram[i];
	free(ram);
	return true;
};
