#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

"$root_dir/scripts/build.sh"
version=$($root_dir/build/haregirl --version)
[ "$version" = "HareGirl 0.1.0" ]
"$root_dir/build/haregirl" --help
if "$root_dir/build/haregirl" --unknown >/dev/null 2>&1; then
	echo "unknown option was accepted" >&2
	exit 1
fi

# SDL_VIDEODRIVER=dummy でヘッドレス環境(CI)でも --test-screen の一連の処理
# (SDL2 初期化・ウィンドウ/レンダラー/テクスチャ生成・描画・破棄)が
# エラーなく完走することを確認する。--frames で自動終了させる。
SDL_VIDEODRIVER=dummy "$root_dir/build/haregirl" --test-screen --frames 3

# SDL_AUDIODRIVER=dummy でヘッドレス環境(CI)でも --test-audio の一連の処理
# (SDL2 音声デバイス初期化・APU 駆動・SDL_QueueAudio・破棄)がエラーなく
# 完走することを確認する(フェーズ6 DoD の実時間再生パスのスモークテスト)。
SDL_AUDIODRIVER=dummy "$root_dir/build/haregirl" --test-audio --frames 3

# フェーズ8 DoD: 設定ファイルの保存・読込ラウンドトリップ(--config で任意の
# 場所を指定できることも合わせて確認する)。
config_test_file="$root_dir/build/config-test.ini"
rm -f "$config_test_file"
"$root_dir/build/haregirl" --config "$config_test_file" --scale 7 --volume 55 --save-config >/dev/null
printed=$("$root_dir/build/haregirl" --config "$config_test_file" --print-config)
case "$printed" in
	*"scale=7"*"volume=55"*) : ;;
	*)
		echo "config round-trip failed: $printed" >&2
		exit 1
		;;
esac
rm -f "$config_test_file"

# CPU・バスのフェーズ2単体スモークテスト。
stdlib_paths=$(hare version -v | awk '
	/^HAREPATH:/ { infield=1; next }
	infield && /^\t/ { sub(/^\t/, ""); print; next }
	infield { exit }
')
harepath="$root_dir/src"
for p in $stdlib_paths; do
	harepath="$harepath:$p"
done
# build.sh 同様、aarch64 環境での PIE リンクエラーを回避する。
HAREPATH="$harepath" LDFLAGS="-no-pie" hare build -q -o "$root_dir/build/core-test" "$root_dir/tests"
"$root_dir/build/core-test"
