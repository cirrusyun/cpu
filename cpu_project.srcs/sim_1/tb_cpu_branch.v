`timescale 1ns/1ps
// End-to-end test: 6 conditional branches, taken and not-taken.
//
// 策略：用 ADDI 设好 rs1/rs2，跑分支指令，然后让分支走两条路径：
//   - taken  路径写 rd=1
//   - skip   路径写 rd=2
// 通过 rd 终值判断是否取分支。
//
// 关键 corner：BLT/BGE 在 signed overflow 时 (例如 rs1=0x80000000, rs2=1)
// 用 SUB+negative 会算错，必须用 SLT。本 tb cover 这条。
module tb_cpu_branch;
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

    // 单个测试 program 模板：
    //   程序写 x10/x11 = 操作数，跑 branch，分支到 PC=24 写 x12=1，
    //   不取就 fall-through 写 x13=1、x12=2，最后都跳到 PC=32 自循环。
    //   x13 是 flush 哨兵：taken 分支若错误执行 fall-through，会被 x13!=0 抓到。
    //
    //   mem[0] = ADDI x10, x0, <A>            // 写 rs1
    //   mem[1] = ADDI x11, x0, <B>            // 写 rs2
    //   mem[2] = B<cond> x10, x11, +16        // 跳到 mem[6]（PC=24）
    //   mem[3] = ADDI x13, x0, 1              // not-taken 哨兵
    //   mem[4] = ADDI x12, x0, 2              // not-taken 结果
    //   mem[5] = JAL  x0, +12                 // 跳到 mem[8]（PC=32）
    //   mem[6] = ADDI x12, x0, 1              // taken 路径
    //   mem[7] = JAL  x0, +4                  // 跳到 mem[8]
    //   mem[8] = JAL  x0, 0                   // halt loop (PC=32)
    task run_case;
        input [31:0] inst_addi_a;   // 写 x10
        input [31:0] inst_addi_b;   // 写 x11
        input [31:0] inst_branch;   // B<cond> x10, x11, +16 (offset 0x10)
        input [31:0] expected_x12;
        input [255:0] name;
        reg   [31:0] expected_x13;
        begin
            // 拉复位线，并在 hold 期间装填程序
            rst_n = 0;
            u_if.mem[0] = inst_addi_a;
            u_if.mem[1] = inst_addi_b;
            u_if.mem[2] = inst_branch;
            u_if.mem[3] = 32'h00100693;   // ADDI x13, x0, 1  (fall-through probe)
            u_if.mem[4] = 32'h00200613;   // ADDI x12, x0, 2  (not-taken result)
            u_if.mem[5] = 32'h00C0006F;   // JAL x0, +12 → mem[8] (at PC=20)
            u_if.mem[6] = 32'h00100613;   // ADDI x12, x0, 1  (taken result at PC=24)
            u_if.mem[7] = 32'h0040006F;   // JAL x0, +4  → mem[8] (at PC=28)
            u_if.mem[8] = 32'h0000006F;   // JAL x0, 0   (halt at PC=32)
            // hold reset 至少 3 个 25MHz 周期（120ns），确保异步置位 + IF/EX 寄存器全部清干净
            #160 rst_n = 1;
            // 跑足够多的周期让 case 执行完
            #(40 * 20);
            check(name, 5'd12, expected_x12);
            expected_x13 = (expected_x12 == 32'd1) ? 32'd0 : 32'd1;
            if (u_cpu.u_rf.regs[13] !== expected_x13) begin
                $display("FAIL %0s fall-through probe: regs[13]=%h, expected %h",
                         name, u_cpu.u_rf.regs[13], expected_x13);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #1;   // 让 fake_ifetch 的 time-0 NOP fill 先跑完，再让 run_case 写程序
        // BEQ x10, x11 (相等取分支)
        // BEQ 编码：opcode=1100011, funct3=000, rs1=10, rs2=11, imm=+16
        // imm=16 → imm[12|10:5|4:1|11] = 0|000000|1000|0
        // inst[31|7|30:25|11:8] = 0|0|000000|1000
        // → 32'h00B50863 (rs2=11, rs1=10, funct3=000)
        run_case(32'h00500513,  // ADDI x10, x0, 5
                 32'h00500593,  // ADDI x11, x0, 5
                 32'h00B50863,  // BEQ x10, x11, +16
                 32'd1, "BEQ taken (5==5)");

        run_case(32'h00500513,  // x10=5
                 32'h00300593,  // x11=3
                 32'h00B50863,  // BEQ
                 32'd2, "BEQ not-taken (5!=3)");

        // BNE: funct3=001 → 32'h00B51863
        run_case(32'h00500513, 32'h00300593,
                 32'h00B51863,
                 32'd1, "BNE taken (5!=3)");
        run_case(32'h00500513, 32'h00500593,
                 32'h00B51863,
                 32'd2, "BNE not-taken (5==5)");

        // BLT: funct3=100 → 32'h00B54863（有符号小于）
        run_case(32'h00300513, 32'h00500593,  // 3 < 5
                 32'h00B54863, 32'd1, "BLT taken (3<5)");
        run_case(32'h00500513, 32'h00300593,  // 5 < 3 = false
                 32'h00B54863, 32'd2, "BLT not-taken (5>=3)");

        // BLT signed overflow corner: rs1=0x80000000 (min-), rs2=1
        //   SUB+negative 会得 0x80000000-1=0x7FFFFFFF (positive!) → 错判 not-taken
        //   SLT 应当正确判 taken
        // mem[0] 改用 LUI x10, 0x80000 (这条直接写 x10=0x80000000，无需 ADDI 拼接)
        run_case(32'h80000537,  // LUI x10, 0x80000 → x10 = 0x80000000
                 32'h00100593,  // ADDI x11, x0, 1
                 32'h00B54863,  // BLT x10, x11, +16
                 32'd1, "BLT signed corner (0x80000000 < 1)");

        // BGE: funct3=101 → 32'h00B55863
        run_case(32'h00500513, 32'h00300593,  // 5 >= 3 → taken
                 32'h00B55863, 32'd1, "BGE taken (5>=3)");
        run_case(32'h00300513, 32'h00500593,  // 3 >= 5 = false
                 32'h00B55863, 32'd2, "BGE not-taken (3<5)");

        // BLTU: funct3=110 → 32'h00B56863（无符号小于）
        run_case(32'h00300513, 32'h00500593,  // 3 < 5 → taken
                 32'h00B56863, 32'd1, "BLTU taken (3<5)");
        // 无符号比较：0xFFFFFFFF > 1
        run_case(32'hFFF00513,  // ADDI x10, x0, -1 (= 0xFFFFFFFF as unsigned)
                 32'h00100593,  // ADDI x11, x0, 1
                 32'h00B56863,
                 32'd2, "BLTU not-taken (max unsigned >= 1)");

        // BGEU: funct3=111 → 32'h00B57863
        run_case(32'hFFF00513,  // x10 = -1 = 0xFFFFFFFF (max unsigned)
                 32'h00100593,  // x11 = 1
                 32'h00B57863,
                 32'd1, "BGEU taken (max unsigned >= 1)");
        run_case(32'h00100513,  // x10 = 1
                 32'hFFF00593,  // x11 = -1 = 0xFFFFFFFF (max unsigned)
                 32'h00B57863,
                 32'd2, "BGEU not-taken (1 < max unsigned)");

        $display("");
        if (errors == 0) begin
            $display("==== tb_cpu_branch PASS ====");
            $finish;
        end else begin
            $display("==== tb_cpu_branch FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_branch failed");
        end
    end
endmodule
