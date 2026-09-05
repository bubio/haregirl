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

# aarch64 環境 (Ubuntu の gcc は --enable-default-pie) では、Hare の rt が
# 参照する glibc の environ シンボルへのアクセスが PIC 非対応のコード生成に
# なっており、PIE としてリンクすると失敗する。-no-pie でリンクすることで回避する。
HAREPATH="$harepath" LDFLAGS="-no-pie" hare build "$@" -o "$output_dir/HareGirl" -l SDL2 "$root_dir/src/app"
