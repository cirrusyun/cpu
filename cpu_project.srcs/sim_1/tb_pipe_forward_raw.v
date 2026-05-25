`timescale 1ns/1ps
// Pipeline test: ALU→ALU RAW forwarding (EX/MEM 和 MEM/WB 两路)
//   Program:
//     mem[0] = ADDI x5, x0, 7        = 0x00700293
//     mem[1] = ADD  x6, x5, x5       = 0x00528333  (x6 ← x5+x5 → forward EX/MEM→EX)
//     mem[2] = ADD  x7, x6, x5       = 0x005303B3  (x7 ← x6+x5：x6 from EX/MEM, x5 from MEM/WB)
//     mem[3] = JAL  x0, 0            = 0x0000006F  (self-loop)
//   Expected: x5=7, x6=14, x7=21
module tb_pipe_forward_raw;
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
        u_if.mem[1] = 32'h00528333;
        u_if.mem[2] = 32'h005303B3;
        u_if.mem[3] = 32'h0000006F;

        #80 rst_n = 1;   // release between posedges 60 and 100 to avoid race
        #(40 * 15);

        $display("");
        $display("==== tb_pipe_forward_raw ====");
        $display("x5 = %0d (expected 7)",  u_dut.u_rf.regs[5]);
        $display("x6 = %0d (expected 14)", u_dut.u_rf.regs[6]);
        $display("x7 = %0d (expected 21)", u_dut.u_rf.regs[7]);

        if (u_dut.u_rf.regs[5] !== 32'd7)  begin $display("FAIL: x5"); errors=errors+1; end
        if (u_dut.u_rf.regs[6] !== 32'd14) begin $display("FAIL: x6"); errors=errors+1; end
        if (u_dut.u_rf.regs[7] !== 32'd21) begin $display("FAIL: x7"); errors=errors+1; end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_pipe_forward_raw failed");
        end
    end
endmodule
