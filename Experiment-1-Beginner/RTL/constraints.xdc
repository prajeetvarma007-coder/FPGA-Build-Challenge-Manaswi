## ============================================================
## PYNQ-Z2 Constraints File
## Project    : Automated Digital Circuit Tester
## Experiment : 1 (Beginner)
## Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
## ============================================================

## System clock - 125 MHz
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 8.000 -waveform {0.000 4.000} [get_ports clk]

## BTN0 - reset
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports rst]

## BTN1 - start / restart test
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports start]

## LEDs - status display
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## Asynchronous/manual inputs - exclude from timing analysis
set_false_path -from [get_ports rst]
set_false_path -from [get_ports start]
