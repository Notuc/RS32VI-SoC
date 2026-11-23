#!/usr/bin/env bash
# run_soc.sh -- build sw/c/io_demo.c and run it on the whole SoC in Icarus.
# The testbench (src/testbench/soc_tb.sv) acts as the terminal and the switches.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
"$HERE/build_c.sh" "$HERE/c/io_demo.c"
iverilog -g2012 -DMEMFILE="\"$ROOT/build/c/io_demo.hex\"" -o "$ROOT/build/c/soc_tb.vvp" \
    "$ROOT"/src/cpu/*.sv "$ROOT"/src/soc/*.sv "$ROOT"/src/periph/*.sv "$ROOT"/src/axi/*.sv "$ROOT"/src/sim/*.sv "$ROOT/src/testbench/soc_tb.sv"
vvp "$ROOT/build/c/soc_tb.vvp" | grep -v '^WARNING.*readmemh'
