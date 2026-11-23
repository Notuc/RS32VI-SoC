#!/usr/bin/env bash
# run_adapter_tb.sh -- unit test of the AXI4-Lite slave adapter with a random master.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
mkdir -p "$ROOT/build"
iverilog -g2012 -o "$ROOT/build/axil_adapter_tb.vvp" \
    "$ROOT/src/axi/axil_slave_adapter.sv" "$ROOT/src/sim/axil_checker.sv" "$ROOT/src/testbench/axil_adapter_tb.sv"
vvp "$ROOT/build/axil_adapter_tb.vvp"

