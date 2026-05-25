`timescale 1ns/1ps
// ALU
//   alu_op encoding (4 bits):
//     0000 ADD   0001 SUB   0010 AND   0011 OR    0100 XOR
//     0101 SLL   0110 SRL   0111 SRA   1000 SLT   1001 SLTU
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result,
    output wire        zero
);
    localparam OP_ADD  = 4'b0000;
    localparam OP_SUB  = 4'b0001;
    localparam OP_AND  = 4'b0010;
    localparam OP_OR   = 4'b0011;
    localparam OP_XOR  = 4'b0100;
    localparam OP_SLL  = 4'b0101;
    localparam OP_SRL  = 4'b0110;
    localparam OP_SRA  = 4'b0111;
    localparam OP_SLT  = 4'b1000;
    localparam OP_SLTU = 4'b1001;

    wire signed [31:0] sa = a;
    wire signed [31:0] sb = b;
    wire        [4:0]  shamt = b[4:0];

    always @(*) begin
        case (alu_op)
            OP_ADD : result = a + b;
            OP_SUB : result = a - b;
            OP_AND : result = a & b;
            OP_OR  : result = a | b;
            OP_XOR : result = a ^ b;
            OP_SLL : result = a << shamt;
            OP_SRL : result = a >> shamt;
            OP_SRA : result = sa >>> shamt;
            OP_SLT : result = (sa < sb) ? 32'd1 : 32'd0;
            OP_SLTU: result = (a  < b ) ? 32'd1 : 32'd0;
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);
endmodule
