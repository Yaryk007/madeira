#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build GameHub's session host (host.c) as a stripped x86-64 PE and stage it
# as app/Madeira/arm64ec-windows/gamehubhost.exe (a build output), which the
# app starts as C:\windows\system32\gamehubhost.exe. Without it, GameHub
# keeps one game per app run.
# LLVM_MINGW=<dir with x86_64-w64-mingw32-clang> overrides the toolchain.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
MINGW="${LLVM_MINGW:-$REPO_ROOT/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin}"
CC="$MINGW/x86_64-w64-mingw32-clang"
OUT="$REPO_ROOT/app/Madeira/arm64ec-windows"
[ -x "$CC" ] || { echo "missing cross compiler: $CC (set LLVM_MINGW)" >&2; exit 1; }
mkdir -p "$OUT"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror -mwindows \
    -static -Wl,--strip-all -Wl,--no-insert-timestamp \
    -o "$OUT/gamehubhost.exe" "$DIR/host.c"
if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$OUT/gamehubhost.exe"; else sha256sum "$OUT/gamehubhost.exe"; fi
