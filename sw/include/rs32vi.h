/* memory map and helpers
 *
 *   0x0000_0000 - 0x0000_FFFF   RAM (64 KB block RAM, code + data + stack)
 *   0x1000_0000                 TOHOST: simulation-only "test finished" register
 *   0x2000_0000                 IO registers (LEDs, display, switches, buttons, clock)
 *   0x2000_1000                 UART
 *   0x2000_2000                 timer (mtime, mtimecmp, msip)
 *   0x2000_3000                 interrupt controller
 *   0x2000_4000                 AMD AXI GPIO (external AXI4-Lite slave)
 *
 * Everything from 0x1000_0000 up is reached over AXI4-Lite; a load or
 * store there takes a few cycles instead of one.  Programs do not notice.
 *
 * Matches src/soc/soc.sv, io_regs.sv, uart_periph.sv, timer.sv and irq_ctrl.sv.
 */
 
#ifndef RS32VI_H
#define RS32VI_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

// simulation 
#define SIM_TOHOST REG32(0x10000000u)

/* End the simulation: 1 = pass, (code << 1) | 1 = fail with that code.
 * On the board these stores are ignored and the CPU just spins. */
static inline void sim_pass(void)          { SIM_TOHOST = 1u;               for (;;) {} }
static inline void sim_fail(uint32_t code) { SIM_TOHOST = (code << 1) | 1u; for (;;) {} }

// IO registers 
#define IO_BASE        0x20000000u
#define IO_ID          REG32(IO_BASE + 0x00)   // R   0x52563332 "RV32"                 
#define IO_LED         REG32(IO_BASE + 0x04)   // RW  Io LEDs [23:0], 1 = on            
#define IO_DISPLAY     REG32(IO_BASE + 0x08)   // RW  4 hex digits [15:0]               
#define IO_DISP_CTRL   REG32(IO_BASE + 0x0C)   // RW  bit0 on, bits[4:1] decimal points 
#define IO_SWITCHES    REG32(IO_BASE + 0x10)   // R   Io DIP switches [23:0], 1 = on    
#define IO_BUTTONS     REG32(IO_BASE + 0x14)   // R   Io buttons [4:0], 1 = pressed     
#define IO_BTN_COUNT   REG32(IO_BASE + 0x18)   // RW  button presses; write clears      
#define IO_BOARD_LED   REG32(IO_BASE + 0x1C)   // RW  the 8 LEDs on the Au [7:0]        
#define IO_SCRATCH     REG32(IO_BASE + 0x20)   // RW  free                              
#define IO_CLK_HZ      REG32(IO_BASE + 0x24)   // R   CPU clock in Hz                   
#define IO_CYCLES      REG32(IO_BASE + 0x28)   // R   free-running cycle counter        

#define DISP_ON        0x1u

// UART 
#define UART_BASE      0x20001000u
#define UART_DATA      REG32(UART_BASE + 0x00) // W send byte, R received byte (clears RX_VALID) 
#define UART_STATUS    REG32(UART_BASE + 0x04)
#define UART_TX_READY  0x1u
#define UART_RX_VALID  0x2u
#define UART_RX_OVERRUN 0x4u

// timer
#define TIMER_BASE     0x20002000u
#define TIMER_MTIME    REG32(TIMER_BASE + 0x00)   // counts CPU clock cycles (64-bit, low half) 
#define TIMER_MTIMEH   REG32(TIMER_BASE + 0x04)
#define TIMER_MTIMECMP  REG32(TIMER_BASE + 0x08)  // timer interrupt while mtime >= mtimecmp 
#define TIMER_MTIMECMPH REG32(TIMER_BASE + 0x0C)
#define TIMER_MSIP     REG32(TIMER_BASE + 0x10)   // write 1: software interrupt 

// interrupt controller
#define IRQ_BASE       0x20003000u
#define IRQ_PENDING    REG32(IRQ_BASE + 0x00)     // R: requesting; W1C: clear button bits 
#define IRQ_ENABLE     REG32(IRQ_BASE + 0x04)
#define IRQ_ACTIVE     REG32(IRQ_BASE + 0x08)     // PENDING & ENABLE 
#define IRQ_UART_RX    0x01u                      // level: byte waiting in UART_DATA 
#define IRQ_UART_TX    0x02u                      // level: transmitter idle 
#define IRQ_BTN(n)     (0x04u << (n))             // edge: button n pressed (n = 0..4) 
#define IRQ_BTN_ALL    0x7Cu

// AMD AXI GPIO (axi_gpio v2.0, dual channel)
#define GPIO_BASE      0x20004000u
#define GPIO_DATA      REG32(GPIO_BASE + 0x000)   // channel 1: 8 outputs -> Au LEDs        
#define GPIO_TRI       REG32(GPIO_BASE + 0x004)   // channel 1 direction (0 = output)       
#define GPIO2_DATA     REG32(GPIO_BASE + 0x008)   // channel 2: 24 inputs <- Io DIP switches 
#define GPIO2_TRI      REG32(GPIO_BASE + 0x00C)   //   (raw pins: a switch reads 0 when on)  

// CSRs 

#define csr_read(csr)       ({ uint32_t __v; __asm__ volatile ("csrr %0, " #csr : "=r"(__v) :: "memory"); __v; })
#define csr_write(csr, val) __asm__ volatile ("csrw " #csr ", %0" :: "r"((uint32_t)(val)) : "memory")
#define csr_set(csr, bits)  __asm__ volatile ("csrs " #csr ", %0" :: "r"((uint32_t)(bits)) : "memory")
#define csr_clear(csr, bits) __asm__ volatile ("csrc " #csr ", %0" :: "r"((uint32_t)(bits)) : "memory")

#define MSTATUS_MIE    0x00000008u
#define MSTATUS_MPIE   0x00000080u
#define MIE_MSIE       0x00000008u
#define MIE_MTIE       0x00000080u
#define MIE_MEIE       0x00000800u
#define MCAUSE_INTERRUPT 0x80000000u

static inline void irq_global_enable(void)  { csr_set(mstatus, MSTATUS_MIE); }
static inline void irq_global_disable(void) { csr_clear(mstatus, MSTATUS_MIE); }

// helpers (sw/lib/rs32vi.c)

void     uart_putc(char c);
void     uart_puts(const char *s);          // "\n" is sent as "\r\n" 
void     uart_puthex(uint32_t v);           // 8 hex digits 
void     uart_putdec(uint32_t v);
int      uart_getc_nb(void);                // received byte, or -1 if none 
char     uart_getc(void);                   // waits for a byte 

void     delay_cycles(uint32_t n);
void     delay_ms(uint32_t ms);

uint64_t timer_now(void);                   // 64-bit mtime, read safely 
void     timer_set_cmp(uint64_t when);      // set mtimecmp without a spurious interrupt 
void     timer_after(uint32_t cycles);      // interrupt this many cycles from now 

#endif
