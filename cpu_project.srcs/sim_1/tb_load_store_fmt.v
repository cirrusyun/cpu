`timescale 1ns/1ps
// Unit test for load_store_fmt.v
//   Store: SB×4 offsets, SH×2 offsets, SW
//   Load:  LB×4 offsets (signed/unsigned), LH×2 offsets (signed/unsigned), LW
module tb_load_store_fmt;
    reg  [31:0] addr;
    reg  [1:0]  mem_size;     // 00=B, 01=H, 10=W
    reg         mem_signed;
    reg  [31:0] mem_rdata;
    reg  [31:0] rs2_data;
    wire [31:0] load_data;
    wire [31:0] mem_wdata;
    wire [3:0]  byte_en;

    load_store_fmt dut (
        .addr(addr), .mem_size(mem_size), .mem_signed(mem_signed),
        .mem_rdata(mem_rdata), .rs2_data(rs2_data),
        .load_data(load_data), .mem_wdata(mem_wdata), .byte_en(byte_en)
    );

    integer errors = 0;
    task chk_st;
        input [255:0] name;
        input [31:0]  exp_wdata;
        input [3:0]   exp_be;
        begin
            if (mem_wdata !== exp_wdata || byte_en !== exp_be) begin
                $display("FAIL %0s: got wdata=%h be=%b, expected wdata=%h be=%b",
                         name, mem_wdata, byte_en, exp_wdata, exp_be);
                errors = errors + 1;
            end
        end
    endtask
    task chk_ld;
        input [255:0] name;
        input [31:0]  expected;
        begin
            if (load_data !== expected) begin
                $display("FAIL %0s: got %h, expected %h", name, load_data, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        addr = 32'b0; mem_size = 2'b00; mem_signed = 1'b0;
        mem_rdata = 32'b0; rs2_data = 32'b0;

        // ============ Store ============
        rs2_data = 32'h1234_5678;

        // SW (任意对齐应当 addr[1:0]=00)
        mem_size = 2'b10; addr = 32'h0000_0000; #1
        chk_st("SW", 32'h1234_5678, 4'b1111);

        // SH addr[1:0]=00 → 写低半字
        mem_size = 2'b01; addr = 32'h0000_0000; #1
        chk_st("SH offset 0", {16'b0, 16'h5678}, 4'b0011);

        // SH addr[1:0]=10 → 写高半字
        mem_size = 2'b01; addr = 32'h0000_0002; #1
        chk_st("SH offset 2", {16'h5678, 16'b0}, 4'b1100);

        // SB 四个 offset
        mem_size = 2'b00;
        addr = 32'h0000_0000; #1 chk_st("SB off 0", {24'b0,        8'h78},        4'b0001);
        addr = 32'h0000_0001; #1 chk_st("SB off 1", {16'b0, 8'h78,  8'b0},        4'b0010);
        addr = 32'h0000_0002; #1 chk_st("SB off 2", { 8'b0, 8'h78, 16'b0},        4'b0100);
        addr = 32'h0000_0003; #1 chk_st("SB off 3", {       8'h78, 24'b0},        4'b1000);

        // ============ Load ============
        mem_rdata = 32'h89AB_CDEF;
        // mem_rdata[7:0]   = 0xEF
        // mem_rdata[15:8]  = 0xCD
        // mem_rdata[23:16] = 0xAB
        // mem_rdata[31:24] = 0x89

        // LW
        mem_size = 2'b10; mem_signed = 1; addr = 32'h0000_0000; #1
        chk_ld("LW", 32'h89AB_CDEF);

        // LH signed (LH)
        mem_size = 2'b01; mem_signed = 1;
        addr = 32'h0000_0000; #1 chk_ld("LH off 0 = 0xCDEF (sign)", 32'hFFFF_CDEF);
        addr = 32'h0000_0002; #1 chk_ld("LH off 2 = 0x89AB (sign)", 32'hFFFF_89AB);

        // LH unsigned (LHU)
        mem_signed = 0;
        addr = 32'h0000_0000; #1 chk_ld("LHU off 0",  32'h0000_CDEF);
        addr = 32'h0000_0002; #1 chk_ld("LHU off 2",  32'h0000_89AB);

        // LB signed
        mem_size = 2'b00; mem_signed = 1;
        addr = 32'h0000_0000; #1 chk_ld("LB off 0 = 0xEF (sign)", 32'hFFFF_FFEF);
        addr = 32'h0000_0001; #1 chk_ld("LB off 1 = 0xCD (sign)", 32'hFFFF_FFCD);
        addr = 32'h0000_0002; #1 chk_ld("LB off 2 = 0xAB (sign)", 32'hFFFF_FFAB);
        addr = 32'h0000_0003; #1 chk_ld("LB off 3 = 0x89 (sign)", 32'hFFFF_FF89);

        // LB unsigned (LBU)
        mem_signed = 0;
        addr = 32'h0000_0000; #1 chk_ld("LBU off 0", 32'h0000_00EF);
        addr = 32'h0000_0003; #1 chk_ld("LBU off 3", 32'h0000_0089);

        // LB 正数（high bit 0）符号扩展应为 0
        mem_rdata = 32'h0000_007F;
        mem_size = 2'b00; mem_signed = 1; addr = 32'h0000_0000; #1
        chk_ld("LB 0x7F (sign, no flip)", 32'h0000_007F);

        // LH 0x7FFF 应当符号扩展为 0x00007FFF
        mem_rdata = 32'h0000_7FFF;
        mem_size = 2'b01; mem_signed = 1; addr = 32'h0000_0000; #1
        chk_ld("LH 0x7FFF (sign, no flip)", 32'h0000_7FFF);

        $display("");
        if (errors == 0) begin
            $display("==== tb_load_store_fmt PASS ====");
            $finish;
        end else begin
            $display("==== tb_load_store_fmt FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_load_store_fmt failed");
        end
    end
endmodule
