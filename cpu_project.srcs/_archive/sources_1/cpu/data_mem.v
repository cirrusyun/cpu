`timescale 1ns/1ps
// Data memory: 32KB (8192 x 32-bit words), behavioral LUTRAM.
//   Async read for both CPU and debug. Sync byte-enabled write for CPU,
//   sync full-word write for debug.
//   No reset on the memory array — reset must not erase operands loaded
//   by `wd` over the UART debug bus (架构 §9).
//   Address selection (DMem range vs MMIO) is done in TopDebug; this
//   module is selected only when the address falls inside DMem.
module data_mem #(
    parameter         WORDS     = 8192,
    parameter         ADDR_W    = 13,        // log2(WORDS)
    parameter         INIT_FILE = ""
) (
    input  wire        clk,
    // CPU port
    input  wire        cpu_we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  byte_en,
    output wire [31:0] rdata,
    // Debug port (full word, 4-byte aligned addr)
    input  wire        dbg_we,
    input  wire [31:0] dbg_addr,
    input  wire [31:0] dbg_wdata,
    output wire [31:0] dbg_rdata
);
    reg [31:0] mem [0:WORDS-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    wire [ADDR_W-1:0] cpu_idx = addr[ADDR_W+1:2];
    wire [ADDR_W-1:0] dbg_idx = dbg_addr[ADDR_W+1:2];

    assign rdata     = mem[cpu_idx];
    assign dbg_rdata = mem[dbg_idx];

    always @(posedge clk) begin
        if (dbg_we) begin
            mem[dbg_idx] <= dbg_wdata;
        end else if (cpu_we) begin
            if (byte_en[0]) mem[cpu_idx][ 7: 0] <= wdata[ 7: 0];
            if (byte_en[1]) mem[cpu_idx][15: 8] <= wdata[15: 8];
            if (byte_en[2]) mem[cpu_idx][23:16] <= wdata[23:16];
            if (byte_en[3]) mem[cpu_idx][31:24] <= wdata[31:24];
        end
    end
endmodule
