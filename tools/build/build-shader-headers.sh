#!/usr/bin/env bash
# Compile DXMT's .metal airconv shaders to .air and embed them as C headers.
# The DXMT meson flow does this via its metalir/hexdump generators; the iOS
# static-library flow consumes the headers directly, so this step reproduces
# that generation with the same compiler, flags, and xxd embedding.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SRC="$ROOT/dxmt/src/airconv/shaders"
OUT="$ROOT/build/dxmt-ios/shader-headers"
SHADERS=(air_msad air_samplepos air_tessellation)

# Metal toolchain 32023 (Xcode 27) gave __metal_atomic_fetch_add_explicit a fifth
# memory-flags argument. Pass it when the toolchain defines it.
python3 - "$SRC/air_tessellation.metal" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
old = "  return __metal_atomic_fetch_add_explicit(out_count, 1, int(memory_order_relaxed), __METAL_MEMORY_SCOPE_THREADGROUP__);\n"
if "__METAL_MEMORY_FLAGS_NONE__" not in s:
    if old not in s:
        raise SystemExit(f"expected atomic call not found in {p}")
    new = ("#ifdef __METAL_MEMORY_FLAGS_NONE__\n"
           + old.replace("__);", "__, __METAL_MEMORY_FLAGS_NONE__);")
           + "#else\n" + old + "#endif\n")
    p.write_text(s.replace(old, new, 1))
PY

# The Glass fork builds on GitHub's Macs, whose toolchain can define the flags constant
# while its atomic still takes four arguments. Ask the compiler instead of the macro.
probe=$(mktemp -d)
cat > "$probe/probe.metal" <<'METAL'
#include <metal_stdlib>
using namespace metal;
kernel void probe(threadgroup atomic_int *c [[threadgroup(0)]]) {
  __metal_atomic_fetch_add_explicit(c, 1, int(memory_order_relaxed), __METAL_MEMORY_SCOPE_THREADGROUP__, __METAL_MEMORY_FLAGS_NONE__);
}
METAL
if ! xcrun -sdk macosx metal -o "$probe/probe.air" -c "$probe/probe.metal" -std=metal3.1 --target=air64-apple-macos14.0 2>/dev/null; then
  echo "shader headers: this toolchain's atomic takes four arguments"
  sed -i.orig 's/, __METAL_MEMORY_FLAGS_NONE__//' "$SRC/air_tessellation.metal"
fi
rm -rf "$probe"

for name in "${SHADERS[@]}"; do
  [[ -f "$SRC/$name.metal" ]] || { echo "ERROR: missing shader source $SRC/$name.metal (is the dxmt submodule checked out?)" >&2; exit 1; }
  echo "shader $name: compiling"
  mkdir -p "$OUT"
  xcrun -sdk macosx metal -o "$OUT/$name.air" -c "$SRC/$name.metal" \
    -std=metal3.1 --target=air64-apple-macos14.0
  xxd -n "$name" -i "$OUT/$name.air" "$OUT/$name.h"
done
