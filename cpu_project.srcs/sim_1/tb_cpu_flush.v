`timescale 1ns/1ps
// Regression test for branch flush (Finding 1 in 5/18 review)
//
//   Program proves that a non-NOP fall-through after JAL is NOT executed:
//     mem[0]  = JAL  x0, 8           = 0x008000EF   (jump +8 to mem[2])
//     mem[1]  = ADDI x5, x0, 1       = 0x00100293   (fall-through，必须被 flush 掉)
//     mem[2]  = ADDI x6, x0, 2       = 0x00200313   (real target)
//     mem[3]  = JAL  x0, 0           = 0x0000006F   (self-loop = halt)
//
//   原 bug 行为：fake_ifetch 在 cycle 5 把 mem[1]=ADDI x5 当 inst_out 喂给 CPU，
//                CPU 会执行 ADDI x5, x0, 1，最终 x5=1（错的）。
//   修复后行为：cycle 5 inst_out=NOP（pending_flush 拉高），x5 保持 0。
//
//   Pass criteria:
//     x5 == 0  （flush 生效，fall-through 没执行）
//     x6 == 2  （真目标执行成功）
module tb_cpu_flush;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;

    wire [31:0] next_pc, pc_out, inst_out, pc_fetch;
    wire        pc_we, branch_redirect;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_be;
    wire        mem_we;

    always #20 clk = ~clk;   // 25MHz

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

    initial begin
        #1;   // 让 fake_ifetch/fake_dmem 的 time-0 NOP fill 先跑完
        u_if.mem[0] = 32'h008000EF;   // JAL  x0, +8
        u_if.mem[1] = 32'h00100293;   // ADDI x5, x0, 1   ← 必须被 flush
        u_if.mem[2] = 32'h00200313;   // ADDI x6, x0, 2
        u_if.mem[3] = 32'h0000006F;   // JAL  x0, 0  (halt loop)

        #80 rst_n = 1;
        #(40 * 12);                   // 跑 12 拍，足够 4 条指令 + 几次 JAL 循环

        $display("");
        $display("==== flush regression result ====");
        $display("x5 = %0d (expected 0, fall-through must be flushed)", u_cpu.u_rf.regs[5]);
        $display("x6 = %0d (expected 2, real branch target)",           u_cpu.u_rf.regs[6]);

        if (u_cpu.u_rf.regs[5] !== 32'd0) begin $display("FAIL: x5 was executed (delay slot bug)"); errors = errors + 1; end
        if (u_cpu.u_rf.regs[6] !== 32'd2) begin $display("FAIL: x6 not set");                      errors = errors + 1; end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_flush failed");
        end
    end

    initial begin
        $display(" T  |  pc_out  | pc_fetch | inst_out | redir | x5 | x6 | next_pc");
        $display("----+----------+----------+----------+-------+----+----+---------");
        forever @(posedge clk) if (rst_n) begin
            $display(" %3t | %08h | %08h | %08h |   %b   | %2d | %2d | %08h",
                     $time, pc_out, pc_fetch, inst_out, branch_redirect,
                     u_cpu.u_rf.regs[5], u_cpu.u_rf.regs[6], next_pc);
        end
    end
endmodule
