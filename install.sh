#!/bin/sh
# Install this vim config for the current user. No sudo, no network.
#
# Works from two places:
#   ~/.vim/install.sh           (git checkout)  -> just links ~/.vimrc
#   <extracted bundle>/.vim/install.sh          -> copies config + plugins to ~/.vim,
#                                                  installs the bundled static vim/fzf
#                                                  and sets PATH/EDITOR in ~/.bashrc
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
STAMP=$(date +%Y%m%d-%H%M%S)
MARK="# installed by ~/.vim/install.sh"
OURS_FILE=".vim-offline"            # marks a ~/.vim that this installer created

while [ $# -gt 0 ]; do
  case "$1" in
    --vim)      [ $# -ge 2 ] || { echo "--vim needs a value" >&2; exit 2; }
                WANT_VIM=$2; shift 2 ;;
    --vim=*)    WANT_VIM=${1#*=}; shift ;;
    --no-vi)    WANT_VI=0; shift ;;
    --prefix)   [ $# -ge 2 ] || { echo "--prefix needs a value" >&2; exit 2; }
                PREFIX=$2; shift 2 ;;
    --prefix=*) PREFIX=${1#*=}; shift ;;
    -h|--help)  awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case $WANT_VIM in auto|yes|no) ;; *) echo "--vim must be auto, yes or no" >&2; exit 2 ;; esac

say()  { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33mwarning:\033[0m %s\n' "$*" >&2; }

case $(uname -m) in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *)             ARCH=$(uname -m) ;;
esac

OFF="$SRC/offline"                  # only present in the offline bundle
BIN="$PREFIX/bin"
OPT="$PREFIX/opt/vim"
BUNDLE=0
[ "$SRC" != "$(cd "$DEST" 2>/dev/null && pwd -P)" ] && BUNDLE=1

# ------------------------------------------------------------ 1. config -> ~/.vim
if [ "$BUNDLE" = 1 ]; then
  if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    # A ~/.vim from a previous run of this installer keeps a single backup
    # (~/.vim.bak); anything else gets its own timestamped backup.
    bak="$DEST.bak-$STAMP"
    if [ -f "$DEST/$OURS_FILE" ]; then
      if [ ! -e "$DEST.bak" ] || [ -f "$DEST.bak/$OURS_FILE" ]; then bak="$DEST.bak"; fi
    fi
    rm -rf "$DEST.bak.tmp"
    [ "$bak" = "$DEST.bak" ] && [ -e "$bak" ] && mv "$bak" "$DEST.bak.tmp"
    say "backing up existing $DEST -> $bak"
    mv "$DEST" "$bak"
    rm -rf "$DEST.bak.tmp"
  fi
  say "copying config to $DEST"
  cp -a "$SRC" "$DEST"
  rm -rf "$DEST/offline"            # binaries are installed under $PREFIX instead
  if [ -f "$OFF/BUILDINFO" ]; then cp "$OFF/BUILDINFO" "$DEST/$OURS_FILE"; else : > "$DEST/$OURS_FILE"; fi
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
ours() { [ ! -e "$1" ] || grep -q "^$MARK" "$1" 2>/dev/null; }

write_wrapper() {  # name, extra vim args
  if ! ours "$BIN/$1"; then warn "$BIN/$1 exists and is not ours, leaving it alone"; return 0; fi
  cat > "$BIN/$1" <<EOF
#!/bin/sh
$MARK
VIM="$OPT" VIMRUNTIME="$OPT/runtime" exec "$OPT/bin/vim" $2 "\$@"
EOF
  chmod +x "$BIN/$1"
}

need_vim() {
  case $WANT_VIM in
    yes) return 0 ;;
    no)  return 1 ;;
  esac
  [ -d "$OPT" ] && return 0                           # ours already -> update it
  command -v vim >/dev/null 2>&1 || return 0          # no vim at all
  vim --version 2>/dev/null | grep -q '+eval' && return 1
  return 0                                            # vim-tiny / vim-small
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
    if [ "$WANT_VI" = 1 ]; then
      write_wrapper vi ""
    elif [ -e "$BIN/vi" ] && ours "$BIN/vi"; then
      rm -f "$BIN/vi"; say "removed $BIN/vi (--no-vi)"
    fi
    "$BIN/vim" --version | head -n 1
  fi
elif [ -d "$OFF" ]; then
  say "full vim already available ($(command -v vim)), skipping static vim (use --vim yes to force)"
fi

# ------------------------------------------------------------ 4. fzf binary (bundle only)
if [ -x "$OFF/fzf-$ARCH" ] && [ -d "$DEST/plugged/fzf" ]; then
  mkdir -p "$DEST/plugged/fzf/bin"
  cp "$OFF/fzf-$ARCH" "$DEST/plugged/fzf/bin/fzf"
  if [ -L "$BIN/fzf" ] && [ "$(readlink "$BIN/fzf")" = "$DEST/plugged/fzf/bin/fzf" ]; then
    :                                                 # ours already
  elif ! command -v fzf >/dev/null 2>&1 && [ ! -e "$BIN/fzf" ]; then
    mkdir -p "$BIN"
    ln -s "$DEST/plugged/fzf/bin/fzf" "$BIN/fzf"
    say "installed fzf to $BIN/fzf"
  fi
fi

# ------------------------------------------------------------ 5. PATH + EDITOR (bundle only)
# Managed block, rewritten in place on every run. EDITOR/VISUAL are only set
# when the user has not set them, so git commit / sudoedit use this vim.
set_block() {  # rc file
  rc=$1
  editor=vim
  if [ -e "$BIN/vim" ] && ours "$BIN/vim"; then editor="$BIN/vim"; fi
  block="# >>> vim-offline >>>"
  if [ -d "$BIN" ]; then
    block="$block
case \":\$PATH:\" in *\":$BIN:\"*) ;; *) export PATH=\"$BIN:\$PATH\" ;; esac"
  fi
  block="$block
[ -n \"\${EDITOR:-}\" ] || export EDITOR=\"$editor\"
[ -n \"\${VISUAL:-}\" ] || export VISUAL=\"$editor\"
# <<< vim-offline <<<"
  if grep -qx '# >>> vim-offline >>>' "$rc" 2>/dev/null && grep -qx '# <<< vim-offline <<<' "$rc"; then
    tmp="$rc.vim-offline.tmp"
    BLOCK=$block awk '
      $0 == "# >>> vim-offline >>>" { print ENVIRON["BLOCK"]; skip = 1; next }
      $0 == "# <<< vim-offline <<<" && skip { skip = 0; next }
      !skip { print }' "$rc" > "$tmp"
    cat "$tmp" > "$rc"; rm -f "$tmp"     # cat keeps symlinks/permissions of rc
    say "updated vim-offline block in $rc"
  else
    printf '\n%s\n' "$block" >> "$rc"
    say "added vim-offline block (PATH, EDITOR) to $rc"
  fi
}

if [ "$BUNDLE" = 1 ]; then
  set_block "$HOME/.bashrc"
  [ -f "$HOME/.zshrc" ] && set_block "$HOME/.zshrc"
fi

# ------------------------------------------------------------ done
[ -d "$DEST/plugged" ] || warn "no plugins in $DEST/plugged: run :PlugInstall (needs network) or use the offline bundle"
case ":$PATH:" in
  *":$BIN:"*) say "done" ;;
  *) if [ "$BUNDLE" = 1 ] && [ -d "$BIN" ]; then
       say "done. Open a new shell (or run: export PATH=\"$BIN:\$PATH\") to use it"
     else
       say "done"
     fi ;;
esac
