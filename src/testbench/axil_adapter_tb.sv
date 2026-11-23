// axil_adapter_tb unit test of axil_slave_adapter against a randomised
// AXI4-Lite master.
//
// The CPU's bridge always sends AW and W together, so the system tests never
// show the adapter AW-before-W, W-before-AW, or a master that is slow to take
// its response.  This test does: 2000 random reads / writes (random byte
// strobes), each channel delayed independently by 0-4 cycles, checked against
// a reference copy of the registers, with the protocol checker watching.

`timescale 1ns / 1ps

module axil_adapter_tb;

  logic clk = 0, reset = 1;
  always #5 clk = ~clk;

  logic [31:0] awaddr, wdata, araddr, rdata;
  logic [3:0] wstrb;
  logic [1:0] bresp, rresp;
  logic awvalid = 0, awready, wvalid = 0, wready, bvalid, bready = 0;
  logic arvalid = 0, arready, rvalid, rready = 0;

  // register port -> a 16-word register block with byte enables
  logic reg_sel, reg_re;
  logic [11:0] reg_addr;
  logic [ 3:0] reg_be;
  logic [31:0] reg_wdata, reg_rdata;
  logic [31:0] regs[16];

  axil_slave_adapter #(
      .AW(12)
  ) dut (
      .clk(clk),
      .reset(reset),
      .s_awaddr(awaddr),
      .s_awprot(3'b0),
      .s_awvalid(awvalid),
      .s_awready(awready),
      .s_wdata(wdata),
      .s_wstrb(wstrb),
      .s_wvalid(wvalid),
      .s_wready(wready),
      .s_bresp(bresp),
      .s_bvalid(bvalid),
      .s_bready(bready),
      .s_araddr(araddr),
      .s_arprot(3'b0),
      .s_arvalid(arvalid),
      .s_arready(arready),
      .s_rdata(rdata),
      .s_rresp(rresp),
      .s_rvalid(rvalid),
      .s_rready(rready),
      .reg_sel(reg_sel),
      .reg_addr(reg_addr),
      .reg_be(reg_be),
      .reg_wdata(reg_wdata),
      .reg_re(reg_re),
      .reg_rdata(reg_rdata)
  );

  axil_checker #(
      .NAME("adapter")
  ) chk (
      .clk(clk),
      .reset(reset),
      .awaddr(awaddr),
      .awvalid(awvalid),
      .awready(awready),
      .wdata(wdata),
      .wstrb(wstrb),
      .wvalid(wvalid),
      .wready(wready),
      .bresp(bresp),
      .bvalid(bvalid),
      .bready(bready),
      .araddr(araddr),
      .arvalid(arvalid),
      .arready(arready),
      .rdata(rdata),
      .rresp(rresp),
      .rvalid(rvalid),
      .rready(rready)
  );

  assign reg_rdata = regs[reg_addr[5:2]];
  always_ff @(posedge clk)
    if (reg_sel)
      for (int i = 0; i < 4; i++) if (reg_be[i]) regs[reg_addr[5:2]][8*i+:8] <= reg_wdata[8*i+:8];

  // reference copy
  logic [31:0] ref_regs[16];

  // master tasks: each channel on its own random delay 
  task automatic send_aw(input logic [31:0] a);
    repeat ($urandom_range(0, 4)) @(posedge clk);
    awaddr  <= a;
    awvalid <= 1;
    do @(posedge clk); while (!awready);
    awvalid <= 0;
  endtask
  task automatic send_w(input logic [31:0] d, input logic [3:0] s);
    repeat ($urandom_range(0, 4)) @(posedge clk);
    wdata  <= d;
    wstrb  <= s;
    wvalid <= 1;
    do @(posedge clk); while (!wready);
    wvalid <= 0;
  endtask
  task automatic take_b();
    do @(posedge clk); while (!bvalid);
    repeat ($urandom_range(0, 4)) @(posedge clk);  // slow to accept the response
    bready <= 1;
    @(posedge clk);
    bready <= 0;
  endtask

  task automatic write(input int r, input logic [31:0] d, input logic [3:0] s);
    fork
      send_aw({20'h0, 6'h0, r[3:0], 2'b00});
      send_w(d, s);
    join
    take_b();
    for (int i = 0; i < 4; i++) if (s[i]) ref_regs[r][8*i+:8] = d[8*i+:8];
  endtask

  task automatic read(input int r, output logic [31:0] d);
    repeat ($urandom_range(0, 4)) @(posedge clk);
    araddr  <= {26'h0, r[3:0], 2'b00};
    arvalid <= 1;
    do @(posedge clk); while (!arready);
    arvalid <= 0;
    do @(posedge clk); while (!rvalid);
    repeat ($urandom_range(0, 4)) @(posedge clk);
    d = rdata;
    rready <= 1;
    @(posedge clk);
    rready <= 0;
  endtask

  int errors = 0, writes = 0, reads = 0, seed = 42, r;
  logic [31:0] got;

  initial begin
    void'($urandom(seed));
    for (int i = 0; i < 16; i++) begin
      regs[i] = 0;
      ref_regs[i] = 0;
    end
    repeat (3) @(posedge clk);
    reset = 0;

    for (int n = 0; n < 2000; n++) begin
      r = $urandom_range(0, 15);
      if ($urandom_range(0, 1)) begin
        write(r, $urandom(), $urandom_range(1, 15));
        writes++;
      end else begin
        read(r, got);
        reads++;
        if (got !== ref_regs[r]) begin
          if (errors < 5) $display("FAIL  reg %0d: read 0x%h, expected 0x%h", r, got, ref_regs[r]);
          errors++;
        end
      end
    end

    $display("%0d writes, %0d reads, %0d mismatches, %0d checked transfers", writes, reads, errors,
             chk.transfers);
    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d mismatches", errors);
    $finish;
  end

endmodule
