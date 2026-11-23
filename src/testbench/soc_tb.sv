// soc_tb -- runs sw/c/io_demo.c on the SoC (run with sw/run_soc.sh).
//
// Acts as the PC terminal and the board's switches. Checks that:
//   - the greeting arrives over the UART
//   - the switches show up on the Io LEDs and the display
//   - a typed 'x' is echoed back
//   - Enter prints the "switches = 0x..." line
//
// Runs at 25 MHz / 115200 baud, so the UART bit timing is realistic.

`timescale 1ns / 1ps

`ifndef MEMFILE
`define MEMFILE "program.mem"
`endif

module soc_tb;

  localparam int  CLK_HZ       = 25_000_000;
  localparam int  BAUD         = 115_200;
  localparam int  CLKS_PER_BIT = CLK_HZ / BAUD;   // same formula as uart_tx/rx
  localparam real CLK_NS       = 1.0e9 / CLK_HZ;  // 40 ns

  logic clk = 0, reset = 1;
  logic usb_rx = 1, usb_tx;
  logic [7:0]      led;
  logic [2:0][7:0] io_led;
  logic [2:0][7:0] io_dip = {3{8'hFF}};  // all switches off (active low)
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
  axi_gpio_model gpio (
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

  // terminal: receive what the CPU prints
  string rx_text = "";

  initial begin : uart_monitor
    logic [7:0] b;
    forever begin
      @(negedge usb_tx);  // start bit
      repeat (CLKS_PER_BIT + CLKS_PER_BIT / 2) @(posedge clk);
      for (int i = 0; i < 8; i++) begin
        b[i] = usb_tx;
        repeat (CLKS_PER_BIT) @(posedge clk);
      end
      if (b == 8'h0A) $display("  uart| %s", rx_text_line());
      if (b != 8'h0D) rx_text = {rx_text, string'(b)};
    end
  end

  // the current (last) line of the received text, for printing
  function automatic string rx_text_line();
    int i = rx_text.len() - 1;
    while (i >= 0 && rx_text[i] != 8'h0A) i--;
    return rx_text.substr(i + 1, rx_text.len() - 1);
  endfunction

  // terminal: type a character
  task automatic send_byte(input logic [7:0] b);
    usb_rx = 0;  // start bit
    repeat (CLKS_PER_BIT) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
      usb_rx = b[i];
      repeat (CLKS_PER_BIT) @(posedge clk);
    end
    usb_rx = 1;  // stop bit
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

  // test 
  localparam logic [23:0] SW = 24'h5A_A5C3;

  int len_before;

  initial begin
    repeat (5) @(posedge clk);
    reset = 0;

    // greeting
    wait_for_text("> ", 200_000);
    check(contains(rx_text, "hello, rs32vi"), "greeting printed");
    check(contains(rx_text, "clock: 25000000 Hz"), "clock frequency printed");

    // switches -> LEDs and display
    io_dip = ~SW;  // switches are active low
    repeat (2000) @(posedge clk);
    check(io_led == ~SW, "Io LED pins mirror the switches");
    check(dut.io.reg_display[15:0] == SW[15:0], "display register shows switches[15:0]");
    check(dut.io.reg_disp_ctrl[0] == 1'b1, "display enabled");
    check(io_select != 4'b1111, "a display digit is being driven");

    // echo
    len_before = rx_text.len();
    begin
      send_byte("x");
      wait_for_text("> x", 20 * CLKS_PER_BIT);
      repeat (3 * 10 * CLKS_PER_BIT) @(posedge clk);  // room for any extra echoes
      check(rx_text.len() == len_before + 1 && rx_text[len_before] == "x",
            "typed 'x' is echoed exactly once");
    end

    // Enter prints the switch value
    send_byte(8'h0D);
    wait_for_text("switches = 0x005AA5C3", 40 * 10 * CLKS_PER_BIT);
    check(contains(rx_text, "switches = 0x005AA5C3"), "Enter prints the switch value");
    repeat (6 * 10 * CLKS_PER_BIT) @(posedge clk);  // let the rest of the line arrive

    $display("");
    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d check(s)", errors);
    $finish;
  end

  initial begin
    #50_000_000;  // 50 ms
    $display("TIMEOUT");
    $finish;
  end

endmodule
