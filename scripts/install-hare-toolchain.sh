#!/bin/sh
set -eu

# Bootstrap the native Hare toolchain from source.  Some BSD package archives
# do not ship Hare for every architecture, while Hare itself supports each OS
# in the release matrix.
case "$(uname -s)" in
	Linux) platform=linux ;;
	FreeBSD) platform=freebsd ;;
	OpenBSD) platform=openbsd ;;
	NetBSD) platform=netbsd ;;
	DragonFly) platform=dragonfly ;;
	*) echo "unsupported operating system: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
	x86_64|amd64) arch=x86_64 ;;
	aarch64|arm64) arch=aarch64 ;;
	riscv64) arch=riscv64 ;;
	*) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

work_dir=${TMPDIR:-/tmp}/haregirl-toolchain
rm -rf "$work_dir"
mkdir -p "$work_dir"

jobs=1
if command -v nproc >/dev/null 2>&1; then
	jobs=$(nproc)
elif command -v getconf >/dev/null 2>&1; then
	jobs=$(getconf NPROCESSORS_ONLN 2>/dev/null || printf 1)
elif command -v sysctl >/dev/null 2>&1; then
	jobs=$(sysctl -n hw.ncpu 2>/dev/null || printf 1)
fi

git clone --depth 1 https://github.com/omenos/mirror-qbe.git "$work_dir/qbe"
make -C "$work_dir/qbe" -j"$jobs"
make -C "$work_dir/qbe" install PREFIX=/usr/local

for component in harec hare; do
	git clone --depth 1 "https://git.sr.ht/~sircmpwn/$component" "$work_dir/$component"
	cp "$work_dir/$component/configs/$platform.mk" "$work_dir/$component/config.mk"
	# Hare's bootstrap Makefile has generated-interface dependencies which are
	# not safe to parallelize on every BSD make implementation.
	if [ "$component" = hare ]; then
		make -C "$work_dir/$component" ARCH="$arch"
	else
		make -C "$work_dir/$component" -j"$jobs" ARCH="$arch"
	fi
	make -C "$work_dir/$component" install PREFIX=/usr/local ARCH="$arch"
done

hare version
