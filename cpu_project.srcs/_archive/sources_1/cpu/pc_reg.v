`timescale 1ns/1ps
// Program counter register
//   Async reset, clock-enable updated. Pattern is identical for all CPU
//   state registers (架构 §9) so pipeline halt/step reuses the same
//   clock-enable mechanism without rewriting.
module pc_reg (
    input  wire        clk,
    input  wire        rst,        // async, active high (rst_cpu)
    input  wire        clk_en,     // 0 when CPU halted
    input  wire [31:0] pc_next,
    output reg  [31:0] pc
);
    always @(posedge clk or posedge rst) begin
        if (rst)         pc <= 32'h0000_0000;
        else if (clk_en) pc <= pc_next;
    end
endmodule
