`timescale 1ns/1ps
// Unit test for imm_gen.v — all 5 immediate types, sign-extension boundaries
//
// imm_type 编码（与 ctrl.v 一致）：
//   000=I-type, 001=S-type, 010=B-type, 011=U-type, 100=J-type
module tb_imm_gen;
    reg  [31:0] inst;
    reg  [2:0]  imm_type;
    wire [31:0] imm;

    imm_gen dut (.inst(inst), .imm_type(imm_type), .imm(imm));

    integer errors = 0;
    task check;
        input [255:0] name;
        input [31:0]  expected;
        begin
            if (imm !== expected) begin
                $display("FAIL %0s: inst=%h type=%b → got %h, expected %h",
                         name, inst, imm_type, imm, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // ============ I-type (000) ============
        imm_type = 3'b000;

        // ADDI x1, x0, 5   → imm = 5
        inst = 32'h00500093; #1 check("I +5",   32'h00000005);

        // ADDI x1, x0, -1  → imm = 0xFFFFFFFF (符号扩展)
        inst = 32'hFFF00093; #1 check("I -1",   32'hFFFFFFFF);

        // ADDI x1, x0, 0x7FF (max+)
        inst = 32'h7FF00093; #1 check("I max+ 2047", 32'h000007FF);

        // ADDI x1, x0, 0x800 → -2048 (符号位)
        inst = 32'h80000093; #1 check("I min- -2048", 32'hFFFFF800);

        // ============ S-type (001) ============
        imm_type = 3'b001;

        // SW x2, 4(x0)  inst[31:25]=0, inst[11:7]=00100, imm=4
        inst = 32'h00202223; #1 check("S +4",   32'h00000004);

        // SW with imm=-1: imm[11:5]=7'b1111111, imm[4:0]=5'b11111
        // 把 imm=-1 拼回去: inst[31:25]=1111111, inst[11:7]=11111
        inst = 32'hFE201FA3; #1 check("S -1",   32'hFFFFFFFF);

        // S max+ = 0x7FF
        inst = 32'h7E201FA3; #1 check("S max+", 32'h000007FF);

        // S min- = -2048
        inst = 32'h80202023; #1 check("S min- -2048", 32'hFFFFF800);

        // ============ B-type (010) ============
        imm_type = 3'b010;

        // BEQ +8: imm[12|10:5|4:1|11] = 0|000000|0100|0 → inst[31|7|30:25|11:8] = 0|0|000000|0100
        // funct3=000, opcode=1100011
        inst = 32'h00000463; #1 check("B +8",   32'h00000008);

        // BEQ -4: imm = 0xFFFFFFFC
        // imm[12]=1, imm[11]=1, imm[10:5]=111111, imm[4:1]=1110 → bit0=0
        // inst[31]=1, inst[7]=1, inst[30:25]=111111, inst[11:8]=1110
        inst = 32'hFE000EE3; #1 check("B -4",   32'hFFFFFFFC);

        // BEQ +4094: largest positive B immediate
        inst = 32'h7E000FE3; #1 check("B max+ +4094", 32'h00000FFE);

        // BEQ -4096: smallest negative B immediate
        inst = 32'h80000063; #1 check("B min- -4096", 32'hFFFFF000);

        // ============ U-type (011) ============
        imm_type = 3'b011;

        // LUI x1, 0x12345  → imm = 0x12345000 (already shifted left 12)
        inst = 32'h123450B7; #1 check("U 0x12345", 32'h12345000);

        // LUI x1, 0xFFFFF (即 0xFFFFF000)
        inst = 32'hFFFFF0B7; #1 check("U 0xFFFFF", 32'hFFFFF000);

        // LUI x1, 0  → 0
        inst = 32'h000000B7; #1 check("U 0",       32'h00000000);

        // ============ J-type (100) ============
        imm_type = 3'b100;

        // JAL x1, +8: imm[20|10:1|11|19:12] = 0|0000000100|0|00000000
        // inst[31|19:12|20|30:21] = 0|00000000|0|0000000100
        inst = 32'h008000EF; #1 check("J +8",   32'h00000008);

        // JAL x1, -4: imm=0xFFFFFFFC
        // imm[20]=1, imm[11]=1, imm[10:1]=1111111110, imm[19:12]=11111111
        inst = 32'hFFDFF0EF; #1 check("J -4",   32'hFFFFFFFC);

        // JAL x1, max+ (+1MB-2 = 0xFFFFE)
        inst = 32'h7FFFF0EF; #1 check("J max+", 32'h000FFFFE);

        // JAL x1, min- (-1MB)
        inst = 32'h800000EF; #1 check("J min- -1048576", 32'hFFF00000);

        imm_type = 3'b111;
        inst = 32'hFFFFFFFF; #1 check("invalid imm_type defaults 0", 32'h00000000);

        $display("");
        if (errors == 0) begin
            $display("==== tb_imm_gen PASS ====");
            $finish;
        end else begin
            $display("==== tb_imm_gen FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_imm_gen failed");
        end
    end
endmodule
