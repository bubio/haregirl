# HareGirl

[日本語](README.ja.md)

<p align="center">
  <a href="https://github.com/bubio/haregirl/releases/latest">
    <img src="https://img.shields.io/github/v/release/bubio/haregirl" alt="Latest Release">
  </a>
  <a href="https://github.com/bubio/haregirl/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/bubio/haregirl" alt="License">
  </a>
  <a href="https://github.com/bubio/haregirl/actions/workflows/ci.yml">
    <img src="https://github.com/bubio/haregirl/actions/workflows/ci.yml/badge.svg">
  </a>
  <a href="https://github.com/bubio/haregirl/releases/latest">
    <img src="https://img.shields.io/github/downloads/bubio/haregirl/total.svg" alt="Downloads">
  </a>
</p>

<p align="center">
  <img src="docs/CoverArt.jpg" alt="Cover" width="*" height="*">
</p>

HareGirl is a Game Boy Color emulator written in Hare, using SDL2 as its multimedia layer. Start it from the command line by specifying a ROM.

The emulation core is based on [BubiBoy Lite](https://github.com/bubio/BubiBoyLite) (Odin + SDL2, MIT License), ported to Hare.

## Status

This is an experimental project under active development. It currently implements the CPU, PPU, APU, timer, interrupts, joypad, serial, cartridges (including MBC1/2/3/5), basic DMG/CGB emulation, battery-backed RAM, save states, configuration files, and video/audio output through SDL2.

Compatibility and performance still have room for improvement. If you use commercial game ROMs, verify that you own them and comply with the terms applicable to each ROM.

![Astro Rabby running on HareGirl on Ubuntu 24.04](docs/Screenshot1.png)
![Astro Rabby running on HareGirl on FreeBSD](docs/Screenshot2.png)

## Supported platforms

The [release workflow](.github/workflows/release.yml) builds, tests, and packages native executables for the following targets. Versions below identify the workflow build environments.

| OS | Build environment | Architectures |
|---|---|---|
| Linux | Ubuntu 22.04 | amd64 |
| Linux | Ubuntu 24.04 | arm64 / riscv64 |
| FreeBSD | 14.4 | amd64 / aarch64 |
| OpenBSD | 7.8 | amd64 / aarch64 |
| NetBSD | 11 | amd64 |
| DragonFlyBSD | 6.4 | amd64 |

When a release is published and all target builds succeed, the following zip archives are attached to the GitHub Release. Other workflow runs make them available as Actions artifacts.

| Target | Archive |
|---|---|
| Linux amd64 | `HareGirl-<version>-linux-amd64.zip` |
| Linux arm64 | `HareGirl-<version>-linux-arm64.zip` |
| Linux riscv64 | `HareGirl-<version>-linux-riscv64.zip` |
| FreeBSD amd64 | `HareGirl-<version>-freebsd-amd64.zip` |
| FreeBSD aarch64 | `HareGirl-<version>-freebsd-aarch64.zip` |
| OpenBSD amd64 | `HareGirl-<version>-openbsd-amd64.zip` |
| OpenBSD aarch64 | `HareGirl-<version>-openbsd-aarch64.zip` |
| NetBSD amd64 | `HareGirl-<version>-netbsd-amd64.zip` |
| DragonFlyBSD amd64 | `HareGirl-<version>-dragonfly-amd64.zip` |

Each archive contains `HareGirl` and `LICENSE`. The system SDL2 library is required at runtime. Run these installation commands as root (using `sudo` on Ubuntu).

| OS | Install SDL2 |
|---|---|
| Ubuntu | `sudo apt install libsdl2-2.0-0` |
| FreeBSD / DragonFlyBSD | `pkg install sdl2` |
| OpenBSD | `pkg_add sdl2` |
| NetBSD | `pkg_add SDL2` |

NetBSD also requires the X11 libraries used by SDL2. On minimal installations, use `install-netbsd-x11.sh` as described below. From the extracted archive directory, launch with `./HareGirl path/to/game.gb`.

## Usage

```text
HareGirl [options] game.gb|game.gbc
```

Run a Game Boy / Game Boy Color ROM:

```sh
./build/HareGirl path/to/game.gb
./build/HareGirl path/to/game.gbc
```

Temporarily change the display scale, volume, and interpolation method from the command line:

```sh
./build/HareGirl --scale 3 --volume 80 --shader smooth path/to/game.gb
```

Save or inspect the current configuration:

```sh
./build/HareGirl --scale 3 --volume 80 --shader smooth --save-config
./build/HareGirl --print-config
```

Launch the test screen or test audio without a ROM. With `--frames N`, the program exits after rendering or playing N frames.

```sh
./build/HareGirl --test-screen --frames 300
./build/HareGirl --test-audio --frames 300
```

Benchmarking requires a ROM and a positive frame count:

```sh
./build/HareGirl --benchmark --frames 3600 path/to/game.gb
```

Options:

| Option | Description |
|---|---|
| `-h`, `--help` | Show usage and exit |
| `-v`, `--version` | Show the version and exit |
| `--test-screen` | Display the test screen |
| `--test-audio` | Play test audio |
| `--benchmark` | Benchmark the specified ROM; requires a ROM and `--frames N` (N > 0) |
| `--frames N` | Exit after N frames during tests, benchmarking, or ROM execution |
| `--config PATH` | Specify the configuration file path |
| `--scale N` | Set the display scale (1–8; default: 4; values above 8 are clamped to 8) |
| `--shader KIND` | Select `nearest` or `smooth` interpolation (default: `nearest`) |
| `--volume N` | Set the volume (0–100; default: 100) |
| `--save-config` | Save the active configuration and exit |
| `--print-config` | Print the active configuration and exit |

Keyboard and SDL2-compatible game controller controls during gameplay:

| Action | Keyboard | Controller |
|---|---|---|
| D-pad | Arrow keys | D-pad or left stick |
| A | `Z` | Right face button |
| B | `X` | Bottom face button |
| Start | `Enter` | Start / Options |
| Select | Right `Shift` | Back / Share |
| Save state | `F5` | — |
| Load state | `F7` | — |
| Quit | `Esc` | — |

Save states are stored beside the ROM with a `.state` extension and are rejected when they belong to a different ROM.

The `--help` language follows the runtime locale: Japanese for `ja` locales and English otherwise. `LC_ALL`, `LC_MESSAGES`, and `LANG` are checked in that order.

Unless a configuration path is specified, HareGirl uses `$XDG_CONFIG_HOME/HareGirl/config.ini`, or `$HOME/.config/HareGirl/config.ini` when `XDG_CONFIG_HOME` is unset.

## Building from source

You need the [Hare](https://harelang.org/) toolchain and SDL2 development libraries. Build natively on the target OS and architecture. Install Git first, then clone the repository:

```sh
git clone https://github.com/bubio/haregirl.git
cd haregirl
```

Run the dependency and toolchain installation commands below as root (using `sudo` on Ubuntu), from the repository root. `install-hare-toolchain.sh` builds QBE, harec, and Hare from source and installs them under `/usr/local`. It defaults to the harec and Hare `master` branches and detects the native OS and architecture.

### Ubuntu / Linux

```sh
sudo apt-get update
sudo apt-get install -y build-essential git scdoc libsdl2-dev zip curl python3
sudo sh scripts/install-hare-toolchain.sh
```

For riscv64, replace the toolchain installation command above with this command to use Hare 0.26.0, matching the workflow:

```sh
sudo env HARE_REF=0.26.0 HAREC_REF=0.26.0 sh scripts/install-hare-toolchain.sh
```

### FreeBSD

On amd64, use the packaged Hare toolchain:

```sh
pkg install -y git hare-lang sdl2 zip curl python3
```

On aarch64, build the toolchain from source:

```sh
pkg install -y binutils git scdoc sdl2 zip
sh scripts/install-hare-toolchain.sh
```

### OpenBSD

```sh
pkg_add binutils git scdoc sdl2 zip
sh scripts/install-hare-toolchain.sh
```

Set the SDL2 library search path in the shell used for building, testing, and packaging:

```sh
export LDFLAGS="${LDFLAGS:-} -L/usr/local/lib"
```

### NetBSD

Restore missing X11 libraries on minimal installations, then install dependencies and the toolchain. The X11 helper makes no changes if the required library is already present.

```sh
sh scripts/install-netbsd-x11.sh
pkg_add binutils git scdoc SDL2 zip
sh scripts/install-hare-toolchain.sh
```

### DragonFlyBSD

```sh
pkg install -y binutils git scdoc sdl2 zip
HARE_REF=0.26.0 HAREC_REF=0.26.0 sh scripts/install-hare-toolchain.sh
```

Select GNU bfd, which supports Hare's linker script, in the shell used for building, testing, and packaging:

```sh
export LDFLAGS="${LDFLAGS:-} -fuse-ld=bfd"
```

### Build and test

After installing dependencies, run these commands as a regular user. Ensure `/usr/local/bin` is in `PATH` and `hare version` works.

```sh
sh scripts/build.sh
./build/HareGirl path/to/game.gb
sh scripts/test.sh
```

The executable is generated at `build/HareGirl`. The default is a release build. Select a debug build with:

```sh
HAREGIRL_BUILD_MODE=debug sh scripts/build.sh
```

To require external test ROMs, matching the Linux release workflow, install `curl` and `python3`, then run:

```sh
sh scripts/fetch-test-roms.sh
HAREGIRL_REQUIRE_TEST_ROMS=1 sh scripts/test.sh
```

### Create a release archive

With `zip` installed, pass the platform and architecture matching your build machine. For example, on Linux amd64:

```sh
sh scripts/package.sh linux amd64
```

The script builds natively and packages the result as `dist/HareGirl-<version>-linux-amd64.zip`; it does not cross-compile. Use the target labels from the archive table above for other platforms (for example, `freebsd aarch64`, `openbsd amd64`, `netbsd amd64`, or `dragonfly amd64`).

## License

[MIT License](LICENSE)

The ROMs for individual games, SDL2, and Hare are subject to the terms of their respective copyright holders and distributors.
