// riscv_test minimal riscv-tests environment for rs32vi (no CSRs, no
// traps)
//
// Drop-in replacement for riscv-tests/env/p/riscv_test.h.  The official one
// sets up CSRs and ends with an ecall; this core has neither.
// Instead, a test reports its result by storing to the "tohost" register:
//
//     value 1            -> PASS
//     value (n << 1) | 1 -> FAIL in test case n
//
// The testbench watches for that store and ends the simulation.

#ifndef _ENV_RS32VI_H
#define _ENV_RS32VI_H

#define TOHOST_ADDR_HI 0x10000 // lui value: tohost = 0x1000_0000

#define RVTEST_RV32U
#define RVTEST_RV64U // rv32ui/*.S #undef + redefine this

#define TESTNUM gp

// Start / end of code

#define RVTEST_CODE_BEGIN                                                      \
  .section.text.init;                                                          \
  .align 2;                                                                    \
  .globl _start;                                                               \
  _start:

#define RVTEST_CODE_END .word 0

// Pass / fail: store the result to tohost, then spin

#define RVTEST_PASS                                                            \
  fence;                                                                       \
  li TESTNUM, 1;                                                               \
  lui t0, TOHOST_ADDR_HI;                                                      \
  sw TESTNUM, 0(t0);                                                           \
  1 : j 1b

#define RVTEST_FAIL                                                            \
  fence;                                                                       \
  1 : beqz TESTNUM, 1b;                                                        \
  sll TESTNUM, TESTNUM, 1;                                                     \
  or TESTNUM, TESTNUM, 1;                                                      \
  lui t0, TOHOST_ADDR_HI;                                                      \
  sw TESTNUM, 0(t0);                                                           \
  2 : j 2b

// Data section

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                                      \
  EXTRA_DATA.align 4;                                                          \
  .global begin_signature;                                                     \
  begin_signature:

#define RVTEST_DATA_END                                                        \
  .align 4;                                                                    \
  .global end_signature;                                                       \
  end_signature:

#endif
