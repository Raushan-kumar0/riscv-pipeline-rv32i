// bubble_sort.S - a real program: sort 32 numbers, then verify the order
#include "test_macros.h"
    .section .text.init
    .globl _start
_start:
    li   s0, 0x400             // array base
    li   s1, 32                // n

    // fill with a pseudo-random sequence: x = (x * 75 + 74) mod 65537-ish (LCG with shifts)
    li   t0, 12345
    li   t2, 0
fill:
    slli t1, t0, 6
    add  t0, t0, t1            // x *= 65
    addi t0, t0, 7
    li   t3, 0xFFFF
    and  t0, t0, t3
    slli t4, t2, 2
    add  t4, s0, t4
    sw   t0, 0(t4)
    addi t2, t2, 1
    blt  t2, s1, fill

    // bubble sort (signed compare)
    addi s2, s1, -1            // outer counter
outer:
    li   t2, 0                 // i
    mv   t5, s0                // pointer
inner:
    lw   a0, 0(t5)
    lw   a1, 4(t5)
    ble  a0, a1, noswap
    sw   a1, 0(t5)
    sw   a0, 4(t5)
noswap:
    addi t5, t5, 4
    addi t2, t2, 1
    blt  t2, s2, inner
    addi s2, s2, -1
    bnez s2, outer

    // verify: a[i] <= a[i+1] for all i
    li   gp, 1
    li   t2, 0
    addi s2, s1, -1
    mv   t5, s0
check:
    lw   a0, 0(t5)
    lw   a1, 4(t5)
    bgt  a0, a1, fail
    addi t5, t5, 4
    addi t2, t2, 1
    blt  t2, s2, check

    j pass
    PASS_FAIL
