module alchitry_io_interface #(
    parameter int CLK_HZ = 100_000_000  // clock frequency, so the debounce time stays 10 ms
) (
    input logic clk,
    input logic reset,

    // Connections from Register File
    input  logic [31:0] led_register,        // Address 0x04 contents
    input  logic [31:0] display_register,    // Address 0x08 contents
    input  logic [31:0] disp_ctrl_register,  // Address 0x0C contents
    output logic [31:0] switches_out,        // Feeds into Address 0x10
    output logic [31:0] buttons_out,         // Feeds into Address 0x14

    // Physical FPGA Pins
    output logic [2:0][7:0] io_led,     // 3 banks of 8 LEDs
    input  logic [2:0][7:0] io_dip,     // 3 banks of 8 DIP switches
    input  logic [4:0]      io_button,  // 5 push buttons
    output logic [3:0]      io_select,  // 7-segment digit select
    output logic [7:0]      io_segment  // 7-segment segment
);

  // LED Driver (Active-Low Inversion)
  // invert the register bits so software '1' = LED ON.
  // A [2:0][7:0] packed array is the same 24 bits as led_register[23:0]:
  // io_led[bank][bit] == bit (bank*8 + bit).
  assign io_led = ~led_register[23:0];

  // DIP Switches (Active-Low Inversion)
  // DIP switches pull to GND when closed (ON). 
  // switch (bank, bit) lands in bit bank*8 + bit
  assign switches_out = {8'b0, ~io_dip};

  // Push Buttons (Active-High) + Debouncing 
  logic [4:0] debounced_buttons;

  // Instantiate a debouncer for each of the 5 push buttons
  genvar i;
  generate
    for (i = 0; i < 5; i++) begin : gen_debouncers
      button_debouncer #(
          .CLK_FREQ_HZ(CLK_HZ),
          .DEBOUNCE_MS(10)
      ) db_inst (
          .clk(clk),
          .reset(reset),
          .button_in(io_button[i]),
          .button_out(debounced_buttons[i])
      );
    end
  endgenerate

  // Feed the clean, debounced signals into your register file bus
  always_comb begin
    buttons_out = '0;
    buttons_out[4:0] = debounced_buttons;
  end

  // 7-Segment Display & Multiplexing
  // Scans through the 4 digits rapidly using a clock divider counter
  logic [15:0] scan_counter;
  logic [ 1:0] current_digit;

  always_ff @(posedge clk) begin
    if (reset) begin
      scan_counter <= '0;
    end else begin
      scan_counter <= scan_counter + 1;
    end
  end

  // Use upper bits of the counter to switch digits every few milliseconds
  assign current_digit = scan_counter[15:14];

  // Hex-to-7-segment decoder function (Active-Low segments)
  function automatic logic [7:0] sev_seg_dec(input logic [3:0] val, input logic dp);
    logic [6:0] segs;
    case (val)
      4'h0: segs = 7'b0000001;  // 0
      4'h1: segs = 7'b1001111;  // 1
      4'h2: segs = 7'b0010010;  // 2
      4'h3: segs = 7'b0000110;  // 3
      4'h4: segs = 7'b1001100;  // 4
      4'h5: segs = 7'b0100100;  // 5 
      4'h6: segs = 7'b0100000;  // 6
      4'h7: segs = 7'b0001111;  // 7
      4'h8: segs = 7'b0000000;  // 8
      4'h9: segs = 7'b0000100;  // 9
      4'hA: segs = 7'b0001000;  // A
      4'hB: segs = 7'b1100000;  // b
      4'hC: segs = 7'b0110001;  // C
      4'hD: segs = 7'b1000010;  // d
      4'hE: segs = 7'b0110000;  // E
      4'hF: segs = 7'b0111000;  // F
      default: segs = 7'b1111111;  // Blank
    endcase
    // Bit 7 is DP (Decimal Point). Active low on Alchitry IO.
    return {~dp, segs};
  endfunction

  // Multiplexer logic for 4 digits
  always_comb begin
    // Default: turn off all digit (Active low: 4'b1111 means all off)
    io_select  = 4'b1111;
    io_segment = 8'hFF;  // All segments off

    // enable the display multiplexer
    if (disp_ctrl_register[0]) begin
      case (current_digit)
        2'd0: begin
          io_select  = 4'b1110;  // Enable Digit 0 (Rightmost)
          io_segment = sev_seg_dec(display_register[3:0], disp_ctrl_register[1]);
        end
        2'd1: begin
          io_select  = 4'b1101;  // Enable Digit 1
          io_segment = sev_seg_dec(display_register[7:4], disp_ctrl_register[2]);
        end
        2'd2: begin
          io_select  = 4'b1011;  // Enable Digit 2
          io_segment = sev_seg_dec(display_register[11:8], disp_ctrl_register[3]);
        end
        2'd3: begin
          io_select  = 4'b0111;  // Enable Digit 3 (Leftmost)
          io_segment = sev_seg_dec(display_register[15:12], disp_ctrl_register[4]);
        end
        default: ;
      endcase
    end
  end

endmodule
