// test_macros.h - helpers for self-checking test programs
//   gp (x3)  holds the current sub-test number
//   t6 (x31) is scratch for the expected value
#define TOHOST 0x3FFC

// CHECK: if reg != expected, jump to fail with sub-test number n
#define CHECK(n, reg, expected) \
    li   gp, n;                 \
    li   t6, expected;          \
    bne  reg, t6, fail;

// write 1 to TOHOST = PASS, then spin
#define PASS_FAIL               \
pass:                           \
    li   t0, 1;                 \
    li   t1, TOHOST;            \
    sw   t0, 0(t1);             \
1:  j    1b;                    \
fail:                           \
    slli t0, gp, 1;             \
    ori  t0, t0, 1;             \
    li   t1, TOHOST;            \
    sw   t0, 0(t1);             \
2:  j    2b;
