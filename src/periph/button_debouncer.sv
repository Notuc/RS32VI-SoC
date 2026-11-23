module button_debouncer #(
    parameter int CLK_FREQ_HZ = 100_000_000,  // 100 MHz clock on Alchitry Au
    parameter int DEBOUNCE_MS = 10            // 10 ms stability window
) (
    input  logic clk,
    input  logic reset,
    input  logic button_in,  // Raw physical button pin
    output logic button_out  // Clean, debounced button signal
);

  // ticks needed for the target delay time
  // 10ms at 100MHz = 1,000,000 clock cycles
  localparam int MAX_COUNT = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

  // Synchronize the asynchronous button input to prevent metastability
  logic sync_0, sync_1;
  always_ff @(posedge clk) begin
    if (reset) begin
      sync_0 <= 1'b0;
      sync_1 <= 1'b0;
    end else begin
      sync_0 <= button_in;
      sync_1 <= sync_0;
    end
  end

  // Debounce counter and state machine logic
  logic [$clog2(MAX_COUNT)-1:0] counter;
  logic debounced_reg;

  always_ff @(posedge clk) begin
    if (reset) begin
      counter       <= '0;
      debounced_reg <= 1'b0;
    end else begin
      // synchronized input doesn't match current output, start counting
      if (sync_1 != debounced_reg) begin
        if (counter == MAX_COUNT - 1) begin
          debounced_reg <= sync_1;  // Accept the new stable state
          counter       <= '0;
        end else begin
          counter <= counter + 1;
        end
      end else begin
        // Input matches output
        // reset the counter
        counter <= '0;
      end
    end
  end

  assign button_out = debounced_reg;

endmodule
