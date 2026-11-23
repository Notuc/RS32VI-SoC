#!/usr/bin/env bash
# run_c.sh -- build a C program and run it on the CPU in simulation (Icarus).
#
#   sw/run_c.sh sw/c/c_test.c                 builds at -O0, -O2 and -Os and runs each
#   OPTS="-O2" sw/run_c.sh sw/c/c_test.c      only these optimisation levels
#
# Output per run:  PASS  |  FAIL: test case N  |  TIMEOUT
# "test case N" is the number main() returned (0 means everything passed).
# Exit status is non-zero if any run is not a PASS.

set -uo pipefail

[ "$#" -ge 1 ] || { echo "usage: $0 prog.c [more.c ...]"; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
NAME="$(basename "$1" .c)"
OPTS="${OPTS:--O0 -O2 -Os}"
MAX_CYCLES="${MAX_CYCLES:-5000000}"

status=0
for opt in $OPTS; do
    tag="$NAME${opt}"
    out="$ROOT/build/c/$tag"
    OPT="$opt" OUT="$out" "$HERE/build_c.sh" "$@" || { echo "$tag: BUILD FAILED"; status=1; continue; }

    iverilog -g2012 -DMEMFILE="\"$out.hex\"" -DMAX_CYCLES="$MAX_CYCLES" -o "$out.vvp" \
        "$ROOT"/src/cpu/*.sv "$ROOT"/src/soc/*.sv "$ROOT"/src/periph/*.sv "$ROOT"/src/axi/*.sv "$ROOT"/src/sim/*.sv "$ROOT/src/testbench/riscv_tests_tb.sv" 2> "$out.iverilog.log" \
        || { echo "$tag: COMPILE ERROR (see $out.iverilog.log)"; status=1; continue; }

    result="$(vvp "$out.vvp" 2>&1 | grep -E '^(PASS|FAIL|TIMEOUT)' | head -1)"
    printf '%-18s %s\n' "$tag" "${result:-NO RESULT}"
    [ "$result" = "PASS" ] || status=1
done
exit $status
