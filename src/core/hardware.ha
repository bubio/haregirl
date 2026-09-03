// Game Boy hardware constants.
export const SCREEN_WIDTH: int = 160;
export const SCREEN_HEIGHT: int = 144;
export const CPU_HZ: u64 = 4194304;
export const CYCLES_PER_FRAME: u64 = 70224;

export type Gb_Mode = enum { Dmg, Cgb };

export const FLAG_Z: u8 = 0x80;
export const FLAG_N: u8 = 0x40;
export const FLAG_H: u8 = 0x20;
export const FLAG_C: u8 = 0x10;

export const IF_ADDR: u16 = 0xFF0F;
export const IE_ADDR: u16 = 0xFFFF;
export const INT_VBLANK: u8 = 0x01;
export const INT_STAT: u8 = 0x02;
export const INT_TIMER: u8 = 0x04;
export const INT_SERIAL: u8 = 0x08;
export const INT_JOYPAD: u8 = 0x10;
