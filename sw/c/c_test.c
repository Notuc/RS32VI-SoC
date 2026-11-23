/* main returns 0 if every check passes, otherwise the number of the first
 * check that failed (the section number * 100 + the check within it).
 * crt0.S turns that into the finish-register value, and the testbench prints
 * PASS or "FAIL: test case N".
 *
 * Sections:  1 loops    2 function calls   3 arrays     4 recursion   5 mul/div
 *            6 data     7 types / bytes    8 switch     9 bit ops    10
 * algorithms
 */
#include <stddef.h>
#include <stdint.h>

extern size_t strlen(const char *s);
extern int memcmp(const void *a, const void *b, size_t n);

/* Hide a value from the optimiser so the computation really runs on the CPU
 * instead of being folded away at compile time. */
#define OPAQUE(x)                                                              \
  ({                                                                           \
    __typeof__(x) _v = (x);                                                    \
    __asm__ volatile("" : "+r"(_v));                                           \
    _v;                                                                        \
  })

/* Fail with this code if the condition is false. */
#define CHECK(code, cond)                                                      \
  do {                                                                         \
    if (!(cond))                                                               \
      return (code);                                                           \
  } while (0)

// 1 loop
static int test_loops(void) {
  int n = OPAQUE(100);
  int sum = 0;
  for (int i = 1; i <= n; i++)
    sum += i;
  CHECK(101, sum == 5050);

  int count = 0;
  for (int i = 0; i < OPAQUE(10); i++)
    for (int j = 0; j < OPAQUE(10); j++)
      count++;
  CHECK(102, count == 100);

  int odd = 0;
  for (int i = 0; i < OPAQUE(50); i++) {
    if (i % 2 == 0)
      continue;
    odd++;
  }
  CHECK(103, odd == 25);

  int k = 0, steps = 0;
  do {
    k += 3;
    steps++;
  } while (k < OPAQUE(30));
  CHECK(104, steps == 10);

  int w = OPAQUE(1000), halvings = 0;
  while (w > 1) {
    w >>= 1;
    halvings++;
  }
  CHECK(105, halvings == 9);
  return 0;
}

//  2 function calls 
__attribute__((noinline)) static int add3(int a, int b, int c) {
  return a + b + c;
}

__attribute__((noinline)) static int
sum9(int a, int b, int c, int d, int e, int f, int g, int h,
     int i) { // 9 arguments: the last one is passed on the stack
  return a + b + c + d + e + f + g + h + i;
}

__attribute__((noinline)) static int op_add(int a, int b) { return a + b; }
__attribute__((noinline)) static int op_sub(int a, int b) { return a - b; }
__attribute__((noinline)) static int op_mul(int a, int b) { return a * b; }

static int test_calls(void) {
  CHECK(201, add3(OPAQUE(1), 2, 3) == 6);
  CHECK(202, add3(add3(OPAQUE(1), 2, 3), add3(4, 5, 6), OPAQUE(7)) == 28);
  CHECK(203, sum9(OPAQUE(1), 2, 3, 4, 5, 6, 7, 8, 9) == 45);

  int (*ops[3])(int, int) = {op_add, op_sub, op_mul}; // indirect calls 
  CHECK(204, ops[OPAQUE(2)](OPAQUE(6), 7) == 42);
  CHECK(205, ops[OPAQUE(1)](10, OPAQUE(3)) == 7);
  CHECK(206, ops[OPAQUE(0)](OPAQUE(-4), 4) == 0);
  return 0;
}

