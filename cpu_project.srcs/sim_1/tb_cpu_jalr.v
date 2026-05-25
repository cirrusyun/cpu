`timescale 1ns/1ps
// End-to-end test: JALR (link, bit0 clear, x0 link) + AUIPC + LUI
module tb_cpu_jalr;
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
        // ============================================================
        // Test 1: AUIPC x10, 0x10000  (写 pc + 0x10000_000 到 x10)
        // ============================================================
        //   mem[0] = AUIPC x10, 0x10000 → x10 = PC + (0x10000 << 12) = 0 + 0x10000000
        //   mem[1] = JAL x0, 0  (halt)
        rst_n = 0;
        u_if.mem[0] = 32'h10000517;   // AUIPC x10, 0x10000
        u_if.mem[1] = 32'h0000006F;   // JAL x0, 0
        // 清掉其它 mem 避免污染
        u_if.mem[2] = 32'h00000013;
        u_if.mem[3] = 32'h00000013;
        u_if.mem[4] = 32'h00000013;
        u_if.mem[5] = 32'h00000013;
        u_if.mem[6] = 32'h00000013;
        u_if.mem[7] = 32'h00000013;
        u_if.mem[8] = 32'h00000013;
        u_if.mem[9] = 32'h00000013;
        u_if.mem[10] = 32'h00000013;
        u_if.mem[11] = 32'h00000013;
        u_if.mem[12] = 32'h00000013;
        #160 rst_n = 1;
        #(40 * 10);
        check("AUIPC x10 = 0+0x10000000", 5'd10, 32'h1000_0000);

        // ============================================================
        // Test 2: LUI x11, 0xABCDE  (写 0xABCDE000 到 x11)
        // ============================================================
        rst_n = 0;
        u_if.mem[0] = 32'hABCDE5B7;   // LUI x11, 0xABCDE
        u_if.mem[1] = 32'h0000006F;
        #160 rst_n = 1;
        #(40 * 10);
        check("LUI x11 = 0xABCDE000", 5'd11, 32'hABCD_E000);

        // ============================================================
        // Test 3: JALR x1, x0, 8  (跳到 PC=8, link 写 x1 = PC_at_JALR + 4)
        //
        // 关键 false-pass 规避：fall-through 写 x13（独立的"探针"寄存器），
        // 目标指令写 x12。如果 flush 失效让 fall-through 执行了，x13=99 立刻被发现；
        // 不能让 fall-through 跟目标写同一寄存器（会被覆盖掩盖）。
        // ============================================================
        //   mem[0] = JALR x1, x0, 8   →  PC ← (x0+8)&~1 = 8;  x1 ← 0+4 = 4
        //   mem[1] = ADDI x13, x0, 99 (probe，必须被 flush，x13 应保持 0)
        //   mem[2] = ADDI x12, x0, 5  (executes at PC=8)
        //   mem[3] = JAL x0, 0        (halt at PC=12)
        rst_n = 0;
        u_if.mem[0] = 32'h008000E7;   // JALR x1, x0, 8
        u_if.mem[1] = 32'h06300693;   // ADDI x13, x0, 99 (flush probe)
        u_if.mem[2] = 32'h00500613;   // ADDI x12, x0, 5
        u_if.mem[3] = 32'h0000006F;   // halt
        #160 rst_n = 1;
        #(40 * 10);
        check("JALR target → x12=5",                    5'd12, 32'd5);
        check("JALR link → x1 = 0+4 = 4",               5'd1,  32'd4);
        check("JALR flush probe → x13 stays 0",         5'd13, 32'd0);

        // ============================================================
        // Test 4: JALR bit0 cleared
        //   JALR x1, x0, 9 → target = (0+9)&~1 = 8
        // ============================================================
        rst_n = 0;
        u_if.mem[0] = 32'h009000E7;   // JALR x1, x0, 9
        u_if.mem[1] = 32'h06300693;   // ADDI x13, x0, 99 (flush probe)
        u_if.mem[2] = 32'h00700613;   // ADDI x12, x0, 7
        u_if.mem[3] = 32'h0000006F;
        #160 rst_n = 1;
        #(40 * 10);
        check("JALR bit0 cleared 9→8, x12=7", 5'd12, 32'd7);
        check("Test4 flush probe → x13 stays 0", 5'd13, 32'd0);

        // ============================================================
        // Test 5: JALR x0 link (返回式，rd=x0 不写)
        // ============================================================
        rst_n = 0;
        u_if.mem[0] = 32'h00800067;   // JALR x0, x0, 8 (rd=x0)
        u_if.mem[1] = 32'h06300693;   // ADDI x13, x0, 99 (flush probe)
        u_if.mem[2] = 32'h01100613;   // ADDI x12, x0, 17
        u_if.mem[3] = 32'h0000006F;
        #160 rst_n = 1;
        #(40 * 10);
        check("JALR x0 link, x12=17",  5'd12, 32'd17);
        check("JALR x0 link suppressed, x0=0", 5'd0, 32'd0);
        check("Test5 flush probe → x13 stays 0", 5'd13, 32'd0);

        // ============================================================
        // Test 6: JALR with non-zero rs1
        //   先 ADDI x5, x0, 12 → x5=12
        //   再 JALR x1, x5, 4 → target=(12+4)&~1=16
        //   mem[4] at PC=16 应被执行
        // ============================================================
        rst_n = 0;
        u_if.mem[0] = 32'h00C00293;   // ADDI x5, x0, 12
        u_if.mem[1] = 32'h004280E7;   // JALR x1, x5, 4
        u_if.mem[2] = 32'h06300713;   // ADDI x14, x0, 99 (flush probe, must not execute)
        u_if.mem[3] = 32'h00000013;   // NOP (dead code, PC=12 never reached)
        u_if.mem[4] = 32'h01F00613;   // ADDI x12, x0, 31 (executes)
        u_if.mem[5] = 32'h0000006F;
        #160 rst_n = 1;
        #(40 * 10);
        check("JALR rs1+imm target, x12=31",       5'd12, 32'd31);
        check("JALR link from PC=4, x1=4+4=8",     5'd1,  32'd8);
        check("Test6 flush probe → x14 stays 0",   5'd14, 32'd0);

        // ============================================================
        // Test 7: Reserved JALR funct3 must not redirect or write link
        //   JALR only accepts funct3=000. funct3=001 is reserved and should act as NOP.
        //   If it is decoded as real JALR, PC jumps to mem[2], x13 is flushed, and x1=4.
        // ============================================================
        rst_n = 0;
        u_if.mem[0] = 32'h008010E7;   // JALR-like encoding with funct3=001 (invalid)
        u_if.mem[1] = 32'h03700693;   // ADDI x13, x0, 55 (must execute)
        u_if.mem[2] = 32'h0000006F;   // halt
        u_if.mem[3] = 32'h00000013;
        u_if.mem[4] = 32'h00000013;
        u_if.mem[5] = 32'h00000013;
        #160 rst_n = 1;
        #(40 * 10);
        check("Invalid JALR funct3 falls through, x13=55", 5'd13, 32'd55);
        check("Invalid JALR funct3 does not write x1",     5'd1,  32'd0);

        // ============================================================
        // Test 8: AUIPC + JAL combo（架构 §12 提到的 JAL+AUIPC 基础功能）
        //   mem[0] = AUIPC x1, 0  → x1 = PC=0 + 0 = 0
        //   mem[1] = JAL x2, +8   → PC ← 4+8=12; x2 ← 4+4=8
        //   mem[2] = ADDI x14, x0, 99 (flush probe，独立寄存器)
        //   mem[3] = ADDI x3, x0, 42 (PC=12, executes)
        //   mem[4] = JAL x0, 0
        // ============================================================
        rst_n = 0;
        u_if.mem[0] = 32'h00000097;   // AUIPC x1, 0
        u_if.mem[1] = 32'h0080016F;   // JAL x2, +8
        u_if.mem[2] = 32'h06300713;   // ADDI x14, x0, 99 (flush probe)
        u_if.mem[3] = 32'h02A00193;   // ADDI x3, x0, 42 (executes)
        u_if.mem[4] = 32'h0000006F;
        #160 rst_n = 1;
        #(40 * 10);
        check("AUIPC x1 = 0",            5'd1,  32'd0);
        check("JAL link x2 = 4+4 = 8",   5'd2,  32'd8);
        check("JAL target → x3 = 42",    5'd3,  32'd42);
        check("Test8 flush probe → x14 stays 0", 5'd14, 32'd0);

        $display("");
        if (errors == 0) begin
            $display("==== tb_cpu_jalr PASS ====");
            $finish;
        end else begin
            $display("==== tb_cpu_jalr FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_jalr failed");
        end
    end
endmodule
