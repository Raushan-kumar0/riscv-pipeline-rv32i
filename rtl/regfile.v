// regfile.v - 32 x 32-bit register file, x0 hard-wired to zero.
// Two combinational read ports, one synchronous write port.
// Write-through bypass: if WB writes a register in the same cycle ID reads it,
// the new value is returned (so WB->ID needs no extra forwarding path).
module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    input  wire        we,
    input  wire [4:0]  wa,
    input  wire [31:0] wd
);
    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;
        end else if (we && (wa != 5'd0)) begin
            regs[wa] <= wd;
        end
    end

    assign rd1 = (ra1 == 5'd0)                 ? 32'b0 :
                 (we && (wa == ra1))           ? wd    : regs[ra1];
    assign rd2 = (ra2 == 5'd0)                 ? 32'b0 :
                 (we && (wa == ra2))           ? wd    : regs[ra2];
endmodule
