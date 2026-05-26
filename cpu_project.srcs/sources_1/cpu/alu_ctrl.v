`timescale 1ns/1ps
// ALU control unit
//   opcode/funct3/funct7 -> alu_op (matches alu.v encoding)
//   Branch path uses SLT/SLTU/SUB explicitly (not SUB+negative) to avoid
//   the signed-overflow trap noted in 架构 §3.
module alu_ctrl (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [3:0] alu_op
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
    localparam OP_MUL  = 4'b1011;
    wire funct7_5 = funct7[5];
    always @(*) begin
        case (opcode)
            7'b0110011: begin   // R-Type
                case (funct3)
                    3'b000: begin
                        case (funct7)
                            7'b0000000: alu_op = OP_ADD;
                            7'b0100000: alu_op = OP_SUB;
                            7'b0000001: alu_op = OP_MUL;
                            default:    alu_op = OP_ADD;
                        endcase
                    end
                    3'b001: alu_op = OP_SLL;
                    3'b010: alu_op = OP_SLT;
                    3'b011: alu_op = OP_SLTU;
                    3'b100: alu_op = OP_XOR;
                    3'b101: alu_op = funct7_5 ? OP_SRA : OP_SRL;
                    3'b110: alu_op = OP_OR;
                    3'b111: alu_op = OP_AND;
                    default: alu_op = OP_ADD;
                endcase
            end
            7'b0010011: begin   // I-ALU
                case (funct3)
                    3'b000: alu_op = OP_ADD;
                    3'b001: alu_op = OP_SLL;
                    3'b010: alu_op = OP_SLT;
                    3'b011: alu_op = OP_SLTU;
                    3'b100: alu_op = OP_XOR;
                    3'b101: alu_op = funct7_5 ? OP_SRA : OP_SRL;
                    3'b110: alu_op = OP_OR;
                    3'b111: alu_op = OP_AND;
                    default: alu_op = OP_ADD;
                endcase
            end
            7'b1100011: begin   // Branch
                case (funct3)
                    3'b000, 3'b001: alu_op = OP_SUB;   // BEQ / BNE
                    3'b100, 3'b101: alu_op = OP_SLT;   // BLT / BGE
                    3'b110, 3'b111: alu_op = OP_SLTU;  // BLTU / BGEU
                    default: alu_op = OP_SUB;
                endcase
            end
            // Load / Store / JALR / AUIPC / LUI / JAL: all need ADD
            // (LUI uses A=ZERO so result = 0 + imm = imm)
            default: alu_op = OP_ADD;
        endcase
    end
endmodule
