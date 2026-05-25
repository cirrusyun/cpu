`timescale 1ns/1ps
// Exercise cpu_top.v mode-switch wrapper. Run the same program in both
// single-cycle and pipeline modes; final RF state must match.
//   Program: sum of 1..5 = 15 via simple loop
//     mem[0] = ADDI x10, x0, 5      // counter
//     mem[1] = ADDI x11, x0, 0      // accumulator
//     mem[2] = ADD  x11, x11, x10   // acc += i
//     mem[3] = ADDI x10, x10, -1
//     mem[4] = BNE  x10, x0, -8     // loop while x10 != 0
//     mem[5] = JAL  x0, 0
//   Expected: x10=0, x11=15
module tb_topmode_switch;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;
    reg mode_select = 1;   // start in single-cycle

    wire [31:0] next_pc, pc_out, inst_out, pc_fetch;
    wire        pc_we, branch_redirect;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_be;
    wire        mem_we;

    always #20 clk = ~clk;

    fake_ifetch u_if (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch)
    );
    fake_dmem u_dm (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata)
    );
    cpu_top u_top (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .mode_select(mode_select),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata),
        .dbg_reg_addr(5'd0), .dbg_reg_data()
    );

    integer errors = 0;
    integer sc_x11, pp_x11;

    initial begin
        #1;   // 让 fake_ifetch/fake_dmem 的 time-0 NOP fill 先跑完
        u_if.mem[0] = 32'h00500513;          // ADDI x10, x0, 5
        u_if.mem[1] = 32'h00000593;          // ADDI x11, x0, 0
        u_if.mem[2] = 32'h00A585B3;          // ADD  x11, x11, x10
        u_if.mem[3] = 32'hFFF50513;          // ADDI x10, x10, -1
        u_if.mem[4] = 32'hFE051CE3;          // BNE  x10, x0, -8 (target=mem[2])
        u_if.mem[5] = 32'h0000006F;          // JAL  x0, 0

        // ─── Phase 1: single-cycle ───
        mode_select = 1;
        #80 rst_n = 1;   // release between posedges 60 and 100 to avoid race
        #(40 * 60);
        sc_x11 = u_top.u_cpu_sc.u_rf.regs[11];
        $display("[SC] x10=%0d x11=%0d (expected x10=0, x11=15)",
                 u_top.u_cpu_sc.u_rf.regs[10], sc_x11);
        if (u_top.u_cpu_sc.u_rf.regs[10] !== 32'd0)  begin $display("FAIL SC x10"); errors=errors+1; end
        if (u_top.u_cpu_sc.u_rf.regs[11] !== 32'd15) begin $display("FAIL SC x11"); errors=errors+1; end

        // ─── Phase 2: 切到 pipeline，复位再跑 ───
        rst_n = 0;
        mode_select = 0;
        #80 rst_n = 1;
        #(40 * 80);     // pipeline 多几拍 bubble
        pp_x11 = u_top.u_cpu_pp.u_rf.regs[11];
        $display("[PP] x10=%0d x11=%0d (expected x10=0, x11=15)",
                 u_top.u_cpu_pp.u_rf.regs[10], pp_x11);
        if (u_top.u_cpu_pp.u_rf.regs[10] !== 32'd0)  begin $display("FAIL PP x10"); errors=errors+1; end
        if (u_top.u_cpu_pp.u_rf.regs[11] !== 32'd15) begin $display("FAIL PP x11"); errors=errors+1; end

        $display("");
        $display("==== tb_topmode_switch ====");
        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_topmode_switch failed");
        end
    end
endmodule
