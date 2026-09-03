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

HAREPATH="$harepath" hare build -o "$output_dir/haregirl" -l SDL2 "$root_dir/src/app"
