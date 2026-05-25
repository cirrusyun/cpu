`timescale 1ns/1ps
// 8-digit hex 7-segment driver for EGO1
//   EGO1 数码管为共阴极，段选 + 位选都是 active-HIGH (用户手册 §6.4)。
//   value: 32 bits = 8 hex digits, value[3:0] -> the digit selected by an[0].
//   Bit ordering of seg: {DP, G, F, E, D, C, B, A} (LSB=A).
//   In XDC, broadcast seg[7:0] to both DN0 and DN1 segment pins:
//     seg[0] -> CA0(B4) and CA1(D4)
//     seg[1] -> CB0(A4) and CB1(E3)
//     ...
//     seg[7] -> DP0(D5) and DP1(H2)
//   And map an[i] to a single BIT line (active-HIGH).
//   Free-running scan: not gated by CPU clk_en — display keeps refreshing
//   even when CPU is halted, otherwise the digit currently lit would burn in.
module seg7_driver (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] value,
    output reg  [7:0]  seg,
    output reg  [7:0]  an
);
    // 100 MHz / 2^14 ~= 6.1 kHz per-digit refresh; 8 digits => ~760 Hz full
    reg [16:0] scan_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) scan_cnt <= 17'b0;
        else     scan_cnt <= scan_cnt + 17'd1;
    end
    wire [2:0] digit_sel = scan_cnt[16:14];

    reg [3:0] nibble;
    always @(*) begin
        case (digit_sel)
            3'd0: nibble = value[ 3: 0];
            3'd1: nibble = value[ 7: 4];
            3'd2: nibble = value[11: 8];
            3'd3: nibble = value[15:12];
            3'd4: nibble = value[19:16];
            3'd5: nibble = value[23:20];
            3'd6: nibble = value[27:24];
            3'd7: nibble = value[31:28];
            default: nibble = 4'h0;
        endcase
    end

    // Common-cathode hex font, active HIGH segments, DP off
    always @(*) begin
        case (nibble)
            4'h0: seg = 8'b0011_1111;
            4'h1: seg = 8'b0000_0110;
            4'h2: seg = 8'b0101_1011;
            4'h3: seg = 8'b0100_1111;
            4'h4: seg = 8'b0110_0110;
            4'h5: seg = 8'b0110_1101;
            4'h6: seg = 8'b0111_1101;
            4'h7: seg = 8'b0000_0111;
            4'h8: seg = 8'b0111_1111;
            4'h9: seg = 8'b0110_1111;
            4'ha: seg = 8'b0111_0111;
            4'hb: seg = 8'b0111_1100;
            4'hc: seg = 8'b0011_1001;
            4'hd: seg = 8'b0101_1110;
            4'he: seg = 8'b0111_1001;
            4'hf: seg = 8'b0111_0001;
            default: seg = 8'b0000_0000;
        endcase
    end

    always @(*) begin
        an = 8'b0000_0001 << digit_sel;
    end
endmodule
