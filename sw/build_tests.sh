#!/usr/bin/env bash
# build_tests.sh -- compile riscv-tests into hex files for the CPU.
#
#   sw/build_tests.sh                     rv32ui, every test except the documented skips
#   SUITE=rv32mi sw/build_tests.sh        machine-mode tests (CSRs, traps)
#   sw/build_tests.sh add lw sb           only these (from $SUITE)
#   ALL=1 sw/build_tests.sh               also build the skipped ones
#   ENV=rs32vi sw/build_tests.sh          use the old minimal environment (no CSRs needed)
#
# Default ENV=p is riscv-tests' own environment (env/p/riscv_test.h): it sets up
# mtvec, ends each test with ecall and reports through "tohost" (at 0x1000_0000,
# see link.ld).  This needs the M5 CSRs and traps.
#
# Output: build/<suite>/<test>.hex  (+ .elf and a .dump disassembly for debugging)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
RT="${RISCV_TESTS:-$ROOT/third_party/riscv-tests}"
PREFIX="${CROSS:-riscv64-unknown-elf}"
SUITE="${SUITE:-rv32ui}"
ENV="${ENV:-p}"
OUT="$ROOT/build/$SUITE"

case "$SUITE" in
  # ma_data : misaligned loads/stores; this core traps on them instead (allowed by the spec)
  rv32ui) SKIP="ma_data" ;;
  # breakpoint : needs debug triggers   pmpaddr : needs PMP   (neither is in this core)
  rv32mi) SKIP="breakpoint pmpaddr" ;;
  *)      SKIP="" ;;
esac

if [ "$ENV" = "p" ]; then
    INC="-I$RT/env/p -I$RT/env"
else
    INC="-I$HERE/env"
fi

mkdir -p "$OUT"

if [ "$#" -gt 0 ]; then
    TESTS="$*"
else
    TESTS=""
    for f in "$RT"/isa/$SUITE/*.S; do
        t="$(basename "$f" .S)"
        if [ -z "${ALL:-}" ] && [[ " $SKIP " == *" $t "* ]]; then continue; fi
        TESTS="$TESTS $t"
    done
fi

CFLAGS="-march=rv32i_zicsr_zifencei -mabi=ilp32 -mno-relax -static -nostdlib -nostartfiles \
        $INC -I$RT/isa/macros/scalar -T$HERE/link.ld"

fail=0
for t in $TESTS; do
    if ! $PREFIX-gcc $CFLAGS "$RT/isa/$SUITE/$t.S" -o "$OUT/$t.elf" 2> "$OUT/$t.log"; then
        echo "BUILD FAILED: $t   (see $OUT/$t.log)"
        fail=1
        continue
    fi
    $PREFIX-objcopy -O binary -j .text -j .text.init -j .data -j .rodata "$OUT/$t.elf" "$OUT/$t.bin"
    python3 "$HERE/bin2hex.py" "$OUT/$t.bin" "$OUT/$t.hex"
    $PREFIX-objdump -d "$OUT/$t.elf" > "$OUT/$t.dump"
    printf '%-18s %5d words\n' "$t" "$(wc -l < "$OUT/$t.hex")"
done
exit $fail

