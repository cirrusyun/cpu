`timescale 1ns/1ps
// Simulation stub for B's ifetch.v
//   Replicates the contract: BRAM 同步读 + startup NOP + PC 寄存器在内部。
//   PC@T 送 BRAM → inst_out@T+1 = mem[PC@T]，pc_out@T+1 = PC@T（两者配对）。
//   集成时直接替换为 B 的真 ifetch.v，端口完全一致。
module fake_ifetch #(
    parameter MEM_SIZE = 1024,   // 4KB / 4 bytes
    parameter INIT_FILE = "",    // 仿真用 $readmemh 加载；为空则不加载
    parameter INIT_FILE_FALLBACK = ""
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_step,

    // 来自 A 的 cpu.v
    input  wire [31:0] next_pc,
    input  wire        pc_we,
    input  wire        branch_redirect,   // 1=本周期 EX 出了控制流重定向，下一拍必须 flush

    // 给 A 的 cpu.v
    output wire [31:0] pc_out,
    output wire [31:0] inst_out,
    output reg  [31:0] pc_fetch       // 当前 IF 阶段 PC，A 用来算 next_pc = pc_fetch+4
);
    reg [31:0] mem [0:MEM_SIZE-1];
    reg [31:0] pc_execute;
    reg [31:0] bram_dout;
    reg        startup;
    reg        pending_flush;   // 上一拍 redirect 了，这一拍的 bram_dout 是 fall-through 错指令

    integer k;
    integer init_fd;
    initial begin
        for (k = 0; k < MEM_SIZE; k = k + 1) mem[k] = 32'h00000013;  // NOP fill
        if (INIT_FILE != "") begin
            init_fd = $fopen(INIT_FILE, "r");
            if (init_fd == 0) begin
                if (INIT_FILE_FALLBACK == "") begin
                    $fatal(1, "fake_ifetch: cannot open INIT_FILE '%0s'", INIT_FILE);
                end
                init_fd = $fopen(INIT_FILE_FALLBACK, "r");
                if (init_fd == 0) begin
                    $fatal(1, "fake_ifetch: cannot open INIT_FILE '%0s' or fallback '%0s'",
                           INIT_FILE, INIT_FILE_FALLBACK);
                end
                $fclose(init_fd);
                $readmemh(INIT_FILE_FALLBACK, mem);
            end else begin
                $fclose(init_fd);
                $readmemh(INIT_FILE, mem);
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_fetch      <= 32'b0;
            pc_execute    <= 32'b0;
            bram_dout     <= 32'b0;
            startup       <= 1'b1;
            pending_flush <= 1'b0;
        end else if (cpu_step) begin
            startup       <= 1'b0;
            bram_dout     <= mem[pc_fetch[31:2]];   // BRAM 同步读（fall-through 已被锁存）
            pc_execute    <= pc_fetch;
            pending_flush <= branch_redirect;       // EX 在 redirect → IF 提前 prefetch 的指令作废
            if (pc_we) pc_fetch <= next_pc;
        end
    end

    assign pc_out   = pc_execute;
    // 第 0 拍 startup 或紧跟 redirect 的 bubble 拍：强制 NOP，避免错误执行
    assign inst_out = (startup | pending_flush) ? 32'h00000013 : bram_dout;
    // pc_fetch 由 always 块直接驱动（output reg）
endmodule
