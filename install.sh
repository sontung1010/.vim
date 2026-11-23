#!/bin/sh
# Install this vim config for the current user. No sudo, no network.
#
# Works from two places:
#   ~/.vim/install.sh           (git checkout)  -> just links ~/.vimrc
#   <extracted bundle>/.vim/install.sh          -> copies config + plugins to ~/.vim
#                                                  and installs the bundled static vim/fzf
#
# Options:
#   --vim auto|yes|no   install the bundled static vim (default: auto = only if there
#                       is no full vim in PATH, e.g. the box only has vim-tiny `vi`)
#   --no-vi             do not put `vi` (-> static vim) into the bin dir
#   --prefix DIR        where binaries go (default: ~/.local -> DIR/bin, DIR/opt/vim)
set -eu

SRC=$(cd "$(dirname "$0")" && pwd -P)
DEST="$HOME/.vim"
PREFIX="$HOME/.local"
WANT_VIM=auto
WANT_VI=1
ADDED_BIN=0
STAMP=$(date +%Y%m%d-%H%M%S)
MARK="# installed by ~/.vim/install.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --vim) WANT_VIM=$2; shift 2 ;;
    --vim=*) WANT_VIM=${1#*=}; shift ;;
    --no-vi) WANT_VI=0; shift ;;
    --prefix) PREFIX=$2; shift 2 ;;
    --prefix=*) PREFIX=${1#*=}; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33mwarning:\033[0m %s\n' "$*" >&2; }

case $(uname -m) in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *)             ARCH=$(uname -m) ;;
esac

# ------------------------------------------------------------ 1. config -> ~/.vim
if [ "$SRC" != "$(cd "$DEST" 2>/dev/null && pwd -P)" ]; then
  if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    say "backing up existing $DEST -> $DEST.bak-$STAMP"
    mv "$DEST" "$DEST.bak-$STAMP"
  fi
  say "copying config to $DEST"
  cp -a "$SRC" "$DEST"
  rm -rf "$DEST/offline"            # binaries are installed under $PREFIX instead
fi

# ------------------------------------------------------------ 2. ~/.vimrc symlink
if [ "$(readlink "$HOME/.vimrc" 2>/dev/null || true)" != "$DEST/vimrc.vim" ]; then
  if [ -e "$HOME/.vimrc" ] || [ -L "$HOME/.vimrc" ]; then
    say "backing up existing ~/.vimrc -> ~/.vimrc.bak-$STAMP"
    mv "$HOME/.vimrc" "$HOME/.vimrc.bak-$STAMP"
  fi
  ln -s "$DEST/vimrc.vim" "$HOME/.vimrc"
  say "linked ~/.vimrc -> $DEST/vimrc.vim"
fi

# ------------------------------------------------------------ 3. static vim (bundle only)
OFF="$SRC/offline"
BIN="$PREFIX/bin"
OPT="$PREFIX/opt/vim"

ours() { [ ! -e "$1" ] || grep -q "^$MARK" "$1" 2>/dev/null; }

write_wrapper() {  # name, extra vim args
  if ! ours "$BIN/$1"; then warn "$BIN/$1 exists and is not ours, leaving it alone"; return; fi
  cat > "$BIN/$1" <<EOF
#!/bin/sh
$MARK
VIM="$OPT" VIMRUNTIME="$OPT/runtime" exec "$OPT/bin/vim" $2 "\$@"
EOF
  chmod +x "$BIN/$1"
  ADDED_BIN=1
}

need_vim() {
  case $WANT_VIM in
    yes) return 0 ;;
    no)  return 1 ;;
  esac
  [ -d "$OPT" ] && return 0                          # ours already -> update it
  command -v vim >/dev/null 2>&1 || return 0          # no vim at all
  vim --version 2>/dev/null | grep -q '+eval' && return 1
  return 0                                           # vim-tiny / vim-small
}

if [ -d "$OFF" ] && need_vim; then
  if [ ! -x "$OFF/vim-$ARCH" ]; then
    warn "bundle has no static vim for $ARCH (has: $(cd "$OFF" && ls vim-* 2>/dev/null | tr '\n' ' '))"
  elif ! "$OFF/vim-$ARCH" --version >/dev/null 2>&1; then
    warn "bundled vim-$ARCH does not run on this machine, skipping"
  else
    say "installing static vim ($ARCH) to $OPT"
    rm -rf "$OPT"; mkdir -p "$OPT/bin" "$BIN"
    cp "$OFF/vim-$ARCH" "$OPT/bin/vim"
    cp -a "$OFF/runtime" "$OPT/runtime"
    write_wrapper vim ""
    write_wrapper vimdiff "-d"
    write_wrapper view "-R"
    [ "$WANT_VI" = 1 ] && write_wrapper vi ""
    "$BIN/vim" --version | head -n 1
  fi
elif [ -d "$OFF" ]; then
  say "full vim already available ($(command -v vim)), skipping static vim (use --vim yes to force)"
fi

# ------------------------------------------------------------ 4. fzf binary (bundle only)
if [ -x "$OFF/fzf-$ARCH" ] && [ -d "$DEST/plugged/fzf" ]; then
  mkdir -p "$DEST/plugged/fzf/bin"
  cp "$OFF/fzf-$ARCH" "$DEST/plugged/fzf/bin/fzf"
  if ! command -v fzf >/dev/null 2>&1; then
    mkdir -p "$BIN"
    ln -sf "$DEST/plugged/fzf/bin/fzf" "$BIN/fzf"
    ADDED_BIN=1
    say "installed fzf to $BIN/fzf"
  fi
fi

# ------------------------------------------------------------ 5. PATH
if [ "$ADDED_BIN" = 1 ]; then
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || [ "$rc" = "$HOME/.bashrc" ] || continue
    grep -q '>>> vim-offline >>>' "$rc" 2>/dev/null && continue
    cat >> "$rc" <<EOF

# >>> vim-offline >>>
case ":\$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:\$PATH" ;; esac
# <<< vim-offline <<<
EOF
    say "added $BIN to PATH in $rc"
  done
fi

# ------------------------------------------------------------ done
[ -d "$DEST/plugged" ] || warn "no plugins in $DEST/plugged: run :PlugInstall (needs network) or use the offline bundle"
case "$ADDED_BIN:$PATH:" in
  0:*|*":$BIN:"*) say "done" ;;
  *) say "done. Open a new shell (or run: export PATH=\"$BIN:\$PATH\") to use the new vim" ;;
esac
