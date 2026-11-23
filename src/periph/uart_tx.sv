module uart_tx #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int BAUD     = 115_200
) (
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] data,    // Byte to send
    input  logic       start,   // Pulse high for 1 cycle while ready = 1
    output logic       usb_tx,  // Serial line out to the FTDI chip
    output logic       ready    // High when idle and able to accept a byte
);

  localparam int CLKS_PER_BIT = CLK_FREQ / BAUD;

  typedef enum logic [1:0] {
    IDLE,
    START_BIT,
    DATA_BITS,
    STOP_BIT
  } state_t;

  state_t state;

  logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
  logic [2:0] bit_index;
  logic [7:0] tx_shift_reg;

  always_ff @(posedge clk) begin : tx_uart
    if (reset) begin
      state        <= IDLE;
      usb_tx       <= 1'b1;  // UART line idles high
      clk_count    <= '0;
      bit_index    <= '0;
      tx_shift_reg <= '0;
    end else begin
      case (state)
        IDLE: begin
          usb_tx    <= 1'b1;
          clk_count <= '0;
          bit_index <= '0;
          if (start) begin
            tx_shift_reg <= data;  // Latch the byte so the caller can move on
            state        <= START_BIT;
          end
        end

        START_BIT: begin
          usb_tx <= 1'b0;  // Start bit is low
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;
            state     <= DATA_BITS;
          end else begin
            clk_count <= clk_count + 1;
          end
        end

        DATA_BITS: begin
          usb_tx <= tx_shift_reg[bit_index];  // LSB first
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;
            if (bit_index == 3'd7) begin
              bit_index <= '0;
              state     <= STOP_BIT;
            end else begin
              bit_index <= bit_index + 1;
            end
          end else begin
            clk_count <= clk_count + 1;
          end
        end

        STOP_BIT: begin
          usb_tx <= 1'b1;  // Stop bit is high
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;
            state     <= IDLE;
          end else begin
            clk_count <= clk_count + 1;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end : tx_uart

  assign ready = (state == IDLE);

endmodule
