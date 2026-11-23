// board top for the Alchitry Au (XC7A35T) + Io shield
//
//   rst_n button + MMCM "locked" -> synchronised reset -> soc
//   soc's external AXI4-Lite port -> AMD AXI GPIO (axi_gpio_0)
//       channel 1: 8 outputs, OR'd onto the Au LEDs
//       channel 2: 24 inputs, the Io DIP switch pins (raw: 0 = switch on)

module rs32vi_top #(
    parameter     MEM_FILE = "rs32vi/program.mem",
    parameter int CPU_HZ   = 100_000_000
) (
    input  logic            clk,        // 100 MHz
    input  logic            rst_n,      // Au reset button, active low
    input  logic            usb_rx,
    output logic            usb_tx,
    output logic [7:0]      led,        // Au LEDs
    output logic [2:0][7:0] io_led,
    input  logic [2:0][7:0] io_dip,
    input  logic [4:0]      io_button,
    output logic [3:0]      io_select,
    output logic [7:0]      io_segment
);

  // Clock
  logic cpu_clk, locked;

  clk_wiz_cpu clk_gen (
      .clk_in1 (clk),
      .clk_out1(cpu_clk),
      .locked  (locked)
  );

  // Reset - Asserts immediately  and is eleased synchronously to cpu_clk,
  // two cycles later, so every flip-flop
  // leaves reset on the same edge.

  logic       arst_n;
  logic [1:0] rst_sync;
  assign arst_n = rst_n & locked;

  always_ff @(posedge cpu_clk or negedge arst_n) begin
    if (!arst_n) rst_sync <= 2'b11;
    else rst_sync <= {rst_sync[0], 1'b0};
  end

  logic reset;
  assign reset = rst_sync[1];

  // system

  logic [7:0] soc_led, gpio_led;
  logic [31:0] ext_awaddr, ext_wdata, ext_araddr, ext_rdata;
  logic [3:0] ext_wstrb;
  logic [1:0] ext_bresp, ext_rresp;
  logic ext_awvalid, ext_awready, ext_wvalid, ext_wready, ext_bvalid, ext_bready;
  logic ext_arvalid, ext_arready, ext_rvalid, ext_rready;

  soc #(
      .MEM_FILE(MEM_FILE),
      .CLK_HZ(CPU_HZ),
      .BAUD(115_200)
  ) soc_i (
      .clk        (cpu_clk),
      .reset      (reset),
      .usb_rx     (usb_rx),
      .usb_tx     (usb_tx),
      .led        (soc_led),
      .io_led     (io_led),
      .io_dip     (io_dip),
      .io_button  (io_button),
      .io_select  (io_select),
      .io_segment (io_segment),
      .ext_awaddr (ext_awaddr),
      .ext_awvalid(ext_awvalid),
      .ext_awready(ext_awready),
      .ext_wdata  (ext_wdata),
      .ext_wstrb  (ext_wstrb),
      .ext_wvalid (ext_wvalid),
      .ext_wready (ext_wready),
      .ext_bresp  (ext_bresp),
      .ext_bvalid (ext_bvalid),
      .ext_bready (ext_bready),
      .ext_araddr (ext_araddr),
      .ext_arvalid(ext_arvalid),
      .ext_arready(ext_arready),
      .ext_rdata  (ext_rdata),
      .ext_rresp  (ext_rresp),
      .ext_rvalid (ext_rvalid),
      .ext_rready (ext_rready)
  );

  //  AMD AXI GPIO on the external AXI4-Lite port
  axi_gpio_0 gpio (
      .s_axi_aclk   (cpu_clk),
      .s_axi_aresetn(!reset),
      .s_axi_awaddr (ext_awaddr[8:0]),
      .s_axi_awvalid(ext_awvalid),
      .s_axi_awready(ext_awready),
      .s_axi_wdata  (ext_wdata),
      .s_axi_wstrb  (ext_wstrb),
      .s_axi_wvalid (ext_wvalid),
      .s_axi_wready (ext_wready),
      .s_axi_bresp  (ext_bresp),
      .s_axi_bvalid (ext_bvalid),
      .s_axi_bready (ext_bready),
      .s_axi_araddr (ext_araddr[8:0]),
      .s_axi_arvalid(ext_arvalid),
      .s_axi_arready(ext_arready),
      .s_axi_rdata  (ext_rdata),
      .s_axi_rresp  (ext_rresp),
      .s_axi_rvalid (ext_rvalid),
      .s_axi_rready (ext_rready),
      .gpio_io_o    (gpio_led),
      .gpio2_io_i   (io_dip)
  );

  assign led = soc_led | gpio_led;

endmodule
