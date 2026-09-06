# HareGirl

[English](README.md)

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

Hare言語で書かれた、SDL2をマルチメディア層に利用するGame Boy Colorエミュレーターです。コマンドラインからROMを指定して起動します。

エミュレーションコアは[BubiBoy Lite](https://github.com/bubio/BubiBoyLite)（Odin + SDL2、MIT License）をHareへ移植したものです。



## 現状

実験的な開発中のプロジェクトです。CPU、PPU、APU、タイマー、割り込み、ジョイパッド、シリアル、カートリッジ（MBC1/2/3/5を含む）、DMG/CGB向けの基本的なエミュレーション、バッテリーバックアップRAM、設定ファイル、SDL2による映像・音声出力を実装しています。

互換性やパフォーマンスにはまだ改善の余地があります。市販ゲームのROMを使用する場合は、所有権と各ROMの利用条件を確認してください。

![Astro Rabby on HareGirl running on Ubuntu 24.04](/docs/Screenshot1.png)
![Astro Rabby on HareGirl running on FreeBSD](/docs/Screenshot2.png)

## 対応プラットフォーム

- Ubuntu 22.04以降（amd64 / arm64）
- FreeBSD 14.4以降（x64）

GitHub Releasesでは、次のネイティブ実行ファイルを含むzipを配布します。

| 対象 | 配布ファイル |
|---|---|
| Linux amd64 | `HareGirl-<version>-linux-amd64.zip` |
| Linux arm64 | `HareGirl-<version>-linux-arm64.zip` |
| FreeBSD amd64 | `HareGirl-<version>-freebsd-amd64.zip` |

各zipには `HareGirl` と `LICENSE` が含まれます。実行時にはシステムのSDL2が必要です。

Ubuntuでは次のように導入します。

```sh
sudo apt install libsdl2-2.0-0
```

FreeBSDでは次のように導入します。

```sh
pkg install sdl2
```

## ソースからビルドする場合

- [Hare](https://harelang.org/)
- SDL2（実行時ライブラリおよびビルド用ヘッダー）

Ubuntuではビルド用ヘッダーも導入します。

```sh
sudo apt install libsdl2-2.0-0 libsdl2-dev
```

FreeBSDではHareツールチェーンを含むパッケージを導入します。

```sh
pkg install hare-lang sdl2
```

## ビルド

```sh
git clone https://github.com/bubio/haregirl.git
cd haregirl
./scripts/build.sh
```

実行ファイルは `build/HareGirl` に生成されます。詳細な動作確認は次のコマンドで行えます。

```sh
./scripts/test.sh
```

デバッグ用ビルドは環境変数で切り替えられます。

```sh
HAREGIRL_BUILD_MODE=debug ./scripts/build.sh
```

## 使い方

```text
HareGirl [options] game.gb|game.gbc
```

Game Boy / Game Boy Color ROMを起動するには、次のように実行します。

```sh
./build/HareGirl path/to/game.gb
./build/HareGirl path/to/game.gbc
```

画面倍率、音量、補間方法はコマンドラインで一時的に変更できます。

```sh
./build/HareGirl --scale 3 --volume 80 --shader smooth path/to/game.gb
```

設定を保存または確認するには、次のように実行します。

```sh
./build/HareGirl --scale 3 --volume 80 --shader smooth --save-config
./build/HareGirl --print-config
```

テスト画面・テスト音声はROMなしで起動できます。`--frames N` を指定すると、Nフレーム描画または再生した後に終了します。

```sh
./build/HareGirl --test-screen --frames 300
./build/HareGirl --test-audio --frames 300
```

ベンチマークにはROMと正のフレーム数が必要です。

```sh
./build/HareGirl --benchmark --frames 3600 path/to/game.gb
```

オプション:

| オプション | 説明 |
|---|---|
| `-h`, `--help` | 使い方を表示して終了 |
| `-v`, `--version` | バージョンを表示して終了 |
| `--test-screen` | テスト画面を表示する |
| `--test-audio` | テスト音声を再生する |
| `--benchmark` | 指定したROMをベンチマークする。ROMと `--frames N`（N > 0）が必須 |
| `--frames N` | テスト・ベンチマーク・ROM実行をNフレーム後に終了する |
| `--config PATH` | 設定ファイルのパスを指定する |
| `--scale N` | 画面の表示倍率を指定する（1〜8、既定値: 4。9以上は8） |
| `--shader KIND` | 拡大表示の補間方法を `nearest` または `smooth` から選ぶ（既定値: `nearest`） |
| `--volume N` | 音量を指定する（0〜100、既定値: 100） |
| `--save-config` | 現在有効な設定を保存して終了する |
| `--print-config` | 現在有効な設定を表示して終了する |

ゲーム中の標準キーボード操作は、矢印キー（十字キー）、`Z`（A）、`X`（B）、`Enter`（Start）、右`Shift`（Select）、`Esc`（終了）です。SDL2対応ゲームコントローラーでは、十字キーまたは左スティック（方向）、右側フェイスボタン（A）、下側フェイスボタン（B）、Start/Options（Start）、Back/Share（Select）を使用できます。割り当てはBubiBoy Liteと同じです。

`--help` の表示言語は実行環境のロケールに従います。`ja` 系のロケールでは日本語、その他では英語を表示します。`LC_ALL`、`LC_MESSAGES`、`LANG` の順に参照します。

設定ファイルを指定しない場合、`$XDG_CONFIG_HOME/HareGirl/config.ini`、未設定時は `$HOME/.config/HareGirl/config.ini` を使用します。

## ライセンス

[MIT License](LICENSE)

HareGirlのソースコードにはBubiBoy Lite由来のコードが含まれています。各ゲームのROM、SDL2、Hareのライセンスはそれぞれの著作権者および配布元の条件に従います。
