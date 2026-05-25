`timescale 1ns/1ps
// Forwarding unit for cpu_pipe.v
//   EX/MEM -> EX has priority over MEM/WB -> EX.
//   fwd_store selects the value latched into ex_mem_store_data so that
//   a store can consume an in-flight ALU/Load result without stalling.
module forward_unit (
    input  wire [4:0] id_ex_rs1_addr,
    input  wire [4:0] id_ex_rs2_addr,
    input  wire [4:0] ex_mem_rd_addr,
    input  wire       ex_mem_reg_write,
    input  wire [4:0] mem_wb_rd_addr,
    input  wire       mem_wb_reg_write,
    output wire [1:0] fwd_a,
    output wire [1:0] fwd_b,
    output wire [1:0] fwd_store
);
    // 2'b10 = forward from EX/MEM, 2'b01 = forward from MEM/WB, 2'b00 = no forward
    wire ex_hit_a = ex_mem_reg_write && (ex_mem_rd_addr != 5'd0)
                 && (ex_mem_rd_addr == id_ex_rs1_addr);
    wire ex_hit_b = ex_mem_reg_write && (ex_mem_rd_addr != 5'd0)
                 && (ex_mem_rd_addr == id_ex_rs2_addr);
    wire wb_hit_a = mem_wb_reg_write && (mem_wb_rd_addr != 5'd0)
                 && (mem_wb_rd_addr == id_ex_rs1_addr);
    wire wb_hit_b = mem_wb_reg_write && (mem_wb_rd_addr != 5'd0)
                 && (mem_wb_rd_addr == id_ex_rs2_addr);

    assign fwd_a     = ex_hit_a ? 2'b10 : wb_hit_a ? 2'b01 : 2'b00;
    assign fwd_b     = ex_hit_b ? 2'b10 : wb_hit_b ? 2'b01 : 2'b00;
    assign fwd_store = ex_hit_b ? 2'b10 : wb_hit_b ? 2'b01 : 2'b00;
endmodule
