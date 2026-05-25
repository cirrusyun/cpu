`timescale 1ns/1ps
// Hazard unit for cpu_pipe.v
//   Sole stall source: load-use (LW in EX with dependent in ID).
//   Branch / JAL / JALR / ECALL flush: kill the sequential successor in
//   ID/EX. The redirect-causing instruction itself is NOT squashed
//   (JAL/JALR still write their link register).
module hazard_unit (
    input  wire       id_ex_mem_read,
    input  wire [4:0] id_ex_rd_addr,
    input  wire [4:0] if_id_rs1_addr,
    input  wire [4:0] if_id_rs2_addr,
    input  wire       if_id_uses_rs1,    // 1=ID-stage instr actually reads rs1
    input  wire       if_id_uses_rs2,    // 1=ID-stage instr actually reads rs2
    input  wire       ex_redirect,
    output wire       stall_if,
    output wire       stall_id,
    output wire       flush_if_id,
    output wire       flush_id_ex
);
    // 只有当 ID 阶段实际会读这个源寄存器时才视为冲突。否则 ADDI/LUI/AUIPC/JAL
    // 等不读 rs2 的指令，其 inst[24:20] 是立即数字段，会被误判为寄存器号造成
    // 无效的 load-use stall。
    wire match_rs1 = if_id_uses_rs1 && (if_id_rs1_addr == id_ex_rd_addr);
    wire match_rs2 = if_id_uses_rs2 && (if_id_rs2_addr == id_ex_rd_addr);
    wire load_use  = id_ex_mem_read
                  && (id_ex_rd_addr != 5'd0)
                  && (match_rs1 || match_rs2);

    assign stall_if    = load_use;
    assign stall_id    = load_use;
    assign flush_if_id = ex_redirect & ~load_use;   // load_use can't co-occur with redirect
    assign flush_id_ex = load_use | ex_redirect;
endmodule
