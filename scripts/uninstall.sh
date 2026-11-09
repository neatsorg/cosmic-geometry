#!/usr/bin/env bash
# cosmic-geometry をアンインストールする。次のログインから公式の cosmic-comp に戻る。
# 使い方: scripts/uninstall.sh [--purge]   (--purge はビルド用キャッシュも消す)
set -euo pipefail

SHARE="$HOME/.local/share/cosmic-geometry"
LIB="$HOME/.local/lib/cosmic-geometry"
BIN="$HOME/.local/bin"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cosmic-geometry"
MARK="cosmic-geometry: cosmic-comp の起動ラッパー"

# cos-desktop-size で作った .desktop は cos-cli を経由するので、消して元の .desktop に戻す
# (cos-cli を消した後に残ると、そのアプリがメニューから起動できなくなる)
if [[ -x "$SHARE/bin/cos-desktop-size" ]]; then
    "$SHARE/bin/cos-desktop-size" --list | cut -f1 | while read -r id; do
        "$SHARE/bin/cos-desktop-size" --remove "$id"
    done
fi

systemctl --user disable --now cosmic-geometry-rebuild.path 2>/dev/null || true
rm -f -- "$UNITS/cosmic-geometry-rebuild.path" "$UNITS/cosmic-geometry-rebuild.service"
systemctl --user daemon-reload 2>/dev/null || true

# 自分が置いたものだけ消す
grep -qF "$MARK" "$BIN/cosmic-comp" 2>/dev/null && rm -f -- "$BIN/cosmic-comp"
for f in cos-cli cos-desktop-size; do
    if [[ -L "$BIN/$f" ]]; then
        case "$(readlink "$BIN/$f")" in "$SHARE"/*|"$LIB"/*) rm -f -- "$BIN/$f" ;; esac
    fi
done
rm -rf -- "$SHARE" "$LIB"
[[ "${1:-}" == "--purge" ]] && rm -rf -- "$CACHE"

echo "アンインストールしました。退避したファイル(*.before-cosmic-geometry)があれば手で戻してください。"
