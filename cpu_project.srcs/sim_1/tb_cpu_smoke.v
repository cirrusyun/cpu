`timescale 1ns/1ps
// Smoke test for A's cpu.v + fake_ifetch + fake_dmem
//
//   Program (hand-encoded):
//     mem[0] = ADDI x10, x0, 5         = 0x00500513
//     mem[1] = ADDI x11, x0, 3         = 0x00300593
//     mem[2] = ADD  x12, x10, x11      = 0x00B50633
//     mem[3] = JAL  x0, .              = 0x0000006F  (infinite loop at PC=12)
//
//   Pass criteria:
//     x10 = 5, x11 = 3, x12 = 8
//     PC ∈ {12, 16}（JAL 自循环 + BRAM 2 级流水固有 1-cycle branch bubble，
//                    pc_out 在 JAL 周期=12 / bubble NOP 周期=16 之间交替）
//
//   Timing reference (BRAM 同步读 + startup NOP，2 级流水):
//     T=0  rst_n 释放      startup=1, inst_out=NOP, pc_out=0, pc_fetch=0
//     T=1  执行 mem[0]     inst_out=ADDI x10, pc_out=0, pc_fetch=4
//     T=2  执行 mem[1]     inst_out=ADDI x11, pc_out=4, pc_fetch=8
//     T=3  执行 mem[2]     inst_out=ADD,      pc_out=8, pc_fetch=12
//     T=4  执行 mem[3]     inst_out=JAL,      pc_out=12, pc_fetch=16
//     T=5  bubble          inst_out=NOP,      pc_out=16, pc_fetch=12（JAL 已重定向）
//     T=6  执行 mem[3]     inst_out=JAL,      pc_out=12, pc_fetch=16（回环）
//     T=7+  cycles 5/6 交替 forever
module tb_cpu_smoke;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;     // 持续运行（不模拟 halt/step）

    // CPU ↔ ifetch
    wire [31:0] next_pc;
    wire        pc_we;
    wire        branch_redirect;
    wire [31:0] pc_out;
    wire [31:0] inst_out;
    wire [31:0] pc_fetch;

    // CPU ↔ dmem
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_be;
    wire        mem_we;
    wire [31:0] mem_rdata;

    // 25MHz: period 40ns, half 20ns
    always #20 clk = ~clk;

    fake_ifetch u_if (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch)
    );

    fake_dmem u_dm (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we),
        .mem_rdata(mem_rdata)
    );

    cpu u_cpu (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we),
        .mem_rdata(mem_rdata),
        .dbg_reg_addr(5'd0), .dbg_reg_data()
    );

    integer errors = 0;

    initial begin
        #1;   // 让 fake_ifetch 的 time-0 NOP fill 先跑完
        // 手动塞程序到 ifetch 的 mem
        u_if.mem[0] = 32'h00500513;   // ADDI x10, x0, 5
        u_if.mem[1] = 32'h00300593;   // ADDI x11, x0, 3
        u_if.mem[2] = 32'h00B50633;   // ADD  x12, x10, x11
        u_if.mem[3] = 32'h0000006F;   // JAL  x0, .

        // 复位 2 个时钟周期
        #80 rst_n = 1;

        // 跑 10 个时钟周期，足够 4 条指令执行完 + 几个 JAL 自循环
        #(40 * 10);

        // 校验
        $display("");
        $display("==== smoke test result ====");
        $display("x10      = %0d (expected 5)",  u_cpu.u_rf.regs[10]);
        $display("x11      = %0d (expected 3)",  u_cpu.u_rf.regs[11]);
        $display("x12      = %0d (expected 8)",  u_cpu.u_rf.regs[12]);
        $display("pc_out   = 0x%08h (expected 12 or 16, JAL self-loop)", pc_out);
        $display("pc_fetch = 0x%08h", pc_fetch);

        if (u_cpu.u_rf.regs[10] !== 32'd5)  begin $display("FAIL: x10"); errors = errors + 1; end
        if (u_cpu.u_rf.regs[11] !== 32'd3)  begin $display("FAIL: x11"); errors = errors + 1; end
        if (u_cpu.u_rf.regs[12] !== 32'd8)  begin $display("FAIL: x12"); errors = errors + 1; end
        if (pc_out !== 32'd12 && pc_out !== 32'd16)
            begin $display("FAIL: PC not in {12,16}"); errors = errors + 1; end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_smoke failed");
        end
    end

    // 可选：trace 每拍状态，方便 debug
    initial begin
        $display(" T  |  pc_out  | pc_fetch | inst_out | x10 | x11 | x12 | next_pc");
        $display("----+----------+----------+----------+-----+-----+-----+---------");
        forever @(posedge clk) begin
            if (rst_n) begin
                $display(" %3t | %08h | %08h | %08h | %3d | %3d | %3d | %08h",
                         $time, pc_out, pc_fetch, inst_out,
                         u_cpu.u_rf.regs[10], u_cpu.u_rf.regs[11], u_cpu.u_rf.regs[12],
                         next_pc);
            end
        end
    end
endmodule
