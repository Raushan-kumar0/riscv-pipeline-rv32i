// riscv_defs.vh - shared constants for the RV32I pipelined core
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// ---- Opcodes (instr[6:0]) ----
`define OP_LUI     7'b0110111
`define OP_AUIPC   7'b0010111
`define OP_JAL     7'b1101111
`define OP_JALR    7'b1100111
`define OP_BRANCH  7'b1100011
`define OP_LOAD    7'b0000011
`define OP_STORE   7'b0100011
`define OP_IMM     7'b0010011
`define OP_REG     7'b0110011

// ---- ALU operations ----
`define ALU_ADD    4'd0
`define ALU_SUB    4'd1
`define ALU_SLL    4'd2
`define ALU_SLT    4'd3
`define ALU_SLTU   4'd4
`define ALU_XOR    4'd5
`define ALU_SRL    4'd6
`define ALU_SRA    4'd7
`define ALU_OR     4'd8
`define ALU_AND    4'd9

// ---- ALU operand A select ----
`define A_RS1      2'd0
`define A_PC       2'd1
`define A_ZERO     2'd2

// ---- ALU operand B select ----
`define B_RS2      2'd0
`define B_IMM      2'd1
`define B_FOUR     2'd2

// ---- Write-back source ----
`define WB_ALU     1'b0
`define WB_MEM     1'b1

// NOP = addi x0, x0, 0 (used to fill flushed slots)
`define NOP_INSTR  32'h0000_0013

`endif
