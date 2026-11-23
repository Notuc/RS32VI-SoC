#!/usr/bin/env bash
# run_rv32ui.sh -- build and run a riscv-tests suite (SUITE=rv32ui default, or rv32mi) on the CPU with Icarus Verilog.
#
#   sw/run_rv32ui.sh               run everything
#   sw/run_rv32ui.sh add lw        run just these
#   SUITE=rv32mi sw/run_rv32ui.sh  machine-mode suite (CSRs, traps)
#   ALL=1 sw/run_rv32ui.sh         include the skipped tests (ma_data; rv32mi: breakpoint, pmpaddr)
#
# Prints one PASS/FAIL line per test and a summary.  Exit status is non-zero
# if any test did not pass.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
SUITE="${SUITE:-rv32ui}"
OUT="$ROOT/build/$SUITE"

"$HERE/build_tests.sh" "$@" > /dev/null || { echo "build failed, run sw/build_tests.sh to see why"; exit 1; }

if [ "$#" -gt 0 ]; then
    TESTS="$*"
else
    TESTS="$(cd "$OUT" && ls *.hex | sed 's/\.hex$//')"
    if [ -z "${ALL:-}" ]; then
        TESTS="$(echo "$TESTS" | grep -v -x -e ma_data -e breakpoint -e pmpaddr)"
    fi
fi

pass=0; total=0; failed=""
for t in $TESTS; do
    total=$((total + 1))
    iverilog -g2012 -DMEMFILE="\"$OUT/$t.hex\"" -o "$OUT/$t.vvp" \
        "$ROOT"/src/cpu/*.sv "$ROOT"/src/soc/*.sv "$ROOT"/src/periph/*.sv "$ROOT"/src/axi/*.sv "$ROOT"/src/sim/*.sv "$ROOT/src/testbench/riscv_tests_tb.sv" 2> "$OUT/$t.iverilog.log" \
        || { printf '%-10s COMPILE ERROR (see %s)\n' "$t" "$OUT/$t.iverilog.log"; failed="$failed $t"; continue; }
    result="$(vvp "$OUT/$t.vvp" 2>&1 | grep -E '^(PASS|FAIL|TIMEOUT)' | head -1)"
    printf '%-10s %s\n' "$t" "${result:-NO RESULT}"
    if [ "$result" = "PASS" ]; then pass=$((pass + 1)); else failed="$failed $t"; fi
done

echo "------------------------------------------"
echo "$pass / $total passed"
[ -n "$failed" ] && echo "not passing:$failed"
[ "$pass" -eq "$total" ]
