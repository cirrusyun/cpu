`timescale 1ns/1ps
// 32 x 32 register file (A 域，25MHz)
//   x0 hardwired to 0 via read mux + write mask.
//   Reset (rst_n_cpu, active-low): x2(sp)=0x0000_7FFC, x3(gp)=0x0000_4000, others 0.
//   Async read on rs1/rs2/dbg ports; sync write.
//   Debug 只读端口（老师 DebugController 不写 RegFile，所以没有 dbg_we）。
module reg_file (
    input  wire        clk,
    input  wire        rst_n,        // active-low, async
    input  wire        cpu_step,     // clock enable (from DebugController via TopDebug)

    // CPU read
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,

    // CPU write
    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,

    // Debug read-only port
    input  wire [4:0]  dbg_addr,
    output wire [31:0] dbg_rdata
);
    reg [31:0] regs [0:31];
    integer i;

    assign rs1_data  = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data  = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];
    assign dbg_rdata = (dbg_addr == 5'd0) ? 32'b0 : regs[dbg_addr];

    // 复位初值显式枚举：x0 / x1 / x4–x31 = 0；x2 = sp 顶 = 0x7FFC；x3 = gp 基 = 0x4000。
    // 不用 for + 覆盖写法是为了避免依赖"非阻塞同周期后写覆盖前写"这条隐式规则。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            regs[ 0] <= 32'h0;
            regs[ 1] <= 32'h0;
            regs[ 2] <= 32'h0000_7FFC;   // sp: top of 32KB DMem
            regs[ 3] <= 32'h0000_4000;   // gp: Difftest data base
            for (i = 4; i < 32; i = i + 1) regs[i] <= 32'h0;
        end else if (cpu_step && we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end
endmodule
