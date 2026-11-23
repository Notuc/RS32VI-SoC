/* checks every trap path of the CPU and SoC in simulation.
 *
 *   1xx exceptions: ecall, ebreak, illegal (opcode, unknown CSR, write to
 *       read-only CSR), misaligned load / store / jump target -- each with
 *       the right mcause, mepc and mtval, and no register or memory change
 *   2xx CSRs: mscratch, csrrw/csrrs/csrrc results, misa, mhartid, mstatus.MPP,
 *       mcycle / minstret counting, time == mtime
 *   3xx interrupts: timer, masked timer then unmasked, software, external
 *       (via the interrupt controller), priority, MIE/MPIE handling, mret,
 *       vectored mtvec
 */
#include "rs32vi.h"

#define CHECK(code, cond) do { if (!(cond)) sim_fail(code); } while (0)

// handlers (override the weak ones in trap.c) 
static volatile uint32_t exc_count, exc_cause, exc_epc, exc_tval;
static volatile uint32_t timer_hits, ext_hits, sw_hits;
static volatile uint32_t isr_mstatus;
static volatile uint32_t order[4], order_n;

uint32_t exception_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
    exc_count++;
    exc_cause = cause;
    exc_epc   = epc;
    exc_tval  = tval;
    return epc + 4;                       // skip the faulting instruction 
}

static void log_irq(void)
{
    if (order_n < 4) order[order_n++] = csr_read(mcause);
    isr_mstatus = csr_read(mstatus);
}

void irq_timer(void)    { timer_hits++; log_irq(); timer_set_cmp(~0ull); }  // silence it 
void irq_software(void) { sw_hits++;    log_irq(); TIMER_MSIP = 0; }
void irq_external(void) { ext_hits++;   log_irq(); IRQ_ENABLE = 0; }

static void reset_log(void)
{
    exc_count = 0; exc_cause = exc_epc = exc_tval = 0;
    timer_hits = ext_hits = sw_hits = 0; order_n = 0;
}

// busy-wait until *flag becomes non-zero (or give up) 
static int wait_for(volatile uint32_t *flag, uint32_t loops)
{
    while (loops--) if (*flag) return 1;
    return 0;
}

/* a vector table for mtvec mode 1: entry n is used for interrupt cause n.
 * Entry 7 (timer) marks mscratch = 7 before continuing to the normal handler. */
__asm__(
    "    .section .text\n"
    "    .align 6\n"
    "vector_table:\n"
    "    .rept 7\n"
    "    j trap_entry\n"
    "    .endr\n"
    "    j vec_timer\n"        // entry 7 
    "    .rept 4\n"
    "    j trap_entry\n"
    "    .endr\n"
    "vec_timer:\n"
    "    csrwi mscratch, 7\n"
    "    j trap_entry\n");
extern char vector_table[];

// a minimal trap handler: skip the faulting instruction (4 instructions, uses t5) 
__asm__(
    "    .section .text\n"
    "    .align 2\n"
    "skip_handler:\n"
    "    csrr t5, mepc\n"
    "    addi t5, t5, 4\n"
    "    csrw mepc, t5\n"
    "    mret\n");
extern char skip_handler[];
extern void trap_entry(void);

static uint32_t buf[4] = { 0x11111111, 0x22222222, 0x33333333, 0x44444444 };

