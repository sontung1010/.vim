#!/usr/bin/env bash
# Build a single self-extracting offline installer: dist/vim-offline.sh
#
# It contains this config, the plugins pinned in plugins.lock, and a static vim
# and fzf for x86_64 and aarch64. Run it on a machine without network/sudo:
#
#   ./bundle.sh --deploy edge1 --deploy user@edge2     # build, scp, install
#   ./bundle.sh && scp dist/vim-offline.sh edge:~ && ssh edge sh vim-offline.sh
#
# Options:
#   --update          :PlugUpdate, then pin the new plugin commits in plugins.lock
#   --no-plug         do not run vim-plug (no network); plugins still come from the lock
#   --arch "A B"      architectures to include (default: "x86_64 aarch64")
#   -o FILE           output file (default: dist/vim-offline.sh)
#   --deploy HOST     after building, scp + run the installer on HOST (repeatable)
#   -- ARGS...        extra options for install.sh on the deploy hosts (e.g. -- --vim yes)
# Needs network the first time (no Docker/root); everything is cached in build/
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd -P)
ARCHES="x86_64 aarch64"
UPDATE=0
RUN_PLUG=1
OUTFILE="$ROOT/dist/vim-offline.sh"
LOCK="$ROOT/plugins.lock"
HOSTS=()
INSTALL_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --update)  UPDATE=1; shift ;;
    --no-plug) RUN_PLUG=0; shift ;;
    --arch)    ARCHES=${2:?--arch needs a value}; shift 2 ;;
    -o)        OUTFILE=$(realpath -m "${2:?-o needs a value}"); shift 2 ;;
    --deploy)  HOSTS+=("${2:?--deploy needs a host}"); shift 2 ;;
    --)        shift; INSTALL_ARGS=("$@"); break ;;
    -h|--help)  awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ "$UPDATE" = 1 ] && [ "$RUN_PLUG" = 0 ] && { echo "--update and --no-plug conflict" >&2; exit 2; }