// 3 arrays 
static int test_arrays(void) {
  int a[16];
  int n = OPAQUE(16);
  for (int i = 0; i < n; i++)
    a[i] = i * i;
  int sum = 0;
  for (int i = 0; i < n; i++)
    sum += a[i];
  CHECK(301, sum == 1240);
  CHECK(302, a[15] == 225);

  int v[12]; // bubble sort, descending in 
  for (int i = 0; i < 12; i++)
    v[i] = 12 - i + OPAQUE(0);
  for (int i = 0; i < 11; i++)
    for (int j = 0; j < 11 - i; j++)
      if (v[j] > v[j + 1]) {
        int t = v[j];
        v[j] = v[j + 1];
        v[j + 1] = t;
      }
  for (int i = 0; i < 12; i++)
    CHECK(303, v[i] == i + 1);

  int m[4][4]; // 2-D array, transpose 
  for (int i = 0; i < 4; i++)
    for (int j = 0; j < 4; j++)
      m[i][j] = i * 4 + j + OPAQUE(0);
  int trace = 0, total = 0;
  for (int i = 0; i < 4; i++) {
    trace += m[i][i];
    for (int j = 0; j < 4; j++)
      total += m[i][j];
  }
  CHECK(304, trace == 30);
  CHECK(305, total == 120);
  for (int i = 0; i < 4; i++)
    for (int j = 0; j < i; j++) {
      int t = m[i][j];
      m[i][j] = m[j][i];
      m[j][i] = t;
    }
  CHECK(306, m[0][3] == 12 && m[3][0] == 3);

  static unsigned char sieve[100]; // sieve of Eratosthenes (in .bss) 
  for (int i = 0; i < 100; i++)
    sieve[i] = 1;
  sieve[0] = sieve[1] = 0;
  for (int i = 2; i * i < 100; i++)
    if (sieve[i])
      for (int j = i * i; j < 100; j += i)
        sieve[j] = 0;
  int primes = 0;
  for (int i = 0; i < 100; i++)
    primes += sieve[i];
  CHECK(307, primes == 25);
  return 0;
}

// 4 recursion 
static int fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }
static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
static int gcd(int a, int b) { return b == 0 ? a : gcd(b, a % b); }
static int ack(int m, int n) {
  return m == 0 ? n + 1 : (n == 0 ? ack(m - 1, 1) : ack(m - 1, ack(m, n - 1)));
}
static int is_odd(int n);
static int is_even(int n) { return n == 0 ? 1 : is_odd(n - 1); }
static int is_odd(int n) { return n == 0 ? 0 : is_even(n - 1); }

__attribute__((noinline)) static int
depth(int n) // deep recursion: uses real stack 
{
  volatile int pad[4];
  pad[0] = n;
  return n == 0 ? 0 : 1 + depth(n - 1) + (pad[0] - n);
}

static int test_recursion(void) {
  CHECK(401, fact(OPAQUE(10)) == 3628800);
  CHECK(402, fib(OPAQUE(15)) == 610);
  CHECK(403, gcd(OPAQUE(1071), 462) == 21);
  CHECK(404, ack(2, OPAQUE(3)) == 9);
  CHECK(405, is_even(OPAQUE(10)) == 1 && is_odd(OPAQUE(7)) == 1 &&
                 is_even(OPAQUE(7)) == 0);
  CHECK(406, depth(OPAQUE(60)) ==
                 60); /* ~2.9 KB of stack at -O0; RAM is only 16 KB */
  return 0;
}

/* 5 mul/div 
* RV32I has no multiply or divide instructions: gcc calls libgcc routines
 * (__mulsi3, __divsi3, __udivsi3, ...) that do it with shifts and adds. */
static int test_muldiv(void) {
  int a = OPAQUE(12345), b = OPAQUE(6789);
  CHECK(501, a * b == 83810205);
  CHECK(502, OPAQUE(-123) * OPAQUE(456) == -56088);
  uint32_t big = OPAQUE(0x10001u);
  CHECK(503, big * big == 0x00020001u); // wraps at 32 bits 

  int x = OPAQUE(1000), y = OPAQUE(7);
  CHECK(504, x / y == 142);
  CHECK(505, x % y == 6);
  CHECK(506, (-x) / y == -142); // rounds toward zero 
  CHECK(507, (-x) % y == -6);

  uint32_t u = OPAQUE(4000000000u);
  CHECK(508, u / OPAQUE(3u) == 1333333333u);
  CHECK(509, u % OPAQUE(7u) == 3u);
  return 0;
}

// 6 data 
int g_init = 1234;                                      // .data   
static int g_zero[8];                                   // .bss    
static const int k_table[8] = {3, 1, 4, 1, 5, 9, 2, 6}; // .rodata 
static const char k_msg[] = "hello, rs32vi";            // .rodata 

static int test_data(void) {
  CHECK(601, g_init == 1234);
  g_init += OPAQUE(1);
  CHECK(602, g_init == 1235);

  int zeros = 0;
  for (int i = 0; i < 8; i++)
    zeros |= g_zero[i];
  CHECK(603, zeros == 0); // .bss starts zeroed 
  for (int i = 0; i < 8; i++)
    g_zero[i] = i;
  CHECK(604, g_zero[7] == 7);

  // constants live next to the code: loads must reach that memory 
  const int *t = OPAQUE(&k_table[0]);
  int tsum = 0;
  for (int i = 0; i < 8; i++)
    tsum += t[i];
  CHECK(605, tsum == 31);
  CHECK(606, t[OPAQUE(5)] == 9);

  const char *s = OPAQUE(&k_msg[0]);
  size_t len = 0;
  int chk = 0;
  for (const char *p = s; *p; p++) {
    len++;
    chk += *p;
  }
  CHECK(607, len == 13);
  CHECK(608, chk == 1161);
  CHECK(609, strlen(s) == 13);
  return 0;
}

