`timescale 1ns/1ps
// End-to-end regression for retained MUL plus unsupported ALU encodings.
// MUL is supported; other unsupported R-type funct7 values, invalid
// shift-immediate imm[11:5], and reserved branch funct3 values stay NOPs.
module tb_cpu_illegal_decode;
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
    reg checked_invalid_branch = 1'b0;
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

    always @(posedge clk) begin
        if (rst_n && !checked_invalid_branch && inst_out === 32'h0052A463) begin
            checked_invalid_branch <= 1'b1;
            if (u_cpu.branch !== 1'b0 || branch_redirect !== 1'b0) begin
                $display("FAIL reserved branch control: branch=%b redirect=%b, expected 0/0",
                         u_cpu.branch, branch_redirect);
                errors = errors + 1;
            end
        end
    end

    initial begin
        #1;   // 让 fake_ifetch/fake_dmem 的 time-0 NOP fill 先跑完
        u_if.mem[0] = 32'h00400293;   // ADDI x5, x0, 4
        u_if.mem[1] = 32'h02528333;   // MUL x6, x5, x5 -> 16 (retained M-extension instruction)
        u_if.mem[2] = 32'h405293B3;   // R-type SLL with funct7=0100000: invalid, must NOP
        u_if.mem[3] = 32'h40129413;   // SLLI with imm[11:5]=0100000: invalid, must NOP
        u_if.mem[4] = 32'hFE12D493;   // SRLI/SRAI with imm[11:5]=1111111: invalid, must NOP
        u_if.mem[5] = 32'h0052A463;   // Branch opcode with reserved funct3=010: invalid, must NOP
        u_if.mem[6] = 32'h04D00613;   // ADDI x12, x0, 77 (must not be skipped)
        u_if.mem[7] = 32'h40028533;   // valid SUB x10, x5, x0 -> 4
        u_if.mem[8] = 32'h4012D593;   // valid SRAI x11, x5, 1 -> 2
        u_if.mem[9] = 32'h0000006F;   // halt loop

        #160 rst_n = 1;
        #(40 * 20);

        check("setup x5",                         5'd5,  32'd4);
        check("retained MUL works",               5'd6,  32'd16);
        check("invalid R-type funct7 stays NOP",  5'd7,  32'd0);
        check("invalid SLLI imm[11:5] stays NOP", 5'd8,  32'd0);
        check("invalid SRAI imm[11:5] stays NOP", 5'd9,  32'd0);
        check("reserved branch funct3 falls through", 5'd12, 32'd77);
        if (!checked_invalid_branch) begin
            $display("FAIL reserved branch control: test instruction was not observed");
            errors = errors + 1;
        end
        check("valid SUB still works",            5'd10, 32'd4);
        check("valid SRAI still works",           5'd11, 32'd2);

        if (errors == 0) begin
            $display("==== tb_cpu_illegal_decode PASS ====");
            $finish;
        end else begin
            $display("==== tb_cpu_illegal_decode FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_cpu_illegal_decode failed");
        end
    end
endmodule
