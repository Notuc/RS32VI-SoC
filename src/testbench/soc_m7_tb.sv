// soc_m7_tb -- runs sw/c/axi_gpio.c on the SoC (run with sw/run_soc_m7.sh).
//
// The external AXI port has axi_gpio_model, a stand-in for AMD's AXI GPIO that
// delays every handshake by 0-3 random cycles.
//
// Checks that:
//   - switches read through the GPIO reach the Io LEDs and display
//   - io_regs and the GPIO give the same switch reading
//   - the counter written through the GPIO reaches its output pins
//   - one AXI load counts as one instruction (minstret)
//   - the AXI checkers saw transfers and no violations
//
// Runs at 1 MHz / 62500 baud to keep the simulation short.

`timescale 1ns / 1ps

`ifndef MEMFILE
`define MEMFILE "program.mem"
`endif

module soc_m7_tb;

  localparam int  CLK_HZ       = 1_000_000;
  localparam int  BAUD         = 62_500;
  localparam int  CLKS_PER_BIT = CLK_HZ / BAUD;
  localparam real CLK_NS       = 1.0e9 / CLK_HZ;

  logic clk = 0, reset = 1;
  logic usb_rx = 1, usb_tx;
  logic [7:0]      led;
  logic [2:0][7:0] io_led;
  logic [2:0][7:0] io_dip = {3{8'hFF}};
  logic [4:0]      io_button = '0;
  logic [3:0]      io_select;
  logic [7:0]      io_segment;

  // external AXI4-Lite slave: model of AMD's AXI GPIO (random handshake delays)
  logic [31:0] ext_awaddr, ext_wdata, ext_araddr, ext_rdata;
  logic [3:0] ext_wstrb;
  logic [1:0] ext_bresp, ext_rresp;
  logic ext_awvalid, ext_awready, ext_wvalid, ext_wready, ext_bvalid, ext_bready;
  logic ext_arvalid, ext_arready, ext_rvalid, ext_rready;
  logic [7:0] gpio_out;
  axi_gpio_model #(
      .RANDOM_DELAYS(1),
      .SEED(7)
  ) gpio (
      .s_axi_aclk   (clk),
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
      .gpio_io_o    (gpio_out),
      .gpio2_io_i   (io_dip)
  );

  soc #(
      .MEM_FILE(`MEMFILE),
      .CLK_HZ(CLK_HZ),
      .BAUD(BAUD)
  ) dut (
      .*
  );

  always #(CLK_NS / 2) clk = ~clk;

  // terminal
  string rx_text = "";
  initial begin : uart_monitor
    logic [7:0] b;
    forever begin
      @(negedge usb_tx);
      repeat (CLKS_PER_BIT + CLKS_PER_BIT / 2) @(posedge clk);
      for (int i = 0; i < 8; i++) begin
        b[i] = usb_tx;
        repeat (CLKS_PER_BIT) @(posedge clk);
      end
      if (b == 8'h0A) $display("  uart| %s", last_line());
      if (b != 8'h0D) rx_text = {rx_text, string'(b)};
    end
  end

  function automatic string last_line();
    int i = rx_text.len() - 1;
    while (i >= 0 && rx_text[i] != 8'h0A) i--;
    return rx_text.substr(i + 1, rx_text.len() - 1);
  endfunction

  task automatic send_byte(input logic [7:0] b);
    usb_rx = 0;
    repeat (CLKS_PER_BIT) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
      usb_rx = b[i];
      repeat (CLKS_PER_BIT) @(posedge clk);
    end
    usb_rx = 1;
    repeat (CLKS_PER_BIT) @(posedge clk);
  endtask

  function automatic bit contains(string hay, string needle);
    if (needle.len() > hay.len()) return 0;
    for (int i = 0; i + needle.len() <= hay.len(); i++)
    if (hay.substr(i, i + needle.len() - 1) == needle) return 1;
    return 0;
  endfunction

  task automatic wait_for_text(string needle, int max_cycles);
    int n = 0;
    while (!contains(
        rx_text, needle
    ) && n < max_cycles) begin
      @(posedge clk);
      n++;
    end
  endtask

  int errors = 0;
  task automatic check(bit ok, string what);
    if (ok) $display("ok    %s", what);
    else begin
      $display("FAIL  %s", what);
      errors++;
    end
  endtask

  localparam logic [23:0] SW = 24'h3C_A5C3;
  logic [7:0] g0, g1;

  initial begin
    repeat (5) @(posedge clk);
    reset = 0;

    wait_for_text("> ", 200_000);
    check(contains(rx_text, "AMD AXI GPIO at 0x20004000"), "greeting printed");
    check(contains(rx_text, "bus instret check: ok"), "one AXI load counts as one instruction");

    // switches -> AMD GPIO channel 2 -> firmware -> Io LEDs and display
    io_dip = ~SW;
    repeat (3000) @(posedge clk);
    check(io_led == ~SW, "switches read through AMD GPIO reach the Io LEDs");
    check(dut.io.reg_display[15:0] == SW[15:0], "... and the display");

    // Enter: both readings printed, and they agree
    send_byte(8'h0D);
    wait_for_text("mismatches so far", 120 * 10 * CLKS_PER_BIT);
    repeat (20 * 10 * CLKS_PER_BIT) @(posedge clk);
    check(contains(rx_text, "io_regs: 0x003CA5C3  axi_gpio: 0x003CA5C3  match"),
          "io_regs and AMD GPIO read the same switches");
    check(contains(rx_text, "mismatches so far: 0"), "no mismatches");

    // counter written through AMD GPIO channel 1 reaches its pins
    g0 = gpio_out;
    repeat (CLK_HZ / 8 + 2000) @(posedge clk);
    g1 = gpio_out;
    check(g1 != g0 && g1 != 8'h00, $sformatf("AMD GPIO outputs count: %0d -> %0d", g0, g1));

    // traffic really went over the bus, with no protocol violation
    check(dut.chk_master.transfers > 1000, $sformatf(
          "%0d AXI transfers from the CPU, no protocol violation", dut.chk_master.transfers));
    check(dut.chk_ext.transfers > 300, $sformatf(
          "%0d AXI transfers to the AMD GPIO (random delays)", dut.chk_ext.transfers));

    $display("");
    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d check(s)", errors);
    $finish;
  end

  initial begin
    #2_000_000_000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
