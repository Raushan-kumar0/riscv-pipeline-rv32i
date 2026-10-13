// alu_test.S - every R-type and I-type ALU instruction, plus LUI/AUIPC
#include "test_macros.h"
    .section .text.init
    .globl _start
_start:
    li   a0, 0x12345678
    li   a1, -100              // 0xFFFFFF9C
    li   a2, 5

    add  s0, a0, a1            ; CHECK(1,  s0, 0x12345614)
    sub  s0, a0, a1            ; CHECK(2,  s0, 0x123456DC)
    sll  s0, a0, a2            ; CHECK(3,  s0, 0x468ACF00)
    slt  s0, a1, a0            ; CHECK(4,  s0, 1)          // -100 < big positive
    slt  s0, a0, a1            ; CHECK(5,  s0, 0)
    sltu s0, a1, a0            ; CHECK(6,  s0, 0)          // 0xFFFFFF9C is huge unsigned
    sltu s0, a0, a1            ; CHECK(7,  s0, 1)
    xor  s0, a0, a1            ; CHECK(8,  s0, 0xEDCBA9E4)
    srl  s0, a1, a2            ; CHECK(9,  s0, 0x07FFFFFC)
    sra  s0, a1, a2            ; CHECK(10, s0, 0xFFFFFFFC) // sign bit copied in
    or   s0, a0, a1            ; CHECK(11, s0, 0xFFFFFFFC)
    and  s0, a0, a1            ; CHECK(12, s0, 0x12345618)

    addi  s0, a0, -1           ; CHECK(13, s0, 0x12345677)
    slti  s0, a1, -99          ; CHECK(14, s0, 1)
    sltiu s0, a1, -1           ; CHECK(15, s0, 1)          // imm -1 = 0xFFFFFFFF unsigned
    xori  s0, a0, -1           ; CHECK(16, s0, 0xEDCBA987) // bitwise NOT
    ori   s0, a0, 0x0FF        ; CHECK(17, s0, 0x123456FF)
    andi  s0, a0, 0x0F0        ; CHECK(18, s0, 0x00000070)
    slli  s0, a0, 4            ; CHECK(19, s0, 0x23456780)
    srli  s0, a1, 28           ; CHECK(20, s0, 0x0000000F)
    srai  s0, a1, 28           ; CHECK(21, s0, 0xFFFFFFFF)

    lui   s0, 0xABCDE          ; CHECK(22, s0, 0xABCDE000)
here:
    auipc s0, 0                // s0 = address of 'here'
    la    s1, here             // assembler computes the same address
    li    gp, 23
    bne   s0, s1, fail

    // x0 must stay zero even when written
    addi  x0, x0, 55
    li    gp, 24
    bnez  x0, fail
    add   s0, x0, x0           ; CHECK(25, s0, 0)

    j pass
    PASS_FAIL
