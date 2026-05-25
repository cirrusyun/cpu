`timescale 1ns/1ps
// Pipeline test: JAL / JALR link writeback + flush
//   Program:
//     mem[0] = ADDI x5, x0, 7        = 0x00700293
//     mem[1] = JAL  x1, +8           = 0x008000EF  (PC=4 → 12, x1=8)
//     mem[2] = ADDI x5, x0, 99       = 0x06300293  (SKIPPED)
//     mem[3] = ADDI x6, x0, 50       = 0x03200313  (target of JAL)
//     mem[4] = JALR x0, x1, 16       = 0x01008067  (PC=16 → x1+16=24)
//     mem[5] = ADDI x5, x0, 100      = 0x06400293  (SKIPPED)
//     mem[6] = ADDI x7, x0, 30       = 0x01E00393  (target of JALR)
//     mem[7] = JAL  x0, 0            = 0x0000006F
//   Expected: x1=8, x5=7, x6=50, x7=30
module tb_pipe_jal_jalr;
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
        u_if.mem[0] = 32'h00700293;
        u_if.mem[1] = 32'h008000EF;
        u_if.mem[2] = 32'h06300293;
        u_if.mem[3] = 32'h03200313;
        u_if.mem[4] = 32'h01008067;
        u_if.mem[5] = 32'h06400293;
        u_if.mem[6] = 32'h01E00393;
        u_if.mem[7] = 32'h0000006F;

        #80 rst_n = 1;   // release between posedges 60 and 100 to avoid race
        #(40 * 30);

        $display("");
        $display("==== tb_pipe_jal_jalr ====");
        $display("x1 = %0d (expected 8, JAL link)",   u_dut.u_rf.regs[1]);
        $display("x5 = %0d (expected 7, others skipped)", u_dut.u_rf.regs[5]);
        $display("x6 = %0d (expected 50)",  u_dut.u_rf.regs[6]);
        $display("x7 = %0d (expected 30)",  u_dut.u_rf.regs[7]);

        if (u_dut.u_rf.regs[1] !== 32'd8)  begin $display("FAIL: x1"); errors=errors+1; end
        if (u_dut.u_rf.regs[5] !== 32'd7)  begin $display("FAIL: x5"); errors=errors+1; end
        if (u_dut.u_rf.regs[6] !== 32'd50) begin $display("FAIL: x6"); errors=errors+1; end
        if (u_dut.u_rf.regs[7] !== 32'd30) begin $display("FAIL: x7"); errors=errors+1; end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_pipe_jal_jalr failed");
        end
    end
endmodule
