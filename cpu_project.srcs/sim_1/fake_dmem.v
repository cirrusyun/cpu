`timescale 1ns/1ps
// Simulation stub for B's dmem.v
//   Replicates the contract: 同周期读（仿真里直接组合读 = 真实 BRAM 反相时钟半周期内完成）。
//   字节使能写入按 mem_be 拆分。
//   mem_we 应由 A 的 cpu.v 用 cpu_step gate；桩内断言该契约，避免 halt 写入 false pass。
//   集成时直接替换为 B 的真 dmem.v，端口完全一致。
module fake_dmem #(
    parameter MEM_SIZE = 8192   // 32KB / 4 bytes
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_step,

    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_be,
    input  wire        mem_we,
    output wire [31:0] mem_rdata
);
    reg [31:0] mem [0:MEM_SIZE-1];
    wire [31:0] idx = mem_addr[31:2];

    integer k;
    initial for (k = 0; k < MEM_SIZE; k = k + 1) mem[k] = 32'b0;

    assign mem_rdata = mem[idx];   // 组合读（仿真里等效同周期）

    always @(posedge clk) begin
        if (rst_n && mem_we) begin
            if (!cpu_step) begin
                $fatal(1, "fake_dmem: mem_we asserted while cpu_step=0");
            end else begin
                if (mem_be[0]) mem[idx][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_be[1]) mem[idx][15: 8] <= mem_wdata[15: 8];
                if (mem_be[2]) mem[idx][23:16] <= mem_wdata[23:16];
                if (mem_be[3]) mem[idx][31:24] <= mem_wdata[31:24];
            end
        end
    end
endmodule
