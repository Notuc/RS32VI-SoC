// cpu_tb -- runs program.mem and checks the final register / memory values

`timescale 1ns / 1ps

module cpu_tb;

  logic clk = 0;
  logic reset = 1;

`ifndef MEMFILE
  `define MEMFILE "program.mem"
`endif

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

  // print every instruction as it executes
  always @(posedge clk)
    if (!reset)
      if (dut.cpu_i.valid_wb)  // each instruction as it leaves the pipeline (WB)
        $display(
            "PC=%h  instr=%h  result=%0d",
            dut.cpu_i.pc_wb,
            dut.cpu_i.instr_wb,
            $signed(
                dut.cpu_i.result_wb
            )
        );

  localparam int DB = 32'h400;  // smoke-test data lives at 0x400+, clear of the code
  int errors = 0;
  task automatic check_reg(int r, int expected);
    if (dut.cpu_i.rf.regs[r] !== expected) begin
      $display("FAIL: x%0d = %0d, expected %0d", r, dut.cpu_i.rf.regs[r], expected);
      errors++;
    end
  endtask

  // check a data-memory word by its byte address
  task automatic check_mem(int byte_addr, logic [31:0] expected);
    if (dut.ram.mem[byte_addr/4] !== expected) begin
      $display("FAIL: mem[%0d] = 0x%h, expected 0x%h", byte_addr, dut.ram.mem[byte_addr/4],
               expected);
      errors++;
    end
  endtask

  initial begin
    #12 reset = 0;  // release reset
    // run until the program reaches its final idle loop (beq x0, x0, 0) in WB
    do @(posedge clk); while (!(dut.cpu_i.valid_wb && dut.cpu_i.instr_wb == 32'h0000_0063));
    repeat (5) @(posedge clk);
    #1;

    check_reg(1, 5);
    check_reg(2, 7);
    check_reg(3, 12);
    check_reg(4, 2);
    check_reg(5, 5);
    check_reg(6, 7);
    check_reg(7, 1);
    check_reg(8, 12);
    check_reg(9, 1);
    check_reg(10, 32'h30);
    check_reg(11, -1);
    check_reg(12, 1);
    check_reg(13, 1);
    check_reg(14, 1);
    // ALU ops (new alu.sv)
    check_reg(15, 640);
    check_reg(16, 1);
    check_reg(17, 2);
    check_reg(18, 32'h07FF_FFFF);
    check_reg(19, -1);
    check_reg(20, -8);
    check_reg(21, -4);
    check_reg(22, 15);
    check_reg(23, 40);
    check_reg(24, -6);
    check_reg(25, 1);
    check_reg(26, 1);
    check_reg(27, 3);
    check_reg(28, 13);
    check_mem(DB + 4, 12);

    // lui / auipc
    check_reg(29, 32'h1234_5678);
    check_mem(DB + 100, 32'h0000_1108);  // auipc x31, 1 at PC 0x108

    // byte / halfword loads from 0x12345678
    check_mem(DB + 64, 32'h0000_0078);  // lb  @8
    check_mem(DB + 68, 32'h0000_0012);  // lb  @11
    check_mem(DB + 72, 32'h0000_1234);  // lh  @10
    check_mem(DB + 76, 32'h0000_5678);  // lhu @8
    // after sb 0xFE @9 and sh 0xFFFE @10
    check_mem(DB + 80, 32'hFFFF_FFFE);  // lb  @9  (sign-extended)
    check_mem(DB + 84, 32'h0000_00FE);  // lbu @9  (zero-extended)
    check_mem(DB + 88, 32'hFFFF_FFFE);  // lh  @10 (sign-extended)
    check_mem(DB + 92, 32'h0000_FFFE);  // lhu @10 (zero-extended)
    check_mem(DB + 96, 32'hFFFE_FE78);  // lw  @8  (sb/sh only touched their bytes)
    check_mem(DB + 8, 32'hFFFE_FE78);

    // jal / jalr
    check_mem(DB + 104, 77);  // subroutine ran and returned
    check_mem(DB + 108, 32'h0000_0134);  // jalr link = PC+4, target bit 0 cleared

    if (errors == 0) $display("\nALL TESTS PASSED");
    else $display("\n%0d TEST(S) FAILED", errors);
    $finish;
  end

endmodule