static void test_exceptions(void)
{
    uint32_t at, v;

    /* ecall */
    reset_log();
    __asm__ volatile ("1: ecall\n la %0, 1b" : "=r"(at) :: "memory");
    CHECK(101, exc_count == 1 && exc_cause == 11 && exc_epc == at);

    // ebreak: mtval = its address 
    reset_log();
    __asm__ volatile ("1: ebreak\n la %0, 1b" : "=r"(at) :: "memory");
    CHECK(102, exc_count == 1 && exc_cause == 3 && exc_epc == at && exc_tval == at);

    // illegal opcode: mtval = the instruction 
    reset_log();
    __asm__ volatile ("1: .word 0xFFFFFFFF\n la %0, 1b" : "=r"(at) :: "memory");
    CHECK(103, exc_count == 1 && exc_cause == 2 && exc_epc == at && exc_tval == 0xFFFFFFFFu);

    // unknown CSR, and a write to a read-only CSR; rd must not change 
    reset_log();
    v = 0x5A5A;
    __asm__ volatile ("csrr %0, 0x7C0" : "+r"(v) :: "memory");
    CHECK(104, exc_count == 1 && exc_cause == 2 && v == 0x5A5A);
    reset_log();
    __asm__ volatile ("csrw mhartid, zero" ::: "memory");
    CHECK(105, exc_count == 1 && exc_cause == 2);
    reset_log();
    __asm__ volatile ("csrr %0, mhartid" : "=r"(v) :: "memory");    // reading it is fine 
    CHECK(106, exc_count == 0 && v == 0);

    // misaligned load: cause 4, mtval = address, destination unchanged 
    reset_log();
    v = 0x1234;
    __asm__ volatile ("1: lw %0, 1(%2)\n la %1, 1b" : "+r"(v), "=r"(at) : "r"(buf) : "memory");
    CHECK(107, exc_count == 1 && exc_cause == 4 && exc_epc == at &&
               exc_tval == (uint32_t)buf + 1 && v == 0x1234);
    reset_log();
    __asm__ volatile ("lh %0, 3(%1)" : "+r"(v) : "r"(buf) : "memory");
    CHECK(108, exc_count == 1 && exc_cause == 4 && exc_tval == (uint32_t)buf + 3);
    reset_log();
    __asm__ volatile ("lb %0, 3(%1)" : "=r"(v) : "r"(buf) : "memory");   // bytes are never misaligned 
    CHECK(109, exc_count == 0 && v == 0x11);

    // misaligned store: cause 6, memory unchanged 
    reset_log();
    __asm__ volatile ("sw %0, 2(%1)" :: "r"(0xDEADBEEF), "r"(buf) : "memory");
    CHECK(110, exc_count == 1 && exc_cause == 6 && exc_tval == (uint32_t)buf + 2 &&
               buf[0] == 0x11111111 && buf[1] == 0x22222222);
    reset_log();
    __asm__ volatile ("sh %0, 5(%1)" :: "r"(0xBEEF), "r"(buf) : "memory");
    CHECK(111, exc_count == 1 && exc_cause == 6 && buf[1] == 0x22222222);

    /* jump to an address that is not a multiple of 4: cause 0, mtval = target,
       mepc = the jump, and the link register is not written */
    reset_log();
    {
        uint32_t target, link = 0x55;
        __asm__ volatile (
            "    la   %1, 2f\n"
            "    addi %1, %1, 2\n"          // target = 2f + 2 
            "1:  jalr %2, 0(%1)\n"
            "2:  la   %0, 1b\n"             //handler resumes here (mepc + 4) 
            : "=r"(at), "=&r"(target), "+r"(link) :: "memory");
        CHECK(112, exc_count == 1 && exc_cause == 0 && exc_epc == at &&
                   exc_tval == target && link == 0x55);
    }

    // a branch to a misaligned target traps; a not-taken one does not 
    reset_log();
    __asm__ volatile (
        "    li   t0, 1\n"
        "    bne  t0, zero, 1f + 2\n"       // taken -> misaligned 
        "    nop\n"
        "1:  nop\n" ::: "t0", "memory");
    CHECK(113, exc_count == 1 && exc_cause == 0);
    reset_log();
    __asm__ volatile (
        "    beq  zero, zero, 1f\n"
        "    nop\n"
        "1:  bne  zero, zero, 1b + 2\n"     // not taken -> no trap 
        ::: "memory");
    CHECK(114, exc_count == 0);
}


static void test_csrs(void)
{
    uint32_t a, b, c;

    csr_write(mscratch, 0xCAFEF00D);
    CHECK(201, csr_read(mscratch) == 0xCAFEF00D);
    __asm__ volatile ("csrrw %0, mscratch, %1" : "=r"(a) : "r"(0x12345678) : "memory");
    CHECK(202, a == 0xCAFEF00D && csr_read(mscratch) == 0x12345678);
    __asm__ volatile ("csrrs %0, mscratch, %1" : "=r"(a) : "r"(0x0000000F) : "memory");
    CHECK(203, a == 0x12345678 && csr_read(mscratch) == 0x1234567F);
    __asm__ volatile ("csrrc %0, mscratch, %1" : "=r"(a) : "r"(0x00000070) : "memory");
    CHECK(204, a == 0x1234567F && csr_read(mscratch) == 0x1234560F);
    __asm__ volatile ("csrrwi %0, mscratch, 21" : "=r"(a) :: "memory");
    CHECK(205, a == 0x1234560F && csr_read(mscratch) == 21);
    __asm__ volatile ("csrrsi %0, mscratch, 10" : "=r"(a) :: "memory");
    CHECK(206, a == 21 && csr_read(mscratch) == 31);
    __asm__ volatile ("csrrci %0, mscratch, 3" : "=r"(a) :: "memory");
    CHECK(207, a == 31 && csr_read(mscratch) == 28);

    CHECK(208, csr_read(misa) == 0x40000100u);
    CHECK(209, csr_read(mhartid) == 0);
    CHECK(210, (csr_read(mstatus) & 0x1800u) == 0x1800u);          // MPP = machine 

    // minstret counts retired instructions: two back-to-back reads differ by 1 
    __asm__ volatile ("csrr %0, minstret\n csrr %1, minstret" : "=r"(a), "=r"(b) :: "memory");
    CHECK(211, b - a == 1);
    // mcycle counts every clock (single-cycle CPU: same as instructions here) 
    __asm__ volatile ("csrr %0, mcycle\n nop\n nop\n csrr %1, mcycle" : "=r"(a), "=r"(b) :: "memory");
    CHECK(212, b - a == 3);
    // the user-level aliases read the same counters 
    __asm__ volatile ("csrr %0, cycle\n csrr %1, mcycle" : "=r"(a), "=r"(b) :: "memory");
    CHECK(213, b - a == 1);
    /* an instruction that traps does not retire.  With a 4-instruction handler,
       the instructions retired between the two reads are: the first csrr and
       the 4 handler instructions = 5 (the illegal instruction itself: 0).
       Counting retired instructions, not cycles, so it holds on any pipeline. */
    {
        uint32_t i0, i1, saved = csr_read(mtvec);
        csr_write(mtvec, (uint32_t)skip_handler);
        __asm__ volatile ("csrr %0, minstret\n .word 0xFFFFFFFF\n csrr %1, minstret"
                          : "=r"(i0), "=r"(i1) :: "t5", "memory");
        csr_write(mtvec, saved);
        CHECK(215, i1 - i0 == 5);
    }
    // time follows the timer peripheral's mtime 
    a = csr_read(time);
    b = TIMER_MTIME;
    c = csr_read(time);
    CHECK(214, a <= b && b <= c && c - a < 50);
}


