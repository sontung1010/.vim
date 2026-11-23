#!/usr/bin/env bash
# Build a single self-extracting offline installer: dist/vim-offline.sh
#
# It contains this config, all plugins (from ./plugged), a static vim and fzf
# for x86_64 and aarch64. Copy it to a machine without network and run it:
#
#   scp dist/vim-offline.sh edge:~ && ssh edge sh vim-offline.sh
#
# Options:
#   --update          run :PlugUpdate first (default: only :PlugInstall missing ones)
#   --no-plug         do not touch plugins, bundle ./plugged as it is
#   --arch "A B"      architectures to include (default: "x86_64 aarch64")
#   -o FILE           output file (default: dist/vim-offline.sh)
# Needs network the first time (no Docker/root); everything is cached in build/
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd -P)
ARCHES="x86_64 aarch64"
PLUG_CMD="PlugInstall --sync"
OUTFILE="$ROOT/dist/vim-offline.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --update)  PLUG_CMD="PlugUpdate --sync"; shift ;;
    --no-plug) PLUG_CMD=""; shift ;;
    --arch)    ARCHES=$2; shift 2 ;;
    -o)        OUTFILE=$(realpath -m "$2"); shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
BUILD="$ROOT/build"
mkdir -p "$BUILD/cache"

# ------------------------------------------------------------ 1. plugins
if [ -n "$PLUG_CMD" ]; then
  say "vim-plug: $PLUG_CMD"
  # vim-plug needs a real terminal (in `vim -es` it quits on stdin EOF), so give it a pty.
  cmd="vim -N -u '$ROOT/vimrc.vim' -i NONE +'$PLUG_CMD' +qa"
  if command -v script >/dev/null; then
    script -qec "$cmd" /dev/null </dev/null >/dev/null 2>&1 || true
  else
    eval "$cmd" || true
  fi
fi
[ -d "$ROOT/plugged" ] || { echo "error: $ROOT/plugged is empty" >&2; exit 1; }

# ------------------------------------------------------------ 2. static vim
ARCHES="$ARCHES" "$ROOT/tools/build-static-vim.sh"
VIM_DIR=$(ls -d "$BUILD"/vim-static/*/ | sort -V | tail -n 1)

# ------------------------------------------------------------ 3. fzf binaries
FZF_VERSION=$(sed -n 's/^version=//p' "$ROOT/plugged/fzf/install" 2>/dev/null | head -n 1 || true)
[ -n "$FZF_VERSION" ] || echo "warning: plugged/fzf not found, bundling without fzf binary" >&2
fzf_bin() {  # arch -> path of cached fzf binary
  local goarch=$1; [ "$1" = x86_64 ] && goarch=amd64; [ "$1" = aarch64 ] && goarch=arm64
  local dir="$BUILD/fzf/$FZF_VERSION" tgz="$BUILD/cache/fzf-$FZF_VERSION-linux_$goarch.tar.gz"
  if [ ! -x "$dir/fzf-$1" ]; then
    [ -s "$tgz" ] || curl -fsSL --retry 3 -o "$tgz" \
      "https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION/fzf-$FZF_VERSION-linux_$goarch.tar.gz"
    mkdir -p "$dir"; tar xzf "$tgz" -C "$dir" fzf; mv "$dir/fzf" "$dir/fzf-$1"
  fi
  echo "$dir/fzf-$1"
}

# ------------------------------------------------------------ 4. stage
STAGE="$BUILD/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE/.vim/offline"
say "staging config + plugins"
tar -C "$ROOT" -cf - --exclude=./.git --exclude='./plugged/*/.git' \
    --exclude=./build --exclude=./dist --exclude=./offline --exclude=.netrwhist --exclude='*.swp' --exclude='*~' . \
  | tar -C "$STAGE/.vim" -xf -
cp -a "$VIM_DIR/runtime" "$STAGE/.vim/offline/runtime"
for a in $ARCHES; do
  cp "$VIM_DIR/vim-$a" "$STAGE/.vim/offline/vim-$a"
  if [ -n "$FZF_VERSION" ]; then cp "$(fzf_bin "$a")" "$STAGE/.vim/offline/fzf-$a"; fi
done
{
  echo "built:   $(date -Iseconds)"
  echo "vim:     $(basename "$VIM_DIR")"
  echo "fzf:     ${FZF_VERSION:-none}"
  echo "arches:  $ARCHES"
  echo "commit:  $(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo unknown)"
} > "$STAGE/.vim/offline/BUILDINFO"

# ------------------------------------------------------------ 5. self-extracting script
mkdir -p "$(dirname "$OUTFILE")"
cat > "$OUTFILE" <<'EOF'
#!/bin/sh
# Self-extracting offline vim installer (built by ~/.vim/bundle.sh).
#   sh vim-offline.sh [install.sh options]   extract to a temp dir and install
#   sh vim-offline.sh --extract [DIR]        only extract (default: .)
set -e
line=$(awk '/^__PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$0")
if [ "${1:-}" = "--extract" ]; then
  mkdir -p "${2:-.}"; tail -n +"$line" "$0" | tar xzf - -C "${2:-.}"
  echo "extracted to ${2:-.}/.vim (run ${2:-.}/.vim/install.sh)"; exit 0
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vim-offline.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
tail -n +"$line" "$0" | tar xzf - -C "$tmp"
cat "$tmp/.vim/offline/BUILDINFO"
sh "$tmp/.vim/install.sh" "$@"
exit 0
__PAYLOAD_BELOW__
EOF
tar -C "$STAGE" -czf - .vim >> "$OUTFILE"
chmod +x "$OUTFILE"
rm -rf "$STAGE"

say "built $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
cat <<EOF

  scp $OUTFILE <host>:~
  ssh <host> sh vim-offline.sh
EOF
