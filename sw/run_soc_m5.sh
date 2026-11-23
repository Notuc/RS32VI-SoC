#!/usr/bin/env bash
# run_soc_m5.sh -- build sw/c/stopwatch.c and run it on the whole SoC in Icarus.
# The testbench (src/testbench/soc_m5_tb.sv) presses buttons, types and flips switches.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
"$HERE/build_c.sh" "$HERE/c/stopwatch.c"
iverilog -g2012 -DMEMFILE="\"$ROOT/build/c/stopwatch.hex\"" -o "$ROOT/build/c/soc_m5_tb.vvp" \
    "$ROOT"/src/cpu/*.sv "$ROOT"/src/soc/*.sv "$ROOT"/src/periph/*.sv "$ROOT"/src/axi/*.sv "$ROOT"/src/sim/*.sv "$ROOT/src/testbench/soc_m5_tb.sv" \
    2>&1 | grep -v "sorry: constant selects" || true
vvp "$ROOT/build/c/soc_m5_tb.vvp" | grep -v '^WARNING.*readmemh'
