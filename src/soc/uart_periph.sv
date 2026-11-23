// memory-mapped UART, base address 0x2000_1000
//   offset  name    access  meaning
//   0x00    DATA    W       send this byte (only if STATUS.TX_READY = 1; otherwise ignored)
//   0x04    STATUS  R       bit 0 TX_READY  : transmitter idle, a write to DATA will be sent
//                           bit 1 RX_VALID  : a received byte is waiting in DATA
//                           bit 2 RX_OVERRUN: a byte arrived before the previous one was read

module uart_periph #(
    parameter int CLK_HZ = 25_000_000,
    parameter int BAUD   = 115_200
) (
    input logic clk,
    input logic reset,

    input  logic        sel,
    input  logic [ 3:0] addr,   // byte offset within the block
    input  logic [ 3:0] be,
    input  logic        re,     // CPU is doing a load
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    input  logic usb_rx,
    output logic usb_tx,

    output logic irq_rx_valid,  // to irq_ctrl
    output logic irq_tx_ready
);

  logic tx_ready, tx_start;
  logic [7:0] rx_byte, rx_data;
  logic rx_strobe, rx_valid, rx_overrun;

  // a store to DATA starts a transmission (one-cycle pulse: the store lasts one cycle)
  assign tx_start = sel && (addr[3:2] == 2'd0) && be[0] && tx_ready;

  uart_tx #(
      .CLK_FREQ(CLK_HZ),
      .BAUD(BAUD)
  ) tx (
      .clk   (clk),
      .reset (reset),
      .data  (wdata[7:0]),
      .start (tx_start),
      .usb_tx(usb_tx),
      .ready (tx_ready)
  );

  uart_rx #(
      .CLK_FREQ(CLK_HZ),
      .BAUD(BAUD)
  ) rx (
      .clk       (clk),
      .reset     (reset),
      .usb_rx    (usb_rx),
      .data      (rx_byte),
      .data_valid(rx_strobe)
  );

  // one-byte receive buffer
  logic rd_data;
  assign rd_data = sel && re && (addr[3:2] == 2'd0);

  always_ff @(posedge clk) begin
    if (reset) begin
      rx_data    <= '0;
      rx_valid   <= 1'b0;
      rx_overrun <= 1'b0;
    end else begin
      if (rd_data) begin
        rx_valid   <= 1'b0;
        rx_overrun <= 1'b0;
      end
      if (rx_strobe) begin  // a new byte wins over a read in the same cycle
        rx_data    <= rx_byte;
        rx_valid   <= 1'b1;
        rx_overrun <= rx_valid && !rd_data;
      end
    end
  end

  always_comb begin
    case (addr[3:2])
      2'd0:    rdata = {24'b0, rx_data};
      2'd1:    rdata = {29'b0, rx_overrun, rx_valid, tx_ready};
      default: rdata = 32'b0;
    endcase
  end

  assign irq_rx_valid = rx_valid;
  assign irq_tx_ready = tx_ready;

endmodule
