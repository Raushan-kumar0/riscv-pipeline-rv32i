// riscv_core.v - 5-stage pipelined RV32I core
//
//   IF  -> ID  -> EX  -> MEM -> WB
//   fetch  decode  execute  memory  write-back
//
// Hazard handling
//   * Data hazards : forwarding from EX/MEM and MEM/WB into EX,
//                    plus a write-through register file (WB -> ID).
//   * Load-use     : 1-cycle stall (a load's data only exists after MEM).
//   * Control      : branches/jumps resolve in EX. Fetch always predicts
//                    "not taken"; on a taken branch the 2 younger
//                    instructions (in IF/ID and ID/EX) are flushed.
//
// Memory interface: separate instruction and data ports with combinational
// (same-cycle) reads, synchronous byte-masked writes.
//
// Deliberate-bug switches for verification practice (all OFF by default):
//   BUG_NO_EXMEM_FWD, BUG_NO_LOAD_STALL, BUG_NO_FLUSH_IFID (+ BUG_SRA_AS_SRL in alu.v)
`include "riscv_defs.vh"
module riscv_core (
    input  wire        clk,
    input  wire        rst,             // synchronous, active-high
    // instruction memory port
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    // data memory port
    output wire [31:0] dmem_addr,       // word-aligned
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,      // byte enables for stores
    output wire        dmem_we,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata
);
    // =====================================================================
    // Signals that cross stages (declared early)
    // =====================================================================
    wire        stall;                  // load-use hazard: freeze PC and IF/ID
    wire        redirect;               // taken branch / jump in EX
    wire [31:0] redirect_pc;

    // ---- ID/EX pipeline register ----
    reg         id_ex_valid, id_ex_reg_write, id_ex_mem_read, id_ex_mem_write;
    reg         id_ex_wb_sel, id_ex_is_branch, id_ex_is_jal, id_ex_is_jalr;
    reg  [1:0]  id_ex_a_sel, id_ex_b_sel;
    reg  [3:0]  id_ex_alu_op;
    reg  [2:0]  id_ex_funct3;
    reg  [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg  [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;

    // ---- EX/MEM pipeline register ----
    reg         ex_mem_valid, ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_wb_sel;
    reg  [2:0]  ex_mem_funct3;
    reg  [4:0]  ex_mem_rd;
    reg  [31:0] ex_mem_alu_result, ex_mem_rs2_val;

    // ---- MEM/WB pipeline register ----
    // mem_wb_valid = "an instruction retires this cycle"; the testbench counts it for CPI
    /* verilator lint_off UNUSEDSIGNAL */
    reg         mem_wb_valid;
    /* verilator lint_on UNUSEDSIGNAL */
    reg         mem_wb_reg_write, mem_wb_wb_sel;
    reg  [4:0]  mem_wb_rd;
    reg  [31:0] mem_wb_alu_result, mem_wb_load_data;
    wire [31:0] wb_data;

    // =====================================================================
    // IF : fetch
    // =====================================================================
    reg  [31:0] pc;
    reg  [31:0] if_id_pc, if_id_instr;
    reg         if_id_valid;

    always @(posedge clk) begin
        if (rst)            pc <= 32'h0;
        else if (redirect)  pc <= redirect_pc;     // taken branch / jump wins
        else if (!stall)    pc <= pc + 32'd4;
    end
    assign imem_addr = pc;

    always @(posedge clk) begin
`ifdef BUG_NO_FLUSH_IFID
        if (rst) begin                             // injected bug: wrong-path instr survives
