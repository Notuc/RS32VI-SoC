// soc -- rs32vi SoC: CPU, 64 KB RAM, and AXI4-Lite peripherals.
//
// RAM is on the CPU's direct data port. Everything else goes through
// axil_master_bridge -> axil_interconnect -> one slave per region.
//
// Memory map (keep in sync with sw/include/rs32vi.h):
//   0x0000_0000  RAM (64 KB): code, data, stack
//   0x1000_0000  tohost: ends the simulation; unmapped on the board
//   0x2000_0000  io_regs: LEDs, display, switches, buttons
//   0x2000_1000  uart_periph
//   0x2000_2000  timer: mtime, mtimecmp, msip
//   0x2000_3000  irq_ctrl
//   0x2000_4000  external AXI port (AMD axi_gpio on the board)
//   other        default slave: reads 0, writes ignored
//
// RAM loads/stores are sent from EX. Bus accesses are sent from the MEM stage
// registers and stall the pipeline (bus_wait) until the AXI response.

module soc #(
    parameter     MEM_FILE  = "program.mem",
    parameter int RAM_WORDS = 16384,          // 64 KB
    parameter int CLK_HZ    = 25_000_000,     // must match the real CPU clock
    parameter int BAUD      = 115_200
) (
    input logic clk,
    input logic reset,

    input  logic            usb_rx,
    output logic            usb_tx,
    output logic [7:0]      led,
    output logic [2:0][7:0] io_led,
    input  logic [2:0][7:0] io_dip,
    input  logic [4:0]      io_button,
    output logic [3:0]      io_select,
    output logic [7:0]      io_segment,

    // external AXI4-Lite slave at 0x2000_4000 (AMD AXI GPIO on the board)
    output logic [31:0] ext_awaddr,
    output logic        ext_awvalid,
    input  logic        ext_awready,
    output logic [31:0] ext_wdata,
    output logic [ 3:0] ext_wstrb,
    output logic        ext_wvalid,
    input  logic        ext_wready,
    input  logic [ 1:0] ext_bresp,
    input  logic        ext_bvalid,
    output logic        ext_bready,
    output logic [31:0] ext_araddr,
    output logic        ext_arvalid,
    input  logic        ext_arready,
    input  logic [31:0] ext_rdata,
    input  logic [ 1:0] ext_rresp,
    input  logic        ext_rvalid,
    output logic        ext_rready
);

  // CPU
  logic [31:0] imem_addr, imem_rdata;
  logic imem_en;
  logic [31:0] d_addr, d_wdata, d_rdata;  // RAM data port (EX)
  logic [3:0] d_be;
  logic b_req, b_write, b_wait;  // bus port (MEM)
  logic [31:0] b_addr, b_wdata, b_rdata;
  logic [ 3:0] b_be;
  logic [63:0] mtime;
  logic irq_mtip, irq_msip, irq_meip;

  cpu cpu_i (
      .clk       (clk),
      .reset     (reset),
      .imem_addr (imem_addr),
      .imem_en   (imem_en),
      .imem_rdata(imem_rdata),
      .dmem_addr (d_addr),
      .dmem_be   (d_be),
      .dmem_wdata(d_wdata),
      .dmem_rdata(d_rdata),
      .bus_req   (b_req),
      .bus_write (b_write),
      .bus_addr  (b_addr),
      .bus_be    (b_be),
      .bus_wdata (b_wdata),
      .bus_wait  (b_wait),
      .bus_rdata (b_rdata),
      .irq_msip  (irq_msip),
      .irq_mtip  (irq_mtip),
      .irq_meip  (irq_meip),
      .mtime     (mtime)
  );

  // RAM
  // The CPU only sends RAM accesses here (bus ones come from MEM on b_*),
  // so the RAM's write enable is just the CPU's byte enables.

  unified_ram #(
      .WORDS(RAM_WORDS),
      .MEM_FILE(MEM_FILE)
  ) ram (
      .clk    (clk),
      .a_en   (imem_en),
      .a_addr (imem_addr),
      .a_rdata(imem_rdata),
      .b_addr (d_addr),
      .b_be   (d_be),
      .b_wdata(d_wdata),
      .b_rdata(d_rdata)
  );

  // AXI4-Lite master
  logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
  logic [2:0] m_awprot, m_arprot;
  logic [3:0] m_wstrb;
  logic [1:0] m_bresp, m_rresp;
  logic m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
  logic m_arvalid, m_arready, m_rvalid, m_rready;

  axil_master_bridge bridge (
      .clk      (clk),
      .reset    (reset),
      .cpu_req  (b_req),
      .cpu_write(b_write),
      .cpu_addr (b_addr),
      .cpu_be   (b_be),
      .cpu_wdata(b_wdata),
      .cpu_wait (b_wait),
      .cpu_rdata(b_rdata),
      .m_awaddr (m_awaddr),
      .m_awprot (m_awprot),
      .m_awvalid(m_awvalid),
      .m_awready(m_awready),
      .m_wdata  (m_wdata),
      .m_wstrb  (m_wstrb),
      .m_wvalid (m_wvalid),
      .m_wready (m_wready),
      .m_bresp  (m_bresp),
      .m_bvalid (m_bvalid),
      .m_bready (m_bready),
      .m_araddr (m_araddr),
      .m_arprot (m_arprot),
      .m_arvalid(m_arvalid),
      .m_arready(m_arready),
      .m_rdata  (m_rdata),
      .m_rresp  (m_rresp),
      .m_rvalid (m_rvalid),
      .m_rready (m_rready)
  );

  // interconnect
  localparam int N = 5;

  // [4] ext [3] irq [2] timer [1] uart [0] io
  localparam logic [N*32-1:0] BASE = {
    32'h2000_4000, 32'h2000_3000, 32'h2000_2000, 32'h2000_1000, 32'h2000_0000
  };
  localparam logic [N*32-1:0] MASK = {5{32'hFFFF_F000}};

  logic [N*32-1:0] s_awaddr, s_wdata, s_araddr, s_rdata;
  logic [N*3-1:0] s_awprot, s_arprot;
  logic [N*4-1:0] s_wstrb;
  logic [N*2-1:0] s_bresp, s_rresp;
  logic [N-1:0] s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
  logic [N-1:0] s_arvalid, s_arready, s_rvalid, s_rready;

  axil_interconnect #(
      .N(N),
      .BASE(BASE),
      .MASK(MASK)
  ) xbar (
      .clk      (clk),
      .reset    (reset),
      .s_awaddr (m_awaddr),
      .s_awprot (m_awprot),
      .s_awvalid(m_awvalid),
      .s_awready(m_awready),
      .s_wdata  (m_wdata),
      .s_wstrb  (m_wstrb),
      .s_wvalid (m_wvalid),
      .s_wready (m_wready),
      .s_bresp  (m_bresp),
      .s_bvalid (m_bvalid),
      .s_bready (m_bready),
      .s_araddr (m_araddr),
      .s_arprot (m_arprot),
      .s_arvalid(m_arvalid),
      .s_arready(m_arready),
      .s_rdata  (m_rdata),
      .s_rresp  (m_rresp),
      .s_rvalid (m_rvalid),
      .s_rready (m_rready),
      .m_awaddr (s_awaddr),
      .m_awprot (s_awprot),
      .m_awvalid(s_awvalid),
      .m_awready(s_awready),
      .m_wdata  (s_wdata),
      .m_wstrb  (s_wstrb),
      .m_wvalid (s_wvalid),
      .m_wready (s_wready),
      .m_bresp  (s_bresp),
      .m_bvalid (s_bvalid),
      .m_bready (s_bready),
      .m_araddr (s_araddr),
      .m_arprot (s_arprot),
      .m_arvalid(s_arvalid),
      .m_arready(s_arready),
      .m_rdata  (s_rdata),
      .m_rresp  (s_rresp),
      .m_rvalid (s_rvalid),
      .m_rready (s_rready)
  );

  // slaves 0..3: our peripherals behind adapters
  logic [3:0] p_sel, p_re;
  logic [4*12-1:0] p_addr;
  logic [ 4*4-1:0] p_be;
  logic [4*32-1:0] p_wdata, p_rdata;

  genvar g;
  generate
    for (g = 0; g < 4; g++) begin : adapters
      axil_slave_adapter #(
          .AW(12)
      ) adp (
          .clk      (clk),
          .reset    (reset),
          .s_awaddr (s_awaddr[g*32+:32]),
          .s_awprot (s_awprot[g*3+:3]),
          .s_awvalid(s_awvalid[g]),
          .s_awready(s_awready[g]),
          .s_wdata  (s_wdata[g*32+:32]),
          .s_wstrb  (s_wstrb[g*4+:4]),
          .s_wvalid (s_wvalid[g]),
          .s_wready (s_wready[g]),
          .s_bresp  (s_bresp[g*2+:2]),
          .s_bvalid (s_bvalid[g]),
          .s_bready (s_bready[g]),
          .s_araddr (s_araddr[g*32+:32]),
          .s_arprot (s_arprot[g*3+:3]),
          .s_arvalid(s_arvalid[g]),
          .s_arready(s_arready[g]),
          .s_rdata  (s_rdata[g*32+:32]),
          .s_rresp  (s_rresp[g*2+:2]),
          .s_rvalid (s_rvalid[g]),
          .s_rready (s_rready[g]),
          .reg_sel  (p_sel[g]),
          .reg_addr (p_addr[g*12+:12]),
          .reg_be   (p_be[g*4+:4]),
          .reg_wdata(p_wdata[g*32+:32]),
          .reg_re   (p_re[g]),
          .reg_rdata(p_rdata[g*32+:32])
      );
    end
  endgenerate

  logic [4:0] btn_press;
  logic uart_rx_valid, uart_tx_ready;

  io_regs #(
      .CLK_HZ(CLK_HZ)
  ) io (
      .clk       (clk),
      .reset     (reset),
      .sel       (p_sel[0]),
      .addr      (p_addr[0*12+:6]),
      .be        (p_be[0*4+:4]),
      .wdata     (p_wdata[0*32+:32]),
      .rdata     (p_rdata[0*32+:32]),
      .btn_press (btn_press),
      .led       (led),
      .io_led    (io_led),
      .io_dip    (io_dip),
      .io_button (io_button),
      .io_select (io_select),
      .io_segment(io_segment)
  );

  uart_periph #(
      .CLK_HZ(CLK_HZ),
      .BAUD  (BAUD)
  ) uart (
      .clk         (clk),
      .reset       (reset),
      .sel         (p_sel[1]),
      .addr        (p_addr[1*12+:4]),
      .be          (p_be[1*4+:4]),
      .re          (p_re[1]),
      .wdata       (p_wdata[1*32+:32]),
      .rdata       (p_rdata[1*32+:32]),
      .usb_rx      (usb_rx),
      .usb_tx      (usb_tx),
      .irq_rx_valid(uart_rx_valid),
      .irq_tx_ready(uart_tx_ready)
  );

  timer tmr (
      .clk     (clk),
      .reset   (reset),
      .sel     (p_sel[2]),
      .addr    (p_addr[2*12+:5]),
      .be      (p_be[2*4+:4]),
      .wdata   (p_wdata[2*32+:32]),
      .rdata   (p_rdata[2*32+:32]),
      .mtime   (mtime),
      .irq_mtip(irq_mtip),
      .irq_msip(irq_msip)
  );

  irq_ctrl irqc (
      .clk          (clk),
      .reset        (reset),
      .sel          (p_sel[3]),
      .addr         (p_addr[3*12+:4]),
      .be           (p_be[3*4+:4]),
      .wdata        (p_wdata[3*32+:32]),
      .rdata        (p_rdata[3*32+:32]),
      .uart_rx_valid(uart_rx_valid),
      .uart_tx_ready(uart_tx_ready),
      .btn_press    (btn_press),
      .irq_meip     (irq_meip)
  );

  //  slave 4: the external port
  assign ext_awaddr   = s_awaddr[4*32 +: 32];
  assign ext_awvalid  = s_awvalid[4];
  assign s_awready[4] = ext_awready;
  assign ext_wdata    = s_wdata[4*32 +: 32];
  assign ext_wstrb    = s_wstrb[4*4 +: 4];
  assign ext_wvalid   = s_wvalid[4];
  assign s_wready[4]  = ext_wready;
  assign s_bresp[4*2 +: 2] = ext_bresp;
  assign s_bvalid[4]  = ext_bvalid;
  assign ext_bready   = s_bready[4];
  assign ext_araddr   = s_araddr[4*32 +: 32];
  assign ext_arvalid  = s_arvalid[4];
  assign s_arready[4] = ext_arready;
  assign s_rdata[4*32 +: 32] = ext_rdata;
  assign s_rresp[4*2 +: 2]   = ext_rresp;
  assign s_rvalid[4]  = ext_rvalid;
  assign ext_rready   = s_rready[4];

  // simulation only: AXI protocol checkers
