`timescale 1ns/1ps
// Pipeline test: ECALL flush + handler jump
//   Phase 1: legitimate ECALL flushes + jumps to handler.
//     mem[0]  = ADDI x5,  x0, 7      = 0x00700293
//     mem[1]  = ECALL                = 0x00000073  (redirect to PC=0x80=mem[32])
//     mem[2]  = ADDI x6,  x0, 99     = 0x06300313  (SKIPPED)
//     mem[3]  = ADDI x7,  x0, 88     = 0x05800393  (SKIPPED)
//     mem[32] = ADDI x10, x0, 1      = 0x00100513  (handler at 0x80, x10=1)
//     mem[33] = ADDI x11, x0, 2      = 0x00200593  (x11=2)
//     mem[34] = SYSTEM (rs1!=0)      = 0x00108073  (reserved encoding → NOP)
//     mem[35] = ADDI x12, x0, 3      = 0x00300613  (must execute after illegal NOP)
//     mem[36] = JAL  x0, 0           = 0x0000006F  (handler self-loop)
//   Expected: x5=7, x6=0, x7=0, x10=1, x11=2, x12=3
//   The illegal SYSTEM at 0x88 must NOT trigger an ECALL trap; x12 must commit.
module tb_pipe_ecall;
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
        u_if.mem[0]  = 32'h00700293;
        u_if.mem[1]  = 32'h00000073;
        u_if.mem[2]  = 32'h06300313;
        u_if.mem[3]  = 32'h05800393;
        u_if.mem[32] = 32'h00100513;
        u_if.mem[33] = 32'h00200593;
        u_if.mem[34] = 32'h00008073;   // SYSTEM funct12=0 funct3=000 rs1=x1 rd=x0 → reserved (ECALL 精确译码必须把它当 NOP)
        u_if.mem[35] = 32'h00300613;
        u_if.mem[36] = 32'h0000006F;

        #80 rst_n = 1;   // release between posedges 60 and 100 to avoid race
        #(40 * 40);

        $display("");
        $display("==== tb_pipe_ecall ====");
        $display("x5  = %0d (expected 7)",  u_dut.u_rf.regs[5]);
        $display("x6  = %0d (expected 0, skipped)", u_dut.u_rf.regs[6]);
        $display("x7  = %0d (expected 0, skipped)", u_dut.u_rf.regs[7]);
        $display("x10 = %0d (expected 1, handler executed)", u_dut.u_rf.regs[10]);
        $display("x11 = %0d (expected 2, handler executed)", u_dut.u_rf.regs[11]);
        $display("x12 = %0d (expected 3, after illegal SYSTEM)", u_dut.u_rf.regs[12]);

        if (u_dut.u_rf.regs[5]  !== 32'd7) begin $display("FAIL: x5"); errors=errors+1; end
        if (u_dut.u_rf.regs[6]  !== 32'd0) begin $display("FAIL: x6 (skipped instr executed)"); errors=errors+1; end
        if (u_dut.u_rf.regs[7]  !== 32'd0) begin $display("FAIL: x7 (skipped instr executed)"); errors=errors+1; end
        if (u_dut.u_rf.regs[10] !== 32'd1) begin $display("FAIL: x10 (handler did not run)"); errors=errors+1; end
        if (u_dut.u_rf.regs[11] !== 32'd2) begin $display("FAIL: x11"); errors=errors+1; end
        if (u_dut.u_rf.regs[12] !== 32'd3) begin $display("FAIL: x12 (illegal SYSTEM triggered trap or stalled flow)"); errors=errors+1; end

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_pipe_ecall failed");
        end
    end
endmodule
