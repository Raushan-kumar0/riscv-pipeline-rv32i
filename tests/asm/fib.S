// fib.S - iterative Fibonacci; fib(30) = 832040
#include "test_macros.h"
    .section .text.init
    .globl _start
_start:
    li   a0, 0                 // fib(0)
    li   a1, 1                 // fib(1)
    li   t0, 30
    li   t1, 1
loop:
    add  a2, a0, a1
    mv   a0, a1
    mv   a1, a2
    addi t1, t1, 1
    blt  t1, t0, loop
    CHECK(1, a1, 832040)
    j pass
    PASS_FAIL
