`timescale 1ns/1ps
// 64-bit cycle and retired-instruction counters, gated by cpu_step.
//   inst_retired_inc: assert when WB stage holds a non-bubble instruction
//   that committed an architectural side effect (reg write or memory write).
module cycle_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_step,
    input  wire        inst_retired_inc,
    output reg  [63:0] cycle_count,
    output reg  [63:0] inst_retired
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count  <= 64'b0;
            inst_retired <= 64'b0;
        end else if (cpu_step) begin
            cycle_count <= cycle_count + 64'd1;
            if (inst_retired_inc) inst_retired <= inst_retired + 64'd1;
        end
    end
endmodule
