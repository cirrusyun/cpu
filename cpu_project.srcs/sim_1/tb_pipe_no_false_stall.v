`timescale 1ns/1ps
// Regression for the hazard_unit false-stall fix (uses_rs1/uses_rs2 gating).
//
// 测试两个序列：
//   A. LW x5, 0(x0); ADDI x6, x0, 5; JAL x0, 0
//        ADDI 的 inst[24:20] = imm[4:0] = 5'b00101 = 5，"看上去"像 rs2=x5
//        预修复 hazard_unit 会误判为 load-use，多停 1 拍。
//   B. LW x5, 0(x0); ADDI x6, x0, 7; JAL x0, 0
//        ADDI 的 inst[24:20] = 5'b00111 = 7，不和 x5 重合。
//
// 修复后两段程序到 x6 commit 的 HW cycle 数必须一致；如果 hazard 没 gate
// uses_rs2，序列 A 会比 B 多 1 拍。
module tb_pipe_no_false_stall;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;

    wire [31:0] next_pc, pc_out, inst_out, pc_fetch;
    wire        pc_we, branch_redirect;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_be;
    wire        mem_we;
    wire [63:0] cycle_count, inst_retired;

    always #20 clk = ~clk;

    fake_ifetch u_if (.clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch));
    fake_dmem u_dm (.clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata));
    cpu_top u_top (.clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .mode_select(1'b0),                // pipeline only
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata),
        .dbg_reg_addr(5'd0), .dbg_reg_data(),
        .cycle_count(cycle_count), .inst_retired(inst_retired));

    integer errors = 0;
    integer cyc_a, cyc_b, count;
    reg done;

    task wait_for_x6;
        input integer expected;
        output integer cycles_taken;
        begin
            count = 0;
            done = 0;
            while (!done && count < 200) begin
                @(posedge clk);
                count = count + 1;
                if (u_top.u_cpu_pp.u_rf.regs[6] === expected) done = 1;
            end
            #1;
            cycles_taken = cycle_count[31:0];
        end
    endtask

    initial begin
        // ─── Phase A: ADDI x6, x0, 5 (false match candidate) ───
        #1;
        u_if.mem[0] = 32'h00002283;          // LW x5, 0(x0)
        u_if.mem[1] = 32'h00500313;          // ADDI x6, x0, 5 (imm[4:0]=5 = "rs2"=x5)
        u_if.mem[2] = 32'h0000006F;          // JAL x0, 0
        u_dm.mem[0] = 32'd99;

        #80 rst_n = 1;
        wait_for_x6(32'd5, cyc_a);

        // ─── Phase B: ADDI x6, x0, 7 (no match) ───
        rst_n = 0;
        #80;
        u_if.mem[1] = 32'h00700313;          // ADDI x6, x0, 7
        rst_n = 1;
        wait_for_x6(32'd7, cyc_b);

        $display("");
        $display("==== tb_pipe_no_false_stall ====");
        $display("Phase A (imm=5, looks like rs2=x5): %0d cycles", cyc_a);
        $display("Phase B (imm=7, no false match)  : %0d cycles", cyc_b);

        if (cyc_a !== cyc_b) begin
            $display("FAIL: Phase A took %0d cycles vs Phase B %0d cycles", cyc_a, cyc_b);
            $display("      → hazard_unit may be triggering false load-use stall");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_pipe_no_false_stall failed");
        end
    end
endmodule
