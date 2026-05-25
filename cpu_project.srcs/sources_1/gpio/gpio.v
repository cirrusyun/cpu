`timescale 1ns/1ps
// Memory-mapped GPIO (架构 §7)
//   0x10000  SW_REG  read  : returns {16'b0, sw[15:0]}; write ignored
//   0x10004  LED_REG write : updates LED[15:0]; read returns 0
//   0x10008  SEG_REG write : updates 7-seg display value (8 hex digits); read 0
//   0x1000C  unallocated   : read 0; write ignored
//   Only word-aligned LW/SW are supported (架构 §7); sub-word access has
//   undefined behavior — accept full-word writes only.
module gpio (
    input  wire        clk,
    input  wire        rst,
    // CPU MMIO interface (selected when address in MMIO range)
    input  wire        sel,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  byte_en,
    output reg  [31:0] rdata,
    // Board IO
    input  wire [15:0] sw,
    output reg  [15:0] led,
    output wire [7:0]  seg,
    output wire [7:0]  an
);
    reg [31:0] seg_value;
    wire [3:0] off = addr[3:0];

    always @(*) begin
        case (off)
            4'h0:    rdata = {16'b0, sw};
            default: rdata = 32'h0;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led       <= 16'b0;
            seg_value <= 32'b0;
        end else if (sel && we && (byte_en == 4'b1111)) begin
            case (off)
                4'h4:    led       <= wdata[15:0];
                4'h8:    seg_value <= wdata;
                default: ;   // 0x10000 (read-only) and 0x1000C (unalloc) ignored
            endcase
        end
    end

    seg7_driver u_seg (
        .clk(clk), .rst(rst),
        .value(seg_value),
        .seg(seg), .an(an)
    );
endmodule
