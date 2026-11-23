// axil_interconnect  one AXI4-Lite master to N slaves, by address
//
// Slave i owns every address where (addr & MASK[i]) == BASE[i].  Anything
// else goes to a built-in default slave that answers OKAY, reads 0 and
// ignores writes.
//
// The master (axil_master_bridge) has one transaction in flight and keeps its
// address steady until the response, so routing is purely combinational:
// AW / W / B follow the write address, AR / R follow the read address.
//
// Slave ports are flattened vectors: slave i uses bits [i*32 +: 32] etc.

module axil_interconnect #(
    parameter int              N    = 5,
    parameter logic [N*32-1:0] BASE = '0,
    parameter logic [N*32-1:0] MASK = '0
) (
    input logic clk,
    input logic reset,

    // from the master
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

    // to the slaves
    output logic [N*32-1:0] m_awaddr,
    output logic [N*3-1:0]  m_awprot,
    output logic [N-1:0]    m_awvalid,
    input  logic [N-1:0]    m_awready,
    output logic [N*32-1:0] m_wdata,
    output logic [N*4-1:0]  m_wstrb,
    output logic [N-1:0]    m_wvalid,
    input  logic [N-1:0]    m_wready,
    input  logic [N*2-1:0]  m_bresp,
    input  logic [N-1:0]    m_bvalid,
    output logic [N-1:0]    m_bready,
    output logic [N*32-1:0] m_araddr,
    output logic [N*3-1:0]  m_arprot,
    output logic [N-1:0]    m_arvalid,
    input  logic [N-1:0]    m_arready,
    input  logic [N*32-1:0] m_rdata,
    input  logic [N*2-1:0]  m_rresp,
    input  logic [N-1:0]    m_rvalid,
    output logic [N-1:0]    m_rready
);

  // address decode
  logic [N-1:0] wsel, rsel;
  genvar g;
  generate
    for (g = 0; g < N; g++) begin : dec
      assign wsel[g]            = ((s_awaddr & MASK[g*32+:32]) == BASE[g*32+:32]);
      assign rsel[g]            = ((s_araddr & MASK[g*32+:32]) == BASE[g*32+:32]);

      // requests go to every slave; only the selected one sees VALID
      assign m_awaddr[g*32+:32] = s_awaddr;
      assign m_awprot[g*3+:3]   = s_awprot;
      assign m_awvalid[g]       = s_awvalid && wsel[g];
      assign m_wdata[g*32+:32]  = s_wdata;
      assign m_wstrb[g*4+:4]    = s_wstrb;
      assign m_wvalid[g]        = s_wvalid && wsel[g];
      assign m_bready[g]        = s_bready && wsel[g];
      assign m_araddr[g*32+:32] = s_araddr;
      assign m_arprot[g*3+:3]   = s_arprot;
      assign m_arvalid[g]       = s_arvalid && rsel[g];
      assign m_rready[g]        = s_rready && rsel[g];
    end
  endgenerate

  logic wdef, rdef;  // no slave matched: default slave
  assign wdef = (wsel == '0);
  assign rdef = (rsel == '0);

  // default slave
  // accepts AW and W (any order), then answers OKAY; reads return 0
  logic d_aw, d_w, d_bvalid, d_rvalid;
  always_ff @(posedge clk) begin
    if (reset) begin
      d_aw <= 1'b0;
      d_w <= 1'b0;
      d_bvalid <= 1'b0;
      d_rvalid <= 1'b0;
    end else begin
      if (wdef && s_awvalid && s_awready) d_aw <= 1'b1;  // handshakes only
      if (wdef && s_wvalid && s_wready) d_w <= 1'b1;
      if (d_aw && d_w) begin
        d_bvalid <= 1'b1;
        d_aw <= 1'b0;
        d_w <= 1'b0;
      end
      if (d_bvalid && s_bready && wdef) d_bvalid <= 1'b0;
      if (rdef && s_arvalid && s_arready) d_rvalid <= 1'b1;
      else if (d_rvalid && s_rready && rdef) d_rvalid <= 1'b0;
    end
  end

  // responses back to the master
  always_comb begin
    s_awready = wdef && !d_aw && !d_bvalid;
    s_wready  = wdef && !d_w && !d_bvalid;
    s_bvalid  = wdef && d_bvalid;
    s_bresp   = 2'b00;
    s_arready = rdef && !d_rvalid;
    s_rvalid  = rdef && d_rvalid;
    s_rdata   = 32'b0;
    s_rresp   = 2'b00;
    for (int i = 0; i < N; i++) begin
      if (wsel[i]) begin
        s_awready = m_awready[i];
        s_wready  = m_wready[i];
        s_bvalid  = m_bvalid[i];
        s_bresp   = m_bresp[i*2+:2];
      end
      if (rsel[i]) begin
        s_arready = m_arready[i];
        s_rvalid  = m_rvalid[i];
        s_rdata   = m_rdata[i*32+:32];
        s_rresp   = m_rresp[i*2+:2];
      end
    end
  end

endmodule
