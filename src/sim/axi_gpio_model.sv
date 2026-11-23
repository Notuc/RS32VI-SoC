`timescale 1ns / 1ps
// axi_gpio_model -- simulation stand-in for AMD's AXI GPIO IP
// configured like the board: dual channel, channel 1 = 8 outputs, channel 2 =
// 24 inputs.
//
// Same port names and register map as the real IP:
//   0x000  GPIO_DATA    channel 1 data (outputs)
//   0x004  GPIO_TRI     channel 1 direction (reads back what was written)
//   0x008  GPIO2_DATA   channel 2 data (the inputs)
//   0x00C  GPIO2_TRI    channel 2 direction
//
// Like AMD's IP it only accepts a write when AW and W are both valid.  With
// RANDOM_DELAYS = 1 every READY and every response VALID is delayed by 0-3
// random cycles, which is what really exercises the master's handshakes.

module axi_gpio_model #(
    parameter int RANDOM_DELAYS = 1,
    parameter int SEED          = 1
) (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [ 8:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [ 3:0] s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [ 1:0] s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [ 8:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [ 1:0] s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    output logic [ 7:0] gpio_io_o,
    input  logic [23:0] gpio2_io_i
);

  logic [31:0] data1, dir1, dir2;
  int wdelay, bdelay, rdelay, ardelay;
  int rnd_state;

  function automatic int rnd();
    return RANDOM_DELAYS ? $urandom_range(0, 3) : 0;
  endfunction

  initial begin
    rnd_state = SEED;
    void'($urandom(rnd_state));
  end  // seed the generator

  assign s_axi_bresp = 2'b00;
  assign s_axi_rresp = 2'b00;
  assign gpio_io_o   = data1[7:0];

  // writes: AW and W together, after a random delay 
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_awready <= 0;
      s_axi_wready <= 0;
      s_axi_bvalid <= 0;
      data1 <= '0;
      dir1 <= '1;
      dir2 <= '1;
      wdelay <= 0;
      bdelay <= 0;
    end else begin
      s_axi_awready <= 0;
      s_axi_wready  <= 0;
      if (s_axi_awvalid && s_axi_wvalid && !s_axi_awready && !s_axi_bvalid && bdelay == 0) begin
        if (wdelay == 0) begin
          s_axi_awready <= 1;  // accept both in the next cycle
          s_axi_wready  <= 1;
          wdelay        <= rnd();
        end else wdelay <= wdelay - 1;
      end
      if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
        case (s_axi_awaddr[3:2])
          2'd0:
          for (int i = 0; i < 4; i++) if (s_axi_wstrb[i]) data1[8*i+:8] <= s_axi_wdata[8*i+:8];
          2'd1: for (int i = 0; i < 4; i++) if (s_axi_wstrb[i]) dir1[8*i+:8] <= s_axi_wdata[8*i+:8];
          2'd3: for (int i = 0; i < 4; i++) if (s_axi_wstrb[i]) dir2[8*i+:8] <= s_axi_wdata[8*i+:8];
          default: ;  // GPIO2_DATA is input-only
        endcase
        bdelay <= rnd() + 1;
      end
      if (bdelay == 1) s_axi_bvalid <= 1;
      if (bdelay > 0) bdelay <= bdelay - 1;
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
    end
  end

  // reads
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_arready <= 0;
      s_axi_rvalid <= 0;
      rdelay <= 0;
      ardelay <= 0;
    end else begin
      s_axi_arready <= 0;
      if (s_axi_arvalid && !s_axi_arready && !s_axi_rvalid && rdelay == 0) begin
        if (ardelay == 0) begin
          s_axi_arready <= 1;
          ardelay <= rnd();
        end else ardelay <= ardelay - 1;
      end
      if (s_axi_arready && s_axi_arvalid) begin
        case (s_axi_araddr[3:2])
          2'd0: s_axi_rdata <= data1;
          2'd1: s_axi_rdata <= dir1;
          2'd2: s_axi_rdata <= {8'b0, gpio2_io_i};
          2'd3: s_axi_rdata <= dir2;
        endcase
        rdelay <= rnd() + 1;
      end
      if (rdelay == 1) s_axi_rvalid <= 1;
      if (rdelay > 0) rdelay <= rdelay - 1;
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
    end
  end

endmodule
