#!/usr/bin/env bash
# build_c.sh -- compile a C program for the CPU and produce a hex file.
#
#   sw/build_c.sh sw/c/c_test.c            -> build/c/c_test.{elf,hex,dump,map}
#   OPT=-O0 sw/build_c.sh sw/c/c_test.c    choose the optimisation level (default -O2)
#   OUT=build/c/c_test_O0 ...              choose the output name (default: file name)
#
# The program is linked with sw/crt0.S (startup), sw/lib/rt.c (memcpy etc.) and
# sw/lib/rs32vi.c (UART, delay and timer helpers) and sw/lib/trap.S + trap.c (traps)
# using sw/link.ld.  libgcc supplies multiply/divide, because RV32I has no such
# instructions: gcc turns '*', '/' and '%' into calls to __mulsi3, __divsi3, ...

set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: $0 prog.c [more.c ...]"; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
PREFIX="${CROSS:-riscv64-unknown-elf}"
OPT="${OPT:--O2}"
NAME="$(basename "$1" .c)"
OUT="${OUT:-$ROOT/build/c/$NAME}"
mkdir -p "$(dirname "$OUT")"

CFLAGS="-march=rv32i_zicsr -mabi=ilp32 -mno-relax $OPT -g -Wall -Wextra \
        -ffreestanding -fno-builtin-printf -fno-tree-loop-distribute-patterns \
        -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-pic \
        -I$HERE/include"
LDFLAGS="-static -nostdlib -nostartfiles -T$HERE/link.ld -Wl,-Map=$OUT.map -Wl,--gc-sections -Wl,--no-warn-rwx-segments"

$PREFIX-gcc $CFLAGS $LDFLAGS \
    "$HERE/crt0.S" "$HERE/lib/rt.c" "$HERE/lib/rs32vi.c" "$HERE/lib/trap.S" "$HERE/lib/trap.c" "$@" -lgcc -o "$OUT.elf"

$PREFIX-objcopy -O binary "$OUT.elf" "$OUT.bin"
python3 "$HERE/bin2hex.py" "$OUT.bin" "$OUT.hex"
$PREFIX-objdump -d -S "$OUT.elf" > "$OUT.dump"

# size check: code + data must leave room for the stack
$PREFIX-size "$OUT.elf" | tail -1 | awk -v n="$NAME$OPT" \
    '{ printf "%-16s text=%d data=%d bss=%d  (RAM is 65536 bytes, stack grows down from the top)\n", n, $1, $2, $3 }'
