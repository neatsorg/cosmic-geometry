# cosmic-geometry

COSMIC デスクトップで「アプリをいつものサイズで起動する」ための改造一式です。

> **English summary:** COSMIC has no way for an external tool to resize or move another
> application's window (Wayland gives clients no such API). This project adds a
> `set_geometry` request to COSMIC's private `zcosmic_toplevel_manager_v1` protocol
> (patched `cosmic-comp`), a CLI (`cos-cli launch --size WxH -- app`) that resizes the
> app's new window as soon as it appears, and a helper that rewrites `.desktop`
> launchers to go through it. Everything installs per user (no root), and a launcher
> wrapper falls back to the official `cosmic-comp` whenever no patched build matches
> the installed version. This is an unofficial project, not affiliated with System76.

**非公式**のプロジェクトです。System76 および COSMIC 公式とは関係ありません。

## 何ができるか

```sh
# 1400x900 で、画面の利用可能領域の中央に起動する
cos-cli launch -a firefox --size 1400x900 -- firefox

# メニュー・ランチャーから起動したときにも効くよう .desktop を書き換える
cos-desktop-size firefox 1400x900 -- --follow 60

# 開いている窓のサイズを変える
cos-cli geometry -a firefox --size 1280x800
```

## しくみ

Wayland では、アプリの窓のサイズを決めるのはコンポジタ(COSMIC では `cosmic-comp`)ですが、
外部のツールからそれを頼む方法がありません。最大化やドラッグでのリサイズは、コンポジタが
アプリに「このサイズで描いて」(`configure`)と伝えて実現しています。そこで次のものを用意しました。

