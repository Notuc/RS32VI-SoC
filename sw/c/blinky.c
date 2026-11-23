#include "rs32vi.h"

int main(void) {
  uint32_t n = 0;
  for (;;) {
    IO_BOARD_LED = n;        // binary count on the Au LEDs 
    IO_LED = 1u << (n % 24); // one Io LED walks along      
    n++;
    delay_ms(250);
  }
}
