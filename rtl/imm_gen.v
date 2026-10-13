// imm_gen.v - builds the sign-extended immediate for each instruction format
`include "riscv_defs.vh"
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];
    always @(*) begin
        case (opcode)
            `OP_IMM, `OP_LOAD, `OP_JALR:                                   // I-type
                imm = {{20{instr[31]}}, instr[31:20]};
            `OP_STORE:                                                    // S-type
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OP_BRANCH:                                                   // B-type
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            `OP_LUI, `OP_AUIPC:                                           // U-type
                imm = {instr[31:12], 12'b0};
            `OP_JAL:                                                      // J-type
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'b0;
        endcase
    end
endmodule
