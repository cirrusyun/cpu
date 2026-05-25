`timescale 1ns/1ps
// ECALL bonus regression（架构.md §14 max 2 分）
//
//   测试程序：
//     mem[0]  (PC=0x00) : ADDI x10, x0, 42       // 设 x10=42（预 ECALL 状态）
//     mem[1]  (PC=0x04) : SYSTEM imm=0 rs1!=0    // 非精确 ECALL，必须按 NOP 处理
//     mem[2]  (PC=0x08) : ADDI x13, x0, 7        // 证明 rs1!=0 没有误触发 trap
//     mem[3]  (PC=0x0C) : SYSTEM imm=0 rd!=0     // 非精确 ECALL，必须按 NOP 处理
//     mem[4]  (PC=0x10) : ADDI x14, x0, 8        // 证明 rd!=0 没有误触发 trap
//     mem[5]  (PC=0x14) : SYSTEM funct12=2       // 非 ECALL/EBREAK，必须按 NOP 处理
//     mem[6]  (PC=0x18) : ADDI x15, x0, 9        // 证明非法 SYSTEM 没有误触发 trap
//     mem[7]  (PC=0x1C) : ECALL                  // → 跳转到 handler PC=0x80
//     mem[8]  (PC=0x20) : ADDI x10, x0, 99       // **必须被 flush** 掉，x10 应当保持 42
//     ... 中间 NOP fill ...
//     mem[32] (PC=0x80) : ADDI x12, x0, 0xDE     // handler 写 x12=0xDE 证明 trap 命中
//     mem[33] (PC=0x84) : JAL x0, 0              // halt 自循环
//
//   Pass criteria:
//     x10 == 42    (ECALL 后的 fall-through 被 flush，没覆写 x10)
//     x12 == 0xDE  (handler 实际跑到了)
//     x11 == 0     (未触及)
//     x13 == 7     (rs1!=0 的非精确 ECALL 作为 NOP，继续顺序执行)
//     x14 == 8     (rd!=0 的非精确 ECALL 作为 NOP，继续顺序执行)
//     x15 == 9     (非法 SYSTEM 精确解码为 NOP，继续顺序执行)
//
//   反向：如果 ecall_trap 没生效，会直接执行 mem[8]，x10=99，x12=0 → FAIL
//         如果 SYSTEM 只看 funct12/funct3，mem[1] 或 mem[3] 会误触发 trap → FAIL
//
//   EBREAK 仍走 NOP 路径，不在此 tb 测试（架构 §12 base 行为）
module tb_cpu_ecall;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;
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

    initial begin
        #1;   // 让 fake_ifetch 的 time-0 NOP fill 先跑完
        // 主路径
        u_if.mem[0]  = 32'h02A00513;   // ADDI x10, x0, 42
        u_if.mem[1]  = 32'h00008073;   // SYSTEM imm=0, rs1=x1, rd=x0：不是 ECALL，按 NOP
        u_if.mem[2]  = 32'h00700693;   // ADDI x13, x0, 7    ← 应该执行
        u_if.mem[3]  = 32'h000000F3;   // SYSTEM imm=0, rs1=x0, rd=x1：不是 ECALL，按 NOP
        u_if.mem[4]  = 32'h00800713;   // ADDI x14, x0, 8    ← 应该执行
        u_if.mem[5]  = 32'h00200073;   // SYSTEM funct12=2：非法/未支持，按 NOP
        u_if.mem[6]  = 32'h00900793;   // ADDI x15, x0, 9    ← 应该执行
        u_if.mem[7]  = 32'h00000073;   // ECALL
        u_if.mem[8]  = 32'h06300513;   // ADDI x10, x0, 99   ← 不该执行
        // mem[9..31] 由 fake_ifetch 初始填 NOP（00000013）
        // Handler 在 PC=0x80 = mem[32]
        u_if.mem[32] = 32'h0DE00613;   // ADDI x12, x0, 0xDE
        u_if.mem[33] = 32'h0000006F;   // JAL x0, 0  (halt)

        // 复位 + 跑足够周期，覆盖多个 SYSTEM NOP、trap 和 handler 执行
        #160 rst_n = 1;
        #(40 * 30);

        $display("");
        $display("==== ECALL trap result ====");
        $display("x10 = %0d (expected 42, fall-through ADDI x10,99 must be flushed)",
                 u_cpu.u_rf.regs[10]);
        $display("x12 = 0x%h (expected 0xDE, handler must have executed)",
                 u_cpu.u_rf.regs[12]);
        $display("x13 = %0d (expected 7, unsupported SYSTEM must fall through as NOP)",
                 u_cpu.u_rf.regs[13]);
        $display("x14 = %0d (expected 8, rd!=0 SYSTEM must fall through as NOP)",
                 u_cpu.u_rf.regs[14]);
        $display("x15 = %0d (expected 9, unsupported SYSTEM must fall through as NOP)",
                 u_cpu.u_rf.regs[15]);
        $display("pc_out = 0x%h (expected 0x84/0x88 alternating in JAL self-loop bubble)", pc_out);

        check("x10 preserved (ECALL flush worked)", 5'd10, 32'd42);
        check("x12 set by handler",                  5'd12, 32'h0000_00DE);
        check("x11 untouched",                       5'd11, 32'd0);
        check("x13 set after rs1!=0 SYSTEM",          5'd13, 32'd7);
        check("x14 set after rd!=0 SYSTEM",           5'd14, 32'd8);
        check("x15 set after unsupported SYSTEM",     5'd15, 32'd9);
        if (pc_out !== 32'h0000_0084 && pc_out !== 32'h0000_0088) begin
            $display("FAIL handler halt PC: pc_out=%h, expected 00000084 or 00000088", pc_out);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("==== tb_cpu_ecall PASS ====");
            $finish;
        end else begin
            $display("==== tb_cpu_ecall FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_ecall failed");
        end
    end

    // trace 关键周期
    initial begin
        $display(" T   |  pc_out  | pc_fetch | inst_out | redir | x10 | x12 | x13");
        $display("-----+----------+----------+----------+-------+-----+-----+-----");
        forever @(posedge clk) if (rst_n) begin
            $display(" %4t | %08h | %08h | %08h |   %b   | %3d | %3d | %3d",
                     $time, pc_out, pc_fetch, inst_out, branch_redirect,
                     u_cpu.u_rf.regs[10], u_cpu.u_rf.regs[12], u_cpu.u_rf.regs[13]);
        end
    end
endmodule
