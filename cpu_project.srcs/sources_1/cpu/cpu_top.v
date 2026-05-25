`timescale 1ns/1ps
// Mode-switch wrapper: chooses between single-cycle cpu.v and 5-stage cpu_pipe.v.
//
//   mode_select = 1  → 单周期核活跃，流水核被 hold 在 reset
//   mode_select = 0  → 流水核活跃，单周期核被 hold 在 reset
//
//   端口与 cpu.v 完全一致，可直接替换。两核共享 IMem / DMem 和 PC 寄存器（都在
//   B 的 ifetch.v 内），每个核有自己的 RegFile 和（流水模式下）流水寄存器。
//
//   ── 模式切换契约（boot-time configuration）──
//   mode_select 是 **boot-time 配置位**，不支持运行中或 halted 状态下热切换。
//   切换前所有架构状态（含 B 侧 PC 与两核各自 RegFile/流水寄存器）必须经
//   rst_n 一并重置：
//
//     1. 把 rst_n 拉低
//     2. 改 mode_select 到新值
//     3. 重新放 rst_n 高
//     4. （可选）通过 wi/wd 重新加载 IMem/DMem 内容
//     5. 运行
//
//   板上接 `sw[15]` 时建议：把开关变化检测脉冲送进 rst_n 路径的 AND 项
//   （rst_n 低有效，所以"复位脉冲"对应一段低电平窗口），保证开关一动就有
//   一拍 rst_n=0；禁止任何"开关一拨就切换"的隐式热切换。
//
//   tb_topmode_switch 严格按这个契约写：rst_n=0 → 切 mode → rst_n=1 → 重跑。
module cpu_top #(
    parameter [31:0] ECALL_HANDLER_PC = 32'h0000_0080
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_step,
    input  wire        mode_select,     // 1=single-cycle, 0=pipeline

    output wire [31:0] next_pc,
    output wire        pc_we,
    output wire        branch_redirect,
    input  wire [31:0] pc_out,
    input  wire [31:0] inst_out,
    input  wire [31:0] pc_fetch,

    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_be,
    output wire        mem_we,
    input  wire [31:0] mem_rdata,

    input  wire [4:0]  dbg_reg_addr,
    output wire [31:0] dbg_reg_data,

    // 性能监控（cycle 数 + 已 commit 指令数），由内部 cycle_counter 提供
    output wire [63:0] cycle_count,
    output wire [63:0] inst_retired
);
    // 把不活跃的核 hold 在 reset，避免它的 RegFile 跟着推进
    wire rst_n_sc = rst_n &  mode_select;
    wire rst_n_pp = rst_n & ~mode_select;

    // 单周期核输出
    wire [31:0] sc_next_pc, sc_mem_addr, sc_mem_wdata, sc_dbg_reg_data;
    wire        sc_pc_we, sc_branch_redirect, sc_mem_we;
    wire [3:0]  sc_mem_be;

    cpu #(.ECALL_HANDLER_PC(ECALL_HANDLER_PC)) u_cpu_sc (
        .clk(clk), .rst_n(rst_n_sc), .cpu_step(cpu_step),
        .next_pc(sc_next_pc), .pc_we(sc_pc_we),
        .branch_redirect(sc_branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(sc_mem_addr), .mem_wdata(sc_mem_wdata),
        .mem_be(sc_mem_be), .mem_we(sc_mem_we),
        .mem_rdata(mem_rdata),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(sc_dbg_reg_data)
    );

    // 流水核输出
    wire [31:0] pp_next_pc, pp_mem_addr, pp_mem_wdata, pp_dbg_reg_data;
    wire        pp_pc_we, pp_branch_redirect, pp_mem_we;
    wire [3:0]  pp_mem_be;
    wire        pp_retire_valid;

    cpu_pipe #(.ECALL_HANDLER_PC(ECALL_HANDLER_PC)) u_cpu_pp (
        .clk(clk), .rst_n(rst_n_pp), .cpu_step(cpu_step),
        .next_pc(pp_next_pc), .pc_we(pp_pc_we),
        .branch_redirect(pp_branch_redirect),
        .pc_out(pc_out), .inst_out(inst_out), .pc_fetch(pc_fetch),
        .mem_addr(pp_mem_addr), .mem_wdata(pp_mem_wdata),
        .mem_be(pp_mem_be), .mem_we(pp_mem_we),
        .mem_rdata(mem_rdata),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(pp_dbg_reg_data),
        .retire_valid(pp_retire_valid)
    );

    // 性能计数器：cycle_count 永远每 cpu_step 拍 +1。
    // inst_retired 用"非 bubble"作为 valid 口径，**不**依赖指令编码（避免漏算
    // 程序里真实的 ADDI x0,x0,0 NOP）。
    //   - pipeline 核：直接用 cpu_pipe 暴露的 retire_valid（mem_wb 的 valid 位）
    //   - 单周期：追踪 startup + 每次 branch_redirect 后一拍 = bubble
    reg sc_bubble;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          sc_bubble <= 1'b1;
        else if (cpu_step)   sc_bubble <= sc_branch_redirect;
    end
    wire sc_retire_valid = ~sc_bubble;
    wire retire_inc      = mode_select ? sc_retire_valid : pp_retire_valid;

    cycle_counter u_cnt (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .inst_retired_inc(retire_inc),
        .cycle_count(cycle_count),
        .inst_retired(inst_retired)
    );

    // A→B 输出 mux
    assign next_pc         = mode_select ? sc_next_pc         : pp_next_pc;
    assign pc_we           = mode_select ? sc_pc_we           : pp_pc_we;
    assign branch_redirect = mode_select ? sc_branch_redirect : pp_branch_redirect;
    assign mem_addr        = mode_select ? sc_mem_addr        : pp_mem_addr;
    assign mem_wdata       = mode_select ? sc_mem_wdata       : pp_mem_wdata;
    assign mem_be          = mode_select ? sc_mem_be          : pp_mem_be;
    assign mem_we          = mode_select ? sc_mem_we          : pp_mem_we;
    assign dbg_reg_data    = mode_select ? sc_dbg_reg_data    : pp_dbg_reg_data;
endmodule
