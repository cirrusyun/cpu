`timescale 1ns/1ps
// 综合 sanity test：一段 ~30 条指令的真实风格汇编混合，
// 覆盖 R/I/Load/Store/Branch/Jump/LUI/AUIPC 同时跑，模拟真实程序行为
//
// 程序逻辑：
//   1. 用 LUI+ADDI 构造一个 32-bit 立即数 0x12345678 写到 x10
//   2. ADDI 设 sp 偏移 = -16；存 x10 到栈
//   3. 从栈读回到 x11
//   4. 用 R-Type 算术：x12 = x10 + x11, x13 = x10 - x11 (应当为 0), x14 = x10 ^ x11 (应当为 0)
//   5. 循环：从 x15=0 加到 x15=5，用 BNE 控制
//   6. 用 AUIPC 算一个 PC 相对地址放到 x16
//   7. 用 JAL 跳一个子例程，子例程把 x17 = 0xCAFE，然后 JALR 返回
//   8. 最终 JAL 自循环 halt
//
// Pass criteria:
//   x10 = 0x12345678   (LUI+ADDI 构造)
//   x11 = 0x12345678   (从栈读回，证明 SW/LW 通路正确)
//   x12 = 0x2468ACF0   (x10+x11)
//   x13 = 0            (x10-x11)
//   x14 = 0            (x10^x11)
//   x15 = 5            (循环计数)
//   x16 != 0           (AUIPC 算出某个 PC-relative 地址)
//   x17 = 0xCAFE       (子例程写入)
//   x1 != 0            (JAL 写入的返回地址)
module tb_cpu_sanity;
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
    task check_nonzero;
        input [255:0] name;
        input [4:0]   r;
        begin
            if (u_cpu.u_rf.regs[r] == 32'd0) begin
                $display("FAIL %0s: regs[%0d]=0, expected non-zero", name, r);
                errors = errors + 1;
            end
        end
    endtask

    // 单独的 main routine 和 subroutine
    // 主程序从 PC=0 开始；子例程放在 PC=0x100 (mem[64])
    initial begin
        #1;   // 让 fake_ifetch 的 time-0 NOP fill 先跑完
        // PC=0x00 : 构造 0x12345678 → x10
        //   LUI x10, 0x12345     → x10 = 0x12345000
        //   ADDI x10, x10, 0x678 → x10 = 0x12345678
        u_if.mem[0]  = 32'h12345537;   // LUI x10, 0x12345
        u_if.mem[1]  = 32'h67850513;   // ADDI x10, x10, 0x678

        // PC=0x08 : 栈操作
        //   ADDI sp, sp, -16     → sp 偏移
        //   SW x10, 0(sp)        → 存到栈
        //   LW x11, 0(sp)        → 从栈读回
        u_if.mem[2]  = 32'hFF010113;   // ADDI x2, x2, -16
        u_if.mem[3]  = 32'h00A12023;   // SW x10, 0(x2)
        u_if.mem[4]  = 32'h00012583;   // LW x11, 0(x2)

        // PC=0x14 : R-Type 算术
        //   ADD x12, x10, x11
        //   SUB x13, x10, x11
        //   XOR x14, x10, x11
        u_if.mem[5]  = 32'h00B50633;   // ADD x12, x10, x11
        u_if.mem[6]  = 32'h40B506B3;   // SUB x13, x10, x11
        u_if.mem[7]  = 32'h00B54733;   // XOR x14, x10, x11

        // PC=0x20 : 循环 x15 = 0..5
        //   ADDI x15, x0, 0           ; x15 = 0      (PC=0x20)
        // loop: (PC=0x24)
        //   ADDI x15, x15, 1          ; x15++       (PC=0x24)
        //   ADDI x6, x0, 5            ; tmp = 5     (PC=0x28)
        //   BNE x15, x6, loop (-8)    ; while x15 != 5  (PC=0x2C → 0x24, offset=-8)
        u_if.mem[8]  = 32'h00000793;   // ADDI x15, x0, 0
        u_if.mem[9]  = 32'h00178793;   // ADDI x15, x15, 1   ← loop label (PC=0x24)
        u_if.mem[10] = 32'h00500313;   // ADDI x6, x0, 5
        u_if.mem[11] = 32'hFE679CE3;   // BNE x15, x6, -8 → jump to PC=0x24（手算 imm=-8 编码）

        // PC=0x30 : AUIPC 算 PC-relative
        //   AUIPC x16, 0          → x16 = PC + 0 = 0x30
        u_if.mem[12] = 32'h00000817;   // AUIPC x16, 0

        // PC=0x34 : JAL 跳子例程
        //   JAL x1, 0xCC (跳到 PC=0x100 = +0xCC)
        u_if.mem[13] = 32'h0CC000EF;   // JAL x1, +0xCC → PC=0x100

        // PC=0x38 : main 返回点
        //   JAL x0, 0  (halt 自循环)
        u_if.mem[14] = 32'h0000006F;   // JAL x0, 0   (halt)

        // 中间填充 NOP（mem[15..63]，PC=0x3C..0xFC）
        // fake_ifetch initial 已经填了 NOP，不用显式写

        // ================== 子例程 PC=0x100 ==================
        //   LUI x17, 0xC          → x17 = 0xC000 (高位)
        //   ADDI x17, x17, 0xAFE  → wait, 0xAFE > 0x7FF, can't use single ADDI immediate
        //   重新设计：用 LUI 0xCAFE 然后 SRLI 16 把高位推到低位
        //   或更简单：x17 = 0xCAFE = 51966 = 0xCAFE
        //
        //   方法：LUI x17, 0xD (= 0xD000)  →  ADDI x17, x17, -0x302 (= -770)
        //         0xD000 - 0x302 = 0xCCFE  ❌ 错
        //
        //   再试：0xCAFE = 0x0000_CAFE = (0xD << 12) - (0xD000 - 0xCAFE) = 0xD000 - 0x502
        //         LUI x17, 0xD       → 0xD000
        //         ADDI x17, x17, -0x502 (= -1282)
        //         0xD000 + 0xFFFF_FAFE = 0xD000 - 0x502 = 0xCAFE  ✓
        //         但 ADDI imm 是 12-bit 有符号，范围 -2048..2047；-1282 在范围内 ✓
        //
        //   LUI x17, 0xD: opcode=0110111, rd=10001, imm[31:12]=0x0000D
        //                  inst = 0x0000D8B7
        //   ADDI x17, x17, -1282 (= 0xFFFFFAFE → 12-bit = 0xAFE | sign-extended)
        //                  funct3=000, rs1=10001, rd=10001, imm=0xAFE | 0xFFFFF000
        //                  Hmm 12-bit imm 0xAFE 是负数（bit11=1）
        //                  imm[11:0]=101011111110 = 0xAFE = -1282 ✓
        //                  inst = imm[11:0]|rs1[4:0]|funct3|rd[4:0]|opcode
        //                       = 101011111110_10001_000_10001_0010011
        //                       = 0xAFE_8_8_8_93？让我重新拼:
        //                       inst[31:20] = 0xAFE = 1010_1111_1110
        //                       inst[19:15] = rs1 = 10001
        //                       inst[14:12] = funct3 = 000
        //                       inst[11:7]  = rd = 10001
        //                       inst[6:0]   = opcode = 0010011
        //                       inst = 1010_1111_1110 _ 10001 _ 000 _ 10001 _ 0010011
        //                            = 10101111_11101000_10001000_10010011
        //                            = 0xAFE88893
        u_if.mem[64] = 32'h0000D8B7;   // LUI x17, 0xD
        u_if.mem[65] = 32'hAFE88893;   // ADDI x17, x17, -1282

        // PC=0x108 : 返回 main 的 PC=0x38
        //   JALR x0, x1, 0   → 跳到 x1 的地址（main 中 JAL 写入的 0x38）
        u_if.mem[66] = 32'h00008067;   // JALR x0, x1, 0

        // ============= 跑 =============
        #160 rst_n = 1;
        #(40 * 80);   // 跑 80 拍，足够覆盖循环 5 次 + 子例程

        // ============= 校验 =============
        $display("");
        $display("==== sanity test result ====");
        $display("x10 (LUI+ADDI 0x12345678)        = %h", u_cpu.u_rf.regs[10]);
        $display("x11 (LW from stack)              = %h", u_cpu.u_rf.regs[11]);
        $display("x12 (x10+x11)                    = %h", u_cpu.u_rf.regs[12]);
        $display("x13 (x10-x11)                    = %h", u_cpu.u_rf.regs[13]);
        $display("x14 (x10^x11)                    = %h", u_cpu.u_rf.regs[14]);
        $display("x15 (loop counter)               = %0d",u_cpu.u_rf.regs[15]);
        $display("x16 (AUIPC pc-rel)               = %h", u_cpu.u_rf.regs[16]);
        $display("x17 (subroutine 0xCAFE)          = %h", u_cpu.u_rf.regs[17]);
        $display("x1  (JAL link → main return PC)  = %h", u_cpu.u_rf.regs[1]);
        $display("sp                               = %h", u_cpu.u_rf.regs[2]);
        $display("pc_out                           = %h", pc_out);

        check("x10 = 0x12345678",      5'd10, 32'h1234_5678);
        check("x11 = 0x12345678",      5'd11, 32'h1234_5678);
        check("x12 = 0x2468ACF0",      5'd12, 32'h2468_ACF0);
        check("x13 = 0",               5'd13, 32'h0);
        check("x14 = 0",               5'd14, 32'h0);
        check("x15 = 5 (loop end)",    5'd15, 32'd5);
        check("x16 = 0x30 (AUIPC)",    5'd16, 32'h30);
        check("x17 = 0xCAFE",          5'd17, 32'h0000_CAFE);
        check("x1  = 0x38 (return PC)",5'd1,  32'h38);
        check("sp  = 0x7FEC (decremented by 16)", 5'd2, 32'h0000_7FEC);
        if (pc_out !== 32'h0000_0038 && pc_out !== 32'h0000_003C) begin
            $display("FAIL halt PC: pc_out=%h, expected 00000038 or 0000003c", pc_out);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("==== tb_cpu_sanity PASS ====");
            $finish;
        end else begin
            $display("==== tb_cpu_sanity FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_sanity failed");
        end
    end
endmodule