static void test_interrupts(void)
{
    uint32_t loops;

    csr_write(mtvec, (uint32_t)trap_entry);                 // direct mode 
    csr_write(mie, 0);
    irq_global_disable();

    /* timer interrupt */
    reset_log();
    csr_set(mie, MIE_MTIE);
    irq_global_enable();
    timer_after(300);
    loops = 0;
    while (!timer_hits && loops < 10000) loops++;            // main keeps running meanwhile 
    CHECK(301, timer_hits == 1 && order[0] == 0x80000007u);
    CHECK(302, loops > 5);                                   // it really ran in between 
    CHECK(303, (isr_mstatus & MSTATUS_MIE) == 0 &&           // inside: interrupts off, 
               (isr_mstatus & MSTATUS_MPIE) != 0);           // previous state saved
    CHECK(304, (csr_read(mstatus) & MSTATUS_MIE) != 0);      // mret turned them back on 

    // masked: pending shows in mip, but nothing is taken until MIE = 1 
    reset_log();
    irq_global_disable();
    timer_set_cmp(0);                                        // due immediately 
    for (volatile int i = 0; i < 50; i++) {}
    CHECK(305, timer_hits == 0 && (csr_read(mip) & MIE_MTIE) != 0);
    irq_global_enable();
    CHECK(306, wait_for(&timer_hits, 100) && timer_hits == 1);

    // mie disables a single source 
    reset_log();
    csr_clear(mie, MIE_MTIE);
    timer_set_cmp(0);
    for (volatile int i = 0; i < 50; i++) {}
    CHECK(307, timer_hits == 0);
    timer_set_cmp(~0ull);

    // software interrupt 
    reset_log();
    csr_set(mie, MIE_MSIE);
    TIMER_MSIP = 1;
    CHECK(308, wait_for(&sw_hits, 100) && order[0] == 0x80000003u && TIMER_MSIP == 0);

    // external interrupt through the interrupt controller: UART TX idle 
    reset_log();
    CHECK(309, (IRQ_PENDING & IRQ_UART_TX) != 0 && IRQ_ACTIVE == 0);
    csr_set(mie, MIE_MEIE);
    IRQ_ENABLE = IRQ_UART_TX;
    CHECK(310, wait_for(&ext_hits, 100) && order[0] == 0x8000000Bu && IRQ_ENABLE == 0);

    // priority: external before software when both are pending 
    reset_log();
    irq_global_disable();
    TIMER_MSIP = 1;
    IRQ_ENABLE = IRQ_UART_TX;
    irq_global_enable();
    CHECK(311, wait_for(&sw_hits, 100) && ext_hits == 1 && order_n == 2 &&
               order[0] == 0x8000000Bu && order[1] == 0x80000003u);

    // button sources are edge-latched and cleared by writing 1 to PENDING 
    CHECK(312, (IRQ_PENDING & IRQ_BTN_ALL) == 0);

    // vectored mtvec: interrupt cause 7 goes to entry 7 of the table 
    reset_log();
    csr_write(mscratch, 0);
    csr_write(mtvec, (uint32_t)vector_table | 1);
    CHECK(313, csr_read(mtvec) == ((uint32_t)vector_table | 1));
    csr_write(mie, MIE_MTIE);
    timer_after(100);
    CHECK(314, wait_for(&timer_hits, 1000) && csr_read(mscratch) == 7);
    // exceptions still use the base address in vectored mode 
    reset_log();
    csr_write(mscratch, 0);
    __asm__ volatile ("ecall" ::: "memory");
    CHECK(315, exc_count == 1 && csr_read(mscratch) == 0);

    csr_write(mtvec, (uint32_t)trap_entry);
    csr_write(mie, 0);
    irq_global_disable();
}

int main(void)
{
    test_exceptions();
    test_csrs();
    test_interrupts();
    return 0;
}
