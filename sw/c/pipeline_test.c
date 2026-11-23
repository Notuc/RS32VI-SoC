/* pipeline hazards and precise interrupts.
 *
 * (Forwarding between ordinary instructions is already covered by the
 *  riscv-tests: every rv32ui test has bypass variants with 0, 1 and 2
 *  instructions in between.)
 *
 *   1xx  branch / jump shadows: the instruction fetched behind a taken branch
 *        must have no effect -- not even a trap
 *   2xx  CSR read-after-write, x0 never forwarded, store-then-load, mret,
 *        self-modifying code with fence.i
 *   3xx  precise interrupts: timer interrupts arrive every ~200-450 cycles, at
 *        shifting points, while load/branch/call-heavy code runs; the result
 *        must be bit-identical to an uninterrupted run
 */
#include "rs32vi.h"

#define CHECK(code, cond) do { if (!(cond)) sim_fail(code); } while (0)

static volatile uint32_t exc_count;
uint32_t exception_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
    (void)cause; (void)tval;
    exc_count++;
    return epc + 4;
}


static void test_shadows(void)
{
    uint32_t r;

    // taken branch: the next instruction must not execute 
    r = 0;
    __asm__ volatile ("beq zero, zero, 1f\n addi %0, %0, 1\n 1:" : "+r"(r));
    CHECK(101, r == 0);

    // jal and jalr shadows
    r = 0;
    __asm__ volatile ("jal zero, 1f\n addi %0, %0, 1\n 1:" : "+r"(r));
    CHECK(102, r == 0);
    r = 0;
    __asm__ volatile ("la t0, 1f\n jalr zero, 0(t0)\n addi %0, %0, 1\n 1:" : "+r"(r) :: "t0");
    CHECK(103, r == 0);

    // an ecall or illegal instruction in the shadow must not trap 
    exc_count = 0;
    __asm__ volatile ("beq zero, zero, 1f\n ecall\n 1:" ::: "memory");
    __asm__ volatile ("jal zero, 1f\n .word 0xFFFFFFFF\n 1:" ::: "memory");
    CHECK(104, exc_count == 0);

    // a store in the shadow must not happen 
    static volatile uint32_t cell = 7;
    __asm__ volatile ("beq zero, zero, 1f\n sw zero, 0(%0)\n 1:" :: "r"(&cell) : "memory");
    CHECK(105, cell == 7);

    // branch on a value loaded just before (load-use stall + branch in EX) 
    static volatile uint32_t one = 1;
    r = 0;
    __asm__ volatile ("lw t0, 0(%1)\n bnez t0, 1f\n addi %0, %0, 1\n 1:"
                      : "+r"(r) : "r"(&one) : "t0", "memory");
    CHECK(106, r == 0);

    // jalr to an address loaded just before 
    static void *volatile target;
    __asm__ volatile ("la t0, 1f\n sw t0, 0(%1)\n lw t1, 0(%1)\n jalr zero, 0(t1)\n"
                      "addi %0, %0, 1\n 1:" : "+r"(r) : "r"(&target) : "t0", "t1", "memory");
    CHECK(107, r == 0);
}


