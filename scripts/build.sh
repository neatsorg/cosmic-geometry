#!/usr/bin/env bash
# cosmic-geometry: 改造版 cosmic-comp と cos-cli をビルドしてインストールする。
#
# インストール済みの cosmic-comp と同じ版の上流ソース(タグ epoch-<版>)を取得し、
# patches/ のパッチを当ててビルドする。結果は次に置く:
#   ~/.local/lib/cosmic-geometry/<版>/cosmic-comp   (ラッパーが版を見て起動する)
#   ~/.local/lib/cosmic-geometry/cos-cli
#
# 使い方:
#   build.sh                 インストール済みの版向けにビルド(既にあれば何もしない)
#   build.sh --force         既にあっても作り直す
#   build.sh --version X.Y.Z 版を指定する
#   build.sh --auto          systemd から呼ぶとき用(結果をデスクトップ通知する)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$ROOT/patches"
LIB="${COSMIC_GEOMETRY_LIB:-$HOME/.local/lib/cosmic-geometry}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cosmic-geometry"

# 任意の設定(例: RUSTUP_TOOLCHAIN=1.95)。KEY=VALUE 形式
CONF_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/cosmic-geometry/env"
if [[ -f "$CONF_ENV" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$CONF_ENV"
    set +a
fi

COMP_REPO="https://github.com/pop-os/cosmic-comp"
PROTO_REPO="https://github.com/pop-os/cosmic-protocols"
COS_CLI_REPO="https://github.com/estin/cos-cli"
# patches/cos-cli.patch の土台にしたコミット
COS_CLI_REV="be3da634e8648f88a4734120292e524b3b7b9690"

force=0 auto=0 version=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=1 ;;
        --auto) auto=1 ;;
        --version) version="${2:?--version には版を指定してください}"; shift ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "build.sh: 不明な引数: $1" >&2; exit 2 ;;
    esac
    shift
done

notify() {
    echo "cosmic-geometry: $*"
    if [[ $auto == 1 ]] && command -v notify-send >/dev/null 2>&1; then
        notify-send -a cosmic-geometry "cosmic-geometry" "$*" || true
    fi
}
fail() { notify "ビルド失敗: $*"; exit 1; }

# インストール済み cosmic-comp の版(エポックとパッケージ版番号は除く)
installed_version() {
    local v=""
    if command -v pacman >/dev/null 2>&1; then
        v="$(pacman -Q cosmic-comp 2>/dev/null | awk '{print $2}')"
    elif command -v dpkg-query >/dev/null 2>&1; then
        v="$(dpkg-query -W -f='${Version}' cosmic-comp 2>/dev/null || true)"
    fi
    v="${v#*:}"
    printf '%s\n' "${v%%-*}"
}

[[ -n "$version" ]] || version="$(installed_version)"
[[ -n "$version" ]] || fail "cosmic-comp の版がわかりません(--version で指定してください)"

# プロセス名が cosmic-comp のままになるよう、版ごとのディレクトリに同じ名前で置く
target="$LIB/$version/cosmic-comp"
# 足りないものだけビルドする
need_comp=1 need_cli=1
[[ $force == 0 && -x "$target" ]] && need_comp=0
[[ $force == 0 && -x "$LIB/cos-cli" ]] && need_cli=0
if [[ $need_comp == 0 && $need_cli == 0 ]]; then
    echo "cosmic-geometry: $version 向けの改造版は既にあります: $target"
    exit 0
fi

mkdir -p "$CACHE" "$LIB"
# 同時に 2 つ走らないようにする(パス監視とログイン時の両方から起動されうる)
exec 9>"$CACHE/build.lock"
flock -n 9 || { echo "cosmic-geometry: 別のビルドが実行中です"; exit 0; }

[[ $auto == 1 && $need_comp == 1 ]] && notify "cosmic-comp $version 向けの改造版をビルドしています(完了まで公式版で動きます)"

src="$CACHE/src/$version"
rm -rf "$src"
mkdir -p "$src"

echo "== cosmic-comp epoch-$version を取得"
git -c advice.detachedHead=false clone -q --depth 1 --branch "epoch-$version" "$COMP_REPO" "$src/cosmic-comp" \
    || fail "cosmic-comp のタグ epoch-$version を取得できません"

