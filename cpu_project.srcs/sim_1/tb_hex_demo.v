`timescale 1ns/1ps
// 演示用 fake_ifetch 的 INIT_FILE 参数从 .hex 文件加载程序。
//
// 用法：
//   将程序汇编成 32-bit hex（每行一条指令，$readmemh 格式），保存为 .hex 文件，
//   通过 fake_ifetch 的 INIT_FILE 参数加载。
//
// 这个示例加载 case0_and.hex，验证 AND 运算结果。
// 当 C 同学的汇编工具链跑通后，inst.txt 可以直接喂给这个 tb 验证。
module tb_hex_demo;
    reg clk = 0;
    reg rst_n = 0;
    reg cpu_step = 1;

    wire [31:0] next_pc, pc_out, inst_out, pc_fetch;
    wire        pc_we, branch_redirect;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_be;
    wire        mem_we;

    always #20 clk = ~clk;

    fake_ifetch #(
        .INIT_FILE("sim_1/hex_demo/case0_and.hex"),
        .INIT_FILE_FALLBACK("cpu_project/cpu_project.srcs/sim_1/hex_demo/case0_and.hex")
    ) u_if (
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
        #160 rst_n = 1;
        #(40 * 15);   // 跑 15 拍

        $display("");
        $display("==== hex demo result ====");
        $display("Loaded program from: hex_demo/case0_and.hex");
        $display("x10 = 0x%h (expected 0xAB = 171)", u_cpu.u_rf.regs[10]);
        $display("x11 = 0x%h (expected 0xCD = 205)", u_cpu.u_rf.regs[11]);
        $display("x12 = 0x%h (expected 0x89 = 137, = 0xAB & 0xCD)", u_cpu.u_rf.regs[12]);

        if (u_if.mem[0] !== 32'h0AB00513) begin
            $display("FAIL: hex file was not loaded as expected, mem[0]=%h", u_if.mem[0]);
            errors = errors + 1;
        end
        if (u_cpu.u_rf.regs[10] !== 32'h0000_00AB) begin
            $display("FAIL: x10=%h, expected 000000ab", u_cpu.u_rf.regs[10]);
            errors = errors + 1;
        end
        if (u_cpu.u_rf.regs[11] !== 32'h0000_00CD) begin
            $display("FAIL: x11=%h, expected 000000cd", u_cpu.u_rf.regs[11]);
            errors = errors + 1;
        end
        if (u_cpu.u_rf.regs[12] !== 32'h0000_0089) begin
            $display("FAIL: x12=%h, expected 00000089", u_cpu.u_rf.regs[12]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("==== tb_hex_demo PASS ====");
            $finish;
        end else begin
            $display("==== tb_hex_demo FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_hex_demo failed");
        end
    end
endmodule
