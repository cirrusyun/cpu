`timescale 1ns/1ps
// TopDebug — system top module for EGO1 board
//
// EGO1 pin assignment (write into top.xdc):
//   clk          P17  100 MHz SYS_CLK
//   fpga_rst_n   P15  dedicated FPGA_RESET button (active LOW, pull-up)
//   sw[0..15]    R1, N4, M4, R2, P2, P3, P4, P5,        // SW_0 .. SW_7  (拨码)
//                T5, T3, R3, V4, V5, V2, U2, U3         // SW8.0 .. SW8.7 (8-bit DIP)
//   btn[0..4]    R11, R17, R15, V1, U4                  // PB0..PB4 (active HIGH; unused for now)
//   led[0..15]   K3, M1, L1, K6, J5, H5, H6, K1,        // D1_0..D1_7
//                K2, J2, J3, H4, J4, G3, G4, F6         // D2_0..D2_7
//   seg0[7:0]    DN0 segments (active HIGH, common cathode)
//   seg1[7:0]    DN1 segments — driven by same internal signal as seg0
//                Bit ordering: bit0=A, bit1=B, ..., bit6=G, bit7=DP
//                  seg0[0]=CA0(B4)  seg1[0]=CA1(D4)
//                  seg0[1]=CB0(A4)  seg1[1]=CB1(E3)
//                  seg0[2]=CC0(A3)  seg1[2]=CC1(D3)
//                  seg0[3]=CD0(B1)  seg1[3]=CD1(F4)
//                  seg0[4]=CE0(A1)  seg1[4]=CE1(F3)
//                  seg0[5]=CF0(B3)  seg1[5]=CF1(E2)
//                  seg0[6]=CG0(B2)  seg1[6]=CG1(D2)
//                  seg0[7]=DP0(D5)  seg1[7]=DP1(H2)
//   an[0..7]     digit select (active HIGH); an[0]=LSB digit
//                Map XDC so an[0]->BIT8(G6) (rightmost), an[7]->BIT1(G2) (leftmost)
//                if you want LSB on the right; or reverse if you prefer LSB on the left
//                The 8 BIT pins are: BIT1=G2, BIT2=C2, BIT3=C1, BIT4=H1,
//                                    BIT5=G1, BIT6=F1, BIT7=E1, BIT8=G6
//   uart_rx      N5
//   uart_tx      T4
module TopDebug (
    input  wire        clk,
    input  wire        fpga_rst_n,
    input  wire [15:0] sw,
    input  wire [4:0]  btn,
    output wire [15:0] led,
    output wire [7:0]  seg0,    // DN0 segments
    output wire [7:0]  seg1,    // DN1 segments (same value as seg0)
    output wire [7:0]  an,
    input  wire        uart_rx,
    output wire        uart_tx
);
    // ---------- Reset chain (架构 §9 ARSR) ----------
    // FPGA_RESET button is active-LOW (pull-up); rst_btn_raw goes HIGH when pressed.
    wire rst_btn_raw = ~fpga_rst_n;
    reg  rst_sync1, rst_sync2;
    always @(posedge clk or posedge rst_btn_raw) begin
        if (rst_btn_raw) {rst_sync1, rst_sync2} <= 2'b11;          // async assert
        else             {rst_sync1, rst_sync2} <= {1'b0, rst_sync1}; // sync release
    end
    wire rst_from_btn = rst_sync2;

    // ---------- Debug bus stubs (TEMPORARY bring-up policy) ----------
    // These are tied off so the CPU runs free from reset, which is what we
    // need for simulation (with INIT_FILE preloading IMem) and traditional
    // on-board verification. THIS IS NOT THE FINAL CONTRACT.
    //
    // When debug_ctrl is wired up, the architecture (架构 §9) requires:
    //   - dbg_halt resets to 1 (halted) on board reset; host must send `run`
    //     explicitly to start CPU. This avoids running garbage IMem on power-up.
    //   - dbg_reset is a single-cycle pulse from UART `reset` command; it
    //     must reset CPU core only, not debug_ctrl, not GPIO.
    // Do not carry the current free-run-on-reset behavior into the final
    // wiring; the stubs here are a bring-up shortcut, not a default.
    wire        dbg_halt    = 1'b0;
    wire        dbg_step    = 1'b0;
    wire        dbg_reset   = 1'b0;
    wire        dbg_imem_we = 1'b0;
    wire        dbg_dmem_we = 1'b0;
    wire        dbg_reg_we  = 1'b0;
    wire [31:0] dbg_addr    = 32'b0;
    wire [31:0] dbg_wdata   = 32'b0;

    wire rst_cpu    = rst_from_btn | dbg_reset;
    wire cpu_clk_en = dbg_halt ? dbg_step : 1'b1;

    // ---------- CPU ↔ memory wires ----------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        cpu_dmem_we;
    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    wire [3:0]  cpu_dmem_be;
    wire [31:0] cpu_dmem_rdata;

    // ---------- Debug observation wires ----------
    // Declared now so that connecting debug_ctrl later only requires routing
    // these to top-level UART logic; no module-port edits to cpu/inst_mem/data_mem.
    wire [31:0] cpu_pc_out;
    wire [31:0] cpu_dbg_reg_rdata;
    wire [31:0] imem_dbg_rdata;
    wire [31:0] dmem_dbg_rdata;

    cpu u_cpu (
        .clk(clk), .rst(rst_cpu), .clk_en(cpu_clk_en),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_we(cpu_dmem_we), .dmem_addr(cpu_dmem_addr),
        .dmem_wdata(cpu_dmem_wdata), .dmem_be(cpu_dmem_be),
        .dmem_rdata(cpu_dmem_rdata),
        .dbg_reg_we(dbg_reg_we),
        .dbg_reg_addr(dbg_addr[4:0]),
        .dbg_reg_wdata(dbg_wdata),
        .dbg_reg_rdata(cpu_dbg_reg_rdata),
        .pc_out(cpu_pc_out)
    );

    // ---------- IMem ----------
    inst_mem u_imem (
        .clk(clk),
        .pc(imem_addr), .inst(imem_rdata),
        .dbg_we(dbg_imem_we), .dbg_addr(dbg_addr),
        .dbg_wdata(dbg_wdata), .dbg_rdata(imem_dbg_rdata)
    );

    // ---------- DMem / MMIO address decode (架构 §7) ----------
    // Full 32-bit range compare avoids aliases like 0x00020000 hitting DMem
    // or 0xFFFF0000 hitting MMIO.
    wire sel_dmem = (cpu_dmem_addr[31:15] == 17'h00000);          // 0x0000_0000–0x0000_7FFF
    wire sel_mmio = (cpu_dmem_addr[31:4]  == 28'h0001000);        // 0x0001_0000–0x0001_000F

    wire [31:0] dmem_raw_rdata;
    wire [31:0] mmio_rdata;
    wire [7:0]  seg_int;

    data_mem u_dmem (
        .clk(clk),
        .cpu_we(cpu_dmem_we & sel_dmem),
        .addr(cpu_dmem_addr),
        .wdata(cpu_dmem_wdata),
        .byte_en(cpu_dmem_be),
        .rdata(dmem_raw_rdata),
        .dbg_we(dbg_dmem_we), .dbg_addr(dbg_addr),
        .dbg_wdata(dbg_wdata), .dbg_rdata(dmem_dbg_rdata)
    );

    // GPIO reset domain: board button only, NOT rst_cpu.
    // 架构 §9: UART `reset` command (-> dbg_reset) resets CPU core only;
    // it must not clear LED/seg state. Only the board reset button takes
    // GPIO down with the rest of the system.
    gpio u_gpio (
        .clk(clk), .rst(rst_from_btn),
        .sel(sel_mmio),
        .we(cpu_dmem_we & sel_mmio),
        .addr(cpu_dmem_addr),
        .wdata(cpu_dmem_wdata),
        .byte_en(cpu_dmem_be),
        .rdata(mmio_rdata),
        .sw(sw), .led(led),
        .seg(seg_int), .an(an)
    );

    // Fan out same segment value to both 4-digit display banks (DN0, DN1).
    // The active-HIGH digit-select an[7:0] ensures only one digit at a time
    // is lit, so broadcasting identical seg patterns is correct.
    assign seg0 = seg_int;
    assign seg1 = seg_int;

    // CPU-side dmem read mux: DMem | MMIO | 0
    assign cpu_dmem_rdata = sel_dmem ? dmem_raw_rdata
                          : sel_mmio ? mmio_rdata
                          :            32'h0000_0000;

    // ---------- UART placeholder ----------
    assign uart_tx = 1'b1;        // idle high

    // Silence "unused" warnings for inputs and debug rdata wires that have no
    // consumer until UART debug_ctrl is added. The OR collapse stays at 1-bit
    // and gets optimized away in synthesis.
    wire _unused_collapse = uart_rx
                          | (|btn)
                          | (|cpu_pc_out)
                          | (|cpu_dbg_reg_rdata)
                          | (|imem_dbg_rdata)
                          | (|dmem_dbg_rdata);
endmodule
