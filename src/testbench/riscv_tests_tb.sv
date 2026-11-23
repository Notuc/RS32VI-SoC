// riscv_tests_tb -- runs ONE riscv-tests program and reports PASS / FAIL.
//
// The program ends by storing to TOHOST
//     1              -> PASS
//     (n << 1) | 1   -> FAIL in test case n

`timescale 1ns / 1ps

`ifndef MEMFILE
`define MEMFILE "program.mem"
`endif
`ifndef MAX_CYCLES
`define MAX_CYCLES 200000
`endif

module riscv_tests_tb;

  localparam logic [31:0] TOHOST = 32'h1000_0000;

  logic clk = 0;
  logic reset = 1;


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
      .gpio2_io_i   (24'hFF_FFFF)
  );

  soc #(
      .MEM_FILE(`MEMFILE)
  ) dut (
      .clk(clk),
      .reset(reset),
      .usb_rx(1'b1),
      .usb_tx(),
      .led(),
      .io_led(),
      .io_dip({3{8'hFF}}),
      .io_button(5'b0),
      .io_select(),
      .io_segment(),
      .ext_awaddr(ext_awaddr),
      .ext_awvalid(ext_awvalid),
      .ext_awready(ext_awready),
      .ext_wdata(ext_wdata),
      .ext_wstrb(ext_wstrb),
      .ext_wvalid(ext_wvalid),
      .ext_wready(ext_wready),
      .ext_bresp(ext_bresp),
      .ext_bvalid(ext_bvalid),
      .ext_bready(ext_bready),
      .ext_araddr(ext_araddr),
      .ext_arvalid(ext_arvalid),
      .ext_arready(ext_arready),
      .ext_rdata(ext_rdata),
      .ext_rresp(ext_rresp),
      .ext_rvalid(ext_rvalid),
      .ext_rready(ext_rready)
  );

  always #5 clk = ~clk;  // 10 ns clock
  initial #12 reset = 0;

  int cycles = 0;

  always @(posedge clk)
    if (!reset) begin
      cycles <= cycles + 1;

      // a store to TOHOST ends the run
      if (dut.b_req && dut.b_write && dut.b_addr == TOHOST) begin
        $display("cycles=%0d instret=%0d CPI=%0.3f", dut.cpu_i.csr.mcycle, dut.cpu_i.csr.minstret,
                 real'(dut.cpu_i.csr.mcycle) / real'(dut.cpu_i.csr.minstret));
        if (dut.b_wdata == 32'd1) $display("PASS");
        else
          $display(
              "FAIL: test case %0d (tohost = 0x%h, pc = 0x%h)",
              dut.b_wdata >> 1,
              dut.b_wdata,
              dut.cpu_i.pc_mem
          );
        $finish;
      end

      if (cycles >= `MAX_CYCLES) begin
        $display("TIMEOUT after %0d cycles (pc = 0x%h)", cycles, dut.cpu_i.pc_ex);
        $finish;
      end
    end

endmodule
