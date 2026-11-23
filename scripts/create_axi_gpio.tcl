# creates axi_gpio_0, AMD's AXI GPIO IP, used by rs32vi_top.sv

# AXI4-Lite slave, 9-bit address (registers at 0x000-0x00C)
# channel 1: 8 bits, all outputs   -> gpio_io_o   (OR'd onto the Au LEDs)
# channel 2: 24 bits, all inputs   -> gpio2_io_i  (Io DIP switch pins)

create_ip -name axi_gpio -vendor xilinx.com -library ip -module_name axi_gpio_0
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH     {8}  \
    CONFIG.C_ALL_OUTPUTS    {1}  \
    CONFIG.C_IS_DUAL        {1}  \
    CONFIG.C_GPIO2_WIDTH    {24} \
    CONFIG.C_ALL_INPUTS_2   {1}  \
    CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_ips axi_gpio_0]
generate_target all [get_ips axi_gpio_0]
puts "axi_gpio_0 created: channel 1 = 8 outputs, channel 2 = 24 inputs"
