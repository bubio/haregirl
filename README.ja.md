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

実験的な開発中のプロジェクトです。CPU、PPU、APU、タイマー、割り込み、ジョイパッド、シリアル、カートリッジ（MBC1/2/3/5を含む）、DMG/CGB向けの基本的なエミュレーション、バッテリーバックアップRAM、セーブステート、設定ファイル、SDL2による映像・音声出力を実装しています。

互換性やパフォーマンスにはまだ改善の余地があります。市販ゲームのROMを使用する場合は、所有権と各ROMの利用条件を確認してください。

![Astro Rabby on HareGirl running on Ubuntu 24.04](/docs/Screenshot1.png)
![Astro Rabby on HareGirl running on FreeBSD](/docs/Screenshot2.png)

## 対応プラットフォーム

[リリースワークフロー](.github/workflows/release.yml)では、次の環境でネイティブビルド・テスト・zip作成を行います。記載したバージョンはワークフローのビルド環境です。

| OS | ビルド環境 | アーキテクチャ |
|---|---|---|
| Linux | Ubuntu 22.04 | amd64 |
| Linux | Ubuntu 24.04 | arm64 / riscv64 |
| FreeBSD | 14.4 | amd64 / aarch64 |
| OpenBSD | 7.8 | amd64 / aarch64 |
| NetBSD | 11 | amd64 |
| DragonFlyBSD | 6.4 | amd64 |

リリース公開時に全対象のビルドが成功すると、次のzipがGitHub Releaseに添付されます。リリース以外の実行では、Actionsのアーティファクトから取得できます。

| 対象 | 配布ファイル |
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

各zipには `HareGirl` と `LICENSE` が含まれます。実行時にはシステムのSDL2が必要です。次のコマンドは管理者権限で実行してください（Ubuntuでは `sudo` を使用）。

| OS | SDL2の導入 |
|---|---|
| Ubuntu | `sudo apt install libsdl2-2.0-0` |
| FreeBSD / DragonFlyBSD | `pkg install sdl2` |
| OpenBSD | `pkg_add sdl2` |
| NetBSD | `pkg_add SDL2` |

NetBSDではSDL2が利用するX11ライブラリも必要です。最小構成の環境では、下記のビルド手順にある `install-netbsd-x11.sh` で補えます。zipを展開したディレクトリでは `./HareGirl path/to/game.gb` で起動します。

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

ゲーム中のキーボードとSDL2対応ゲームコントローラーの操作:

| 動作 | キーボード | コントローラー |
|---|---|---|
| 十字キー | 矢印キー | 十字キーまたは左スティック |
| A | `Z` | 右側フェイスボタン |
| B | `X` | 下側フェイスボタン |
| Start | `Enter` | Start / Options |
| Select | 右 `Shift` | Back / Share |
| ステート保存 | `F5` | — |
| ステート読込 | `F7` | — |
| 終了 | `Esc` | — |

セーブステートはROMと同じ場所へ拡張子 `.state` で保存され、別のROM用のステートは読み込まれません。

`--help` の表示言語は実行環境のロケールに従います。`ja` 系のロケールでは日本語、その他では英語を表示します。`LC_ALL`、`LC_MESSAGES`、`LANG` の順に参照します。

設定ファイルを指定しない場合、`$XDG_CONFIG_HOME/HareGirl/config.ini`、未設定時は `$HOME/.config/HareGirl/config.ini` を使用します。

## ソースからビルドする場合

[Hare](https://harelang.org/)ツールチェーンとSDL2の開発用ライブラリが必要です。対象OS・アーキテクチャ上でネイティブビルドします。まずGitを導入し、リポジトリを取得してください。

```sh
git clone https://github.com/bubio/haregirl.git
cd haregirl
```

以下の依存パッケージ導入とツールチェーンのインストールは管理者権限で実行します（Ubuntuでは `sudo` を使用）。スクリプトはリポジトリのルートから実行してください。`install-hare-toolchain.sh` はQBE・harec・Hareをソースから構築して `/usr/local` に導入します。既定ではharec・Hareの `master` を使用し、OSとアーキテクチャを自動判定します。

### Ubuntu / Linux

```sh
sudo apt-get update
sudo apt-get install -y build-essential git scdoc libsdl2-dev zip curl python3
sudo sh scripts/install-hare-toolchain.sh
```

riscv64では、ワークフローと同じHare 0.26.0を指定して、上記のツールチェーン導入コマンドを置き換えます。

```sh
sudo env HARE_REF=0.26.0 HAREC_REF=0.26.0 sh scripts/install-hare-toolchain.sh
```

### FreeBSD

amd64ではパッケージ版のHareを使用します。

```sh
pkg install -y git hare-lang sdl2 zip curl python3
```

aarch64ではツールチェーンをソースから構築します。

```sh
pkg install -y binutils git scdoc sdl2 zip
sh scripts/install-hare-toolchain.sh
```

### OpenBSD

```sh
pkg_add binutils git scdoc sdl2 zip
sh scripts/install-hare-toolchain.sh
```

ビルド・テスト・パッケージ作成を実行するシェルで、SDL2のライブラリ検索パスを設定します。

```sh
export LDFLAGS="${LDFLAGS:-} -L/usr/local/lib"
```

### NetBSD

最小構成の環境で不足するX11ライブラリを補い、依存パッケージとツールチェーンを導入します。X11の確認・導入スクリプトは、必要なライブラリが存在する場合は何も変更しません。

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

Hareのリンカスクリプトに対応するGNU bfdを使用するため、ビルド・テスト・パッケージ作成を実行するシェルで次を設定します。

```sh
export LDFLAGS="${LDFLAGS:-} -fuse-ld=bfd"
```

### ビルドとテスト

依存関係の導入後は、通常のユーザー権限で実行できます。`/usr/local/bin` が `PATH` に含まれ、`hare version` が実行できることを確認してください。

```sh
sh scripts/build.sh
./build/HareGirl path/to/game.gb
sh scripts/test.sh
```

実行ファイルは `build/HareGirl` に生成されます。既定はリリースビルドです。デバッグ用ビルドは環境変数で切り替えられます。

```sh
HAREGIRL_BUILD_MODE=debug sh scripts/build.sh
```

Linuxのリリースワークフローと同様に外部テストROMを必須としてテストするには、`curl` と `python3` を導入したうえで実行します。

```sh
sh scripts/fetch-test-roms.sh
HAREGIRL_REQUIRE_TEST_ROMS=1 sh scripts/test.sh
```

### 配布用zipの作成

`zip` を導入したうえで、現在のビルド環境に一致するプラットフォーム名とアーキテクチャを指定します。次はLinux amd64の例です。このスクリプトはネイティブビルドを行い、指定した名前で梱包します。クロスコンパイルは行いません。

```sh
sh scripts/package.sh linux amd64
```

出力先は `dist/HareGirl-<version>-linux-amd64.zip` です。ほかの対象は上の配布ファイル表に合わせて指定してください（例: `freebsd aarch64`、`openbsd amd64`、`netbsd amd64`、`dragonfly amd64`）。

## ライセンス

[MIT License](LICENSE)

各ゲームのROM、SDL2、Hareのライセンスはそれぞれの著作権者および配布元の条件に従います。