`else
        if (rst || redirect) begin                 // flush: replace with a bubble
`endif
            if_id_pc    <= 32'h0;
            if_id_instr <= `NOP_INSTR;
            if_id_valid <= 1'b0;
        end else if (!stall) begin
            if_id_pc    <= pc;
            if_id_instr <= imem_rdata;
            if_id_valid <= 1'b1;
        end
    end

    // =====================================================================
    // ID : decode + register read
    // =====================================================================
    wire [4:0]  id_rs1    = if_id_instr[19:15];
    wire [4:0]  id_rs2    = if_id_instr[24:20];
    wire [4:0]  id_rd     = if_id_instr[11:7];
    wire [2:0]  id_funct3 = if_id_instr[14:12];

    wire        id_reg_write, id_mem_read, id_mem_write, id_wb_sel;
    wire        id_is_branch, id_is_jal, id_is_jalr, id_uses_rs1, id_uses_rs2;
    wire [1:0]  id_a_sel, id_b_sel;
    wire [3:0]  id_alu_op;
    wire [31:0] id_imm, id_rs1_data, id_rs2_data;

    control u_ctrl (
        .instr(if_id_instr),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .wb_sel(id_wb_sel), .a_sel(id_a_sel), .b_sel(id_b_sel), .alu_op(id_alu_op),
        .is_branch(id_is_branch), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
        .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2)
    );

    imm_gen u_imm (.instr(if_id_instr), .imm(id_imm));

    regfile u_rf (
        .clk(clk), .rst(rst),
        .ra1(id_rs1), .ra2(id_rs2), .rd1(id_rs1_data), .rd2(id_rs2_data),
        .we(mem_wb_reg_write), .wa(mem_wb_rd), .wd(wb_data)
    );

    // ---- hazard detection: load followed immediately by a user of its result ----
`ifdef BUG_NO_LOAD_STALL
    assign stall = 1'b0;                           // injected bug
`else
    assign stall = id_ex_valid && id_ex_mem_read && (id_ex_rd != 5'd0) &&
                   ((id_uses_rs1 && (id_ex_rd == id_rs1)) ||
                    (id_uses_rs2 && (id_ex_rd == id_rs2)));
`endif

    always @(posedge clk) begin
        if (rst || redirect || stall) begin        // insert a bubble
            id_ex_valid     <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read  <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_wb_sel    <= `WB_ALU;
            id_ex_is_branch <= 1'b0;
            id_ex_is_jal    <= 1'b0;
            id_ex_is_jalr   <= 1'b0;
            id_ex_a_sel     <= `A_RS1;
            id_ex_b_sel     <= `B_RS2;
            id_ex_alu_op    <= `ALU_ADD;
            id_ex_funct3    <= 3'b0;
            id_ex_rs1       <= 5'd0;
            id_ex_rs2       <= 5'd0;
            id_ex_rd        <= 5'd0;
            id_ex_pc        <= 32'h0;
            id_ex_rs1_data  <= 32'h0;
            id_ex_rs2_data  <= 32'h0;
            id_ex_imm       <= 32'h0;
        end else begin
            id_ex_valid     <= if_id_valid;
            id_ex_reg_write <= id_reg_write;
            id_ex_mem_read  <= id_mem_read;
            id_ex_mem_write <= id_mem_write;
            id_ex_wb_sel    <= id_wb_sel;
            id_ex_is_branch <= id_is_branch;
            id_ex_is_jal    <= id_is_jal;
            id_ex_is_jalr   <= id_is_jalr;
            id_ex_a_sel     <= id_a_sel;
            id_ex_b_sel     <= id_b_sel;
            id_ex_alu_op    <= id_alu_op;
            id_ex_funct3    <= id_funct3;
            id_ex_rs1       <= id_rs1;
            id_ex_rs2       <= id_rs2;
            id_ex_rd        <= id_rd;
            id_ex_pc        <= if_id_pc;
            id_ex_rs1_data  <= id_rs1_data;
            id_ex_rs2_data  <= id_rs2_data;
            id_ex_imm       <= id_imm;
        end
    end

    // =====================================================================
    // EX : execute (ALU, branch decision, forwarding)
    // =====================================================================
    // Forwarding: take the newest copy of a register that is still in flight.
`ifdef BUG_NO_EXMEM_FWD
    wire fwd_a_exmem = 1'b0;                       // injected bug
    wire fwd_b_exmem = 1'b0;
`else
    wire fwd_a_exmem = ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1);
    wire fwd_b_exmem = ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2);
