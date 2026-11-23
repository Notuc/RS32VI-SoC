/* everything driven by interrupts
 *
 * Interrupts:
 *   timer    every 10 ms: advances the stopwatch (shown as SS.CC on the display)
 *            and blinks Au LED 0 once a second
 *   buttons  Io button 0: start / stop    button 1: reset    button 2: lap
 *   UART RX  each received character goes into a small buffer
 *
 * Main loop (never waits for any of the above):
 *   mirrors the DIP switches onto the Io LEDs, counts its own iterations, and
 *   handles the characters the UART interrupt collected:
 *     s  start / stop     r  reset     l  lap     p  print status     ?  help
 *
 * Au LEDs: 0 heartbeat, 1 running, 7..4 number of button presses.
 */
#include "rs32vi.h"

// shared between interrupts and main 
static volatile uint8_t  digits[4];            // BCD, digits[0] = hundredths
static volatile uint32_t running;
static volatile uint32_t ticks;                // 10 ms ticks since start
static volatile uint32_t lap_value, lap_flag;
static volatile uint32_t button_presses;
static volatile uint32_t board_led;

#define RX_SIZE 32
static volatile char     rx_buf[RX_SIZE];
static volatile uint32_t rx_head, rx_tail;      // ISR writes head, main reads tail 

static uint64_t next_tick;
static uint32_t tick_cycles;

static uint32_t display_value(void)
{
    return ((uint32_t)digits[3] << 12) | ((uint32_t)digits[2] << 8) |
           ((uint32_t)digits[1] << 4)  |  (uint32_t)digits[0];
}

static void show(void)
{
    IO_DISPLAY = display_value();
}

static void stopwatch_reset(void)
{
    for (int i = 0; i < 4; i++) digits[i] = 0;
    show();
}

static void toggle_running(void)
{
    running = !running;
    board_led = (board_led & ~0x2u) | (running ? 0x2u : 0u);
    IO_BOARD_LED = board_led;
}

// interrupt handlers 
void irq_timer(void)
{
    next_tick += tick_cycles;        // fixed schedule: no drift */
    timer_set_cmp(next_tick);
    ticks++;

    if (running) {                              // BCD count up, wraps at 99.99 
        for (int i = 0; i < 4; i++) {
            if (++digits[i] < 10) break;
            digits[i] = 0;
        }
        show();
    }
    if (ticks % 50 == 0) {                      // heartbeat: toggles every 0.5 s 
        board_led ^= 0x1u;
        IO_BOARD_LED = board_led;
    }
}

void irq_external(void)
{
    uint32_t active = IRQ_ACTIVE;

    if (active & IRQ_UART_RX) {
        char c = (char)UART_DATA;               // reading clears the request 
        uint32_t next = (rx_head + 1) % RX_SIZE;
        if (next != rx_tail) {                  // drop the character if the buffer is full 
            rx_buf[rx_head] = c;
            rx_head = next;
        }
    }

    uint32_t buttons = active & IRQ_BTN_ALL;
    if (buttons) {
        IRQ_PENDING = buttons;                  // write 1 to clear the latched presses 
        if (buttons & IRQ_BTN(0)) toggle_running();
        if (buttons & IRQ_BTN(1)) stopwatch_reset();
        if (buttons & IRQ_BTN(2)) { lap_value = display_value(); lap_flag = 1; }
        for (uint32_t b = buttons; b; b &= b - 1) button_presses++;
        board_led = (board_led & 0x0Fu) | ((button_presses & 0xF) << 4);
        IO_BOARD_LED = board_led;
    }
}

/* main 
 * main shares board_led and the digits with the interrupt handlers.  
 * A read-modify-write in main could be cut in half by an interrupt, losing one
 * update, so main does those with interrupts briefly switched off. */
 
static inline uint32_t critical_begin(void)
{
    uint32_t s = csr_read(mstatus);
    irq_global_disable();
    return s;
}
static inline void critical_end(uint32_t s)
{
    if (s & MSTATUS_MIE) irq_global_enable();
}

static void print_time(uint32_t v)              // v is BCD SSCC 
{
    uart_putc((char)('0' + ((v >> 12) & 0xF)));
    uart_putc((char)('0' + ((v >> 8) & 0xF)));
    uart_putc('.');
    uart_putc((char)('0' + ((v >> 4) & 0xF)));
    uart_putc((char)('0' + (v & 0xF)));
}

static void help(void)
{
    uart_puts("keys:    s start/stop   r reset   l lap   p status   ? help\n");
    uart_puts("buttons: 0 start/stop   1 reset   2 lap\n");
}

int main(void)
{
    uint32_t loops = 0;

    uart_puts("\nrs32vi stopwatch (M5: timer, button and UART interrupts)\n");
    help();

    stopwatch_reset();
    IO_DISP_CTRL = DISP_ON | (1u << 3);         // decimal point after the seconds 

    // timer: an interrupt every 10 ms 
    tick_cycles = IO_CLK_HZ / 100;
    next_tick   = timer_now() + tick_cycles;
    timer_set_cmp(next_tick);

    // interrupt controller: UART receive and the five buttons 
    IRQ_PENDING = IRQ_BTN_ALL;                  // forget presses from before we started 
    IRQ_ENABLE  = IRQ_UART_RX | IRQ_BTN_ALL;

    csr_set(mie, MIE_MTIE | MIE_MEIE);
    irq_global_enable();

    for (;;) {
        loops++;
        IO_LED = IO_SWITCHES;                   // proof the main loop keeps running 

        if (lap_flag) {
            lap_flag = 0;
            uart_puts("lap ");
            print_time(lap_value);
            uart_puts("\n");
        }

        while (rx_tail != rx_head) {
            char c = rx_buf[rx_tail];
            rx_tail = (rx_tail + 1) % RX_SIZE;

            switch (c) {
            case 's': case 'S': {
                uint32_t cs = critical_begin();
                toggle_running();
                critical_end(cs);
                uart_puts(running ? "started\n" : "stopped\n");
                break;
            }
            case 'r': case 'R': {
                uint32_t cs = critical_begin();
                stopwatch_reset();
                critical_end(cs);
                uart_puts("reset\n");
                break;
            }
            case 'l': case 'L': {
                uint32_t cs = critical_begin();
                lap_value = display_value();
                critical_end(cs);
                lap_flag  = 1;
                break;
            }
            case 'p': case 'P': case '\r': case '\n': {
                uint32_t cs = critical_begin();
                uint32_t v = display_value();          // all four digits from the same tick 
                critical_end(cs);
                uart_puts("time ");
                print_time(v);
                uart_puts(running ? "  running" : "  stopped");
                uart_puts("  main loops: ");
                uart_putdec(loops);
                uart_puts("  ticks: ");
                uart_putdec(ticks);
                uart_puts("\n");
                break;
            }
            case '?': case 'h': case 'H':
                help();
                break;
            default:
                break;
            }
        }
    }
}