`ifndef SYNTHESIS
  // synthesis translate_off
  axil_checker #(
      .NAME("cpu bridge")
  ) chk_master (
      .clk(clk),
      .reset(reset),
      .awaddr(m_awaddr),
      .awvalid(m_awvalid),
      .awready(m_awready),
      .wdata(m_wdata),
      .wstrb(m_wstrb),
      .wvalid(m_wvalid),
      .wready(m_wready),
      .bresp(m_bresp),
      .bvalid(m_bvalid),
      .bready(m_bready),
      .araddr(m_araddr),
      .arvalid(m_arvalid),
      .arready(m_arready),
      .rdata(m_rdata),
      .rresp(m_rresp),
      .rvalid(m_rvalid),
      .rready(m_rready)
  );
  axil_checker #(
      .NAME("external port")
  ) chk_ext (
      .clk(clk),
      .reset(reset),
      .awaddr(ext_awaddr),
      .awvalid(ext_awvalid),
      .awready(ext_awready),
      .wdata(ext_wdata),
      .wstrb(ext_wstrb),
      .wvalid(ext_wvalid),
      .wready(ext_wready),
      .bresp(ext_bresp),
      .bvalid(ext_bvalid),
      .bready(ext_bready),
      .araddr(ext_araddr),
      .arvalid(ext_arvalid),
      .arready(ext_arready),
      .rdata(ext_rdata),
      .rresp(ext_rresp),
      .rvalid(ext_rvalid),
      .rready(ext_rready)
  );

  // the CPU must send only RAM addresses to its RAM port; a bus store that
  // leaked here would also overwrite RAM at (address & 0xFFFF)
  always @(posedge clk)
    if (!reset && d_be != 4'b0 && d_addr[31:28] != 4'h0) begin
      $display("SOC ERROR: RAM write with non-RAM address 0x%08h at %0t", d_addr, $time);
      $fatal(1);
    end
  // synthesis translate_on
`endif

endmodule
