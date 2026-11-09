#!/usr/bin/env bash
# cosmic-geometry をユーザー単位でインストールする(sudo 不要)。
#
#   ~/.local/share/cosmic-geometry/   スクリプト・パッチ一式
#   ~/.local/lib/cosmic-geometry/     改造版 cosmic-comp(<版>/cosmic-comp)と cos-cli
#   ~/.local/bin/cosmic-comp          起動ラッパー(版が合う改造版、なければ公式版を起動)
#   ~/.local/bin/cos-cli, cos-desktop-size
#   ~/.config/systemd/user/cosmic-geometry-rebuild.{path,service}
#
# 使い方: scripts/install.sh [--no-build]
# 既に同名のファイルがあり、cosmic-geometry のものでなければ *.before-cosmic-geometry に退避する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARE="$HOME/.local/share/cosmic-geometry"
LIB="$HOME/.local/lib/cosmic-geometry"
BIN="$HOME/.local/bin"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
MARK="cosmic-geometry: cosmic-comp の起動ラッパー"

build=1
[[ "${1:-}" == "--no-build" ]] && build=0

# dst が cosmic-geometry のものでなければ退避する
make_room() {
    local dst="$1"
    [[ -e "$dst" || -L "$dst" ]] || return 0
    if [[ -L "$dst" ]]; then
        case "$(readlink "$dst")" in "$SHARE"/*|"$LIB"/*) rm -f -- "$dst"; return 0 ;; esac
    elif grep -qF "$MARK" "$dst" 2>/dev/null; then
        rm -f -- "$dst"; return 0
    fi
    local bak="$dst.before-cosmic-geometry"
    [[ -e "$bak" || -L "$bak" ]] && bak="$bak.$(date +%Y%m%d%H%M%S)"
    mv -- "$dst" "$bak"
    echo "退避しました: $dst -> $bak"
}

echo "== ファイルを配置"
mkdir -p "$SHARE" "$LIB" "$BIN" "$UNITS"
for d in scripts patches bin systemd; do
    rm -rf -- "${SHARE:?}/$d"
    cp -a "$ROOT/$d" "$SHARE/$d"
done
cp -a "$ROOT/README.md" "$ROOT/LICENSE" "$SHARE/"

make_room "$BIN/cosmic-comp"
install -m 755 "$SHARE/scripts/cosmic-comp-wrapper" "$BIN/cosmic-comp"
make_room "$BIN/cos-desktop-size"
ln -s "$SHARE/bin/cos-desktop-size" "$BIN/cos-desktop-size"

echo "== systemd ユーザーユニットを登録"
install -m 644 "$SHARE/systemd/cosmic-geometry-rebuild.path" "$SHARE/systemd/cosmic-geometry-rebuild.service" "$UNITS/"
systemctl --user daemon-reload
systemctl --user enable --now cosmic-geometry-rebuild.path

if [[ $build == 1 ]]; then
    echo "== 改造版をビルド"
    "$SHARE/scripts/build.sh"
fi

if [[ -x "$LIB/cos-cli" ]]; then
    make_room "$BIN/cos-cli"
    ln -s "$LIB/cos-cli" "$BIN/cos-cli"
fi

# cosmic-session が ~/.local/bin のラッパーを見つけられるか(PATH の順序)を確認する
session_path="$(systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p')"
first="$(PATH="${session_path:-$PATH}" command -v cosmic-comp || true)"
if [[ "$first" != "$BIN/cosmic-comp" ]]; then
    echo "注意: セッションの PATH で最初に見つかる cosmic-comp が $first です。"
    echo "      ~/.local/bin を /usr/bin より前に置かないとラッパーが使われません。"
fi

echo "完了。ログインし直すと改造版の cosmic-comp で起動します。"
