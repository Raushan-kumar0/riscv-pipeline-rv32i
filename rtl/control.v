// control.v - main decoder.
// Looks at one instruction and produces every control signal the later
// pipeline stages need ("what should each stage do with this instruction?").
`include "riscv_defs.vh"
/* verilator lint_off UNUSEDSIGNAL */          // decoder only looks at some instr bits
module control (
    input  wire [31:0] instr,
    output reg         reg_write,   // writes a result into rd
    output reg         mem_read,    // load
    output reg         mem_write,   // store
    output reg         wb_sel,      // `WB_ALU or `WB_MEM
    output reg  [1:0]  a_sel,       // ALU operand A source
    output reg  [1:0]  b_sel,       // ALU operand B source
    output reg  [3:0]  alu_op,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         uses_rs1,    // used by the hazard unit to avoid false stalls
    output reg         uses_rs2
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire       f7_bit = instr[30];      // distinguishes ADD/SUB and SRL/SRA

    always @(*) begin
        // safe defaults = behave like a NOP
        reg_write = 1'b0;  mem_read  = 1'b0;  mem_write = 1'b0;
        wb_sel    = `WB_ALU;
        a_sel     = `A_RS1; b_sel    = `B_RS2;
        alu_op    = `ALU_ADD;
        is_branch = 1'b0;  is_jal    = 1'b0;  is_jalr   = 1'b0;
        uses_rs1  = 1'b0;  uses_rs2  = 1'b0;

        case (opcode)
            `OP_REG: begin                              // add, sub, sll, ...
                reg_write = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
                case (funct3)
                    3'b000: alu_op = f7_bit ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = f7_bit ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                endcase
            end
            `OP_IMM: begin                              // addi, slti, ...
                reg_write = 1'b1; uses_rs1 = 1'b1; b_sel = `B_IMM;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = f7_bit ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                endcase
            end
            `OP_LOAD: begin                             // address = rs1 + imm
                reg_write = 1'b1; mem_read = 1'b1; wb_sel = `WB_MEM;
                uses_rs1  = 1'b1; b_sel = `B_IMM;
            end
            `OP_STORE: begin                            // address = rs1 + imm, data = rs2
                mem_write = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; b_sel = `B_IMM;
            end
            `OP_BRANCH: begin                           // compare rs1, rs2
                is_branch = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
            end
            `OP_JAL: begin                              // rd = pc + 4
                reg_write = 1'b1; is_jal = 1'b1; a_sel = `A_PC; b_sel = `B_FOUR;
            end
            `OP_JALR: begin                             // rd = pc + 4, target from rs1
                reg_write = 1'b1; is_jalr = 1'b1; uses_rs1 = 1'b1;
                a_sel = `A_PC; b_sel = `B_FOUR;
            end
            `OP_LUI: begin                              // rd = imm
                reg_write = 1'b1; a_sel = `A_ZERO; b_sel = `B_IMM;
            end
            `OP_AUIPC: begin                            // rd = pc + imm
                reg_write = 1'b1; a_sel = `A_PC; b_sel = `B_IMM;
            end
            default: ;                                  // unsupported -> NOP
        endcase
    end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
