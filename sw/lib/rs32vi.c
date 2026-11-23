// UART and delay helpers

#include "rs32vi.h"

void uart_putc(char c)
{
    while (!(UART_STATUS & UART_TX_READY)) {}   // wait until the transmitter is idle 
    UART_DATA = (uint8_t)c;
}

void uart_puts(const char *s)
{
    for (; *s; s++) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s);
    }
}

void uart_puthex(uint32_t v)
{
    for (int i = 28; i >= 0; i -= 4) {
        uint32_t d = (v >> i) & 0xF;
        uart_putc((char)(d < 10 ? '0' + d : 'A' + d - 10));
    }
}

void uart_putdec(uint32_t v)
{
    char buf[11];
    int n = 0;
    do { buf[n++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (n) uart_putc(buf[--n]);
}

int uart_getc_nb(void)
{
    if (!(UART_STATUS & UART_RX_VALID)) return -1;
    return (int)(UART_DATA & 0xFF);
}

char uart_getc(void)
{
    int c;
    while ((c = uart_getc_nb()) < 0) {}
    return (char)c;
}

void delay_cycles(uint32_t n)
{
    uint32_t start = IO_CYCLES;
    while ((uint32_t)(IO_CYCLES - start) < n) {}     // unsigned subtraction handles wrap 
}

void delay_ms(uint32_t ms)
{
    uint32_t per_ms = IO_CLK_HZ / 1000u;
    while (ms--) delay_cycles(per_ms);
}

uint64_t timer_now(void)
{
    uint32_t hi, lo;
    do {                                     // re-read if the low half wrapped in between 
        hi = TIMER_MTIMEH;
        lo = TIMER_MTIME;
    } while (TIMER_MTIMEH != hi);
    return ((uint64_t)hi << 32) | lo;
}

void timer_set_cmp(uint64_t when)
{
    TIMER_MTIMECMPH = 0xFFFFFFFFu;           // park far in the future while the halves change 
    TIMER_MTIMECMP  = (uint32_t)when;
    TIMER_MTIMECMPH = (uint32_t)(when >> 32);
}

void timer_after(uint32_t cycles)
{
    timer_set_cmp(timer_now() + cycles);
}
