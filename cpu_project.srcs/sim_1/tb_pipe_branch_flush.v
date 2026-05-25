`timescale 1ns/1ps
// Pipeline test: taken branch flushes 2 sequential successors
//   Program:
//     mem[0] = ADDI x5, x0, 1        = 0x00100293
//     mem[1] = BEQ  x5, x5, +12      = 0x00528663  (PC=4, target=16, taken)
//     mem[2] = ADDI x6, x0, 99       = 0x06300313  (SKIPPED)
//     mem[3] = ADDI x7, x0, 88       = 0x05800393  (SKIPPED)
//     mem[4] = ADDI x8, x0, 55       = 0x03700413  (target)
//     mem[5] = JAL  x0, 0            = 0x0000006F
//   Expected: x5=1, x6=0, x7=0, x8=55
module tb_pipe_branch_flush;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;

    wire [31:0] next_pc;
    wire        pc_we, branch_redirect;
    wire [31:0] pc_out, inst_out, pc_fetch;
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
    cpu_pipe u_dut (
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
        u_if.mem[0] = 32'h00100293;
        u_if.mem[1] = 32'h00528663;
        u_if.mem[2] = 32'h06300313;
        u_if.mem[3] = 32'h05800393;
        u_if.mem[4] = 32'h03700413;
        u_if.mem[5] = 32'h0000006F;

        #80 rst_n = 1;   // release between posedges 60 and 100 to avoid race
        #(40 * 20);

        $display("");
        $display("==== tb_pipe_branch_flush ====");
        $display("x5 = %0d (expected 1)",  u_dut.u_rf.regs[5]);
        $display("x6 = %0d (expected 0, skipped)",  u_dut.u_rf.regs[6]);
        $display("x7 = %0d (expected 0, skipped)",  u_dut.u_rf.regs[7]);
        $display("x8 = %0d (expected 55)", u_dut.u_rf.regs[8]);

        if (u_dut.u_rf.regs[5] !== 32'd1)  begin $display("FAIL: x5"); errors=errors+1; end
        if (u_dut.u_rf.regs[6] !== 32'd0)  begin $display("FAIL: x6 (skipped instr executed!)"); errors=errors+1; end
        if (u_dut.u_rf.regs[7] !== 32'd0)  begin $display("FAIL: x7 (skipped instr executed!)"); errors=errors+1; end
        if (u_dut.u_rf.regs[8] !== 32'd55) begin $display("FAIL: x8"); errors=errors+1; end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_pipe_branch_flush failed");
        end
    end
endmodule
