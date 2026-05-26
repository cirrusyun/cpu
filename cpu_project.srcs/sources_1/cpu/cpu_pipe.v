`timescale 1ns/1ps
// 5-stage pipelined RV32I CPU core (A 域，25MHz) — bonus track
//   契约见 /home/yun/CS202/接口对齐检查单.md。端口与 cpu.v 完全一致，
//   单周期/流水可以在 cpu_top.v 内自由切换。
//
//   流水线分级：IF (B 内) | ID | EX | MEM | WB
//     A 自己在内部建一份 IF/ID shadow register（见架构 plan §9），
//     不依赖 B 的 ifetch 做 stall gating。
//
//   Hazard 处理（见 hazard_unit.v / forward_unit.v）：
//     - ALU RAW   → EX/MEM 或 MEM/WB → EX 前递，0 cycle penalty
//     - Load-Use  → 1 cycle stall + ID/EX bubble
//     - Branch/JAL/JALR/ECALL → EX 阶段解析 → flush ID/EX，next_pc 重定向
//
//   ECALL bonus：解码精确匹配（funct12=0, funct3=0, rs1=x0, rd=x0），
//     在 EX 阶段触发 next_pc = ECALL_HANDLER_PC，不写 rd，不存返回 PC。
module cpu_pipe #(
    parameter [31:0] ECALL_HANDLER_PC = 32'h0000_0080
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_step,

    // 取指接口（到 B 的 ifetch.v）
    output wire [31:0] next_pc,
    output wire        pc_we,
    output wire        branch_redirect,
    input  wire [31:0] pc_out,
    input  wire [31:0] inst_out,
    input  wire [31:0] pc_fetch,

    // 访存接口（到 B 的 dmem.v）
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_be,
    output wire        mem_we,
    input  wire [31:0] mem_rdata,

    // Debug RegFile 只读端口
    input  wire [4:0]  dbg_reg_addr,
    output wire [31:0] dbg_reg_data,

    // 性能监控：WB 阶段是否提交了真实指令（非 bubble）
    output wire        retire_valid
);
    localparam [31:0] NOP_INST = 32'h00000013;   // ADDI x0,x0,0

    // ============================================================
    // Hazard / forward wires (declared up-front for visibility)
    // ============================================================
    wire        stall_if, stall_id, flush_if_id, flush_id_ex;
    wire [1:0]  fwd_a, fwd_b, fwd_store;

    // EX-stage feedback wires (driven later, used by hazard/forward)
    wire        ex_redirect;
    wire [4:0]  ex_mem_rd_addr_w;
    wire        ex_mem_reg_write_w;
    wire [31:0] ex_mem_alu_result_w;
    wire [4:0]  mem_wb_rd_addr_w;
    wire        mem_wb_reg_write_w;
    wire [31:0] wb_data;

    // ============================================================
    // IF/ID shadow register + held buffer
    //   B 的 ifetch.v 在 stall 期间仍会把 pc_execute / bram_dout 往前推一拍
    //   （只有 pc_fetch 被 pc_we 门控）。所以 stall 释放时如果直接读 B 的
    //   pc_out/inst_out，会拿到 stall 期间 B 自己流过去的指令，丢了真正应该
    //   接下来执行的那条。
    //
    //   修法：stall 第一拍把 B 当前的 (pc_out, inst_out) 捕获到 held buffer，
    //   stall 释放时优先用 held。
    // ============================================================
    reg [31:0] held_pc, held_inst;
    reg        held_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            held_pc    <= 32'b0;
            held_inst  <= NOP_INST;
            held_valid <= 1'b0;
        end else if (cpu_step) begin
            if (flush_if_id) begin
                held_valid <= 1'b0;                  // redirect 丢弃 held
            end else if (stall_if && !held_valid) begin
                held_pc    <= pc_out;                // stall 第一拍捕获
                held_inst  <= inst_out;
                held_valid <= 1'b1;
            end else if (!stall_if && held_valid) begin
                held_valid <= 1'b0;                  // stall 释放消费 held
            end
        end
    end

    // 追踪 B 是否在 bubble 状态（startup or 我们刚 redirect 完）。
    // 之前用 `inst != NOP` 启发式判 valid，会把程序里真实的 ADDI x0,x0,0 漏算；
    // 现在显式跟踪：复位时 b_bubble=1；每次 ex_redirect 后下一拍 B 会送 NOP。
    reg b_bubble;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             b_bubble <= 1'b1;
        else if (cpu_step)      b_bubble <= ex_redirect;
    end

    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg        if_id_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= 32'b0;
            if_id_inst  <= NOP_INST;
            if_id_valid <= 1'b0;
        end else if (cpu_step) begin
            if (flush_if_id) begin
                if_id_inst  <= NOP_INST;
                if_id_valid <= 1'b0;
                if_id_pc    <= pc_out;
            end else if (!stall_if) begin
                if (held_valid) begin
                    if_id_pc    <= held_pc;
                    if_id_inst  <= held_inst;
                    if_id_valid <= 1'b1;     // held 必然是真实 fetch
                end else begin
                    if_id_pc    <= pc_out;
                    if_id_inst  <= inst_out;
                    if_id_valid <= ~b_bubble;
                end
            end
        end
    end

    // ============================================================
    // ID stage: decode + regfile read + immediate gen
    // ============================================================
    wire [6:0]  id_opcode   = if_id_inst[6:0];
    wire [4:0]  id_rd_addr  = if_id_inst[11:7];
    wire [2:0]  id_funct3   = if_id_inst[14:12];
    wire [4:0]  id_rs1_addr = if_id_inst[19:15];
    wire [4:0]  id_rs2_addr = if_id_inst[24:20];
    wire [6:0]  id_funct7   = if_id_inst[31:25];
    wire [11:0] id_funct12  = if_id_inst[31:20];

    wire [1:0]  id_alu_src_a;
    wire        id_alu_src_b;
    wire [1:0]  id_wb_src;
    wire        id_reg_write, id_mem_read, id_mem_write;
    wire        id_branch, id_jump, id_jalr, id_ecall;
    wire [2:0]  id_imm_type;
    wire [1:0]  id_mem_size;
    wire        id_mem_signed;
    wire [3:0]  id_alu_op;
    wire [31:0] id_imm;

    // 哪些指令真正读 rs1 / rs2（用于 hazard_unit 精确判定 load-use）
    reg id_uses_rs1, id_uses_rs2;
    always @(*) begin
        case (id_opcode)
            7'b0110011: begin id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b1; end // R-type
            7'b0010011: begin id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b0; end // I-ALU
            7'b0000011: begin id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b0; end // Load
            7'b0100011: begin id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b1; end // Store
            7'b1100011: begin id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b1; end // Branch
            7'b1100111: begin id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b0; end // JALR
            // JAL / LUI / AUIPC / SYSTEM / FENCE / unknown: 不读源寄存器
            default:    begin id_uses_rs1 = 1'b0; id_uses_rs2 = 1'b0; end
        endcase
    end

    ctrl u_ctrl (
        .opcode(id_opcode), .rd_addr(id_rd_addr),
        .funct3(id_funct3), .rs1_addr(id_rs1_addr),
        .funct7(id_funct7), .funct12(id_funct12),
        .alu_src_a(id_alu_src_a), .alu_src_b(id_alu_src_b),
        .wb_src(id_wb_src), .reg_write(id_reg_write),
        .mem_read(id_mem_read), .mem_write(id_mem_write),
        .branch(id_branch), .jump(id_jump), .jalr(id_jalr),
        .ecall_trap(id_ecall),
        .imm_type(id_imm_type),
        .mem_size(id_mem_size), .mem_signed(id_mem_signed)
    );

    alu_ctrl u_alu_ctrl (
        .opcode(id_opcode), .funct3(id_funct3), .funct7(id_funct7),
        .alu_op(id_alu_op)
    );

    imm_gen u_imm (
        .inst(if_id_inst), .imm_type(id_imm_type), .imm(id_imm)
    );

    wire [31:0] id_rs1_data, id_rs2_data;
    reg_file u_rf (
        .clk(clk), .rst_n(rst_n), .cpu_step(cpu_step),
        .rs1_addr(id_rs1_addr), .rs2_addr(id_rs2_addr),
        .rs1_data(id_rs1_data), .rs2_data(id_rs2_data),
        .we(mem_wb_reg_write_w), .rd_addr(mem_wb_rd_addr_w), .rd_data(wb_data),
        .dbg_addr(dbg_reg_addr), .dbg_rdata(dbg_reg_data)
    );

    // WB→ID bypass: RF async-read happens before the same-edge RF write,
    // so a value being committed this cycle is invisible to a same-cycle
    // ID read. By the next cycle the writer has left mem_wb and the
    // forward unit can no longer catch it. Bypass here.
    wire        id_rs1_wb_hit = mem_wb_reg_write_w && (mem_wb_rd_addr_w != 5'd0)
                             && (mem_wb_rd_addr_w == id_rs1_addr);
    wire        id_rs2_wb_hit = mem_wb_reg_write_w && (mem_wb_rd_addr_w != 5'd0)
                             && (mem_wb_rd_addr_w == id_rs2_addr);
    wire [31:0] id_rs1_eff   = id_rs1_wb_hit ? wb_data : id_rs1_data;
    wire [31:0] id_rs2_eff   = id_rs2_wb_hit ? wb_data : id_rs2_data;

    // ============================================================
    // ID/EX register
    // ============================================================
    reg [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    reg [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    reg [1:0]  id_ex_alu_src_a;
    reg        id_ex_alu_src_b;
    reg [3:0]  id_ex_alu_op;
    reg [2:0]  id_ex_funct3;
    reg [1:0]  id_ex_wb_src;
    reg        id_ex_reg_write;
    reg        id_ex_mem_read, id_ex_mem_write;
    reg [1:0]  id_ex_mem_size;
    reg        id_ex_mem_signed;
    reg        id_ex_branch, id_ex_jump, id_ex_jalr, id_ex_ecall;
    reg        id_ex_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc <= 0; id_ex_rs1_data <= 0; id_ex_rs2_data <= 0; id_ex_imm <= 0;
            id_ex_rs1_addr <= 0; id_ex_rs2_addr <= 0; id_ex_rd_addr <= 0;
            id_ex_alu_src_a <= 0; id_ex_alu_src_b <= 0; id_ex_alu_op <= 0;
            id_ex_funct3 <= 0;
            id_ex_wb_src <= 0; id_ex_reg_write <= 0;
            id_ex_mem_read <= 0; id_ex_mem_write <= 0;
            id_ex_mem_size <= 0; id_ex_mem_signed <= 0;
            id_ex_branch <= 0; id_ex_jump <= 0; id_ex_jalr <= 0; id_ex_ecall <= 0;
            id_ex_valid <= 0;
        end else if (cpu_step) begin
            if (flush_id_ex) begin
                // bubble: 控制信号全 0 = NOP；数据信号保持也无所谓
                id_ex_reg_write <= 1'b0;
                id_ex_mem_read  <= 1'b0;
                id_ex_mem_write <= 1'b0;
                id_ex_branch    <= 1'b0;
                id_ex_jump      <= 1'b0;
                id_ex_jalr      <= 1'b0;
                id_ex_ecall     <= 1'b0;
                id_ex_valid     <= 1'b0;
            end else begin
                id_ex_pc         <= if_id_pc;
                id_ex_rs1_data   <= id_rs1_eff;
                id_ex_rs2_data   <= id_rs2_eff;
                id_ex_imm        <= id_imm;
                id_ex_rs1_addr   <= id_rs1_addr;
                id_ex_rs2_addr   <= id_rs2_addr;
                id_ex_rd_addr    <= id_rd_addr;
                id_ex_alu_src_a  <= id_alu_src_a;
                id_ex_alu_src_b  <= id_alu_src_b;
                id_ex_alu_op     <= id_alu_op;
                id_ex_funct3     <= id_funct3;
                id_ex_wb_src     <= id_wb_src;
                id_ex_reg_write  <= id_reg_write;
                id_ex_mem_read   <= id_mem_read;
                id_ex_mem_write  <= id_mem_write;
                id_ex_mem_size   <= id_mem_size;
                id_ex_mem_signed <= id_mem_signed;
                id_ex_branch     <= id_branch;
                id_ex_jump       <= id_jump;
                id_ex_jalr       <= id_jalr;
                id_ex_ecall      <= id_ecall;
                id_ex_valid      <= if_id_valid;
            end
        end
    end

    // ============================================================
    // EX stage: forwarding muxes + ALU + branch decision
    // ============================================================
    forward_unit u_fwd (
        .id_ex_rs1_addr(id_ex_rs1_addr),
        .id_ex_rs2_addr(id_ex_rs2_addr),
        .ex_mem_rd_addr(ex_mem_rd_addr_w),
        .ex_mem_reg_write(ex_mem_reg_write_w),
        .mem_wb_rd_addr(mem_wb_rd_addr_w),
        .mem_wb_reg_write(mem_wb_reg_write_w),
        .fwd_a(fwd_a), .fwd_b(fwd_b), .fwd_store(fwd_store)
    );

    reg [31:0] rs1_fwd, rs2_fwd, store_fwd;
    always @(*) begin
        case (fwd_a)
            2'b10:   rs1_fwd = ex_mem_alu_result_w;
            2'b01:   rs1_fwd = wb_data;
            default: rs1_fwd = id_ex_rs1_data;
        endcase
        case (fwd_b)
            2'b10:   rs2_fwd = ex_mem_alu_result_w;
            2'b01:   rs2_fwd = wb_data;
            default: rs2_fwd = id_ex_rs2_data;
        endcase
        case (fwd_store)
            2'b10:   store_fwd = ex_mem_alu_result_w;
            2'b01:   store_fwd = wb_data;
            default: store_fwd = id_ex_rs2_data;
        endcase
    end

    reg [31:0] alu_a;
    always @(*) begin
        case (id_ex_alu_src_a)
            2'b00:   alu_a = rs1_fwd;
            2'b01:   alu_a = id_ex_pc;
            2'b10:   alu_a = 32'b0;
            default: alu_a = rs1_fwd;
        endcase
    end
    wire [31:0] alu_b = id_ex_alu_src_b ? id_ex_imm : rs2_fwd;

    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;
    alu u_alu (
        .a(alu_a), .b(alu_b), .alu_op(id_ex_alu_op),
        .result(ex_alu_result), .zero(ex_alu_zero)
    );

    reg ex_take_branch;
    always @(*) begin
        case (id_ex_funct3)
            3'b000:  ex_take_branch =  ex_alu_zero;       // BEQ
            3'b001:  ex_take_branch = ~ex_alu_zero;       // BNE
            3'b100:  ex_take_branch =  ex_alu_result[0];  // BLT
            3'b101:  ex_take_branch = ~ex_alu_result[0];  // BGE
            3'b110:  ex_take_branch =  ex_alu_result[0];  // BLTU
            3'b111:  ex_take_branch = ~ex_alu_result[0];  // BGEU
            default: ex_take_branch = 1'b0;
        endcase
    end
    wire ex_branch_taken = id_ex_branch & ex_take_branch;
    assign ex_redirect   = id_ex_jump | ex_branch_taken | id_ex_ecall;

    wire [31:0] ex_pc_branch = id_ex_pc + id_ex_imm;
    wire [31:0] ex_pc_jalr   = ex_alu_result & 32'hFFFF_FFFE;

    // ============================================================
    // EX/MEM register
    // ============================================================
    reg [31:0] ex_mem_pc, ex_mem_alu_result, ex_mem_store_data;
    reg [4:0]  ex_mem_rd_addr;
    reg [2:0]  ex_mem_funct3;
    reg [1:0]  ex_mem_wb_src;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_read, ex_mem_mem_write;
    reg [1:0]  ex_mem_mem_size;
    reg        ex_mem_mem_signed;
    reg        ex_mem_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_pc <= 0; ex_mem_alu_result <= 0; ex_mem_store_data <= 0;
            ex_mem_rd_addr <= 0; ex_mem_funct3 <= 0;
            ex_mem_wb_src <= 0; ex_mem_reg_write <= 0;
            ex_mem_mem_read <= 0; ex_mem_mem_write <= 0;
            ex_mem_mem_size <= 0; ex_mem_mem_signed <= 0;
            ex_mem_valid <= 0;
        end else if (cpu_step) begin
            // EX/MEM 不因 redirect 而 flush——产生 redirect 的指令本身（JAL 写 link
            // 等）要正常传到 MEM/WB。redirect 影响的是 IF/ID（shadow）和 ID/EX。
            ex_mem_pc          <= id_ex_pc;
            ex_mem_alu_result  <= ex_alu_result;
            ex_mem_store_data  <= store_fwd;
            ex_mem_rd_addr     <= id_ex_rd_addr;
            ex_mem_funct3      <= id_ex_funct3;
            ex_mem_wb_src      <= id_ex_wb_src;
            ex_mem_reg_write   <= id_ex_reg_write;
            ex_mem_mem_read    <= id_ex_mem_read;
            ex_mem_mem_write   <= id_ex_mem_write;
            ex_mem_mem_size    <= id_ex_mem_size;
            ex_mem_mem_signed  <= id_ex_mem_signed;
            ex_mem_valid       <= id_ex_valid;
        end
    end
    assign ex_mem_rd_addr_w    = ex_mem_rd_addr;
    assign ex_mem_reg_write_w  = ex_mem_reg_write;
    assign ex_mem_alu_result_w = ex_mem_alu_result;

    // ============================================================
    // MEM stage: load_store_fmt
    // ============================================================
    wire [31:0] mem_load_data;
    load_store_fmt u_lsfmt (
        .addr(ex_mem_alu_result),
        .mem_size(ex_mem_mem_size),
        .mem_signed(ex_mem_mem_signed),
        .mem_rdata(mem_rdata),
        .rs2_data(ex_mem_store_data),
        .load_data(mem_load_data),
        .mem_wdata(mem_wdata),
        .byte_en(mem_be)
    );
    assign mem_addr = ex_mem_alu_result;
    assign mem_we   = ex_mem_mem_write & cpu_step;     // 方案 A

    // ============================================================
    // MEM/WB register
    // ============================================================
    reg [31:0] mem_wb_pc, mem_wb_alu_result, mem_wb_load_data;
    reg [4:0]  mem_wb_rd_addr;
    reg [1:0]  mem_wb_wb_src;
    reg        mem_wb_reg_write;
    reg        mem_wb_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_pc <= 0; mem_wb_alu_result <= 0; mem_wb_load_data <= 0;
            mem_wb_rd_addr <= 0; mem_wb_wb_src <= 0;
            mem_wb_reg_write <= 0; mem_wb_valid <= 0;
        end else if (cpu_step) begin
            mem_wb_pc          <= ex_mem_pc;
            mem_wb_alu_result  <= ex_mem_alu_result;
            mem_wb_load_data   <= mem_load_data;
            mem_wb_rd_addr     <= ex_mem_rd_addr;
            mem_wb_wb_src      <= ex_mem_wb_src;
            mem_wb_reg_write   <= ex_mem_reg_write;
            mem_wb_valid       <= ex_mem_valid;
        end
    end
    assign mem_wb_rd_addr_w   = mem_wb_rd_addr;
    assign mem_wb_reg_write_w = mem_wb_reg_write;

    // ============================================================
    // WB stage: mux
    // ============================================================
    reg [31:0] wb_mux;
    always @(*) begin
        case (mem_wb_wb_src)
            2'b00:   wb_mux = mem_wb_alu_result;
            2'b01:   wb_mux = mem_wb_load_data;
            2'b10:   wb_mux = mem_wb_pc + 32'd4;
            default: wb_mux = mem_wb_alu_result;
        endcase
    end
    assign wb_data = wb_mux;

    // ============================================================
    // Hazard unit
    // ============================================================
    hazard_unit u_hzd (
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_rd_addr(id_ex_rd_addr),
        .if_id_rs1_addr(id_rs1_addr),
        .if_id_rs2_addr(id_rs2_addr),
        .if_id_uses_rs1(id_uses_rs1),
        .if_id_uses_rs2(id_uses_rs2),
        .ex_redirect(ex_redirect),
        .stall_if(stall_if),
        .stall_id(stall_id),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

    // ============================================================
    // PC update logic (sent to B)
    // ============================================================
    assign next_pc = id_ex_ecall                       ? ECALL_HANDLER_PC
                   : id_ex_jalr                        ? ex_pc_jalr
                   : (id_ex_jump | ex_branch_taken)    ? ex_pc_branch
                   :                                     (pc_fetch + 32'd4);
    assign pc_we           = ~stall_if;
    assign branch_redirect = ex_redirect;

    assign retire_valid    = mem_wb_valid;
endmodule
