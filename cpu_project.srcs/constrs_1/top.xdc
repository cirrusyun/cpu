## EGO1 board constraints for cpu_project / TopDebug
## Pin assignments per Ego1_UserManual_v2.2

## ---------- Clock ----------
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 10.0 -waveform {0 5} [get_ports clk]

## ---------- Reset (dedicated FPGA_RESET button, active-LOW) ----------
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports fpga_rst_n]

## ---------- Switches: 8 拨码 (SW_0..SW_7) + 8 DIP (SW8.0..SW8.7) = 16 ----------
set_property -dict { PACKAGE_PIN R1  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN N4  IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN M4  IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN R2  IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN P2  IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN P4  IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN P5  IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN T5  IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN T3  IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN R3  IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN V4  IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN V5  IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN V2  IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN U2  IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]

## ---------- General-purpose buttons PB0..PB4 (active HIGH; reserved) ----------
set_property -dict { PACKAGE_PIN R11 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN V1  IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]
set_property -dict { PACKAGE_PIN U4  IOSTANDARD LVCMOS33 } [get_ports {btn[4]}]

## ---------- LEDs (16, active HIGH) ----------
set_property -dict { PACKAGE_PIN K3  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN M1  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN K6  IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN J4  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## ---------- 7-segment displays (common cathode, active HIGH) ----------
## Two 4-digit groups DN0/DN1, each with own 8-bit segment bus.
## seg0[*] = DN0; seg1[*] = DN1; both wired to identical signal in TopDebug.
## Bit order: [0]=A [1]=B [2]=C [3]=D [4]=E [5]=F [6]=G [7]=DP
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports {seg0[0]}]
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports {seg0[1]}]
set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports {seg0[2]}]
set_property -dict { PACKAGE_PIN B1  IOSTANDARD LVCMOS33 } [get_ports {seg0[3]}]
set_property -dict { PACKAGE_PIN A1  IOSTANDARD LVCMOS33 } [get_ports {seg0[4]}]
set_property -dict { PACKAGE_PIN B3  IOSTANDARD LVCMOS33 } [get_ports {seg0[5]}]
set_property -dict { PACKAGE_PIN B2  IOSTANDARD LVCMOS33 } [get_ports {seg0[6]}]
set_property -dict { PACKAGE_PIN D5  IOSTANDARD LVCMOS33 } [get_ports {seg0[7]}]

set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports {seg1[0]}]
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports {seg1[1]}]
set_property -dict { PACKAGE_PIN D3  IOSTANDARD LVCMOS33 } [get_ports {seg1[2]}]
set_property -dict { PACKAGE_PIN F4  IOSTANDARD LVCMOS33 } [get_ports {seg1[3]}]
set_property -dict { PACKAGE_PIN F3  IOSTANDARD LVCMOS33 } [get_ports {seg1[4]}]
set_property -dict { PACKAGE_PIN E2  IOSTANDARD LVCMOS33 } [get_ports {seg1[5]}]
set_property -dict { PACKAGE_PIN D2  IOSTANDARD LVCMOS33 } [get_ports {seg1[6]}]
set_property -dict { PACKAGE_PIN H2  IOSTANDARD LVCMOS33 } [get_ports {seg1[7]}]

## ---------- Digit select (active HIGH); an[0]=LSB digit (rightmost) ----------
## an[0]->BIT8 (rightmost of DN1) ... an[7]->BIT1 (leftmost of DN0)
## so value[3:0] shows on rightmost digit.
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports {an[0]}]   ;# BIT8 = DN1_K4
set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports {an[1]}]   ;# BIT7 = DN1_K3
set_property -dict { PACKAGE_PIN F1  IOSTANDARD LVCMOS33 } [get_ports {an[2]}]   ;# BIT6 = DN1_K2
set_property -dict { PACKAGE_PIN G1  IOSTANDARD LVCMOS33 } [get_ports {an[3]}]   ;# BIT5 = DN1_K1
set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports {an[4]}]   ;# BIT4 = DN0_K4
set_property -dict { PACKAGE_PIN C1  IOSTANDARD LVCMOS33 } [get_ports {an[5]}]   ;# BIT3 = DN0_K3
set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports {an[6]}]   ;# BIT2 = DN0_K2
set_property -dict { PACKAGE_PIN G2  IOSTANDARD LVCMOS33 } [get_ports {an[7]}]   ;# BIT1 = DN0_K1

## ---------- UART (USB-UART/JTAG via Type-C) ----------
## Manual labels are from the host/FT232 perspective:
##   "UART_RX" line on T4 = data going TO host = FPGA's TX
##   "UART_TX" line on N5 = data coming FROM host = FPGA's RX
set_property -dict { PACKAGE_PIN T4  IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN N5  IOSTANDARD LVCMOS33 } [get_ports uart_rx]

## ---------- Bitstream / SPI flash settings ----------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
