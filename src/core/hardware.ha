// Game Boy hardware constants.
export def SCREEN_WIDTH: int = 160;
export def SCREEN_HEIGHT: int = 144;
export def CPU_HZ: u64 = 4194304;
export def CYCLES_PER_FRAME: u64 = 70224;

export type Gb_Mode = enum { Dmg, Cgb };

export def FLAG_Z: u8 = 0x80;
export def FLAG_N: u8 = 0x40;
export def FLAG_H: u8 = 0x20;
export def FLAG_C: u8 = 0x10;

export def IF_ADDR: u16 = 0xFF0F;
export def IE_ADDR: u16 = 0xFFFF;
export def INT_VBLANK: u8 = 0x01;
export def INT_STAT: u8 = 0x02;
export def INT_TIMER: u8 = 0x04;
export def INT_SERIAL: u8 = 0x08;
export def INT_JOYPAD: u8 = 0x10;
