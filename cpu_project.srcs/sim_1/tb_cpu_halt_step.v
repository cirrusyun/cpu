`timescale 1ns/1ps
// Verify cpu_step gate semantics（架构.md §9 / 检查单 §4.1）:
//   cpu_step=0 时，CPU 所有状态寄存器冻结：
//     - RegFile 不写入
//     - ifetch 内 pc_fetch / pc_execute 不更新
//     - mem_we 被 A gate 为 0，dmem 不写入
//   cpu_step=1 单次拉高一拍，CPU 应当推进一条指令。
//
// 程序：3 条 ADDI + 1 条 SW + JAL halt
//   mem[0] = ADDI x10, x0, 1   →  x10 = 1
//   mem[1] = ADDI x11, x0, 2   →  x11 = 2
//   mem[2] = ADDI x12, x0, 3   →  x12 = 3
//   mem[3] = SW   x10, 0(x0)   →  dmem[0] = 1（仅 run 时允许发生）
//   mem[4] = JAL  x0, 0        →  halt loop
module tb_cpu_halt_step;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 0;          // 默认 halted

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
    cpu u_cpu (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata),
        .dbg_reg_addr(5'd0), .dbg_reg_data()
    );

    integer errors = 0;
    reg [31:0] hold_pc_out;
    reg [31:0] hold_pc_fetch;
    reg [31:0] hold_inst_out;
    task check;
        input [255:0] name;
        input [4:0]   r;
        input [31:0]  expected;
        begin
            if (u_cpu.u_rf.regs[r] !== expected) begin
                $display("FAIL %0s: regs[%0d]=%h, expected %h",
                         name, r, u_cpu.u_rf.regs[r], expected);
                errors = errors + 1;
            end
        end
    endtask

    // 单步：拉 cpu_step 一拍后释放
    task step_one;
        begin
            @(negedge clk) cpu_step = 1;
            @(negedge clk) cpu_step = 0;
            #1;   // allow combinational outputs gated by cpu_step to settle
        end
    endtask

    initial begin
        #1;   // 让 fake_ifetch/fake_dmem 的 time-0 NOP fill 先跑完
        u_if.mem[0] = 32'h00100513;   // ADDI x10, x0, 1
        u_if.mem[1] = 32'h00200593;   // ADDI x11, x0, 2
        u_if.mem[2] = 32'h00300613;   // ADDI x12, x0, 3
        u_if.mem[3] = 32'h00A02023;   // SW x10, 0(x0)
        u_if.mem[4] = 32'h0000006F;   // JAL x0, 0

        // ─────────── Phase 1：halt 状态下复位 + 静等 5 拍 ───────────
        // 复位释放但 cpu_step 保持 0，所有寄存器应保持复位值
        #160 rst_n = 1;
        #(40 * 5);

        $display("");
        $display("---- Phase 1: halted, 5 cycles after reset ----");
        check("Phase1 x10 still 0",  5'd10, 32'd0);
        check("Phase1 x11 still 0",  5'd11, 32'd0);
        check("Phase1 x12 still 0",  5'd12, 32'd0);
        check("Phase1 sp init",      5'd2,  32'h0000_7FFC);
        check("Phase1 gp init",      5'd3,  32'h0000_4000);
        if (pc_out !== 32'd0) begin
            $display("FAIL Phase1: pc_out=%h, expected 0 (halted)", pc_out);
            errors = errors + 1;
        end
        if (pc_fetch !== 32'd0) begin
            $display("FAIL Phase1: pc_fetch=%h, expected 0 (halted)", pc_fetch);
            errors = errors + 1;
        end
        if (inst_out !== 32'h00000013) begin
            $display("FAIL Phase1: inst_out=%h, expected startup NOP", inst_out);
            errors = errors + 1;
        end

        // ─────────── Phase 2：单步推进 1 条 ───────────
        // step → 应当执行 mem[0]（cycle 1：pc_out=0, inst=ADDI x10,1）
        // 注意 startup NOP 已经在 Phase 1 期间被吃掉（startup 在第 1 个 cpu_step=1 周期清零）
        // 实际：cycle 0 是 startup NOP，但 cpu_step=0 所以 startup 不清零
        // 第一次 step：cpu_step=1 一拍 → startup 清零 + bram_dout 装 mem[0] + pc_fetch 推进
        //              但 inst_out 此时还是 NOP（startup 这拍清零，inst_out 在下个周期才是 mem[0]）
        // 所以需要两次 step 才能让 x10 真正写入
        step_one;   // step 1: 清 startup, prefetch mem[0]
        $display("");
        $display("---- Phase 2a: after 1 step (startup → ADDI x10 prefetched) ----");
        check("Phase2a x10 still 0 (NOP just executed)", 5'd10, 32'd0);

        step_one;   // step 2: 真正执行 ADDI x10, x0, 1
        $display("");
        $display("---- Phase 2b: after 2 steps (ADDI x10 executed) ----");
        check("Phase2b x10 = 1",  5'd10, 32'd1);
        check("Phase2b x11 still 0",  5'd11, 32'd0);

        step_one;   // step 3: ADDI x11, x0, 2
        $display("");
        $display("---- Phase 2c: after 3 steps ----");
        check("Phase2c x10 = 1",  5'd10, 32'd1);
        check("Phase2c x11 = 2",  5'd11, 32'd2);
        check("Phase2c x12 still 0",  5'd12, 32'd0);

        step_one;   // step 4: ADDI x12, x0, 3
        $display("");
        $display("---- Phase 2d: after 4 steps ----");
        check("Phase2d x12 = 3",  5'd12, 32'd3);
        if (mem_we !== 1'b0) begin
            $display("FAIL Phase2d: mem_we=%b while halted on pending SW, expected 0", mem_we);
            errors = errors + 1;
        end
        if (u_dm.mem[0] !== 32'd0) begin
            $display("FAIL Phase2d: dmem[0]=%h, expected 0 before SW is stepped/run", u_dm.mem[0]);
            errors = errors + 1;
        end

        // ─────────── Phase 3：halt 后再等若干拍，所有寄存器值不应变化 ───────────
        // cpu_step=0 持续；如果有 leak，x10/x11/x12 可能被错误指令再次写入，
        // 或者 pending SW 在 halted 状态误写 dmem[0]。
        hold_pc_out   = pc_out;
        hold_pc_fetch = pc_fetch;
        hold_inst_out = inst_out;
        #(40 * 8);
        $display("");
        $display("---- Phase 3: halted 8 cycles, values must be frozen ----");
        check("Phase3 x10 frozen",  5'd10, 32'd1);
        check("Phase3 x11 frozen",  5'd11, 32'd2);
        check("Phase3 x12 frozen",  5'd12, 32'd3);
        if (mem_we !== 1'b0) begin
            $display("FAIL Phase3: mem_we=%b while halted on pending SW, expected 0", mem_we);
            errors = errors + 1;
        end
        if (u_dm.mem[0] !== 32'd0) begin
            $display("FAIL Phase3: dmem[0]=%h, expected 0 while halted", u_dm.mem[0]);
            errors = errors + 1;
        end
        if (pc_out !== hold_pc_out || pc_fetch !== hold_pc_fetch || inst_out !== hold_inst_out) begin
            $display("FAIL Phase3 IF freeze: pc_out %h->%h pc_fetch %h->%h inst %h->%h",
                     hold_pc_out, pc_out, hold_pc_fetch, pc_fetch, hold_inst_out, inst_out);
            errors = errors + 1;
        end

        // ─────────── Phase 4：连续 run（cpu_step=1）跑完剩余 JAL halt ───────────
        cpu_step = 1;
        #(40 * 10);
        $display("");
        $display("---- Phase 4: run mode, should execute SW then reach JAL halt at PC=16 ----");
        // x10/x11/x12 都已经写入，再跑 SW/JAL 不该改变它们
        check("Phase4 x10",  5'd10, 32'd1);
        check("Phase4 x11",  5'd11, 32'd2);
        check("Phase4 x12",  5'd12, 32'd3);
        if (u_dm.mem[0] !== 32'd1) begin
            $display("FAIL Phase4: dmem[0]=%h, expected 1 after SW runs", u_dm.mem[0]);
            errors = errors + 1;
        end

        $display("");
        if (errors == 0) begin
            $display("==== tb_cpu_halt_step PASS ====");
            $finish;
        end else begin
            $display("==== tb_cpu_halt_step FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_halt_step failed");
        end
    end
endmodule
