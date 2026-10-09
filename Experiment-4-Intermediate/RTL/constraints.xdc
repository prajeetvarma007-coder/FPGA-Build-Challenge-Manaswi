## ============================================================
## PYNQ-Z2 Constraints File
## Project    : FAULTX - HIL Fault Injection
## Experiment : 4 (Intermediate)
## Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
## ============================================================

## System clock - 125 MHz
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 8.000 -waveform {0.000 4.000} [get_ports clk]

## BTN0 - reset
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports rst]

## BTN1/BTN2/BTN3 - fault target select (a / b / result)
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports target_a]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports target_b]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports target_result]

## SW0/SW1 - fault_type[1:0]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {fault_type[0]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {fault_type[1]}]

## LEDs - heartbeat/all-match + idx/first-mismatch-idx
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## Asynchronous/manual inputs - exclude from timing analysis
set_false_path -from [get_ports rst]
set_false_path -from [get_ports target_a]
set_false_path -from [get_ports target_b]
set_false_path -from [get_ports target_result]
set_false_path -from [get_ports {fault_type[*]}]
