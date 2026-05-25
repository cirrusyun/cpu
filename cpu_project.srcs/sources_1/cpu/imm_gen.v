`timescale 1ns/1ps
// Immediate generator: 5 immediate types
//   imm_type encoding:
//     000 = I-type (loads, I-ALU, JALR)
//     001 = S-type (stores)
//     010 = B-type (branches)
//     011 = U-type (LUI, AUIPC)  -- imm already << 12
//     100 = J-type (JAL)
module imm_gen (
    input  wire [31:0] inst,
    input  wire [2:0]  imm_type,
    output reg  [31:0] imm
);
    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'b0};
    wire [31:0] imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

    always @(*) begin
        case (imm_type)
            3'b000:  imm = imm_i;
            3'b001:  imm = imm_s;
            3'b010:  imm = imm_b;
            3'b011:  imm = imm_u;
            3'b100:  imm = imm_j;
            default: imm = 32'b0;
        endcase
    end
endmodule