| 部品 | 中身 |
|---|---|
| `patches/cosmic-protocols.patch` | COSMIC 独自プロトコル `zcosmic_toplevel_manager_v1` に `set_geometry`(version 5)と capability `geometry` を追加 |
| `patches/cosmic-comp.patch` | `set_geometry` を受けて、フローティングの窓のサイズと位置を変える |
| `patches/cos-cli.patch` | [estin/cos-cli](https://github.com/estin/cos-cli) に `geometry` / `launch` サブコマンドを追加 |
| `bin/cos-desktop-size` | `.desktop` を `~/.local/share/applications` に上書きコピーし、Exec を `cos-cli launch` 経由にする |
| `scripts/cosmic-comp-wrapper` | `~/.local/bin/cosmic-comp` に置く起動ラッパー(後述) |
| `systemd/` | cosmic-comp のパッケージ更新を検知して、改造版を作り直すユーザーユニット |

### プロトコル

```
set_geometry(toplevel, x, y, width, height)   # since 5
```

- `width` / `height` は COSMIC が管理する外枠のサイズ(COSMIC がタイトルバーを描く窓はタイトルバー込み)。
- `x` / `y` は、窓がいる出力の利用可能領域(パネル等を除く)からの相対座標。軸ごとに、
  `-1` なら現在の中心を保ったままサイズを変え、`-2` 以下なら利用可能領域の中央に置く。
- 窓の最小・最大サイズと利用可能領域に収まるよう調整される。
- タイル中・最大化中・全画面中の窓には効かない(無視される)。
- 公式の COSMIC コンポーネントは version 4 までで接続するので影響を受けない。
  capability `geometry` は version 5 で接続したクライアントにだけ通知する。

### 版ずれへの備え(起動ラッパー)

改造版の cosmic-comp は、ほかの COSMIC コンポーネントと同じ版である必要があります。
`cosmic-session` は `cosmic-comp` を PATH から探すので、`/usr/bin` より前にある
`~/.local/bin/cosmic-comp` にラッパーを置き、次のように振る舞わせています。

1. インストール済みの cosmic-comp と**同じ版**の改造版があれば、それを起動する
2. なければ(パッケージ更新の直後など)**公式版**を起動し、裏で改造版のビルドを始める
3. `~/.config/cosmic-geometry/disable` があれば、常に公式版を起動する

また `/usr/bin/cosmic-comp` の更新を systemd のユーザーユニットが検知して、
次のログインまでに改造版を作り直します(結果はデスクトップ通知で知らせます)。
上流の変更でパッチが当たらなくなった場合は、公式版で動き続けます。

## 必要なもの

- COSMIC デスクトップ(cosmic-comp 1.9.0 で確認)
- パッケージの版を調べるために `pacman`(Arch 系)または `dpkg-query`(Debian 系)
- `git`、Rust(`rustup` 推奨)、cosmic-comp のビルドに必要なライブラリ
  (libinput、libseat、libxkbcommon、mesa、pixman、udev、wayland など。ディストリの
  cosmic-comp パッケージのビルド依存と同じ)
- セッションの PATH で `~/.local/bin` が `/usr/bin` より前にあること

## インストール

```sh
git clone <このリポジトリ>
cd cosmic-geometry
scripts/install.sh
```

上流の cosmic-comp(インストール済みの版のタグ `epoch-<版>`)、それが使う cosmic-protocols、
cos-cli を取得してパッチを当て、ビルドします(数分〜十数分)。終わったらログインし直してください。
次のコマンドで改造版が動いているか確認できます。

```sh
readlink /proc/$(pgrep -x cosmic-comp)/exe    # ~/.local/lib/cosmic-geometry/<版>/cosmic-comp なら改造版
```

cosmic-comp は `rust-toolchain.toml` で Rust の版を指定しています。ほかの版を使いたい場合は
`~/.config/cosmic-geometry/env` に `RUSTUP_TOOLCHAIN=1.95` のように書きます。

インストールされるもの:

| 場所 | 中身 |
|---|---|
| `~/.local/share/cosmic-geometry/` | スクリプト・パッチ一式 |
| `~/.local/lib/cosmic-geometry/` | 改造版 cosmic-comp(`<版>/cosmic-comp`、直近 2 版)と cos-cli |
| `~/.local/bin/cosmic-comp` | 起動ラッパー |
| `~/.local/bin/cos-cli`、`cos-desktop-size` | コマンド |
| `~/.config/systemd/user/cosmic-geometry-rebuild.{path,service}` | 更新の検知と再ビルド |
| `~/.cache/cosmic-geometry/` | ビルド用キャッシュ |

同じ名前のファイルが既にあれば `*.before-cosmic-geometry` に退避します。

## 使い方

### cos-cli launch

```
cos-cli launch [-a APP_ID] --size WxH [--pos X,Y|center|keep] [--follow 秒]
               [--timeout 秒] [--reapply ミリ秒] [--keep-maximized] -- コマンド [引数...]
```

- 起動前から開いていた窓は対象外。新しく現れた(app_id が部分一致する)窓にだけ適用します。
- `--pos` の既定は `center`(利用可能領域の中央)。COSMIC は新しい窓を直前の窓から
  少しずらして置くので、そのままでは中央に来ないためです。
- `--follow N`:最初の 1 つで終わらず、起動から N 秒以内に現れた一致する窓すべてに適用します。
  Firefox のプロファイル選択画面のように、本体より先に別の窓が出るアプリ用です。
  最初の 1 つは N 秒を過ぎても `--timeout`(既定 30 秒)まで待ちます。
- 前回の状態を復元して最大化で開くアプリ(Firefox など)は、最大化を解除してから適用します。
  最大化のままにしたいときは `--keep-maximized`。
- アプリが表示直後に自分でサイズを戻すことがあるので、800ms 後にもう一度適用します(`--reapply`)。
- `--` より後ろはすべてアプリの引数として渡します。

### cos-cli geometry

```
cos-cli geometry (-a APP_ID | -i INDEX) --size WxH [--pos X,Y|center|keep] [--wait 秒]
```

`--pos` の既定は `keep`(今の中心を保ってサイズだけ変える)。`cos-cli info` で窓の一覧と app_id を確認できます。

### cos-desktop-size

```
cos-desktop-size <desktop-id> <W>x<H> [<X>,<Y>|center|keep] [-- <cos-cli launch の追加オプション>]
cos-desktop-size --list
cos-desktop-size --remove <desktop-id>
```

システムの `.desktop` を `~/.local/share/applications` にコピーし、すべての `Exec`
(アクションを含む)を `cos-cli launch` 経由に書き換えます。引数は Desktop Entry 仕様どおりに
引用されます。app_id には `StartupWMClass` か desktop-id を使います。違う場合は
`cos-cli info` で調べて `-- -a <app_id>` で上書きしてください。

## 困ったとき

- **ログインできない・画面が出ない**:`Ctrl+Alt+F3` などで TTY に切り替えてログインし、
  `mkdir -p ~/.config/cosmic-geometry && touch ~/.config/cosmic-geometry/disable` を実行してください。
  次のログインから公式版の cosmic-comp で起動します。
- **再ビルドの状況**:`journalctl --user -u cosmic-geometry-rebuild.service`
- **手動で再ビルド**:`~/.local/share/cosmic-geometry/scripts/build.sh --force`

## 開発時の動作確認(入れ子起動)

改造版をビルドした後、ログアウトせずに今のデスクトップの中で試せます。

```sh
env -u COSMIC_SESSION_SOCK COSMIC_BACKEND=winit ~/.local/lib/cosmic-geometry/<版>/cosmic-comp &
WAYLAND_DISPLAY=<増えたソケット名> cos-cli launch -a CosmicEdit --size 900x600 -- cosmic-edit
```

入れ子の cosmic-comp は `~/.local/state/cosmic-comp/outputs.ron` に仮想モニター `WINIT-0` の
設定を書き足すので、先に退避しておき、終わったら戻してください。

## 制限

- 表示直後の一瞬は、アプリ自身が決めたサイズで表示されます(窓が一覧に載るのは配置された後のため)。
- タイル表示中の窓には効きません。
- 未確認:COSMIC がタイトルバーを描く窓(SSD)、XWayland のアプリ、全ワークスペース表示(sticky)の窓。
- ディストリが cosmic-comp に独自パッチを当てている場合、そのパッチは改造版に入りません
  (上流のタグからビルドするため)。

## アンインストール

```sh
~/.local/share/cosmic-geometry/scripts/uninstall.sh [--purge]
```

ラッパー・コマンド・ユニット・改造版を削除し、`cos-desktop-size` で作った `.desktop` も消して
元に戻します。次のログインから公式版の cosmic-comp で起動します。

## ライセンス

GPL-3.0(`LICENSE`)。`patches/cosmic-comp.patch` は GPL-3.0 の
[cosmic-comp](https://github.com/pop-os/cosmic-comp)、`patches/cosmic-protocols.patch` は MIT の
[cosmic-protocols](https://github.com/pop-os/cosmic-protocols)、`patches/cos-cli.patch` は MIT の
[cos-cli](https://github.com/estin/cos-cli)(Copyright (c) 2026 Evgeniy Tatarkin)に対する変更です。
それぞれの元のライセンスにも従います。
