// soc_top.v - core + instruction memory + data memory (simulation top)
module soc_top (
    input  wire clk,
    input  wire rst
);
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we, dmem_re;

    riscv_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_rdata(dmem_rdata)
    );

    imem u_imem (.addr(imem_addr), .rdata(imem_rdata));

    dmem u_dmem (
        .clk(clk), .addr(dmem_addr), .wdata(dmem_wdata), .wstrb(dmem_wstrb),
        .we(dmem_we), .rdata(dmem_rdata)
    );
endmodule
