// alu.v - 32-bit arithmetic/logic unit
`include "riscv_defs.vh"
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] y
);
    always @(*) begin
        case (op)
            `ALU_ADD : y = a + b;
            `ALU_SUB : y = a - b;
            `ALU_SLL : y = a << b[4:0];
            `ALU_SLT : y = {31'b0, ($signed(a) < $signed(b))};
            `ALU_SLTU: y = {31'b0, (a < b)};
            `ALU_XOR : y = a ^ b;
            `ALU_SRL : y = a >> b[4:0];
`ifdef BUG_SRA_AS_SRL
            `ALU_SRA : y = a >> b[4:0];                 // injected bug: loses the sign bit
`else
            `ALU_SRA : y = $signed(a) >>> b[4:0];
`endif
            `ALU_OR  : y = a | b;
            `ALU_AND : y = a & b;
            default  : y = 32'b0;
        endcase
    end
endmodule
