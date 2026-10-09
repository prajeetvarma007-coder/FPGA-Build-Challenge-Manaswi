# ============================================================
# Vivado Full Build Script - PYNQ-Z2
# Experiment 1: Automated Digital Circuit Tester
# Flow: Create Project -> Synthesis -> Implementation -> Bitstream
# Run: vivado -mode batch -source run_vivado_full.tcl
#
# NOTE for Experiment 2 (TrustFuse): copy this script, rename, and
# change project_name to "trustfuse" and src_dir to the
# Experiment-2-Beginner path below.
# ============================================================

set project_name "digital_circuit_tester"
set project_dir  "C:/Users/siddh/FPGA-Build-Challenge-Manaswi/vivado_project"
set src_dir      "C:/Users/siddh/FPGA-Build-Challenge-Manaswi/Experiment-1-Beginner"
set part         "xc7z020clg400-1"

puts "============================================"
puts " PYNQ-Z2 Full Build Flow"
puts " Part: $part"
puts "============================================"

# -- Step 1: Create Project --
puts "\n-- Step 1: Creating Vivado project..."
create_project $project_name $project_dir/$project_name -part $part -force
set_property target_language Verilog [current_project]
puts "   Done."

# -- Step 2: Add RTL Sources --
puts "\n-- Step 2: Adding RTL sources..."
add_files -norecurse [list "$src_dir/RTL/top_module.v"]
set_property top top_module [current_fileset]
puts "   Done."

# -- Step 3: Add Constraints --
puts "\n-- Step 3: Adding XDC constraints..."
add_files -fileset constrs_1 -norecurse "$src_dir/RTL/constraints.xdc"
puts "   Done."

# -- Step 4: Add Testbench --
puts "\n-- Step 4: Adding testbench..."
add_files -fileset sim_1 -norecurse "$src_dir/Testbench/tb_top.v"
set_property top tb_top [get_filesets sim_1]
puts "   Done."

# -- Step 5: Run Behavioral Simulation --
puts "\n-- Step 5: Running behavioral simulation..."
set_property -name {xsim.simulate.runtime} -value {200us} -objects [get_filesets sim_1]
launch_simulation
run 200us
close_sim
puts "   Simulation complete."

# -- Step 6: Run Synthesis --
puts "\n-- Step 6: Running Synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_prog   [get_property PROGRESS [get_runs synth_1]]
puts "   Synthesis status: $synth_status | Progress: $synth_prog"
if {$synth_prog != "100%"} {
    error "Synthesis FAILED. Check vivado_build.log for errors."
}
puts "   Synthesis COMPLETE."

# Open synthesized design and save reports
open_run synth_1 -name synth_1
report_utilization   -file "$src_dir/Simulation/synth_utilization.rpt"
report_timing_summary -file "$src_dir/Simulation/synth_timing.rpt" -warn_on_violation
puts "   Synthesis reports saved."

# -- Step 7: Run Implementation --
puts "\n-- Step 7: Running Implementation (Place and Route)..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_prog   [get_property PROGRESS [get_runs impl_1]]
puts "   Implementation status: $impl_status | Progress: $impl_prog"
if {$impl_prog != "100%"} {
    error "Implementation FAILED. Check vivado_build.log for errors."
}
puts "   Implementation COMPLETE."

open_run impl_1 -name impl_1
report_utilization   -file "$src_dir/Simulation/impl_utilization.rpt"
report_timing_summary -file "$src_dir/Simulation/impl_timing.rpt" -warn_on_violation
report_power         -file "$src_dir/Simulation/power_report.rpt"
puts "   Implementation reports saved."

# -- Step 8: Generate Bitstream --
puts "\n-- Step 8: Generating Bitstream (.bit)..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "   Bitstream generation COMPLETE."

# -- Step 9: Copy Bitstream to Bitstream/ folder --
puts "\n-- Step 9: Copying bitstream to output folder..."
set bit_src "$project_dir/$project_name/$project_name.runs/impl_1/top_module.bit"
set bit_dst "$src_dir/Bitstream"
file mkdir $bit_dst
if {[file exists $bit_src]} {
    file copy -force $bit_src "$bit_dst/top_module.bit"
    puts "   Bitstream saved: $bit_dst/top_module.bit"
} else {
    puts "   WARNING: Bitstream file not found at expected path: $bit_src"
    puts "   Searching..."
    set found [glob -nocomplain "$project_dir/$project_name/$project_name.runs/impl_1/*.bit"]
    if {[llength $found] > 0} {
        file copy -force [lindex $found 0] "$bit_dst/top_module.bit"
        puts "   Bitstream found and saved: $bit_dst/top_module.bit"
    }
}

# Copy LTX debug file if it exists
set ltx_src "$project_dir/$project_name/$project_name.runs/impl_1/top_module.ltx"
if {[file exists $ltx_src]} {
    file copy -force $ltx_src "$bit_dst/top_module.ltx"
    puts "   Debug probe file saved."
}

# -- Done --
puts "\n============================================"
puts " BUILD SUCCESSFUL!"
puts "============================================"
puts " Bitstream    : $bit_dst/top_module.bit"
puts " Util report  : $src_dir/Simulation/impl_utilization.rpt"
puts " Timing report: $src_dir/Simulation/impl_timing.rpt"
puts "============================================"
puts ""
puts " To program PYNQ-Z2 via Vivado Hardware Manager:"
puts "   open_hw_manager"
puts "   connect_hw_server"
puts "   open_hw_target"
puts "   program_hw_devices -file {$bit_dst/top_module.bit}"
puts "============================================"