`endif
    wire fwd_a_memwb = mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1);
    wire fwd_b_memwb = mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2);

    wire [31:0] ex_rs1_val = fwd_a_exmem ? ex_mem_alu_result :
                             fwd_a_memwb ? wb_data           : id_ex_rs1_data;
    wire [31:0] ex_rs2_val = fwd_b_exmem ? ex_mem_alu_result :
                             fwd_b_memwb ? wb_data           : id_ex_rs2_data;

    wire [31:0] alu_a = (id_ex_a_sel == `A_PC)   ? id_ex_pc :
                        (id_ex_a_sel == `A_ZERO) ? 32'h0    : ex_rs1_val;
    wire [31:0] alu_b = (id_ex_b_sel == `B_IMM)  ? id_ex_imm :
                        (id_ex_b_sel == `B_FOUR) ? 32'd4     : ex_rs2_val;
    wire [31:0] ex_alu_result;

    alu u_alu (.a(alu_a), .b(alu_b), .op(id_ex_alu_op), .y(ex_alu_result));

    wire ex_branch_cond;
    branch_cmp u_bcmp (.a(ex_rs1_val), .b(ex_rs2_val), .funct3(id_ex_funct3), .taken(ex_branch_cond));

    wire [31:0] ex_pc_target   = id_ex_pc + id_ex_imm;                  // branches, JAL
    wire [31:0] ex_jalr_target = (ex_rs1_val + id_ex_imm) & ~32'd1;     // JALR

    assign redirect    = id_ex_valid &&
                         ((id_ex_is_branch && ex_branch_cond) || id_ex_is_jal || id_ex_is_jalr);
    assign redirect_pc = id_ex_is_jalr ? ex_jalr_target : ex_pc_target;

    always @(posedge clk) begin
        if (rst) begin
            ex_mem_valid      <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_wb_sel     <= `WB_ALU;
            ex_mem_funct3     <= 3'b0;
            ex_mem_rd         <= 5'd0;
            ex_mem_alu_result <= 32'h0;
            ex_mem_rs2_val    <= 32'h0;
        end else begin
            ex_mem_valid      <= id_ex_valid;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_wb_sel     <= id_ex_wb_sel;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_alu_result <= ex_alu_result;
            ex_mem_rs2_val    <= ex_rs2_val;      // forwarded store data
        end
    end

    // =====================================================================
    // MEM : data memory access
    // =====================================================================
    wire [1:0] mem_off = ex_mem_alu_result[1:0];  // byte position inside the word

    assign dmem_addr = {ex_mem_alu_result[31:2], 2'b00};
    assign dmem_we   = ex_mem_mem_write;
    assign dmem_re   = ex_mem_mem_read;

    reg [3:0]  st_strb;
    reg [31:0] st_data;
    always @(*) begin
        case (ex_mem_funct3[1:0])
            2'b00:   begin st_strb = 4'b0001 << mem_off;              st_data = {4{ex_mem_rs2_val[7:0]}};  end // SB
            2'b01:   begin st_strb = mem_off[1] ? 4'b1100 : 4'b0011;  st_data = {2{ex_mem_rs2_val[15:0]}}; end // SH
            default: begin st_strb = 4'b1111;                         st_data = ex_mem_rs2_val;            end // SW
        endcase
    end
    assign dmem_wstrb = ex_mem_mem_write ? st_strb : 4'b0000;
    assign dmem_wdata = st_data;

    // pick the right byte/half out of the word and sign- or zero-extend it
    /* verilator lint_off UNUSEDSIGNAL */      // upper bits unused for byte/half loads
    wire [31:0] ld_shifted = dmem_rdata >> {mem_off, 3'b000};
    /* verilator lint_on UNUSEDSIGNAL */
    reg  [31:0] ld_data;
    always @(*) begin
        case (ex_mem_funct3)
            3'b000:  ld_data = {{24{ld_shifted[7]}},  ld_shifted[7:0]};   // LB
            3'b001:  ld_data = {{16{ld_shifted[15]}}, ld_shifted[15:0]};  // LH
            3'b100:  ld_data = {24'b0, ld_shifted[7:0]};                  // LBU
            3'b101:  ld_data = {16'b0, ld_shifted[15:0]};                 // LHU
            default: ld_data = dmem_rdata;                                // LW
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            mem_wb_valid      <= 1'b0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_wb_sel     <= `WB_ALU;
            mem_wb_rd         <= 5'd0;
            mem_wb_alu_result <= 32'h0;
            mem_wb_load_data  <= 32'h0;
        end else begin
            mem_wb_valid      <= ex_mem_valid;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_wb_sel     <= ex_mem_wb_sel;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_load_data  <= ld_data;
        end
    end

    // =====================================================================
    // WB : write-back
    // =====================================================================
    assign wb_data = (mem_wb_wb_sel == `WB_MEM) ? mem_wb_load_data : mem_wb_alu_result;

endmodule
