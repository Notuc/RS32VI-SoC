`timescale 1ns / 1ps
// axil_checker -- simulation only: watches one AXI4-Lite bus and stops the
// simulation on a protocol violation.
//
// Checked on every clock edge (out of reset):
//   1. VALID, once high, stays high until the handshake (VALID && READY)
//   2. the payload does not change while VALID is high and READY is low
//   3. a B response only after both an AW and a W were accepted,
//      an R response only after an AR was accepted
//   4. VALID / READY are never X or Z

module axil_checker #(
    parameter string NAME = "axi"
) (
    input logic        clk,
    input logic        reset,
    input logic [31:0] awaddr,
    input logic        awvalid,
    input logic        awready,
    input logic [31:0] wdata,
    input logic [ 3:0] wstrb,
    input logic        wvalid,
    input logic        wready,
    input logic [ 1:0] bresp,
    input logic        bvalid,
    input logic        bready,
    input logic [31:0] araddr,
    input logic        arvalid,
    input logic        arready,
    input logic [31:0] rdata,
    input logic [ 1:0] rresp,
    input logic        rvalid,
    input logic        rready
);

  logic p_awvalid, p_awready, p_wvalid, p_wready, p_bvalid, p_bready;
  logic p_arvalid, p_arready, p_rvalid, p_rready;
  logic [31:0] p_awaddr, p_wdata, p_araddr, p_rdata;
  logic [3:0] p_wstrb;
  logic [1:0] p_bresp, p_rresp;
  int aw_out, w_out, ar_out;  // accepted, not yet answered
  int    transfers;  // completed transactions (for reports)
  string err;

  always @(posedge clk) begin
    if (reset) begin
      aw_out <= 0;
      w_out <= 0;
      ar_out <= 0;
      transfers <= 0;
      p_awvalid <= 0;
      p_wvalid <= 0;
      p_bvalid <= 0;
      p_arvalid <= 0;
      p_rvalid <= 0;
    end else begin
      err = "";
      // (XOR-reduce: the result is X if any bit is X or Z)
      if ((^{awvalid, awready, wvalid, wready, bvalid, bready,
                   arvalid, arready, rvalid, rready}) === 1'bx)
        err = $sformatf(
            "VALID or READY is X/Z: aw %b%b w %b%b b %b%b ar %b%b r %b%b",
            awvalid,
            awready,
            wvalid,
            wready,
            bvalid,
            bready,
            arvalid,
            arready,
            rvalid,
            rready
        );
      // rules 1 and 2, per channel
      else if (p_awvalid && !p_awready && !awvalid) err = "AW VALID dropped before READY";
      else if (p_awvalid && !p_awready && awaddr != p_awaddr)
        err = "AW address changed while waiting";
      else if (p_wvalid && !p_wready && !wvalid) err = "W VALID dropped before READY";
      else if (p_wvalid && !p_wready && (wdata != p_wdata || wstrb != p_wstrb))
        err = "W data changed while waiting";
      else if (p_bvalid && !p_bready && !bvalid) err = "B VALID dropped before READY";
      else if (p_bvalid && !p_bready && bresp != p_bresp) err = "B response changed while waiting";
      else if (p_arvalid && !p_arready && !arvalid) err = "AR VALID dropped before READY";
      else if (p_arvalid && !p_arready && araddr != p_araddr)
        err = "AR address changed while waiting";
      else if (p_rvalid && !p_rready && !rvalid) err = "R VALID dropped before READY";
      else if (p_rvalid && !p_rready && (rdata != p_rdata || rresp != p_rresp))
        err = "R data changed while waiting";
      // rule 3
      else if (bvalid && bready && (aw_out == 0 || w_out == 0))
        err = "B without an accepted AW and W";
      else if (rvalid && rready && ar_out == 0) err = "R without an accepted AR";

      if (err != "") begin
        $display("AXI PROTOCOL ERROR [%s] at %0t ns: %s", NAME, $time, err);
        $fatal(1);
      end

      aw_out <= aw_out + (awvalid && awready) - (bvalid && bready);
      w_out <= w_out + (wvalid && wready) - (bvalid && bready);
      ar_out <= ar_out + (arvalid && arready) - (rvalid && rready);
      transfers <= transfers + (bvalid && bready) + (rvalid && rready);

      p_awvalid <= awvalid;
      p_awready <= awready;
      p_awaddr <= awaddr;
      p_wvalid <= wvalid;
      p_wready <= wready;
      p_wdata <= wdata;
      p_wstrb <= wstrb;
      p_bvalid <= bvalid;
      p_bready <= bready;
      p_bresp <= bresp;
      p_arvalid <= arvalid;
      p_arready <= arready;
      p_araddr <= araddr;
      p_rvalid <= rvalid;
      p_rready <= rready;
      p_rdata <= rdata;
      p_rresp <= rresp;
    end
  end

endmodule
