# crt0.S -- startup code for C programs on rs32vi
#
# 1. point sp at the top of RAM, and mtvec at trap_entry (sw/lib/trap.S)
# 2. clear .bss
# 3. call main()
# 4. report main's return value through the finish register (tohost):
#        main returns 0   ->  tohost = 1            (PASS)
#        main returns k   ->  tohost = (k << 1) | 1 (FAIL, "test case k")
#    This is the same encoding the riscv-tests use, so the same testbench
#    (src/testbench/riscv_tests_tb.sv) works for both.
#
# .data needs no copy: the whole image is preloaded into the RAM.


        .equ    TOHOST_HI, 0x10000          # lui value: tohost = 0x1000_0000

        .section .text.init
        .globl  _start
_start:
        la      sp, _stack_top
        la      t0, trap_entry              # traps go to sw/lib/trap.S
        csrw    mtvec, t0

        la      t0, __bss_start
        la      t1, __bss_end
1:      bgeu    t0, t1, 2f
        sw      zero, 0(t0)
        addi    t0, t0, 4
        j       1b

2:      call    main

        lui     t0, TOHOST_HI
        beqz    a0, 3f
        slli    a0, a0, 1                   # fail: (k << 1) | 1
        ori     a0, a0, 1
        sw      a0, 0(t0)
        j       4f
3:      li      a1, 1                       # pass: 1
        sw      a1, 0(t0)
4:      j       4b                          # spin; the testbench ends the run
