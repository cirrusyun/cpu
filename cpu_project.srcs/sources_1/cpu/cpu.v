`timescale 1ns/1ps
// Single-cycle RV32I CPU core (A 域，25MHz)
//   契约见 /home/yun/CS202/接口对齐检查单.md。
//
//   PC 寄存器在 B 的 ifetch.v 内（不在 A）。
//   A 算出 next_pc 与 pc_we，交给 B；B 通过 pc_out / inst_out 回传执行级 PC 与指令。
//   pc_out 是与 inst_out 同周期配对的执行 PC（AUIPC/JAL/Branch 基准）。
//
//   mem_we 由 A 内部用 cpu_step gate（方案 A，已与 B 协调）。
//   所有时序寄存器（base 阶段只有 RegFile）使用统一模板：
//     posedge clk or negedge rst_n
//     if (!rst_n)       reg_x <= INIT
//     else if (cpu_step) reg_x <= next_x
//
//   ECALL bonus（架构.md §14, max 2 分）：检测 ECALL 后 next_pc 跳到 ECALL_HANDLER_PC
//   （参数，默认 0x80）。EBREAK 仍走默认 NOP。不保存返回 PC——handler 自包含运行。
module cpu #(
    parameter [31:0] ECALL_HANDLER_PC = 32'h0000_0080
)(
    input  wire        clk,             // 25MHz
    input  wire        rst_n,           // = rst_n_cpu（TopDebug 内合并）
    input  wire        cpu_step,        // clock enable

    // 取指接口（到 B 的 ifetch.v）
    output wire [31:0] next_pc,
    output wire        pc_we,
    output wire        branch_redirect, // 1=本周期 EX 解析出控制流重定向，B 必须 flush prefetch
    input  wire [31:0] pc_out,          // 执行级 PC（与 inst_out 配对）
    input  wire [31:0] inst_out,
    input  wire [31:0] pc_fetch,        // IF 级 PC（A 用来算顺序 next_pc）

    // 访存接口（到 B 的 dmem.v / TopDebug 译码后的 mmio）
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_be,
    output wire        mem_we,
    input  wire [31:0] mem_rdata,

    // Debug RegFile 读端口（只读）
    input  wire [4:0]  dbg_reg_addr,
    output wire [31:0] dbg_reg_data
);
    // ---------- Decode ----------
    wire [31:0] inst     = inst_out;
    wire [6:0]  opcode   = inst[6:0];
    wire [4:0]  rd_addr  = inst[11:7];
    wire [2:0]  funct3   = inst[14:12];
    wire [4:0]  rs1_addr = inst[19:15];
    wire [4:0]  rs2_addr = inst[24:20];
    wire        funct7_5 = inst[30];

    wire [1:0]  alu_src_a;
    wire        alu_src_b;
    wire [1:0]  wb_src;
    wire        reg_write, mem_read, mem_write, branch, jump, jalr, ecall_trap;
    wire [2:0]  imm_type;
    wire [1:0]  mem_size;
    wire        mem_signed;
    wire [3:0]  alu_op;
    wire [31:0] imm;

    ctrl u_ctrl (
        .opcode(opcode), .rd_addr(rd_addr),
        .funct3(funct3), .rs1_addr(rs1_addr),
        .funct7(inst[31:25]),
        .funct12(inst[31:20]),
        .alu_src_a(alu_src_a), .alu_src_b(alu_src_b),
        .wb_src(wb_src), .reg_write(reg_write),
        .mem_read(mem_read), .mem_write(mem_write),
        .branch(branch), .jump(jump), .jalr(jalr),
        .ecall_trap(ecall_trap),
        .imm_type(imm_type),
        .mem_size(mem_size), .mem_signed(mem_signed)
    );

    alu_ctrl u_alu_ctrl (
        .opcode(opcode), .funct3(funct3), .funct7_5(funct7_5),
        .alu_op(alu_op)
    );

    imm_gen u_imm (
        .inst(inst), .imm_type(imm_type), .imm(imm)
    );

    // ---------- Register file ----------
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] wb_data;
    reg_file u_rf (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .we(reg_write), .rd_addr(rd_addr), .rd_data(wb_data),
        .dbg_addr(dbg_reg_addr), .dbg_rdata(dbg_reg_data)
    );

    // ---------- Execute ----------
    reg [31:0] alu_a;
    always @(*) begin
        case (alu_src_a)
            2'b00:   alu_a = rs1_data;     // R / I-ALU / Load / Store / Branch / JALR
            2'b01:   alu_a = pc_out;       // AUIPC / JAL  ← 用配对的执行级 PC
            2'b10:   alu_a = 32'b0;        // LUI (result = 0 + imm = imm)
            default: alu_a = rs1_data;
        endcase
    end
    wire [31:0] alu_b = alu_src_b ? imm : rs2_data;

    wire [31:0] alu_result;
    wire        alu_zero;
    alu u_alu (
        .a(alu_a), .b(alu_b), .alu_op(alu_op),
        .result(alu_result), .zero(alu_zero)
    );

    // ---------- Branch decision ----------
    // 架构 §3 / 检查单 §1.2: BLT/BGE 用 SLT 结果（alu_result==1 表示 rs1 < rs2）;
    // BLTU/BGEU 用 SLTU. SUB + negative 在有符号溢出时会错。
    reg take_branch;
    always @(*) begin
        case (funct3)
            3'b000:  take_branch =  alu_zero;       // BEQ
            3'b001:  take_branch = ~alu_zero;       // BNE
            3'b100:  take_branch =  alu_result[0];  // BLT
            3'b101:  take_branch = ~alu_result[0];  // BGE
            3'b110:  take_branch =  alu_result[0];  // BLTU
            3'b111:  take_branch = ~alu_result[0];  // BGEU
            default: take_branch = 1'b0;
        endcase
    end
    wire branch_taken = branch & take_branch;

    // ---------- Memory access ----------
    wire [31:0] load_data;
    load_store_fmt u_lsfmt (
        .addr(alu_result),
        .mem_size(mem_size),
        .mem_signed(mem_signed),
        .mem_rdata(mem_rdata),
        .rs2_data(rs2_data),
        .load_data(load_data),
        .mem_wdata(mem_wdata),
        .byte_en(mem_be)
    );
    assign mem_we   = mem_write & cpu_step;   // 方案 A：A 内部 gate
    assign mem_addr = alu_result;

    // ---------- Write-back ----------
    reg [31:0] wb_mux;
    always @(*) begin
        case (wb_src)
            2'b00:   wb_mux = alu_result;
            2'b01:   wb_mux = load_data;
            2'b10:   wb_mux = pc_out + 32'd4;   // JAL/JALR link 用配对 PC
            default: wb_mux = alu_result;
        endcase
    end
    assign wb_data = wb_mux;

    // ---------- Next PC ----------
    // 注意：BRAM 2 级流水语义下，pc_fetch 已经领先 pc_execute 一拍（IF 提前 prefetch）。
    // 顺序执行时 next_pc 应当基于 pc_fetch（不是 pc_out），否则 pc_fetch 会停在原地。
    // 跳转/分支目标仍然基于 pc_out（即当前执行指令的 PC）。
    wire [31:0] pc_plus4  = pc_fetch + 32'd4;                   // 顺序：从 IF 级 PC 继续
    wire [31:0] pc_branch = pc_out   + imm;                     // JAL (J-imm) / Branch (B-imm)
    // JALR target = (rs1 + imm) & ~1。
    // ALU 已经算了 rs1+imm（alu_src_a=rs1, alu_src_b=imm），直接复用 alu_result，
    // 避免重复加法器。bit0 清零在 PC mux 内完成，不污染 alu_result（rd 写的是 pc_out+4）。
    wire [31:0] pc_jalr   = alu_result & 32'hFFFF_FFFE;

    assign next_pc         = ecall_trap            ? ECALL_HANDLER_PC
                           : jalr                  ? pc_jalr
                           : (jump | branch_taken) ? pc_branch
                           :                         pc_plus4;
    assign pc_we           = 1'b1;          // base 阶段恒 1（pipeline bonus 时按 hazard 控制）
    assign branch_redirect = jump | branch_taken | ecall_trap;   // ECALL 也要 flush prefetch
endmodule
