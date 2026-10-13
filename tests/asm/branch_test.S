// branch_test.S - all six branches (taken and not taken), JAL, JALR
#include "test_macros.h"
    .section .text.init
    .globl _start
_start:
    li   a0, -1
    li   a1, 1

    li gp, 1;  beq  a1, a1, 1f;  j fail;  1:
    li gp, 2;  beq  a0, a1, fail
    li gp, 3;  bne  a0, a1, 1f;  j fail;  1:
    li gp, 4;  bne  a1, a1, fail
    li gp, 5;  blt  a0, a1, 1f;  j fail;  1:     // -1 < 1 signed
    li gp, 6;  blt  a1, a0, fail
    li gp, 7;  bge  a1, a0, 1f;  j fail;  1:
    li gp, 8;  bge  a0, a1, fail
    li gp, 9;  bge  a1, a1, 1f;  j fail;  1:     // equal counts as >=
    li gp, 10; bltu a1, a0, 1f;  j fail;  1:     // 1 < 0xFFFFFFFF unsigned
    li gp, 11; bltu a0, a1, fail
    li gp, 12; bgeu a0, a1, 1f;  j fail;  1:
    li gp, 13; bgeu a1, a0, fail

    // backward branch: loop 10 times
    li   s0, 0
    li   s1, 10
loop:
    addi s0, s0, 1
    bne  s0, s1, loop
    CHECK(14, s0, 10)

    // JAL writes the return address (pc + 4)
    jal  ra, func1
after_call:
    CHECK(15, s2, 0x77)
    la   t0, after_call
    li   gp, 16
    bne  ra, t0, fail

    // JALR through a register, with an offset
    la   t1, func2
    jalr ra, 4(t1)             // skips the first instruction of func2
    CHECK(17, s3, 2)

    // instructions after a taken jump must NOT execute (flush check)
    li   s4, 0
    j    1f
    addi s4, s4, 1             // must be flushed
    addi s4, s4, 1             // must be flushed
1:  CHECK(18, s4, 0)

    j pass

func1:
    li   s2, 0x77
    ret
func2:
    li   s3, 1                 // skipped by the +4 offset
    li   s3, 2
    ret

    PASS_FAIL
