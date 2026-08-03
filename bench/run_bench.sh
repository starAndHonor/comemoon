#!/usr/bin/env bash
# Run the comemo vs comemoon benchmark suite and print a comparison table.
#
# Usage: bash bench/run_bench.sh [--wasm]
#   (default: native for both sides)

cd "$(dirname "$0")/.."

TARGET="${1:-native}"
if [ "$TARGET" = "--wasm" ]; then TARGET="wasm"; fi

echo "=== Rust comemo (release) ==="
( cd refs/comemo && cargo run --release --example bench 2>/dev/null ) \
  | grep -E '^s[0-9]' > /tmp/bench_rust.txt
cat /tmp/bench_rust.txt

echo ""
echo "=== MoonBit comemoon ($TARGET) ==="
if [ "$TARGET" = "wasm" ]; then
  moon bench 2>/dev/null | grep -E 'ns ±|µs ±' > /tmp/bench_moon.txt
else
  moon bench --target native 2>/dev/null | grep -E 'ns ±|µs ±' > /tmp/bench_moon.txt
fi
cat /tmp/bench_moon.txt

echo ""
echo "=== Comparison (ns/iter; <1 = MoonBit faster) ==="
python3 - <<'PY'
import re

rust_lines = open('/tmp/bench_rust.txt').read().splitlines()
moon_lines = open('/tmp/bench_moon.txt').read().splitlines()

rust_rows = []
for line in rust_lines:
    m = re.match(r'(s\d+_\w+): \d+ iters in .*?\(([\d.]+) ns/iter\)', line)
    if m:
        rust_rows.append((m.group(1), float(m.group(2))))

moon_vals = []
for line in moon_lines:
    m = re.match(r'\s*([\d.]+) (ns|µs)', line)
    if m:
        v = float(m.group(1))
        if m.group(2) == 'µs':
            v *= 1000
        moon_vals.append(v)

names = ['s1_cold_single', 's2_warm_hits', 's3_calc_unrelated_edit',
         's4_same_key_1000x2', 's5_evict_cycle',
         's6_trackedmut_mutable', 's7_multi5_bundle']

print(f"{'scenario':<28} {'rust ns':>12} {'moon ns':>12} {'ratio':>8}")
print("-" * 64)
for i, name in enumerate(names):
    r = rust_rows[i][1] if i < len(rust_rows) else float('nan')
    m = moon_vals[i] if i < len(moon_vals) else float('nan')
    ratio = m / r if r and r > 0 else float('inf')
    flag = "FASTER" if ratio < 1 else "slower"
    print(f"{name:<28} {r:>12.2f} {m:>12.2f} {ratio:>8.2f} {flag}")
PY
