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

# フェーズ9 DoD: 「ROM 起動、入力、終了が CLI から完結する」ことのスモークテスト。
# 電池バックアップ付きMBC1・8KB RAMの最小ROMを合成し、--frames で自動終了させた後
# 電池バックアップRAMがROMと同じディレクトリへ "<rom>.sav" として書き出されることを
# 確認する(実際のジョイパッド入力・描画・音声経路もこの起動シーケンスで通過する)。
rom_test_file="$root_dir/build/rom-test.gb"
rom_test_sav="$root_dir/build/rom-test.sav"
rm -f "$rom_test_file" "$rom_test_sav"
# printf の \xHH は POSIX 未規定(dash では解釈されずリテラル文字列になる)ため、
# 全シェルで確実に動く8進エスケープ(\0NNN)でバイト列を組み立てる。
head -c 32768 /dev/zero > "$rom_test_file"
printf '\000\303\000\001' | dd of="$rom_test_file" bs=1 seek=256 conv=notrunc status=none
printf '\003' | dd of="$rom_test_file" bs=1 seek=327 conv=notrunc status=none # 0x147: MBC1+RAM+BATTERY
printf '\000' | dd of="$rom_test_file" bs=1 seek=328 conv=notrunc status=none # 0x148: 32KB ROM
printf '\002' | dd of="$rom_test_file" bs=1 seek=329 conv=notrunc status=none # 0x149: 8KB RAM
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$root_dir/build/haregirl" --frames 3 "$rom_test_file"
if [ ! -f "$rom_test_sav" ]; then
	echo "ROM launch smoke test: battery save file was not created" >&2
	exit 1
fi
# Benchmarking must work without SDL and must not create a battery save.
rm -f "$rom_test_sav"
SDL_VIDEODRIVER=unavailable SDL_AUDIODRIVER=unavailable \
	"$root_dir/build/haregirl" --benchmark --frames 3 "$rom_test_file"
[ ! -f "$rom_test_sav" ]
if "$root_dir/build/haregirl" --benchmark "$rom_test_file" >/dev/null 2>&1; then
	echo "benchmark without positive frame count was accepted" >&2
	exit 1
fi
rm -f "$rom_test_file" "$rom_test_sav"

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
