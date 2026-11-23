#!/usr/bin/env bash
# Build fully static (musl) vim binaries that run on any Linux box of the same
# CPU architecture, without installing anything there.
#
# No Docker, no root: uses prebuilt musl cross toolchains from musl.cc (they are
# static themselves, so they run on any x86_64 Linux host). Host needs only
# gcc, make, curl and tic/infocmp (ncurses-bin) - all present on stock Ubuntu.
#
#   tools/build-static-vim.sh                 # x86_64 + aarch64
#   ARCHES=aarch64 tools/build-static-vim.sh  # only one arch
#
# Output (gitignored):
#   build/vim-static/<VIM_VERSION>/vim-<arch>   static binary
#   build/vim-static/<VIM_VERSION>/runtime/     arch-independent runtime files
# Downloads (sources + toolchains, ~250 MB) are cached in build/cache/.
set -euo pipefail

VIM_VERSION=${VIM_VERSION:-9.2.1393}
NCURSES_VERSION=${NCURSES_VERSION:-6.5}
ARCHES=${ARCHES:-"x86_64 aarch64"}
JOBS=${JOBS:-$(nproc)}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/vim-static/$VIM_VERSION
CACHE=$ROOT/build/cache
TC=$ROOT/build/work/toolchains   # unpacked on demand, removed after the build
mkdir -p "$CACHE"

# Rebuild when this script (flags, versions) changed since the last build.
BUILD_ID=$(sha256sum "$0" | cut -c1-16)
if [ -d "$OUT" ] && [ "$(cat "$OUT/.build-id" 2>/dev/null)" != "$BUILD_ID" ]; then
  echo "build script changed since last build -> rebuilding $OUT"
  rm -rf "$OUT"
fi
mkdir -p "$OUT" "$TC"
echo "$BUILD_ID" > "$OUT/.build-id"

missing=""
for a in $ARCHES; do [ -x "$OUT/vim-$a" ] || missing="$missing $a"; done
if [ -z "$missing" ] && [ -d "$OUT/runtime" ]; then
  echo "static vim $VIM_VERSION already built for: $ARCHES"
  exit 0
fi

for tool in gcc make curl tic infocmp; do
  command -v "$tool" >/dev/null || { echo "error: '$tool' is required on the build host" >&2; exit 1; }
done

say() { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
fetch() {  # url, cache file name
  [ -s "$CACHE/$2" ] && return 0
  say "download $1"
  curl -fL --retry 3 --progress-bar -o "$CACHE/$2.part" "$1"
  mv -f "$CACHE/$2.part" "$CACHE/$2"
}

fetch "https://github.com/vim/vim/archive/refs/tags/v$VIM_VERSION.tar.gz" "vim-$VIM_VERSION.tar.gz"
fetch "https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES_VERSION.tar.gz" "ncurses-$NCURSES_VERSION.tar.gz"

# Terminal types compiled into ncurses, used when the target has no terminfo db.
FALLBACKS=xterm-256color,xterm,screen-256color,screen,tmux-256color,tmux,linux,vt100

for ARCH in $missing; do
  T=$ARCH-linux-musl
  fetch "https://musl.cc/$T-cross.tgz" "$T-cross.tgz"
  [ -x "$TC/$T-cross/bin/$T-gcc" ] || { say "[$ARCH] unpack toolchain"; tar xzf "$CACHE/$T-cross.tgz" -C "$TC"; }
  export PATH="$TC/$T-cross/bin:$PATH"

  W=$ROOT/build/work/$ARCH; NC=$W/ncurses-root
  rm -rf "$W"; mkdir -p "$W"
  LOG=$W/build.log
  trap 'echo "error: [$ARCH] build failed, see $LOG" >&2' ERR

  say "[$ARCH] ncurses $NCURSES_VERSION"
  tar xzf "$CACHE/ncurses-$NCURSES_VERSION.tar.gz" -C "$W"
  ( cd "$W/ncurses-$NCURSES_VERSION"
    CC=$T-gcc PKG_CONFIG=false ./configure --host=$T --with-build-cc=gcc --prefix=/usr \
      --without-shared --without-cxx --without-cxx-binding --without-ada \
      --without-progs --without-tests --without-manpages --disable-db-install \
      --enable-widec --with-termlib --disable-stripping \
      --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo \
      --with-default-terminfo-dir=/usr/share/terminfo \
      --with-fallbacks=$FALLBACKS --with-tic-path="$(command -v tic)" \
      --with-infocmp-path="$(command -v infocmp)"
    make -j"$JOBS"
    make install DESTDIR="$NC" ) >>"$LOG" 2>&1

  say "[$ARCH] vim $VIM_VERSION"
  tar xzf "$CACHE/vim-$VIM_VERSION.tar.gz" -C "$W"
  ( cd "$W/vim-$VIM_VERSION"
    # Answers for configure checks that cannot run when cross-compiling.
    export vim_cv_toupper_broken=no vim_cv_terminfo=yes vim_cv_tgetent=zero \
      vim_cv_getcwd_broken=no vim_cv_stat_ignores_slash=no vim_cv_tty_group=world \
      vim_cv_tty_mode=0620 vim_cv_memmove_handles_overlap=yes \
      vim_cv_bcopy_handles_overlap=yes vim_cv_memcpy_handles_overlap=no
    # PKG_CONFIG=false: never pick up the build host's libraries (wayland, X11, ...).
    CC=$T-gcc PKG_CONFIG=false CPPFLAGS="-I$NC/usr/include -I$NC/usr/include/ncursesw" \
    LDFLAGS="-static -L$NC/usr/lib" \
    ./configure --host=$T --prefix=/opt/vim --with-features=huge --enable-multibyte \
      --with-tlib=tinfow --disable-gui --without-x --without-wayland --disable-nls --disable-netbeans \
      --disable-gpm --disable-sysmouse --disable-selinux --disable-smack \
      --disable-canberra --disable-libsodium --disable-xattr --enable-fail-if-missing \
      --with-compiledby=vim-offline
    make -j"$JOBS"
    $T-strip -o "$OUT/vim-$ARCH" src/vim
    if [ ! -d "$OUT/runtime" ]; then
      make -C src installruntime DESTDIR="$W/inst"
      cp -a "$W/inst/opt/vim/share/vim/"vim[0-9]* "$OUT/runtime"
    fi ) >>"$LOG" 2>&1
  trap - ERR
  say "[$ARCH] ok: $(du -h "$OUT/vim-$ARCH" | cut -f1)  $(file -b "$OUT/vim-$ARCH" | cut -d, -f1-2)"
done

rm -rf "$ROOT/build/work"
say "done: $OUT"
