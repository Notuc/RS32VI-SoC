#!/usr/bin/env bash
# run_all.sh -- every simulation test, one summary.  Takes a few minutes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
cd "$ROOT"
declare -a RESULTS
status=0
record () { RESULTS+=("$(printf '%-34s %s' "$1" "$2")"); [[ "$2" == PASS* ]] || status=1; }
suite () {   # "N / M passed" -> PASS if N == M
    local n m; read -r n _ m _ <<< "$1"
    if [[ -n "$n" && "$n" == "$m" ]]; then echo "PASS ($1)"; else echo "FAIL (${1:-no result})"; fi
}

iverilog -g2012 -DMEMFILE='"sw/smoke/program.hex"' -o build/smoke_sim \
    src/cpu/*.sv src/soc/*.sv src/periph/*.sv src/axi/*.sv src/sim/*.sv src/testbench/cpu_tb.sv 2>/dev/null
r=$(vvp build/smoke_sim | grep -E "ALL TESTS PASSED|FAILED" | head -1)
record "M2 smoke test (hand-written)" "$([[ $r == "ALL TESTS PASSED" ]] && echo PASS || echo "FAIL ($r)")"

r=$("$HERE/run_rv32ui.sh" 2>&1 | grep "passed")
record "M2 riscv-tests rv32ui" "$(suite "$r")"

r=$(SUITE=rv32mi "$HERE/run_rv32ui.sh" 2>&1 | grep "passed")
record "M5 riscv-tests rv32mi" "$(suite "$r")"

for prog in c_test trap_test pipeline_test; do
    r=$("$HERE/run_c.sh" "$HERE/c/$prog.c" 2>&1 | grep -v "text=")
    record "C $prog (-O0 -O2 -Os)" "$( [[ $(echo "$r" | grep -c ' PASS$') -eq 3 ]] && echo PASS || echo "FAIL: $(echo $r)")"
done

r=$("$HERE/run_soc.sh" 2>&1 | grep -E "^(PASS|FAIL)|AXI PROTOCOL ERROR" | head -1)
record "M4 SoC demo (soc_tb)" "${r:-NO RESULT}"
r=$("$HERE/run_soc_m5.sh" 2>&1 | grep -E "^(PASS|FAIL)|AXI PROTOCOL ERROR" | head -1)
record "M5 stopwatch (soc_m5_tb)" "${r:-NO RESULT}"
r=$("$HERE/run_adapter_tb.sh" 2>&1 | grep -E "^(PASS|FAIL)|AXI PROTOCOL ERROR" | head -1)
record "M7 AXI slave adapter (unit)" "${r:-NO RESULT}"
r=$("$HERE/run_soc_m7.sh" 2>&1 | grep -E "^(PASS|FAIL)|AXI PROTOCOL ERROR" | head -1)
record "M7 AMD GPIO demo (soc_m7_tb)" "${r:-NO RESULT}"

echo "=========================================================="
printf '%s\n' "${RESULTS[@]}"
echo "=========================================================="
exit $status
