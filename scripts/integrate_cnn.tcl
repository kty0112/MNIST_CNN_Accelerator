##########################################################################
## CNN MNIST Integration into Pcam Block Design
## Pcam 2023.1 프로젝트를 새 위치에 복사 후 CNN IP 추가
##########################################################################

set pcam_source  "/home/hyeonjun/pcam_2023/hw"
set new_proj_dir "/home/hyeonjun/cnn_pcam_project"
set ip_repo_path "/home/hyeonjun/claude_test/cnn_vhdl/ip_repo/cnn_mnist_ip"

# 1. Open existing Pcam 2023.1 project and save as new project
open_project $pcam_source/hw.xpr
save_project_as cnn_pcam $new_proj_dir -force
close_project

# 2. Open the new project
open_project $new_proj_dir/cnn_pcam.xpr

# 3. Add CNN IP to repository path
set existing_repos [get_property ip_repo_paths [current_project]]
lappend existing_repos $ip_repo_path
set_property ip_repo_paths $existing_repos [current_project]
update_ip_catalog

# 4. Open Block Design
open_bd_design [get_files system.bd]

# Upgrade any locked IPs (2023.1 -> 2023.2)
set locked_ips [get_ips -filter {IS_LOCKED==1} -quiet]
if {[llength $locked_ips] > 0} {
    upgrade_ip $locked_ips
    puts "Upgraded [llength $locked_ips] locked IPs"
}

# 5. Add CNN IP
create_bd_cell -type ip -vlnv user.org:user:cnn_mnist_ip:1.0 cnn_mnist_0

# 6. Disconnect GammaCorrection -> VDMA direct link
delete_bd_objs [get_bd_intf_nets AXI_GammaCorrection_0_m_axis_video]

# 7. Add AXI4-Stream Broadcaster (1-to-2 split)
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 axis_broadcaster_0
set_property -dict [list \
    CONFIG.M_TDATA_NUM_BYTES {3} \
    CONFIG.S_TDATA_NUM_BYTES {3} \
    CONFIG.NUM_MI {2} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
] [get_bd_cells axis_broadcaster_0]

# 8. Reconnect: GammaCorrection -> Broadcaster -> VDMA + CNN
connect_bd_intf_net [get_bd_intf_pins AXI_GammaCorrection_0/m_axis_video] \
                    [get_bd_intf_pins axis_broadcaster_0/S_AXIS]

connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M00_AXIS] \
                    [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]

connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M01_AXIS] \
                    [get_bd_intf_pins cnn_mnist_0/s_axis]

# 9. Expand AXI peripheral interconnect for CNN AXI-Lite
set num_mi [get_property CONFIG.NUM_MI [get_bd_cells ps7_0_axi_periph]]
set new_mi [expr {$num_mi + 1}]
set_property CONFIG.NUM_MI $new_mi [get_bd_cells ps7_0_axi_periph]

set mi_idx [expr {$new_mi - 1}]
set mi_name "M[format %02d $mi_idx]_AXI"
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/$mi_name] \
                    [get_bd_intf_pins cnn_mnist_0/S_AXI]

# 10. Connect clocks
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins axis_broadcaster_0/aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins cnn_mnist_0/aclk]

# 11. Connect resets
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axis_broadcaster_0/aresetn]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins cnn_mnist_0/aresetn]

# 12. Connect interconnect new master port clock/reset
set mi_clk_name "M[format %02d $mi_idx]_ACLK"
set mi_rst_name "M[format %02d $mi_idx]_ARESETN"
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins ps7_0_axi_periph/$mi_clk_name]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/$mi_rst_name]

# 13. Make prediction/probability external for LED/debug
make_bd_pins_external [get_bd_pins cnn_mnist_0/prediction_out]
make_bd_pins_external [get_bd_pins cnn_mnist_0/probability_out]

# 14. Assign address
assign_bd_address [get_bd_addr_segs cnn_mnist_0/S_AXI/reg0]

# 15. Validate and save
validate_bd_design
save_bd_design

# 16. Generate output products
generate_target all [get_files system.bd]

# 17. Create HDL wrapper
make_wrapper -files [get_files system.bd] -top
set wrapper_file [glob $new_proj_dir/cnn_pcam.gen/sources_1/bd/system/hdl/system_wrapper.*]
add_files -norecurse $wrapper_file

puts "============================================="
puts "  CNN integrated into Pcam Block Design!"
puts "  Project: $new_proj_dir/cnn_pcam.xpr"
puts "============================================="
puts ""
puts "Open in Vivado GUI to verify, then:"
puts "  1. Run Synthesis"
puts "  2. Run Implementation"
puts "  3. Generate Bitstream"
puts "  4. Export Hardware (.xsa) for Vitis"
