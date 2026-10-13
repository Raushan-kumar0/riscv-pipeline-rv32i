// imem.v - instruction memory (simulation model)
// Loads a program from a hex file given on the command line: +HEX=<file>
module imem #(
    parameter WORDS = 4096                    // 16 KB
) (
    input  wire [31:0] addr,
    output wire [31:0] rdata
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    reg [8*256-1:0] hexfile;
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0000_0013;   // fill with NOPs
        if ($value$plusargs("HEX=%s", hexfile)) begin
            $readmemh(hexfile, mem);
        end else begin
            $display("imem: no +HEX=<file> given, memory holds NOPs");
        end
    end

    assign rdata = mem[addr[AW+1:2]];
endmodule
