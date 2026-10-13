// hazard_test.S - back-to-back dependencies that need forwarding or stalls
#include "test_macros.h"
    .section .text.init
    .globl _start
_start:
    // EX/MEM -> EX forwarding (distance 1)
    li   a0, 10
    addi a1, a0, 1
    addi a2, a1, 1
    addi a3, a2, 1             ; CHECK(1, a3, 13)

    // MEM/WB -> EX forwarding (distance 2)
    li   a0, 100
    nop
    addi a1, a0, 5             ; CHECK(2, a1, 105)

    // register file write-through (distance 3)
    li   a0, 200
    nop
    nop
    addi a1, a0, 7             ; CHECK(3, a1, 207)

    // both operands forwarded from different stages
    li   a0, 3
    li   a1, 4
    add  a2, a0, a1            ; CHECK(4, a2, 7)

    // newest value must win when the same register is written twice
    li   a0, 1
    li   a0, 2
    addi a1, a0, 0             ; CHECK(5, a1, 2)

    // load-use: needs a 1-cycle stall
    li   s0, 0x200
    li   t0, 41
    sw   t0, 0(s0)
    lw   a0, 0(s0)
    addi a1, a0, 1             ; CHECK(6, a1, 42)

    // load used by the second operand
    lw   a0, 0(s0)
    sub  a1, zero, a0          ; CHECK(7, a1, -41)

    // load -> store data (store needs the freshly loaded value)
    lw   a0, 0(s0)
    sw   a0, 4(s0)
    lw   a1, 4(s0)             ; CHECK(8, a1, 41)

    // load -> address of next load (pointer chasing)
    li   t0, 0x208
    sw   t0, 12(s0)            // mem[0x20C] = 0x208
    li   t1, 99
    sw   t1, 8(s0)             // mem[0x208] = 99
    lw   a0, 12(s0)
    lw   a1, 0(a0)             ; CHECK(9, a1, 99)

    // load -> branch
    lw   a0, 0(s0)
    li   gp, 10
    li   t1, 41
    bne  a0, t1, fail

    // computed value -> branch (forwarded into the comparator)
    li   a0, 5
    addi a0, a0, -5
    li   gp, 11
    bnez a0, fail

    // load -> JALR target
    la   t0, target
    sw   t0, 16(s0)
    lw   t1, 16(s0)
    jalr ra, 0(t1)
    CHECK(12, s5, 0x5A)

    // writes to x0 must never be forwarded
    li   t0, 0x123
    add  x0, t0, t0
    add  a0, x0, x0            ; CHECK(13, a0, 0)

    j pass

target:
    li   s5, 0x5A
    ret

    PASS_FAIL
