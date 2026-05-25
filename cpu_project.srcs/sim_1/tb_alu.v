`timescale 1ns/1ps
// Unit test for alu.v — cover all 10 alu_op with edge values
module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  alu_op;
    wire [31:0] result;
    wire        zero;

    alu dut (.a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero));

    integer errors = 0;
    task check;
        input [255:0] name;
        input [31:0]  expected;
        begin
            if (result !== expected) begin
                $display("FAIL %0s: a=%h b=%h op=%h → got %h, expected %h",
                         name, a, b, alu_op, result, expected);
                errors = errors + 1;
            end
            if (zero !== (expected == 32'b0)) begin
                $display("FAIL %0s zero flag: result=%h zero=%b, expected %b",
                         name, result, zero, (expected == 32'b0));
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // ADD
        alu_op = 4'b0000;
        a = 32'd5;  b = 32'd3;        #1 check("ADD 5+3", 32'd8);
        a = 32'hFFFFFFFF; b = 32'd1;  #1 check("ADD wrap", 32'd0);
        a = 32'h7FFFFFFF; b = 32'd1;  #1 check("ADD signed overflow", 32'h80000000);

        // SUB
        alu_op = 4'b0001;
        a = 32'd10; b = 32'd3;        #1 check("SUB 10-3", 32'd7);
        a = 32'd0;  b = 32'd1;        #1 check("SUB 0-1 underflow", 32'hFFFFFFFF);
        a = 32'h80000000; b = 32'd1;  #1 check("SUB signed underflow", 32'h7FFFFFFF);

        // AND
        alu_op = 4'b0010;
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; #1 check("AND mask", 32'h0F000F00);

        // OR
        alu_op = 4'b0011;
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; #1 check("OR mask", 32'hFF0FFF0F);

        // XOR
        alu_op = 4'b0100;
        a = 32'hAAAAAAAA; b = 32'h55555555; #1 check("XOR all-bits", 32'hFFFFFFFF);
        a = 32'hAAAAAAAA; b = 32'hAAAAAAAA; #1 check("XOR self=0",   32'h0);

        // SLL (b[4:0] is shamt)
        alu_op = 4'b0101;
        a = 32'h00000001; b = 32'd0;  #1 check("SLL shamt=0",  32'h00000001);
        a = 32'h00000001; b = 32'd31; #1 check("SLL shamt=31", 32'h80000000);
        a = 32'h00000001; b = 32'd32; #1 check("SLL shamt=32 (uses b[4:0]=0)", 32'h00000001);

        // SRL (logical right)
        alu_op = 4'b0110;
        a = 32'h80000000; b = 32'd31; #1 check("SRL msb→lsb",  32'h00000001);
        a = 32'hFFFFFFFF; b = 32'd16; #1 check("SRL fill 0",   32'h0000FFFF);

        // SRA (arithmetic right)
        alu_op = 4'b0111;
        a = 32'h80000000; b = 32'd31; #1 check("SRA neg keep sign", 32'hFFFFFFFF);
        a = 32'h40000000; b = 32'd1;  #1 check("SRA pos",           32'h20000000);
        a = 32'hFFFFFFF0; b = 32'd4;  #1 check("SRA -16 >> 4 = -1", 32'hFFFFFFFF);

        // SLT (signed less than)
        alu_op = 4'b1000;
        a = 32'h80000000; b = 32'd1;  #1 check("SLT -big < 1 = 1",          32'd1);
        a = 32'd1; b = 32'h80000000;  #1 check("SLT 1 < -big = 0",          32'd0);
        a = 32'h7FFFFFFF; b = 32'h80000000; #1 check("SLT max+ < min- = 0", 32'd0);

        // SLTU (unsigned less than)
        alu_op = 4'b1001;
        a = 32'h80000000; b = 32'd1;  #1 check("SLTU big > 1 = 0",        32'd0);
        a = 32'd1; b = 32'h80000000;  #1 check("SLTU 1 < big = 1",        32'd1);
        a = 32'hFFFFFFFF; b = 32'h00000000; #1 check("SLTU max > 0 = 0", 32'd0);

        // zero flag check
        alu_op = 4'b0001;
        a = 32'd42; b = 32'd42; #1
        check("zero flag SUB 42-42", 32'd0);

        $display("");
        if (errors == 0) begin
            $display("==== tb_alu PASS ====");
            $finish;
        end else begin
            $display("==== tb_alu FAIL (%0d errors) ====", errors);
            $fatal(1, "tb_alu failed");
        end
    end
endmodule
