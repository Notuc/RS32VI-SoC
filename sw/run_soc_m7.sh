#!/usr/bin/env bash
# run_soc_m7.sh -- build sw/c/axi_gpio.c and run it on the whole SoC in Icarus.
# The testbench (src/testbench/soc_m7_tb.sv) drives the switches and a model of the AMD GPIO.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
"$HERE/build_c.sh" "$HERE/c/axi_gpio.c"
iverilog -g2012 -DMEMFILE="\"$ROOT/build/c/axi_gpio.hex\"" -o "$ROOT/build/c/soc_m7_tb.vvp" \
    "$ROOT"/src/cpu/*.sv "$ROOT"/src/soc/*.sv "$ROOT"/src/periph/*.sv "$ROOT"/src/axi/*.sv "$ROOT"/src/sim/*.sv "$ROOT/src/testbench/soc_m7_tb.sv" \
    2>&1 | grep -v "sorry: constant selects" || true
vvp "$ROOT/build/c/soc_m7_tb.vvp" | grep -v '^WARNING.*readmemh'