// 7 types and bytes 
typedef uint16_t __attribute__((may_alias)) u16a;
struct mixed {
  char c;
  int i;
  short s;
};

static int test_types(void) {
  unsigned char u8 = (unsigned char)OPAQUE(200);
  signed char s8 = (signed char)u8;
  CHECK(701, (int)u8 == 200);
  CHECK(702, (int)s8 == -56); // lb sign-extends 
  unsigned short u16 = (unsigned short)OPAQUE(40000);
  short s16 = (short)u16;
  CHECK(703, (int)u16 == 40000);  // lhu zero-extends 
  CHECK(704, (int)s16 == -25536); // lh sign-extends  

  /* Signed loads straight from memory.  gcc usually prefers lbu/lhu followed
   * by two shifts, so force the real lb / lh instructions with inline asm. */
  static signed char sb_mem[2] = {-56, 100};
  static short sh_mem[2] = {-25536, 1234};
  int r0, r1, r2, r3;
  __asm__ volatile("lb %0, 0(%1)"
                   : "=r"(r0)
                   : "r"(OPAQUE(&sb_mem[0]))
                   : "memory");
  __asm__ volatile("lb %0, 0(%1)"
                   : "=r"(r1)
                   : "r"(OPAQUE(&sb_mem[1]))
                   : "memory");
  __asm__ volatile("lh %0, 0(%1)"
                   : "=r"(r2)
                   : "r"(OPAQUE(&sh_mem[0]))
                   : "memory");
  __asm__ volatile("lh %0, 0(%1)"
                   : "=r"(r3)
                   : "r"(OPAQUE(&sh_mem[1]))
                   : "memory");
  CHECK(711, r0 == -56 && r1 == 100);
  CHECK(712, r2 == -25536 && r3 == 1234);

  volatile uint32_t word = 0;
  volatile uint8_t *bp = (volatile uint8_t *)&word;
  volatile u16a *hp = (volatile u16a *)&word;
  word = 0x12345678u;
  CHECK(705, bp[0] == 0x78 && bp[1] == 0x56 && bp[2] == 0x34 && bp[3] == 0x12);
  CHECK(706, hp[0] == 0x5678 && hp[1] == 0x1234);
  bp[1] = 0xFE; // sb touches one byte 
  CHECK(707, word == 0x1234FE78u);
  CHECK(713, bp[1] == 0xFE); // lbu: no sign-extension 
  hp[1] = 0xABCD;            // sh touches two bytes 
  CHECK(708, word == 0xABCDFE78u);

  struct mixed a = {'x', -5, -300};
  struct mixed b;
  b = a; // struct copy 
  CHECK(709, sizeof(struct mixed) == 12);
  CHECK(710, b.c == 'x' && b.i == -5 && b.s == -300);
  return 0;
}

/* 8 switch 
 * Every case calls a different function, so gcc cannot collapse the switch into
 * arithmetic or a table of constants: it has to build a jump table of code
 * addresses in .rodata, load an entry with lw, and jump through it with jalr.
 */
__attribute__((noinline)) static int f0(int v) { return v + 1; }
__attribute__((noinline)) static int f1(int v) { return v * 2; }
__attribute__((noinline)) static int f2(int v) { return v - 3; }
__attribute__((noinline)) static int f3(int v) { return v ^ 0x55; }
__attribute__((noinline)) static int f4(int v) { return v << 2; }
__attribute__((noinline)) static int f5(int v) { return v >> 1; }
__attribute__((noinline)) static int f6(int v) { return -v; }
__attribute__((noinline)) static int f7(int v) { return v | 0x100; }

__attribute__((noinline)) static int dispatch(int x, int v) {
  switch (x) {
  case 0:
    return f0(v);
  case 1:
    return f1(v);
  case 2:
    return f2(v);
  case 3:
    return f3(v);
  case 4:
    return f4(v);
  case 5:
    return f5(v);
  case 6:
    return f6(v);
  case 7:
    return f7(v);
  default:
    return -1;
  }
}

