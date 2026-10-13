// dmem.v - data memory (simulation model): combinational read, byte-masked write
module dmem #(
    parameter WORDS = 4096                    // 16 KB
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    input  wire        we,
    output wire [31:0] rdata
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    wire [AW-1:0] idx = addr[AW+1:2];
    integer i;

    initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0;

    always @(posedge clk) begin
        if (we) begin
            if (wstrb[0]) mem[idx][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[idx][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[idx][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[idx][31:24] <= wdata[31:24];
        end
    end

    assign rdata = mem[idx];
endmodule
