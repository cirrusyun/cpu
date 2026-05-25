`timescale 1ns/1ps
// Unit test for reg_file.v — x0 hardwire, sp/gp init, cpu_step gating
module tb_regfile;
    reg         clk = 0;
    reg         rst_n = 0;
    reg         cpu_step = 1;
    reg  [4:0]  rs1_addr, rs2_addr;
    wire [31:0] rs1_data, rs2_data;
    reg         we;
    reg  [4:0]  rd_addr;
    reg  [31:0] rd_data;
    reg  [4:0]  dbg_addr;
    wire [31:0] dbg_rdata;

    reg_file dut (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .we(we), .rd_addr(rd_addr), .rd_data(rd_data),
        .dbg_addr(dbg_addr), .dbg_rdata(dbg_rdata)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    task check;
        input [255:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: got %h, expected %h", name, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // 复位
        we = 0; rd_addr = 0; rd_data = 0;
        rs1_addr = 0; rs2_addr = 0; dbg_addr = 0;
        repeat (2) @(posedge clk);
        @(negedge clk) rst_n = 1;
        #1;

        // 检查复位初值
        rs1_addr = 5'd0;  #1 check("x0 reads 0",       rs1_data, 32'b0);
        rs1_addr = 5'd2;  #1 check("x2 (sp) init",    rs1_data, 32'h0000_7FFC);
        rs1_addr = 5'd3;  #1 check("x3 (gp) init",    rs1_data, 32'h0000_4000);
        rs1_addr = 5'd5;  #1 check("x5 init 0",       rs1_data, 32'b0);
        rs1_addr = 5'd31; #1 check("x31 init 0",      rs1_data, 32'b0);

        // 写入 + 读回
        rd_addr = 5'd10; rd_data = 32'hDEAD_BEEF; we = 1;
        @(posedge clk); #1
        we = 0;
        rs1_addr = 5'd10; #1 check("x10 write/read", rs1_data, 32'hDEAD_BEEF);

        // x0 写抑制
        rd_addr = 5'd0; rd_data = 32'hCAFE_BABE; we = 1;
        @(posedge clk); #1
        we = 0;
        rs1_addr = 5'd0; #1 check("x0 write suppressed", rs1_data, 32'b0);

        // cpu_step gate：halted 时不写入
        rd_addr = 5'd11; rd_data = 32'h1234_5678; we = 1; cpu_step = 0;
        @(posedge clk); #1
        we = 0; cpu_step = 1;
        rs1_addr = 5'd11; #1 check("halted write suppressed", rs1_data, 32'b0);

        // resume 后写入恢复
        rd_addr = 5'd11; rd_data = 32'h1234_5678; we = 1;
        @(posedge clk); #1
        we = 0;
        rs1_addr = 5'd11; #1 check("resumed write works", rs1_data, 32'h1234_5678);

        // 同周期 rs1/rs2 异步读
        rs1_addr = 5'd2; rs2_addr = 5'd3; #1
        check("rs1=sp",  rs1_data, 32'h0000_7FFC);
        check("rs2=gp",  rs2_data, 32'h0000_4000);

        // Debug 端口
        dbg_addr = 5'd0;  #1 check("dbg x0", dbg_rdata, 32'b0);
        dbg_addr = 5'd2;  #1 check("dbg sp", dbg_rdata, 32'h0000_7FFC);
        dbg_addr = 5'd10; #1 check("dbg x10", dbg_rdata, 32'hDEAD_BEEF);

        // 软复位（rst_n 拉低再起，模拟 cpu_dbg_reset 走 rst_n_cpu）
        rst_n = 0;
        @(posedge clk); #1
        rst_n = 1; #1
        rs1_addr = 5'd10; #1 check("x10 after reset", rs1_data, 32'b0);
        rs1_addr = 5'd2;  #1 check("sp after reset",  rs1_data, 32'h0000_7FFC);

        $display("");
        if (errors == 0) begin
            $display("==== tb_regfile PASS ====");
            $finish;
        end else begin
            $display("==== tb_regfile FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_regfile failed");
        end
    end
endmodule
