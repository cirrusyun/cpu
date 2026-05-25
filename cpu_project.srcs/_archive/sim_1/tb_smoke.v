`timescale 1ns/1ps
//
// tb_smoke — basic smoke test for the single-cycle CPU.
//
// Pre-loads a short program into IMem via hierarchical reference, deasserts
// reset, runs ~50 cycles, then checks DMem at gp+{0,4,8,C} for expected
// arithmetic results. No UART, no MMIO traffic — just CPU + memory.
//
// Test program (RV32I assembly):
//   addi t0, x0, 5      ; t0 = 5
//   addi t1, x0, 7      ; t1 = 7
//   add  t2, t0, t1     ; t2 = 12   -> gp+0
//   sw   t2, 0(gp)
//   sub  t3, t1, t0     ; t3 = 2    -> gp+4
//   sw   t3, 4(gp)
//   andi t4, t0, 3      ; t4 = 1    -> gp+8
//   sw   t4, 8(gp)
//   slli t5, t0, 2      ; t5 = 20   -> gp+C
//   sw   t5, 12(gp)
//   jal  x0, 0          ; halt-loop here (PC stuck at 0x28)
//
module tb_smoke;
    reg         clk;
    reg         fpga_rst_n;
    reg  [15:0] sw;
    reg  [4:0]  btn;
    wire [15:0] led;
    wire [7:0]  seg0, seg1, an;
    reg         uart_rx;
    wire        uart_tx;

    TopDebug dut (
        .clk(clk), .fpga_rst_n(fpga_rst_n),
        .sw(sw), .btn(btn),
        .led(led), .seg0(seg0), .seg1(seg1), .an(an),
        .uart_rx(uart_rx), .uart_tx(uart_tx)
    );

    // 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Pre-load program
    initial begin
        dut.u_imem.mem[ 0] = 32'h00500293; // addi t0, x0, 5
        dut.u_imem.mem[ 1] = 32'h00700313; // addi t1, x0, 7
        dut.u_imem.mem[ 2] = 32'h006283B3; // add  t2, t0, t1
        dut.u_imem.mem[ 3] = 32'h0071A023; // sw   t2, 0(gp)
        dut.u_imem.mem[ 4] = 32'h40530E33; // sub  t3, t1, t0
        dut.u_imem.mem[ 5] = 32'h01C1A223; // sw   t3, 4(gp)
        dut.u_imem.mem[ 6] = 32'h0032FE93; // andi t4, t0, 3
        dut.u_imem.mem[ 7] = 32'h01D1A423; // sw   t4, 8(gp)
        dut.u_imem.mem[ 8] = 32'h00229F13; // slli t5, t0, 2
        dut.u_imem.mem[ 9] = 32'h01E1A623; // sw   t5, 12(gp)
        dut.u_imem.mem[10] = 32'h0000006F; // jal  x0, 0  (loop)
    end

    integer fail_cnt;
    task check;
        input [255:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected)
                $display("[PASS] %0s: 0x%08h", name, actual);
            else begin
                $display("[FAIL] %0s: got 0x%08h, expected 0x%08h",
                         name, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        fail_cnt   = 0;
        sw         = 16'h0;
        btn        = 5'h0;
        uart_rx    = 1'b1;
        fpga_rst_n = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        fpga_rst_n = 1'b1;

        repeat (50) @(posedge clk);

        $display("---- smoke test ----");
        // DMem index = byte_addr[14:2]; gp=0x4000 -> index 0x1000
        check("gp+0  add  -> 12",  dut.u_dmem.mem[13'h1000], 32'd12);
        check("gp+4  sub  -> 2",   dut.u_dmem.mem[13'h1001], 32'd2);
        check("gp+8  andi -> 1",   dut.u_dmem.mem[13'h1002], 32'd1);
        check("gp+12 slli -> 20",  dut.u_dmem.mem[13'h1003], 32'd20);
        check("PC stuck at 0x28",  dut.u_cpu.pc,             32'h0000_0028);
        check("sp init = 0x7FFC",  dut.u_cpu.u_rf.regs[2],   32'h0000_7FFC);
        check("gp init = 0x4000",  dut.u_cpu.u_rf.regs[3],   32'h0000_4000);

        if (fail_cnt == 0) begin
            $display("[ALL %0d CHECKS PASSED]", 7);
            $finish;
        end else begin
            $display("[%0d / 7 FAILED]", fail_cnt);
            $fatal(1, "tb_smoke failed");
        end
    end
endmodule
