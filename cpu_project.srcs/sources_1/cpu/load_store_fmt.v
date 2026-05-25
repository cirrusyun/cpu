`timescale 1ns/1ps
// Load/Store byte formatter
//   DMem provides a raw 32-bit word; this block selects the right byte/half
//   for loads (with sign/zero extension) and shifts store data with
//   byte_enable for sub-word stores.
//   Per 架构 §6: HALF requires addr[0]=0, WORD requires addr[1:0]=00;
//   misaligned access is undefined and not handled.
module load_store_fmt (
    input  wire [31:0] addr,
    input  wire [1:0]  mem_size,    // 00=B 01=H 10=W
    input  wire        mem_signed,  // 1=sign-extend (LB/LH), 0=zero-extend
    input  wire [31:0] mem_rdata,   // raw 32-bit word from DMem
    input  wire [31:0] rs2_data,    // store source data (direct from RegFile)
    output reg  [31:0] load_data,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  byte_en
);
    wire [1:0] off = addr[1:0];

    // ---------- Load: select & extend ----------
    reg [7:0]  byte_sel;
    reg [15:0] half_sel;

    always @(*) begin
        case (off)
            2'b00:   byte_sel = mem_rdata[7:0];
            2'b01:   byte_sel = mem_rdata[15:8];
            2'b10:   byte_sel = mem_rdata[23:16];
            2'b11:   byte_sel = mem_rdata[31:24];
            default: byte_sel = 8'b0;
        endcase
        half_sel = off[1] ? mem_rdata[31:16] : mem_rdata[15:0];

        case (mem_size)
            2'b00: load_data = mem_signed ? {{24{byte_sel[7]}},  byte_sel}
                                          : {24'b0,             byte_sel};
            2'b01: load_data = mem_signed ? {{16{half_sel[15]}}, half_sel}
                                          : {16'b0,             half_sel};
            2'b10: load_data = mem_rdata;
            default: load_data = mem_rdata;
        endcase
    end

    // ---------- Store: shift + byte_enable ----------
    always @(*) begin
        case (mem_size)
            2'b00: begin   // SB
                case (off)
                    2'b00: begin mem_wdata = {24'b0, rs2_data[7:0]};        byte_en = 4'b0001; end
                    2'b01: begin mem_wdata = {16'b0, rs2_data[7:0],  8'b0}; byte_en = 4'b0010; end
                    2'b10: begin mem_wdata = { 8'b0, rs2_data[7:0], 16'b0}; byte_en = 4'b0100; end
                    2'b11: begin mem_wdata = {       rs2_data[7:0], 24'b0}; byte_en = 4'b1000; end
                    default: begin mem_wdata = 32'b0; byte_en = 4'b0000; end
                endcase
            end
            2'b01: begin   // SH (addr[0] must be 0)
                if (!off[1]) begin
                    mem_wdata = {16'b0, rs2_data[15:0]};
                    byte_en   = 4'b0011;
                end else begin
                    mem_wdata = {rs2_data[15:0], 16'b0};
                    byte_en   = 4'b1100;
                end
            end
            2'b10: begin   // SW
                mem_wdata = rs2_data;
                byte_en   = 4'b1111;
            end
            default: begin
                mem_wdata = rs2_data;
                byte_en   = 4'b1111;
            end
        endcase
    end
endmodule