static void test_misc(void)
{
    uint32_t a, b;

    //  CSR written, then read right away; the read value used right away 
    __asm__ volatile ("li t0, 0x1234\n csrw mscratch, t0\n csrr %0, mscratch\n addi %1, %0, 1"
                      : "=&r"(a), "=r"(b) :: "t0");
    CHECK(201, a == 0x1234 && b == 0x1235);

    // writes to x0 are never forwarded */
    __asm__ volatile ("li t0, 5\n add zero, t0, t0\n add %0, zero, zero" : "=r"(a) :: "t0");
    CHECK(202, a == 0);
    __asm__ volatile ("lw zero, 0(%1)\n add %0, zero, zero" : "=r"(a) : "r"(&b) : "memory");
    CHECK(203, a == 0);

    // store, then load the same word / other byte lanes straight away 
    static volatile uint32_t w;
    __asm__ volatile ("li t0, 0x11223344\n sw t0, 0(%1)\n lw %0, 0(%1)" : "=r"(a) : "r"(&w) : "t0", "memory");
    CHECK(204, a == 0x11223344);
    __asm__ volatile ("li t0, 0xAB\n sb t0, 2(%1)\n lw %0, 0(%1)" : "=r"(a) : "r"(&w) : "t0", "memory");
    CHECK(205, a == 0x11AB3344);
    __asm__ volatile ("lbu %0, 2(%1)\n addi %0, %0, 1" : "=r"(a) : "r"(&w) : "memory");
    CHECK(206, a == 0xAC);

    // mret straight after csrw mepc 
    __asm__ volatile ("la t0, 1f\n csrw mepc, t0\n mret\n addi %0, zero, 99\n 1: li %0, 42"
                      : "=r"(a) :: "t0");
    CHECK(207, a == 42);

    /* self-modifying code: rewrite the instruction straight after fence.i.
     * Without fence.i refetching, the pipeline has already fetched the old one.
     * (0x02A00513 = addi a0, zero, 42;  0x0000100F = fence.i) */
    {
        register uint32_t a0 __asm__("a0");
        __asm__ volatile (
            "    la   t0, 1f\n"
            "    li   t1, 0x02A00513\n"
            "    sw   t1, 0(t0)\n"
            "    .word 0x0000100F\n"
            "1:  addi a0, zero, 1\n"
            : "=r"(a0) :: "t0", "t1", "memory");
        CHECK(208, a0 == 42);
    }
}

 
static volatile uint32_t ticks;
static uint32_t gap = 200;

void irq_timer(void)
{
    ticks++;
    /* next one 200..455 cycles after this point, varying so interrupts land on
     * different instructions each time.  (At -O0 the handler itself takes a few
     * hundred cycles; much closer together and the main program barely runs.) */
    gap = 200 + ((gap * 7 + 3) & 0xFF);
    timer_after(gap);
}

__attribute__((noinline)) static uint32_t mix(uint32_t h, uint32_t v)
{
    return (h ^ v) * 16777619u;                 // calls into libgcc's multiply 
}

/* load / store / branch / call heavy work 
 * noipa: gcc must not notice that work() / run() have no side effects and
 * reuse the first result instead of running them again */
__attribute__((noipa)) static uint32_t work(uint32_t seed)
{
    uint32_t a[24];
    for (int i = 0; i < 24; i++) {
        seed = seed * 1103515245u + 12345u;
        a[i] = seed >> 8;
    }
    for (int i = 1; i < 24; i++) {              // insertion sort: loads feed branches 
        uint32_t k = a[i];
        int j = i - 1;
        while (j >= 0 && a[j] > k) { a[j + 1] = a[j]; j--; }
        a[j + 1] = k;
    }
    uint32_t h = 2166136261u;
    for (int i = 0; i < 24; i++) h = mix(h, a[i] ^ (uint32_t)i);
    uint8_t *b = (uint8_t *)a;                  // byte loads and stores 
    for (int i = 0; i < 96; i += 3) { b[i] ^= (uint8_t)h; h += b[i + 1]; }
    return h;
}

__attribute__((noipa)) static uint32_t run(int n)
{
    uint32_t sum = 0;
    for (int i = 0; i < n; i++) sum += work((uint32_t)i * 2654435761u);
    return sum;
}

static void test_precise_interrupts(void)
{
    uint32_t ref = run(12);                     // interrupts off 

    ticks = 0;
    csr_set(mie, MIE_MTIE);
    irq_global_enable();
    timer_after(gap);
    uint32_t got = run(12);                     // interrupted hundreds of times 
    irq_global_disable();
    csr_clear(mie, MIE_MTIE);
    timer_set_cmp(~0ull);

    CHECK(301, ticks > 50);
    CHECK(302, got == ref);
}

int main(void)
{
    test_shadows();
    test_misc();
    test_precise_interrupts();
    return 0;
}
