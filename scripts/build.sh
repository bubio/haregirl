#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$root_dir/build"

mkdir -p "$output_dir"

# hare にデフォルトの HAREPATH (標準ライブラリ・サードパーティのパス) を問い合わせ、
# プロジェクトの src/ ディレクトリを先頭に加えて HAREPATH を組み立てる。
# HAREPATH 環境変数はデフォルト値を上書き(追加ではない)するため、
# 標準ライブラリのパスを明示的に引き継ぐ必要がある。
stdlib_paths=$(hare version -v | awk '
	/^HAREPATH:/ { infield=1; next }
	infield && /^\t/ { sub(/^\t/, ""); print; next }
	infield { exit }
')
harepath="$root_dir/src"
for p in $stdlib_paths; do
	harepath="$harepath:$p"
done

# Normal builds omit Hare's runtime debugger. Keep an explicit debug mode
# for detailed failure backtraces; release mode still checks assertions.
case "${HAREGIRL_BUILD_MODE:-release}" in
	release) set -- -R ;;
	debug) set -- ;;
	*)
		printf '%s\n' 'HAREGIRL_BUILD_MODE must be release or debug' >&2
		exit 1
		;;
esac

# Linux/aarch64・riscv64 の gcc は PIE を既定にする。Hare のランタイムが参照する
# glibc の environ へは PIC 非対応のコードを生成するため、これらの組み合わせだけ
# PIE を無効にする。FreeBSD のリンカへ Linux 固有の -no-pie を渡さないことが重要。
link_flags=${LDFLAGS:-}
if [ "$(uname -s)" = Linux ]; then
	case "$(uname -m)" in
		aarch64|riscv64) link_flags="$link_flags -no-pie" ;;
	esac
fi
# BSD package managers install third-party libraries outside the base linker
# search path. SDL2 headers are found by harec, but its library still needs an
# explicit link-time path.
case "$(uname -s)" in
	FreeBSD|DragonFly) link_flags="$link_flags -L/usr/local/lib" ;;
	NetBSD) link_flags="$link_flags -L/usr/pkg/lib -Wl,-R/usr/pkg/lib" ;;
esac

HAREPATH="$harepath" LDFLAGS="$link_flags" hare build "$@" -o "$output_dir/HareGirl" -l SDL2 "$root_dir/src/app"