say()  { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
BUILD="$ROOT/build"
mkdir -p "$BUILD/cache"

# ------------------------------------------------------------ 1. plugins (vim-plug)
if [ "$RUN_PLUG" = 1 ]; then
  plug_cmd="PlugInstall --sync"; [ "$UPDATE" = 1 ] && plug_cmd="PlugUpdate --sync"
  say "vim-plug: $plug_cmd"
  # vim-plug needs a real terminal (in `vim -es` it quits on stdin EOF), so give it a pty.
  cmd="vim -N -u '$ROOT/vimrc.vim' -i NONE +'$plug_cmd' +qa"
  if command -v script >/dev/null; then
    script -qec "$cmd" /dev/null </dev/null >/dev/null 2>&1 || true
  else
    eval "$cmd" || true
  fi
fi

# Plugin list straight from vimrc: "name dir" per line.
PLUGS_TXT="$BUILD/plugs.txt"
rm -f "$PLUGS_TXT"
vim -N -u "$ROOT/vimrc.vim" -i NONE -es \
  -c "call writefile(map(sort(keys(g:plugs)), {_, k -> k . ' ' . g:plugs[k].dir}), '$PLUGS_TXT')" \
  -c 'qa!' </dev/null || true
[ -s "$PLUGS_TXT" ] || die "could not read the plugin list from vimrc.vim"

# ------------------------------------------------------------ 2. resolve plugin commits
declare -A LOCKED=()
if [ -f "$LOCK" ]; then
  while read -r name commit _; do
    [ -n "$name" ] && [ "${name:0:1}" != "#" ] && LOCKED[$name]=$commit
  done < "$LOCK"
fi

declare -A COMMIT=() DIR=()
NAMES=()
while read -r name dir; do
  dir=${dir%/}
  [ -d "$dir/.git" ] || die "plugin '$name' is not installed in $dir (run without --no-plug, needs network)"
  head=$(git -C "$dir" rev-parse HEAD)
  commit=${LOCKED[$name]:-}
  if [ "$UPDATE" = 1 ] || [ -z "$commit" ]; then
    [ -z "$commit" ] && [ "$UPDATE" = 0 ] && say "new plugin '$name': pinning ${head:0:7}"
    commit=$head
  elif ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
    say "fetching locked commit ${commit:0:7} for '$name'"
    # vim-plug clones are shallow: fetch that commit by sha (or deepen as a fallback).
    git -C "$dir" fetch --quiet origin "$commit" 2>/dev/null \
      || git -C "$dir" fetch --quiet --unshallow origin 2>/dev/null || true
    git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null \
      || die "locked commit $commit of '$name' not found (fix plugins.lock or use --update)"
  fi
  [ "$commit" = "$head" ] || warn "'$name': bundling locked ${commit:0:7}, ~/.vim/plugged has ${head:0:7} (./bundle.sh --update to bump)"
  NAMES+=("$name"); COMMIT[$name]=$commit; DIR[$name]=$dir
done < "$PLUGS_TXT"

for name in "${!LOCKED[@]}"; do
  [ -n "${COMMIT[$name]:-}" ] || say "plugin '$name' removed from vimrc: dropping it from the lock"
done

{
  echo "# Plugin commits bundled by ./bundle.sh. Bump with: ./bundle.sh --update"
  for name in "${NAMES[@]}"; do
    echo "$name ${COMMIT[$name]} $(git -C "${DIR[$name]}" remote get-url origin 2>/dev/null || echo -)"
  done
} > "$LOCK.tmp"
if cmp -s "$LOCK.tmp" "$LOCK"; then rm -f "$LOCK.tmp"; else mv "$LOCK.tmp" "$LOCK"; say "wrote plugins.lock"; fi

# ------------------------------------------------------------ 3. static vim
ARCHES="$ARCHES" "$ROOT/tools/build-static-vim.sh"
VIM_DIR=$(ls -d "$BUILD"/vim-static/*/ | sort -V | tail -n 1)
VIM_DIR=${VIM_DIR%/}

# ------------------------------------------------------------ 4. fzf binaries
FZF_VERSION=""
if [ -n "${COMMIT[fzf]:-}" ]; then
  FZF_VERSION=$(git -C "${DIR[fzf]}" show "${COMMIT[fzf]}:install" | sed -n 's/^version=//p' | head -n 1)
fi
[ -n "$FZF_VERSION" ] || warn "no fzf plugin in vimrc: bundling without fzf binary"
fzf_bin() {  # arch -> path of cached fzf binary
  local goarch=$1; [ "$1" = x86_64 ] && goarch=amd64; [ "$1" = aarch64 ] && goarch=arm64
  local dir="$BUILD/fzf/$FZF_VERSION" tgz="$BUILD/cache/fzf-$FZF_VERSION-linux_$goarch.tar.gz"
  if [ ! -x "$dir/fzf-$1" ]; then
    if [ ! -s "$tgz" ]; then
      curl -fsSL --retry 3 -o "$tgz.part" \
        "https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION/fzf-$FZF_VERSION-linux_$goarch.tar.gz"
      mv -f "$tgz.part" "$tgz"
    fi
    mkdir -p "$dir"; tar xzf "$tgz" -C "$dir" fzf; mv "$dir/fzf" "$dir/fzf-$1"
  fi
  echo "$dir/fzf-$1"
}

# ------------------------------------------------------------ 5. stage
STAGE="$BUILD/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE/.vim/offline" "$STAGE/.vim/plugged"
say "staging config + ${#NAMES[@]} plugins"
tar -C "$ROOT" -cf - --exclude=./.git --exclude=./plugged --exclude=./build --exclude=./dist \
    --exclude=./offline --exclude=./.vim-offline --exclude=.netrwhist --exclude='*.swp' --exclude='*~' . \
  | tar -C "$STAGE/.vim" -xf -
for name in "${NAMES[@]}"; do
  mkdir -p "$STAGE/.vim/plugged/$name"
  git -C "${DIR[$name]}" archive "${COMMIT[$name]}" | tar -C "$STAGE/.vim/plugged/$name" -xf -
done
# git archive has no doc/tags (vim-plug generates them), so build them here.
vim -N -u NONE -i NONE -es \
  -c "for d in glob('$STAGE/.vim/plugged/*/doc', 0, 1) | exe 'silent! helptags' fnameescape(d) | endfor" \
  -c 'qa!' </dev/null || true

cp -a "$VIM_DIR/runtime" "$STAGE/.vim/offline/runtime"
for a in $ARCHES; do
  [ -x "$VIM_DIR/vim-$a" ] || die "no static vim for $a in $VIM_DIR"
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

# ------------------------------------------------------------ 6. self-extracting script
mkdir -p "$(dirname "$OUTFILE")"
cat > "$OUTFILE.tmp" <<'EOF'
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
# Unpack under $HOME, not /tmp: /tmp may be noexec or a small tmpfs.
tmp=$(mktemp -d "$HOME/.vim-offline-tmp.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
tail -n +"$line" "$0" | tar xzf - -C "$tmp"
cat "$tmp/.vim/offline/BUILDINFO"
sh "$tmp/.vim/install.sh" "$@"
exit 0
__PAYLOAD_BELOW__
EOF
tar -C "$STAGE" -czf - .vim >> "$OUTFILE.tmp"
chmod +x "$OUTFILE.tmp"
mv -f "$OUTFILE.tmp" "$OUTFILE"
rm -rf "$STAGE"
say "built $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"

# ------------------------------------------------------------ 7. deploy
if [ ${#HOSTS[@]} -eq 0 ]; then
  cat <<EOF

  ./bundle.sh --deploy <host>        # or by hand:
  scp $OUTFILE <host>:~ && ssh <host> sh vim-offline.sh
EOF
  exit 0
fi

remote_args=""
for a in "${INSTALL_ARGS[@]}"; do remote_args+=" '${a//\'/\'\\\'\'}'"; done
failed=()
for h in "${HOSTS[@]}"; do
  say "deploy -> $h"
  if scp -q "$OUTFILE" "$h:vim-offline.sh" \
     && ssh "$h" "sh vim-offline.sh$remote_args; rc=\$?; rm -f vim-offline.sh; exit \$rc"; then
    say "$h: ok"
  else
    warn "$h: FAILED"; failed+=("$h")
  fi
done
[ ${#failed[@]} -eq 0 ] || die "deploy failed on: ${failed[*]}"
