/* AMD's AXI GPIO on our AXI4-Lite bus.
 *
 * The switches are read twice every loop: once through our own io_regs
 * (behind our AXI slave adapter) and once through AMD's AXI GPIO IP.  The
 * two must always agree.
 *
 *   Io LEDs + display   show the switches as read through AMD's GPIO
 *   Au LEDs             binary counter written through AMD's GPIO
 *   UART, Enter         prints both readings and whether they match
 */
#include "rs32vi.h"

int main(void)
{
    uart_puts("\nrs32vi M7: AXI4-Lite bus with AMD AXI GPIO at 0x20004000\n");
    uart_puts("press Enter to compare the two switch readings\n> ");

    GPIO_TRI  = 0x00000000u;             // channel 1: all outputs 
    GPIO2_TRI = 0xFFFFFFFFu;             // channel 2: all inputs  
    IO_DISP_CTRL = DISP_ON;

    uint32_t step     = IO_CLK_HZ / 8;   // counter step every 125 ms 
    uint32_t last     = IO_CYCLES;
    uint32_t count    = 0;
    uint32_t mismatch = 0;

    for (;;) {
        uint32_t sw_amd = ~GPIO2_DATA & 0x00FFFFFFu;   // AMD IP sees the raw pins 
        uint32_t sw_io  = IO_SWITCHES;                 // ours inverts them already 
        if (sw_amd != sw_io && sw_amd == (~GPIO2_DATA & 0x00FFFFFFu))
            mismatch++;                                // (ignore a switch moving mid-read) 

        IO_LED     = sw_amd;
        IO_DISPLAY = sw_amd & 0xFFFF;

        if ((uint32_t)(IO_CYCLES - last) >= step) {
            last += step;
            GPIO_DATA = ++count;                       // Au LEDs, through AMD's IP  
        }

        int c = uart_getc_nb();
        if (c == '\r' || c == '\n') {
            uart_puts("\nio_regs: 0x");
            uart_puthex(sw_io);
            uart_puts("  axi_gpio: 0x");
            uart_puthex(sw_amd);
            uart_puts(sw_io == sw_amd ? "  match" : "  MISMATCH");
            uart_puts("  mismatches so far: ");
            uart_putdec(mismatch);
            uart_puts("\n> ");
        } else if (c >= 0) {
            uart_putc((char)c);
        }
    }
}
