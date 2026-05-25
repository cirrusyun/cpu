`timescale 1ns/1ps
// Pipeline test: cpu_step gate freezes ALL pipeline registers
//   单步语义：一个 cpu_step 脉冲推动整条流水线（IF/ID held buffer, ID/EX,
//   EX/MEM, MEM/WB, RegFile）同时前进一拍。
//
//   程序：3 条 ADDI + JAL
//     mem[0] = ADDI x10, x0, 1
//     mem[1] = ADDI x11, x0, 2
//     mem[2] = ADDI x12, x0, 3
//     mem[3] = JAL  x0, 0
module tb_pipe_halt_step;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 0;

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
    cpu_pipe u_dut (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .next_pc(next_pc), .pc_we(pc_we), .branch_redirect(branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_be(mem_be), .mem_we(mem_we), .mem_rdata(mem_rdata),
        .dbg_reg_addr(5'd0), .dbg_reg_data()
    );

    integer errors = 0;
    reg [31:0] snap_id_ex_pc, snap_ex_mem_alu, snap_mem_wb_pc;
    reg [31:0] snap_pc_fetch, snap_pc_execute;

    task step_one;
        begin
            @(negedge clk) cpu_step = 1;
            @(negedge clk) cpu_step = 0;
            #1;
        end
    endtask

    initial begin
        #1;   // 让 fake_ifetch/fake_dmem 的 time-0 NOP fill 先跑完
        u_if.mem[0] = 32'h00100513;
        u_if.mem[1] = 32'h00200593;
        u_if.mem[2] = 32'h00300613;
        u_if.mem[3] = 32'h0000006F;

        // 复位（halt 状态）
        #80 rst_n = 1;

        // Phase 1: halt 5 拍，所有寄存器应保持 reset 值
        repeat (5) @(negedge clk);
        if (u_dut.id_ex_pc !== 32'b0 || u_dut.ex_mem_alu_result !== 32'b0 ||
            u_dut.mem_wb_rd_addr !== 5'b0) begin
            $display("FAIL: pipeline registers advanced during halt");
            errors = errors + 1;
        end
        if (u_dut.u_rf.regs[10] !== 32'b0) begin
            $display("FAIL: RF written during halt");
            errors = errors + 1;
        end

        // Phase 2: 单步 10 拍，3 条 ADDI 应该最终全部写入 RF
        repeat (10) step_one;

        if (u_dut.u_rf.regs[10] !== 32'd1) begin
            $display("FAIL: x10=%0d expected 1", u_dut.u_rf.regs[10]); errors=errors+1;
        end
        if (u_dut.u_rf.regs[11] !== 32'd2) begin
            $display("FAIL: x11=%0d expected 2", u_dut.u_rf.regs[11]); errors=errors+1;
        end
        if (u_dut.u_rf.regs[12] !== 32'd3) begin
            $display("FAIL: x12=%0d expected 3", u_dut.u_rf.regs[12]); errors=errors+1;
        end

        // Phase 3: 再次 halt，snapshot 流水寄存器，等 5 拍后检查没动
        @(negedge clk);
        snap_id_ex_pc   = u_dut.id_ex_pc;
        snap_ex_mem_alu = u_dut.ex_mem_alu_result;
        snap_mem_wb_pc  = u_dut.mem_wb_pc;
        snap_pc_fetch   = u_if.pc_fetch;
        snap_pc_execute = u_if.pc_execute;

        repeat (5) @(negedge clk);
        if (u_dut.id_ex_pc !== snap_id_ex_pc) begin
            $display("FAIL Phase3: id_ex_pc changed during halt"); errors=errors+1;
        end
        if (u_dut.ex_mem_alu_result !== snap_ex_mem_alu) begin
            $display("FAIL Phase3: ex_mem_alu changed during halt"); errors=errors+1;
        end
        if (u_dut.mem_wb_pc !== snap_mem_wb_pc) begin
            $display("FAIL Phase3: mem_wb_pc changed during halt"); errors=errors+1;
        end
        if (u_if.pc_fetch !== snap_pc_fetch) begin
            $display("FAIL Phase3: pc_fetch changed during halt"); errors=errors+1;
        end

        $display("");
        $display("==== tb_pipe_halt_step ====");
        $display("x10 = %0d, x11 = %0d, x12 = %0d", u_dut.u_rf.regs[10],
                 u_dut.u_rf.regs[11], u_dut.u_rf.regs[12]);

        if (errors == 0) begin
            $display("==== PASS ====");
            $finish;
        end else begin
            $display("==== FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_pipe_halt_step failed");
        end
    end
endmodule
