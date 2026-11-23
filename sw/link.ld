/* link.ld -- one RAM at address 0 holding code and data.
 * Used for the riscv-tests and for C programs.
 *
 * The whole image (code, .rodata, .data) is preloaded into the RAM, so .data
 * needs no copy at startup; only .bss has to be cleared (crt0.S does that).
 *
 * LENGTH must match the RAM size (RAM_WORDS * 4 in soc.sv, 64 KB by default). */

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        *(.text.init)               // _start goes first, at address 0 
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4) {
        *(.rodata .rodata.* .srodata .srodata.*)
    } > RAM

    .data : ALIGN(16) {
        *(.data .data.* .sdata .sdata.*)
    } > RAM

    .bss : ALIGN(4) {
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);               // crt0 clears .bss a word at a time 
        __bss_end = .;
    } > RAM

    _end = .;

    /* riscv-tests' official environment reports results by storing to the symbol
     * "tohost".  Put it at the testbench's finish address.  NOLOAD keeps it out of
     * the hex file (it is not RAM). */
    .tohost 0x10000000 (NOLOAD) : { *(.tohost) }

    // stack grows down from the top of RAM (used by C startup in M3) 
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
