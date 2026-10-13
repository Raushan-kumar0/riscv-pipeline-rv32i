// tb_soc.v - self-checking testbench for the pipelined core
//
// Test-pass convention (same idea as the official riscv-tests):
//   a program ends by storing a code to address TOHOST.
//     code == 1          -> PASS
//     code == (N<<1)|1   -> FAIL in sub-test N
//
// Plusargs:
//   +HEX=<file>        program to run (loaded by imem)
//   +MAXCYCLES=<n>     timeout (default 200000)
//   +DUMP=<file>       write final x0..x31 and data words 0x1000-0x17FC (for model compare)
//   +VCD               dump waveforms to wave.vcd
`timescale 1ns/1ps
module tb_soc;
    localparam [31:0] TOHOST = 32'h0000_3FFC;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;                     // 100 MHz simulation clock

    soc_top dut (.clk(clk), .rst(rst));

    integer cycles  = 0;
    integer instret = 0;                      // instructions retired (reached WB)
    integer max_cycles;
    integer fd, i;
    reg        done = 1'b0;
    reg [31:0] code;
    reg [8*256-1:0] dumpfile;

    initial begin
        if (!$value$plusargs("MAXCYCLES=%d", max_cycles)) max_cycles = 200000;
        if ($test$plusargs("VCD")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_soc);
        end
        repeat (3) @(posedge clk);
        rst <= 1'b0;
    end

    // count cycles / retired instructions, watch for the TOHOST store
    always @(posedge clk) begin
        if (!rst && !done) begin
            cycles <= cycles + 1;
            if (dut.u_core.mem_wb_valid) instret <= instret + 1;
            if (dut.dmem_we && (dut.dmem_addr == TOHOST)) begin
                done <= 1'b1;
                code <= dut.dmem_wdata;
            end
            if (cycles >= max_cycles) begin
                $display("[TIMEOUT] no TOHOST write after %0d cycles", cycles);
                $finish;
            end
        end
    end

    // finish: let older instructions drain, then report
    initial begin
        wait (done == 1'b1);
        repeat (4) @(posedge clk);
        if (code == 32'd1)
            $display("[PASS] cycles=%0d instret=%0d CPI=%0.3f",
                     cycles, instret, (cycles * 1.0) / instret);
        else
            $display("[FAIL] sub-test %0d failed (code=0x%08h) cycles=%0d",
                     code >> 1, code, cycles);

        if ($value$plusargs("DUMP=%s", dumpfile)) begin
            fd = $fopen(dumpfile, "w");
            for (i = 0; i < 32; i = i + 1)
                $fwrite(fd, "%08x\n", dut.u_core.u_rf.regs[i]);
            for (i = 'h400; i < 'h600; i = i + 1)      // words at 0x1000..0x17FC
                $fwrite(fd, "%08x\n", dut.u_dmem.mem[i]);
            $fclose(fd);
        end
        $finish;
    end
endmodule
