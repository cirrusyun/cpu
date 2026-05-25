`timescale 1ns/1ps
// Speedup demo: 同一 sum-of-1..N loop 在 single-cycle 和 pipeline 两种模式下
// 运行，对比 cycle 数。
//
// 测量口径：从 rst_n 释放开始计数，直到 x11 第一次出现 55（即累加完成的瞬间）
// 为止。此时 BNE 还未 commit，JAL 也尚未 commit，所以**不是**到达"halt loop"
// 的完整周期数，而是"累加结果出现"的延迟。这两种口径都能展示流水/单周期的相
// 对开销，但与"程序结束"不同——故意选这个口径是为了让计数停在数据相关的关
// 键事件上，不被 JAL 自循环污染。
//
// 同时读取硬件 cycle_counter (cpu_top.cycle_count) 并与软件计数对照断言，
// 证明 HW counter 接线正确。
//
// Program: sum 1..10 = 55
//   mem[0] = ADDI x10, x0, 10
//   mem[1] = ADDI x11, x0, 0
//   mem[2] = ADD  x11, x11, x10
//   mem[3] = ADDI x10, x10, -1
//   mem[4] = BNE  x10, x0, -8
//   mem[5] = JAL  x0, 0           ← 自循环，跑超后停在这里
module tb_speedup_demo;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;
    reg mode_select = 1;

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
    wire [63:0] cycle_count_hw, inst_retired_hw;
    cpu_top u_top (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .mode_select(mode_select),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata),
        .dbg_reg_addr(5'd0), .dbg_reg_data(),
        .cycle_count(cycle_count_hw),
        .inst_retired(inst_retired_hw)
    );

    integer sc_cycles, pp_cycles;
    integer sc_inst, pp_inst;
    integer sc_hw_cycles, pp_hw_cycles;
    integer errors = 0;

    // 真正记录从 reset 释放到 x11=55 经过的 CPU cycle 数
    task run_program;
        output integer cycles;
        integer count;
        reg done;
        begin
            count = 0;
            done = 0;
            while (!done && count < 500) begin
                @(posedge clk);
                #1;     // 让 NBA 写完 RF 再读，否则会晚 1 拍才看到 x11=55
                count = count + 1;
                if ((mode_select && u_top.u_cpu_sc.u_rf.regs[11] === 32'd55) ||
                    (!mode_select && u_top.u_cpu_pp.u_rf.regs[11] === 32'd55))
                    done = 1;
            end
            cycles = count;
        end
    endtask

    initial begin
        #1;   // 让 fake_ifetch/fake_dmem 的 time-0 NOP fill 先跑完
        u_if.mem[0] = 32'h00A00513;          // ADDI x10, x0, 10
        u_if.mem[1] = 32'h00000593;          // ADDI x11, x0, 0
        u_if.mem[2] = 32'h00A585B3;          // ADD  x11, x11, x10
        u_if.mem[3] = 32'hFFF50513;          // ADDI x10, x10, -1
        u_if.mem[4] = 32'hFE051CE3;          // BNE  x10, x0, -8
        u_if.mem[5] = 32'h0000006F;          // JAL  x0, 0

        // Single-cycle run
        mode_select = 1;
        #80 rst_n = 1;   // release between posedges 60 and 100 to avoid race
        run_program(sc_cycles);
        #1;                                     // 等 NBA 把 cycle_counter 的 <= 应用完
        sc_inst      = inst_retired_hw[31:0];
        sc_hw_cycles = cycle_count_hw[31:0];

        if (u_top.u_cpu_sc.u_rf.regs[11] !== 32'd55) begin
            $display("FAIL SC x11 = %0d, expected 55", u_top.u_cpu_sc.u_rf.regs[11]);
            errors = errors + 1;
        end
        if (sc_hw_cycles !== sc_cycles) begin
            $display("FAIL SC HW counter mismatch: hw=%0d sw=%0d", sc_hw_cycles, sc_cycles);
            errors = errors + 1;
        end

        // Pipeline run (reset, switch mode)
        rst_n = 0;
        mode_select = 0;
        #80 rst_n = 1;
        run_program(pp_cycles);
        #1;
        pp_inst      = inst_retired_hw[31:0];
        pp_hw_cycles = cycle_count_hw[31:0];

        if (u_top.u_cpu_pp.u_rf.regs[11] !== 32'd55) begin
            $display("FAIL PP x11 = %0d, expected 55", u_top.u_cpu_pp.u_rf.regs[11]);
            errors = errors + 1;
        end
        if (pp_hw_cycles !== pp_cycles) begin
            $display("FAIL PP HW counter mismatch: hw=%0d sw=%0d", pp_hw_cycles, pp_cycles);
            errors = errors + 1;
        end

        $display("");
        $display("==== tb_speedup_demo ====");
        $display("Single-cycle: %0d cycles (SW count), %0d cycles (HW counter), %0d retired",
                 sc_cycles, sc_hw_cycles, sc_inst);
        $display("Pipeline    : %0d cycles (SW count), %0d cycles (HW counter), %0d retired",
                 pp_cycles, pp_hw_cycles, pp_inst);
        $display("");
        $display("Note: 5-stage pipeline has CPI~=1 like single-cycle.");
        $display("The performance gain comes from a HIGHER CLOCK FREQUENCY");
        $display("(each pipeline stage has a shorter critical path than the");
        $display("full single-cycle datapath). Cycle counts alone don't show");
        $display("this — see synthesis fmax report for end-to-end speedup.");
        $display("Branch bubbles (3 cycles in pipeline vs 1 in single-cycle)");
        $display("explain why pipeline cycles >= single-cycle cycles here.");

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_speedup_demo failed");
        end
    end
endmodule
