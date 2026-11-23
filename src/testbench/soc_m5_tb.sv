// soc_m5_tb -- runs sw/c/stopwatch.c on the SoC (run with sw/run_soc_m5.sh).
//
// Acts as the user: presses buttons, types on the UART, flips switches.
// Checks that:
//   - the timer interrupt counts at 10 ms per step
//   - button interrupts start, stop, reset and lap the stopwatch
//   - UART receive interrupts handle the 's' and 'p' commands
//   - the main loop keeps mirroring the switches meanwhile
//
// Runs at 1 MHz / 62500 baud to keep the simulation short. The firmware reads
// the clock rate from IO_CLK_HZ, so the same program works on the board.

`timescale 1ns / 1ps

`ifndef MEMFILE
`define MEMFILE "program.mem"
`endif

module soc_m5_tb;

  localparam int  CLK_HZ       = 1_000_000;
  localparam int  BAUD         = 62_500;
  localparam int  CLKS_PER_BIT = CLK_HZ / BAUD;   // 16
  localparam int  TICK         = CLK_HZ / 100;    // 10 ms of cycles
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

  // buttons
  // hold long enough for the 10 ms debouncer, then release for as long
  task automatic press(input int b);
    io_button[b] = 1'b1;
    repeat (TICK + TICK / 2) @(posedge clk);
    io_button[b] = 1'b0;
    repeat (TICK + TICK / 2) @(posedge clk);
  endtask

  // helpers
  function automatic int bcd_to_int(input logic [15:0] v);
    return v[15:12] * 1000 + v[11:8] * 100 + v[7:4] * 10 + v[3:0];
  endfunction

  function automatic int shown();  // stopwatch in hundredths
    return bcd_to_int(dut.io.reg_display[15:0]);
  endfunction

  int errors = 0;
  task automatic check(bit ok, string what);
    if (ok) $display("ok    %s", what);
    else begin
      $display("FAIL  %s", what);
      errors++;
    end
  endtask

  int a, b, c, d;
  logic [15:0] frozen;

  initial begin
    repeat (5) @(posedge clk);
    reset = 0;

    // greeting
    wait_for_text("2 lap", 200_000);
    repeat (20 * 10 * CLKS_PER_BIT) @(posedge clk);  // rest of the line, then setup
    check(contains(rx_text, "rs32vi stopwatch"), "greeting printed");
    check(shown() == 0 && dut.io.reg_disp_ctrl[4:0] == 5'b01001, $sformatf(
          "display 00.00 with decimal point (DISP_CTRL = 0x%0h)", dut.io.reg_disp_ctrl[4:0]));

    // button 0 starts it; the timer interrupt counts exactly 1 per 10 ms
    press(0);
    check(led[1] == 1'b1, "button 0 interrupt: started (Au LED 1)");
    a = shown();
    repeat (20 * TICK) @(posedge clk);
    b = shown();
    check(b - a >= 19 && b - a <= 21, $sformatf(
          "timer interrupt: +%0d hundredths in 20 ticks (expect 20)", b - a));

    // the main loop keeps running: switches still reach the LEDs
    io_dip = ~24'h00_3C5A;
    repeat (2000) @(posedge clk);
    check(io_led == ~24'h00_3C5A, "main loop still mirrors the switches");

    // 's' over the UART (receive interrupt) stops it
    send_byte("s");
    wait_for_text("stopped", 40 * 10 * CLKS_PER_BIT);
    check(contains(rx_text, "stopped"), "UART interrupt: 's' stopped it");
    c = shown();
    repeat (5 * TICK) @(posedge clk);
    check(shown() == c && led[1] == 1'b0, "stopped: display frozen");
    frozen = dut.io.reg_display[15:0];

    // 'p' prints the same time, the loop count and the tick count
    send_byte("p");
    wait_for_text("ticks:", 100 * 10 * CLKS_PER_BIT);
    repeat (20 * 10 * CLKS_PER_BIT) @(posedge clk);
    check(contains(rx_text, $sformatf("time %02x.%02x  stopped", frozen[15:8], frozen[7:0])),
          $sformatf("'p' prints time %02x.%02x", frozen[15:8], frozen[7:0]));
    check(contains(rx_text, "main loops: ") && !contains(rx_text, "main loops: 0 "),
          "main loop count is non-zero");

    // 5. button 2 = lap (prints), button 1 = reset
    press(2);
    wait_for_text("lap ", 40 * 10 * CLKS_PER_BIT);
    check(contains(rx_text, $sformatf("lap %02x.%02x", frozen[15:8], frozen[7:0])),
          "button 2 interrupt: lap printed");
    press(1);
    check(shown() == 0, "button 1 interrupt: reset to 00.00");
    check(led[7:4] == 4'd3, $sformatf(
          "Au LEDs 7..4 count the 3 button presses (shows %0d)", led[7:4]));

    // start again from the UART and make sure it counts
    send_byte("s");
    repeat (10 * TICK) @(posedge clk);
    d = shown();
    check(d >= 8 && d <= 11, $sformatf("restarted from UART: %0d hundredths after ~10 ticks", d));

    $display("");
    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d check(s)", errors);
    $finish;
  end

  initial begin
    #2_000_000_000;  // 2 s of simulated time
    $display("TIMEOUT");
    $finish;
  end

endmodule
