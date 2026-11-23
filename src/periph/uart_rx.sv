module uart_rx #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int BAUD = 115_200
) (
    input logic clk,
    input logic reset,
    input logic usb_rx,
    output logic [7:0] data,
    output logic data_valid
);

  localparam int CLKS_PER_BIT = CLK_FREQ / BAUD;

  // Synchronizer registers for the asynchronous usb_rx input pin (METASTABILITY)
  logic rx_meta, rx_sync;

  always_ff @(posedge clk) begin
    if (reset) begin
      {rx_sync, rx_meta} <= 2'b11;  // Idle high because UART idles at logic 1
    end else begin
      {rx_sync, rx_meta} <= {rx_meta, usb_rx};
      // raw usb_rx goes into rx_meta
      // rx_meta passes its stable value to rx_sync on the next clock tick
    end
  end

  typedef enum logic [1:0] {
    IDLE,
    START_BIT,
    STOP_BIT,
    DATA_BITS
  } state_t;

  state_t state;

  // Counters and Shift Register
  logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
  logic [2:0] bit_index;  // max is 7 (3'b111)
  logic [7:0] rx_shift_reg;

  always_ff @(posedge clk) begin : rx_uart
    if (reset) begin
      state        <= IDLE;
      data         <= '0;
      data_valid   <= '0;
      bit_index    <= '0;
      clk_count    <= '0;
      rx_shift_reg <= '0;
    end else begin
      data_valid <= '0;

      case (state)
        IDLE: begin
          clk_count <= '0;
          bit_index <= '0;
          // Using rx_sync safely instead of raw usb_rx
          if (rx_sync == 1'b0) begin
            state <= START_BIT;
          end
        end

        START_BIT: begin
          // Wait for HALF of the bit period to sample right in the middle
          if (clk_count == (CLKS_PER_BIT / 2 - 1)) begin
            clk_count <= '0;
            if (rx_sync == 1'b0) begin  // Confirm it's still low 
              state <= DATA_BITS;
            end else begin
              state <= IDLE;
            end
          end else begin
            clk_count <= clk_count + 1;
          end
        end

        DATA_BITS: begin
          // Wait for a full clks_per_bit cycle for each data bit
          if (clk_count == (CLKS_PER_BIT - 1)) begin
            clk_count <= '0;
            // Shift the synchronized incoming bit into our receive register
            rx_shift_reg <= {rx_sync, rx_shift_reg[7:1]};

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
          // Wait for the full bit period to check the stop bit
          if (clk_count == (CLKS_PER_BIT - 1)) begin
            clk_count <= '0;
            if (rx_sync == 1'b1) begin  // Stop bit should be high
              data       <= rx_shift_reg;
              data_valid <= 1'b1;  // Data is ready
            end
            state <= IDLE;
          end else begin
            clk_count <= clk_count + 1;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end : rx_uart

endmodule
