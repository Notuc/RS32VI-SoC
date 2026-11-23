# creates the clk_wiz_cpu IP used by rs32vi_top.sv

# input : 100 MHz from the Au oscillator
# output: 25 MHz CPU clock (clk_out1) + locked; no reset input

# To change the CPU clock later: edit CPU_MHZ below, delete the IP, re-source
# this script, and set CPU_HZ in rs32vi_top.sv to the same value.

set CPU_MHZ 25.000

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_cpu
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ                {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  $CPU_MHZ \
    CONFIG.USE_RESET                   {false} \
    CONFIG.USE_LOCKED                  {true} \
] [get_ips clk_wiz_cpu]
generate_target all [get_ips clk_wiz_cpu]
puts "clk_wiz_cpu created: 100 MHz in, $CPU_MHZ MHz out"
