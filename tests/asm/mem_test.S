// mem_test.S - word/half/byte stores and signed/unsigned loads
#include "test_macros.h"
    .section .text.init
    .globl _start
_start:
    li   s0, 0x0100            // base address in data memory
    li   a0, 0x80F1E2D3

    sw   a0, 0(s0)
    lw   s1, 0(s0)             ; CHECK(1,  s1, 0x80F1E2D3)
    lb   s1, 0(s0)             ; CHECK(2,  s1, 0xFFFFFFD3)   // sign-extended
    lbu  s1, 0(s0)             ; CHECK(3,  s1, 0x000000D3)
    lb   s1, 1(s0)             ; CHECK(4,  s1, 0xFFFFFFE2)
    lbu  s1, 2(s0)             ; CHECK(5,  s1, 0x000000F1)
    lb   s1, 3(s0)             ; CHECK(6,  s1, 0xFFFFFF80)
    lh   s1, 0(s0)             ; CHECK(7,  s1, 0xFFFFE2D3)
    lhu  s1, 0(s0)             ; CHECK(8,  s1, 0x0000E2D3)
    lh   s1, 2(s0)             ; CHECK(9,  s1, 0xFFFF80F1)
    lhu  s1, 2(s0)             ; CHECK(10, s1, 0x000080F1)

    // byte stores must touch only one byte
    li   a1, 0x55
    sb   a1, 1(s0)
    lw   s1, 0(s0)             ; CHECK(11, s1, 0x80F155D3)
    sb   a1, 3(s0)
    lw   s1, 0(s0)             ; CHECK(12, s1, 0x55F155D3)

    // half stores must touch only two bytes
    li   a1, 0x1234
    sh   a1, 2(s0)
    lw   s1, 0(s0)             ; CHECK(13, s1, 0x123455D3)
    sh   a1, 0(s0)
    lw   s1, 0(s0)             ; CHECK(14, s1, 0x12341234)

    // negative offsets
    li   a1, 0xCAFEBABE
    sw   a1, -4(s0)
    lw   s1, -4(s0)            ; CHECK(15, s1, 0xCAFEBABE)
    addi s2, s0, -4
    lw   s1, 0(s2)             ; CHECK(16, s1, 0xCAFEBABE)

    j pass
    PASS_FAIL
