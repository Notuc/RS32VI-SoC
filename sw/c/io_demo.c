/* prints a greeting over UART at reset
 * mirrors the 24 Io DIP switches onto the 24 Io LEDs
 * shows the low 16 switch bits on the 7-segment display (hex)
 * echoes every character typed in the terminal; Enter prints the switch
 * value
 * blinks Au LED 0 twice a second as a heartbeat; Au LEDs 7:4 show button presses
 *
 * The main loop never blocks, so all of this happens at once.
 */
#include "rs32vi.h"

int main(void) {
  uart_puts("\nhello, rs32vi\n");
  uart_puts("clock: ");
  uart_putdec(IO_CLK_HZ);
  uart_puts(" Hz\n> ");

  IO_DISP_CTRL = DISP_ON;

  uint32_t half_sec = IO_CLK_HZ / 2;
  uint32_t last = IO_CYCLES;
  uint32_t beat = 0;

  for (;;) {
    uint32_t sw = IO_SWITCHES;
    IO_LED = sw;
    IO_DISPLAY = sw & 0xFFFF;

    int c = uart_getc_nb();
    if (c == '\r' || c == '\n') {
      uart_puts("\nswitches = 0x");
      uart_puthex(sw);
      uart_puts("\n> ");
    } else if (c >= 0) {
      uart_putc((char)c); // echo 
    }

    if ((uint32_t)(IO_CYCLES - last) >= half_sec) {
      last += half_sec;
      beat ^= 1;
    }
    IO_BOARD_LED = ((IO_BTN_COUNT & 0xF) << 4) | beat;
  }
}
