`timescale 1ns/1ps
// Main control unit
//   FENCE / EBREAK and unsupported SYSTEM encodings fall through to default
//   NOP behavior. ECALL is decoded as the exact 32-bit architectural encoding
//   (funct12=0, funct3=0, rs1=x0, rd=x0) for the trap bonus path.
module ctrl (
    input  wire [6:0] opcode,
    input  wire [4:0] rd_addr,
    input  wire [2:0] funct3,
    input  wire [4:0] rs1_addr,
    input  wire [6:0] funct7,
    input  wire [11:0] funct12,      // SYSTEM imm12: ECALL=0, EBREAK=1
    output reg  [1:0] alu_src_a,    // 00=rs1  01=PC   10=ZERO
    output reg        alu_src_b,    //  0=rs2   1=imm
    output reg  [1:0] wb_src,       // 00=ALU  01=MEM  10=PC+4
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg        ecall_trap,    // bonus: ECALL → 跳转固定 handler；EBREAK 仍为 NOP
    output reg  [2:0] imm_type,
    output reg  [1:0] mem_size,     // 00=B 01=H 10=W
    output reg        mem_signed
);
    localparam [6:0] FUNCT7_STD = 7'b0000000;
    localparam [6:0] FUNCT7_ALT = 7'b0100000;   // SUB/SRA/SRAI in RV32I

    always @(*) begin
        // defaults (NOP)
        alu_src_a  = 2'b00;
        alu_src_b  = 1'b0;
        wb_src     = 2'b00;
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        jalr       = 1'b0;
        ecall_trap = 1'b0;
        imm_type   = 3'b000;
        mem_size   = funct3[1:0];
        mem_signed = ~funct3[2];

        case (opcode)
            7'b0110011: begin   // R-Type
                case (funct3)
                    3'b000, 3'b101: begin
                        // ADD/SUB and SRL/SRA are the only R-type pairs that use funct7[5].
                        if (funct7 == FUNCT7_STD || funct7 == FUNCT7_ALT) begin
                            alu_src_a = 2'b00; alu_src_b = 1'b0;
                            wb_src    = 2'b00; reg_write = 1'b1;
                        end
                    end
                    3'b001, 3'b010, 3'b011, 3'b100, 3'b110, 3'b111: begin
                        // Other RV32I R-type ops require funct7=0000000.
                        if (funct7 == FUNCT7_STD) begin
                            alu_src_a = 2'b00; alu_src_b = 1'b0;
                            wb_src    = 2'b00; reg_write = 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
            7'b0010011: begin   // I-ALU
                case (funct3)
                    3'b001: begin
                        // SLLI requires imm[11:5]=0000000.
                        if (funct7 == FUNCT7_STD) begin
                            alu_src_a = 2'b00; alu_src_b = 1'b1;
                            wb_src    = 2'b00; reg_write = 1'b1;
                            imm_type  = 3'b000;
                        end
                    end
                    3'b101: begin
                        // SRLI/SRAI are selected by imm[11:5]=0000000/0100000.
                        if (funct7 == FUNCT7_STD || funct7 == FUNCT7_ALT) begin
                            alu_src_a = 2'b00; alu_src_b = 1'b1;
                            wb_src    = 2'b00; reg_write = 1'b1;
                            imm_type  = 3'b000;
                        end
                    end
                    default: begin
                        alu_src_a = 2'b00; alu_src_b = 1'b1;
                        wb_src    = 2'b00; reg_write = 1'b1;
                        imm_type  = 3'b000;
                    end
                endcase
            end
            7'b0000011: begin   // Load
                // Valid funct3: 000=LB, 001=LH, 010=LW, 100=LBU, 101=LHU.
                // Reserved (011=LD/RV64, 110=LWU/RV64, 111) -> silent NOP
                // so an illegal funct3 won't sneak through as a word access.
                case (funct3)
                    3'b000, 3'b001, 3'b010, 3'b100, 3'b101: begin
                        alu_src_a = 2'b00; alu_src_b = 1'b1;
                        wb_src    = 2'b01; reg_write = 1'b1;
                        mem_read  = 1'b1;  imm_type  = 3'b000;
                    end
                    default: ;   // illegal funct3: NOP (defaults already 0)
                endcase
            end
            7'b0100011: begin   // Store
                // Valid funct3: 000=SB, 001=SH, 010=SW. Others -> NOP.
                case (funct3)
                    3'b000, 3'b001, 3'b010: begin
                        alu_src_a = 2'b00; alu_src_b = 1'b1;
                        mem_write = 1'b1;  imm_type  = 3'b001;
                    end
                    default: ;
                endcase
            end
            7'b1100011: begin   // Branch
                // Valid funct3: BEQ/BNE/BLT/BGE/BLTU/BGEU. Reserved 010/011 -> NOP.
                case (funct3)
                    3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111: begin
                        alu_src_a = 2'b00; alu_src_b = 1'b0;
                        branch    = 1'b1;  imm_type  = 3'b010;
                    end
                    default: ;
                endcase
            end
            7'b1101111: begin   // JAL
                alu_src_a = 2'b01; alu_src_b = 1'b1;     // (ALU result unused; PC mux uses pc+imm)
                wb_src    = 2'b10; reg_write = 1'b1;
                jump      = 1'b1;  imm_type  = 3'b100;
            end
            7'b1100111: begin   // JALR
                // Valid JALR requires funct3=000. Reserved encodings -> NOP.
                if (funct3 == 3'b000) begin
                    alu_src_a = 2'b00; alu_src_b = 1'b1;
                    wb_src    = 2'b10; reg_write = 1'b1;
                    jump      = 1'b1;  jalr      = 1'b1;
                    imm_type  = 3'b000;
                end
            end
            7'b0010111: begin   // AUIPC
                alu_src_a = 2'b01; alu_src_b = 1'b1;
                wb_src    = 2'b00; reg_write = 1'b1;
                imm_type  = 3'b011;
            end
            7'b0110111: begin   // LUI
                alu_src_a = 2'b10; alu_src_b = 1'b1;
                wb_src    = 2'b00; reg_write = 1'b1;
                imm_type  = 3'b011;
            end
            7'b1110011: begin   // SYSTEM
                // ECALL  (funct12=12'h000) -> bonus trap to fixed handler.
                // EBREAK (funct12=12'h001) and unsupported SYSTEM encodings -> NOP.
                if (funct3 == 3'b000 && funct12 == 12'h000 &&
                    rs1_addr == 5'd0 && rd_addr == 5'd0) begin
                    ecall_trap = 1'b1;
                end
                // 不写寄存器、不访存：rd 由 cpu.v 内 PC mux 直接接管
            end
            // 7'b0001111 (FENCE) : default = NOP
            default: begin /* NOP */ end
        endcase
    end
endmodule