# cosmic-comp が実際に使っている cosmic-protocols のコミットを Cargo.lock から読む
proto_rev="$(awk '
    /^name = "cosmic-protocols"$/ { hit = 1; next }
    hit && /^source = / { if (match($0, /#[0-9a-f]+"/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }
    /^\[\[package\]\]$/ { hit = 0 }
' "$src/cosmic-comp/Cargo.lock")"
[[ -n "$proto_rev" ]] || fail "Cargo.lock から cosmic-protocols のコミットを読めません"

echo "== cosmic-protocols $proto_rev を取得"
git init -q "$src/cosmic-protocols"
git -C "$src/cosmic-protocols" fetch -q --depth 1 "$PROTO_REPO" "$proto_rev" \
    || fail "cosmic-protocols $proto_rev を取得できません"
git -C "$src/cosmic-protocols" checkout -q FETCH_HEAD

echo "== パッチを適用"
git -C "$src/cosmic-protocols" apply "$PATCHES/cosmic-protocols.patch" \
    || fail "cosmic-protocols.patch が当たりません(上流が変わった可能性があります)"
git -C "$src/cosmic-comp" apply "$PATCHES/cosmic-comp.patch" \
    || fail "cosmic-comp.patch が当たりません(上流が変わった可能性があります)"

# cosmic-comp の cosmic-protocols を、パッチを当てた手元のものに向ける
awk '
    BEGIN { sec = "[patch.\"https://github.com/pop-os/cosmic-protocols\"]"; line = "cosmic-protocols = { path = \"../cosmic-protocols\" }" }
    $0 == sec { print; print line; in_sec = 1; done = 1; next }
    in_sec && /^cosmic-protocols *=/ { next }
    /^\[/ { in_sec = 0 }
    { print }
    END { if (!done) { print ""; print sec; print line } }
' "$src/cosmic-comp/Cargo.toml" > "$src/cosmic-comp/Cargo.toml.new"
mv "$src/cosmic-comp/Cargo.toml.new" "$src/cosmic-comp/Cargo.toml"

if [[ $need_comp == 1 ]]; then
    # cosmic-comp は rust-toolchain.toml で Rust の版を指定している。
    # RUSTUP_TOOLCHAIN で上書きされていなければ、その版を(なければ)インストールする
    if [[ -z "${RUSTUP_TOOLCHAIN:-}" ]] && command -v rustup >/dev/null 2>&1; then
        (cd "$src/cosmic-comp" && rustup toolchain install) \
            || fail "rust-toolchain.toml の Rust をインストールできません"
    fi

    echo "== cosmic-comp をビルド(数分〜十数分かかります)"
    (
        cd "$src/cosmic-comp"
        CARGO_TARGET_DIR="$CACHE/target-cosmic-comp" nice -n 19 cargo build --release
    ) || fail "cosmic-comp のビルドに失敗しました"
    install -D -m 755 "$CACHE/target-cosmic-comp/release/cosmic-comp" "$target.tmp"
    mv -f "$target.tmp" "$target"

fi

if [[ $need_cli == 1 ]]; then
    echo "== cos-cli を取得・ビルド"
    git init -q "$src/cos-cli"
    git -C "$src/cos-cli" fetch -q --depth 1 "$COS_CLI_REPO" "$COS_CLI_REV" \
        || fail "cos-cli $COS_CLI_REV を取得できません"
    git -C "$src/cos-cli" checkout -q FETCH_HEAD
    git -C "$src/cos-cli" apply "$PATCHES/cos-cli.patch" || fail "cos-cli.patch が当たりません"
    # 上流の Cargo.lock は古い cosmic-protocols 向けに依存の版を固定しているので、解決し直す
    rm -f "$src/cos-cli/Cargo.lock"
    (
        cd "$src/cos-cli"
        CARGO_TARGET_DIR="$CACHE/target-cos-cli" nice -n 19 cargo build --release \
            --config "patch.'https://github.com/pop-os/cosmic-protocols'.cosmic-protocols.path='$src/cosmic-protocols'"
    ) || fail "cos-cli のビルドに失敗しました"
    install -m 755 "$CACHE/target-cos-cli/release/cos-cli" "$LIB/cos-cli.tmp"
    mv -f "$LIB/cos-cli.tmp" "$LIB/cos-cli"
fi

# 古い版の改造版は直近 2 つだけ残す
ls -1dt "$LIB"/[0-9]*/ 2>/dev/null | tail -n +3 | xargs -r rm -rf --
rm -rf "$src"

if [[ $need_comp == 1 ]]; then
    notify "cosmic-comp $version 向けの改造版をインストールしました。次のログインから有効です"
else
    notify "cos-cli をインストールしました"
fi
