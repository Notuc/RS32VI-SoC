/* dispatches traps to handlers a program can override.
 *
 * A program defines any of these (all optional):
 *     void     irq_timer(void);        machine timer interrupt
 *     void     irq_external(void);     interrupt controller (UART, buttons)
 *     void     irq_software(void);     software interrupt (TIMER_MSIP)
 *     uint32_t exception_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval);
 *              returns the address to resume at (e.g. mepc + 4 to skip the instruction)
 *
 * The defaults below switch off an interrupt nobody handles (so it cannot fire
 * forever) and report an unexpected exception over the UART, then stop.
 */
#include "rs32vi.h"

__attribute__((weak)) void irq_timer(void)    { csr_clear(mie, MIE_MTIE); }
__attribute__((weak)) void irq_external(void) { IRQ_ENABLE = 0; }
__attribute__((weak)) void irq_software(void) { TIMER_MSIP = 0; }

__attribute__((weak)) uint32_t exception_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
    uart_puts("\n*** exception: mcause=0x");
    uart_puthex(cause);
    uart_puts(" mepc=0x");
    uart_puthex(epc);
    uart_puts(" mtval=0x");
    uart_puthex(tval);
    uart_puts("\n");
    sim_fail(0xE00 + cause);              // in simulation: FAIL; on the board: stop here
    return epc;
}

uint32_t trap_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
    if (cause & MCAUSE_INTERRUPT) {
        switch (cause & 0xF) {
        case 7:  irq_timer();    break;
        case 11: irq_external(); break;
        case 3:  irq_software(); break;
        default: break;
        }
        return epc;                       // resume the interrupted instruction 
    }
    return exception_handler(cause, epc, tval);
}
