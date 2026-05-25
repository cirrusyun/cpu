`timescale 1ns/1ps
// Instruction memory: 4KB (1024 x 32-bit words), behavioral LUTRAM.
//   Async read for both CPU fetch and debug. Sync write only via debug bus.
//   No reset on the memory array — reset must not erase programs loaded
//   by `wi` over the UART debug bus (架构 §9).
//   For simulation, set INIT_FILE parameter to a hex file path so $readmemh
//   pre-loads the instruction memory.
module inst_mem #(
    parameter         WORDS     = 1024,
    parameter         ADDR_W    = 10,        // log2(WORDS)
    parameter         INIT_FILE = ""
) (
    input  wire        clk,
    // CPU fetch (async read)
    input  wire [31:0] pc,
    output wire [31:0] inst,
    // Debug port
    input  wire        dbg_we,
    input  wire [31:0] dbg_addr,    // byte address (4-byte aligned)
    input  wire [31:0] dbg_wdata,
    output wire [31:0] dbg_rdata
);
    reg [31:0] mem [0:WORDS-1];

    // Initialize for simulation only; ignored by synthesis when string empty.
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    assign inst      = mem[pc[ADDR_W+1:2]];
    assign dbg_rdata = mem[dbg_addr[ADDR_W+1:2]];

    always @(posedge clk) begin
        if (dbg_we) mem[dbg_addr[ADDR_W+1:2]] <= dbg_wdata;
    end
endmodule