static int test_switch(void) {
  int v = OPAQUE(20), sum = 0;
  for (int i = 0; i < OPAQUE(8); i++)
    sum += dispatch(i, v);
  CHECK(801, sum == 21 + 40 + 17 + 65 + 80 + 10 - 20 + 276);
  CHECK(802, dispatch(OPAQUE(8), v) == -1);
  CHECK(803, dispatch(OPAQUE(-1), v) == -1); // out of range, below 
  CHECK(804, dispatch(OPAQUE(3), v) == 65);
  CHECK(805, dispatch(OPAQUE(7), OPAQUE(0)) == 256);
  return 0;
}

// 9 bit ops 
static int test_bits(void) {
  uint32_t one = OPAQUE(1u);
  CHECK(901, (one << 31) == 0x80000000u);
  CHECK(902,
        ((int32_t)OPAQUE(0x80000000u) >> OPAQUE(31)) == -1); // arithmetic 
  CHECK(903, (OPAQUE(0x80000000u) >> OPAQUE(31)) == 1u);     // logical    
  CHECK(904, (OPAQUE(-16) >> 2) == -4);

  uint32_t x = OPAQUE(0xF0F0F0F0u);
  int pop = 0;
  for (uint32_t t = x; t; t &= t - 1)
    pop++;
  CHECK(905, pop == 16);
  CHECK(906, ((x << 4) | (x >> 28)) == 0x0F0F0F0Fu); // rotate left 4 
  CHECK(907, (x & -x) == 0x10u);                     // lowest set bit 
  CHECK(908, (~x) == 0x0F0F0F0Fu);
  CHECK(909, (OPAQUE(5) ^ OPAQUE(3)) == 6);
  CHECK(910, OPAQUE(0xFFFFFFFFu) > OPAQUE(5u)); /* sltu */
  CHECK(911, OPAQUE(-1) < OPAQUE(5));           /* slt  */
  return 0;
}

// 10 algorithms 
static int test_algos(void) {
  uint32_t seed = OPAQUE(12345u); // insertion sort 
  int v[20], sum0 = 0, sum1 = 0;
  for (int i = 0; i < 20; i++) {
    seed = seed * 1103515245u + 12345u;
    v[i] = (int)((seed >> 16) & 0x7FFF);
    sum0 += v[i];
  }
  for (int i = 1; i < 20; i++) {
    int key = v[i], j = i - 1;
    while (j >= 0 && v[j] > key) {
      v[j + 1] = v[j];
      j--;
    }
    v[j + 1] = key;
  }
  for (int i = 0; i < 19; i++)
    CHECK(1001, v[i] <= v[i + 1]);
  for (int i = 0; i < 20; i++)
    sum1 += v[i];
  CHECK(1002, sum0 == sum1);

  int target = v[OPAQUE(13)], lo = 0, hi = 19, found = -1; // binary search 
  while (lo <= hi) {
    int mid = (lo + hi) / 2;
    if (v[mid] == target) {
      found = mid;
      break;
    }
    if (v[mid] < target)
      lo = mid + 1;
    else
      hi = mid - 1;
  }
  CHECK(1003, found >= 0 && v[found] == target);

  char buf[16] = "rs32vi cpu"; // reverse a string 
  size_t n = strlen(buf);
  for (size_t i = 0; i < n / 2; i++) {
    char t = buf[i];
    buf[i] = buf[n - 1 - i];
    buf[n - 1 - i] = t;
  }
  CHECK(1004, memcmp(buf, "upc iv23sr", 11) == 0);

  uint32_t c = OPAQUE(27u); /* Collatz */
  int steps = 0;
  while (c != 1) {
    c = (c & 1) ? 3 * c + 1 : c / 2;
    steps++;
  }
  CHECK(1005, steps == 111);
  return 0;
}

// main 
int main(void) {
  int r;
  if ((r = test_loops()))
    return r;
  if ((r = test_calls()))
    return r;
  if ((r = test_arrays()))
    return r;
  if ((r = test_recursion()))
    return r;
  if ((r = test_muldiv()))
    return r;
  if ((r = test_data()))
    return r;
  if ((r = test_types()))
    return r;
  if ((r = test_switch()))
    return r;
  if ((r = test_bits()))
    return r;
  if ((r = test_algos()))
    return r;
  return 0;
}
