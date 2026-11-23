// axil_slave_adapter -- AXI4-Lite slave  ->  simple register port
//
// Lets an existing peripheral sit on the AXI4-Lite bus without changing it
// The register port is the one those
// modules already had:
//
//   reg_sel   1 for one cycle per access
//   reg_addr  byte address within the slave
//   reg_be    byte enables (0 for a read)
//   reg_wdata write data
//   reg_re    1 for one cycle on a read (for read side effects, e.g. UART RX)
//   reg_rdata read data from the peripheral, used in that same cycle
//
// Writes: AW and W may arrive in either order (or together); each is accepted
// and held, and when both are here the write happens and B is answered.
// Reads:  on the AR handshake the register is read and R is answered next cycle.
// Every response is OKAY.

module axil_slave_adapter #(
    parameter int AW = 12  // address bits passed to the peripheral
) (
    input logic clk,
    input logic reset,

    // AXI4-Lite slave
    input  logic [31:0] s_awaddr,
    input  logic [ 2:0] s_awprot,
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_wdata,
    input  logic [ 3:0] s_wstrb,
    input  logic        s_wvalid,
    output logic        s_wready,
    output logic [ 1:0] s_bresp,
    output logic        s_bvalid,
    input  logic        s_bready,
    input  logic [31:0] s_araddr,
    input  logic [ 2:0] s_arprot,
    input  logic        s_arvalid,
    output logic        s_arready,
    output logic [31:0] s_rdata,
    output logic [ 1:0] s_rresp,
    output logic        s_rvalid,
    input  logic        s_rready,

    // register port to the peripheral
    output logic          reg_sel,
    output logic [AW-1:0] reg_addr,
    output logic [   3:0] reg_be,
    output logic [  31:0] reg_wdata,
    output logic          reg_re,
    input  logic [  31:0] reg_rdata
);

  logic aw_full, w_full;
  logic [AW-1:0] awaddr_q;
  logic [31:0]   wdata_q;
  logic [3:0]    wstrb_q;

  assign s_awready = !aw_full;
  assign s_wready  = !w_full;
  assign s_bresp   = 2'b00;
  assign s_rresp   = 2'b00;

  logic do_write, do_read;
  assign do_write  = aw_full && w_full && !s_bvalid;
  assign s_arready = !s_rvalid && !do_write;  // one register access per cycle
  assign do_read   = s_arvalid && s_arready;

  // the register port
  always_comb begin
    reg_sel   = do_write || do_read;
    reg_addr  = do_write ? awaddr_q : s_araddr[AW-1:0];
    reg_be    = do_write ? wstrb_q  : 4'b0000;
    reg_wdata = wdata_q;
    reg_re    = do_read;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      aw_full  <= 1'b0;
      w_full   <= 1'b0;
      s_bvalid <= 1'b0;
      s_rvalid <= 1'b0;
    end else begin
      if (s_awvalid && s_awready) begin
        aw_full  <= 1'b1;
        awaddr_q <= s_awaddr[AW-1:0];
      end
      if (s_wvalid && s_wready) begin
        w_full  <= 1'b1;
        wdata_q <= s_wdata;
        wstrb_q <= s_wstrb;
      end
      if (do_write) begin
        aw_full  <= 1'b0;
        w_full   <= 1'b0;
        s_bvalid <= 1'b1;
      end
      if (s_bvalid && s_bready) s_bvalid <= 1'b0;

      if (do_read) begin
        s_rvalid <= 1'b1;
        s_rdata  <= reg_rdata;
      end else if (s_rvalid && s_rready) s_rvalid <= 1'b0;
    end
  end

endmodule
