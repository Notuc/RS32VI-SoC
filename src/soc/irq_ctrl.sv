// interrupt controller, base address 0x2000_3000
// Combines the device interrupt sources into the CPU's one external
// interrupt line (MEIP).
//
//   bit  source        kind
//   0    UART RX       level: a received byte is waiting (cleared by reading UART DATA)
//   1    UART TX       level: transmitter idle (disable when there is nothing to send)
//   2-6  buttons 0-4   edge: a new press is latched (cleared by writing 1)
//
//   offset  name     access
//   0x00    PENDING  R
//   0x04    ENABLE   R/W
//   0x08    ACTIVE   R
//
// MEIP = (ACTIVE != 0).  The CPU additionally needs mie.MEIE and mstatus.MIE.

module irq_ctrl (
    input logic clk,
    input logic reset,

    input  logic        sel,
    input  logic [ 3:0] addr,
    input  logic [ 3:0] be,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    input logic       uart_rx_valid,
    input logic       uart_tx_ready,
    input logic [4:0] btn_press,      // one-cycle pulse per new press

    output logic irq_meip
);

  logic [4:0] btn_latched;
  logic [6:0] enable, pending, active;

  logic we;
  assign we = sel && (be != 4'b0);

  always_ff @(posedge clk) begin
    if (reset) begin
      btn_latched <= '0;
      enable      <= '0;
    end else begin
      if (we && addr[3:2] == 2'd1) enable <= wdata[6:0];
      btn_latched <= (we && addr[3:2] == 2'd0 ? btn_latched & ~wdata[6:2] : btn_latched) | btn_press;                         // a new press wins over a clear
    end
  end

  assign pending = {btn_latched, uart_tx_ready, uart_rx_valid};
  assign active  = pending & enable;

  always_comb begin
    case (addr[3:2])
      2'd0:    rdata = {25'b0, pending};
      2'd1:    rdata = {25'b0, enable};
      2'd2:    rdata = {25'b0, active};
      default: rdata = 32'b0;
    endcase
  end

  assign irq_meip = (active != 7'b0);

endmodule
