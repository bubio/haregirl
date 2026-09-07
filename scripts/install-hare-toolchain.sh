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

machine_name=$(uname -m)
[ "$platform" = netbsd ] && [ "$machine_name" = evbarm ] && machine_name=$(uname -p)
case "$machine_name" in
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
# NetBSD reports aarch64 hardware as "evbarm".  QBE recognizes neither that
# name nor uname -p, so without this override it silently selects x86_64.
case "$arch" in
	aarch64) printf '%s\n' '#define Deftgt T_arm64' > "$work_dir/qbe/config.h" ;;
	riscv64) printf '%s\n' '#define Deftgt T_rv64' > "$work_dir/qbe/config.h" ;;
esac
make -C "$work_dir/qbe" -j"$jobs"
make -C "$work_dir/qbe" install PREFIX=/usr/local

for component in harec hare; do
	case "$component" in
		harec) ref=${HAREC_REF:-master} ;;
		hare) ref=${HARE_REF:-master} ;;
	esac
	git clone --depth 1 --branch "$ref" "https://git.sr.ht/~sircmpwn/$component" "$work_dir/$component"
	if [ "$component" = hare ] && [ "$platform" = netbsd ] && [ "$arch" = aarch64 ]; then
		# Upstream currently defines NetBSD siginfo only for x86_64.
		cp scripts/netbsd-aarch64-siginfo.ha "$work_dir/$component/sys/+netbsd/+aarch64.ha"
		sed 's|^sys_ha = |sys_ha = sys/+netbsd/+aarch64.ha |' \
			"$work_dir/$component/makefiles/netbsd.aarch64.mk" \
			> "$work_dir/$component/makefiles/netbsd.aarch64.mk.new"
		mv "$work_dir/$component/makefiles/netbsd.aarch64.mk.new" \
			"$work_dir/$component/makefiles/netbsd.aarch64.mk"
	fi
	cp "$work_dir/$component/configs/$platform.mk" "$work_dir/$component/config.mk"
	# NetBSD's bmake does not let the ARCH command-line assignment override
	# the value included from config.mk.  Harec embeds this default target, so
	# update the copied configuration before building either component.
	if [ "$arch" != x86_64 ]; then
		sed "s/^ARCH = x86_64$/ARCH = $arch/" "$work_dir/$component/config.mk" \
			> "$work_dir/$component/config.mk.new"
		mv "$work_dir/$component/config.mk.new" "$work_dir/$component/config.mk"
	fi
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
