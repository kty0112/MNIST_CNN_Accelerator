##########################################################################
## CNN MNIST IP Packaging Script
## cnn_pcam_wrapper를 Vivado Custom IP로 패키징
##########################################################################

set ip_name "cnn_mnist_ip"
set ip_dir  "[file dirname [info script]]/$ip_name"
set proj_dir "[file dirname [info script]]/package_project"

# 1. Create temporary project for packaging
create_project $ip_name $proj_dir -part xc7z020clg400-1 -force
set_property target_language VHDL [current_project]

# 2. Add all source files
set src_files [glob -directory "$ip_dir/src" *.vhd]
foreach f $src_files {
    add_files -norecurse $f
}

# Set top module
set_property top cnn_pcam_wrapper [current_fileset]
update_compile_order -fileset sources_1

# 3. Package IP
ipx::package_project -root_dir $ip_dir -vendor user.org -library user -taxonomy /UserIP -force

# 4. Set IP metadata
set_property vendor        "user.org"          [ipx::current_core]
set_property library       "user"              [ipx::current_core]
set_property name          "cnn_mnist_ip"      [ipx::current_core]
set_property version       "1.0"               [ipx::current_core]
set_property display_name  "CNN MNIST Digit Recognition" [ipx::current_core]
set_property description   "MNIST digit recognition CNN with AXI Stream input and AXI-Lite result output. LeNet-style 3-layer CNN for Zybo Z7-20." [ipx::current_core]
set_property company_url   "https://github.com/squid55/CNN-VHDL-MNIST" [ipx::current_core]

# 5. Set supported device families
set_property supported_families {zynq Production} [ipx::current_core]

# 6. Identify and configure AXI Stream Slave interface
# Remove auto-detected interfaces and recreate properly
# AXI Stream Slave
if {[llength [ipx::get_bus_interfaces s_axis -of_objects [ipx::current_core] -quiet]] == 0} {
    ipx::add_bus_interface s_axis [ipx::current_core]
}
set axis_intf [ipx::get_bus_interfaces s_axis -of_objects [ipx::current_core]]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $axis_intf
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $axis_intf
set_property interface_mode slave $axis_intf

# Map AXI Stream ports
ipx::add_port_map TDATA  $axis_intf
set_property physical_name s_axis_tdata  [ipx::get_port_maps TDATA  -of_objects $axis_intf]
ipx::add_port_map TVALID $axis_intf
set_property physical_name s_axis_tvalid [ipx::get_port_maps TVALID -of_objects $axis_intf]
ipx::add_port_map TREADY $axis_intf
set_property physical_name s_axis_tready [ipx::get_port_maps TREADY -of_objects $axis_intf]
ipx::add_port_map TLAST  $axis_intf
set_property physical_name s_axis_tlast  [ipx::get_port_maps TLAST  -of_objects $axis_intf]
ipx::add_port_map TUSER  $axis_intf
set_property physical_name s_axis_tuser  [ipx::get_port_maps TUSER  -of_objects $axis_intf]

# Associate clock with AXI Stream
ipx::associate_bus_interfaces -busif s_axis -clock aclk [ipx::current_core]

# 7. Configure AXI-Lite Slave interface
if {[llength [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core] -quiet]] == 0} {
    ipx::add_bus_interface S_AXI [ipx::current_core]
}
set axilite_intf [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $axilite_intf
set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 $axilite_intf
set_property interface_mode slave $axilite_intf

# Map AXI-Lite ports
foreach {logical physical} {
    ARADDR  S_AXI_ARADDR
    ARVALID S_AXI_ARVALID
    ARREADY S_AXI_ARREADY
    RDATA   S_AXI_RDATA
    RRESP   S_AXI_RRESP
    RVALID  S_AXI_RVALID
    RREADY  S_AXI_RREADY
    AWADDR  S_AXI_AWADDR
    AWVALID S_AXI_AWVALID
    AWREADY S_AXI_AWREADY
    WDATA   S_AXI_WDATA
    WSTRB   S_AXI_WSTRB
    WVALID  S_AXI_WVALID
    WREADY  S_AXI_WREADY
    BRESP   S_AXI_BRESP
    BVALID  S_AXI_BVALID
    BREADY  S_AXI_BREADY
} {
    ipx::add_port_map $logical $axilite_intf
    set_property physical_name $physical [ipx::get_port_maps $logical -of_objects $axilite_intf]
}

# Associate clock with AXI-Lite
ipx::associate_bus_interfaces -busif S_AXI -clock aclk [ipx::current_core]

# 8. Set memory map for AXI-Lite (3 registers: 0x00, 0x04, 0x08)
ipx::add_memory_map S_AXI [ipx::current_core]
set_property slave_memory_map_ref S_AXI [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
ipx::add_address_block reg0 [ipx::get_memory_maps S_AXI -of_objects [ipx::current_core]]
set_property range 16 [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps S_AXI -of_objects [ipx::current_core]]]

# 9. Configure reset interface
if {[llength [ipx::get_bus_interfaces aresetn -of_objects [ipx::current_core] -quiet]] == 0} {
    ipx::add_bus_interface aresetn [ipx::current_core]
}
set rst_intf [ipx::get_bus_interfaces aresetn -of_objects [ipx::current_core]]
set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 $rst_intf
set_property bus_type_vlnv xilinx.com:signal:reset:1.0 $rst_intf
set_property interface_mode slave $rst_intf
ipx::add_port_map RST $rst_intf
set_property physical_name aresetn [ipx::get_port_maps RST -of_objects $rst_intf]
set_property VALUE ACTIVE_LOW [ipx::get_bus_parameters POLARITY -of_objects $rst_intf]

# 10. Configure clock interface
if {[llength [ipx::get_bus_interfaces aclk -of_objects [ipx::current_core] -quiet]] == 0} {
    ipx::add_bus_interface aclk [ipx::current_core]
}
set clk_intf [ipx::get_bus_interfaces aclk -of_objects [ipx::current_core]]
set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 $clk_intf
set_property bus_type_vlnv xilinx.com:signal:clock:1.0 $clk_intf
set_property interface_mode slave $clk_intf
ipx::add_port_map CLK $clk_intf
set_property physical_name aclk [ipx::get_port_maps CLK -of_objects $clk_intf]

# Associate reset with clock
ipx::associate_bus_interfaces -busif aresetn -clock aclk [ipx::current_core]

# 11. Save and package
set_property core_revision 1 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]

puts "============================================="
puts "  IP Packaged: $ip_dir"
puts "  Add to IP Repo path in Vivado settings"
puts "============================================="

close_project
