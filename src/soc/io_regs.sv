// memory-mapped registers for the Alchitry Io board
//
//   offset  name        access
//   0x00    ID          R
//   0x04    LED         R/W
//   0x08    DISPLAY     R/W
//   0x0C    DISP_CTRL   R/W
//   0x10    SWITCHES    R
//   0x14    BUTTONS     R
//   0x18    BTN_COUNT   R/W
//   0x1C    BOARD_LED   R/W
//   0x20    SCRATCH     R/W
//   0x24    CLK_HZ      R
//   0x28    CYCLES      R

module io_regs #(
    parameter int CLK_HZ = 25_000_000
) (
    input logic clk,
    input logic reset,

    // bus (from the SoC address decoder)
    input  logic        sel,    // this block is addressed
    input  logic [ 5:0] addr,   // byte offset within the block
    input  logic [ 3:0] be,     // byte write enables
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    // board pins
    output logic [4:0]      btn_press,  // one-cycle pulse per new button press (to irq_ctrl)
    output logic [7:0]      led,
    output logic [2:0][7:0] io_led,
    input  logic [2:0][7:0] io_dip,
    input  logic [4:0]      io_button,
    output logic [3:0]      io_select,
    output logic [7:0]      io_segment
);

  logic [31:0] reg_led, reg_display, reg_disp_ctrl, reg_btn_count;
  logic [31:0] reg_board_led, reg_scratch, cycles;
  logic [31:0] switches, buttons;
  logic [4:0] buttons_prev;

  // byte-enable aware write helper
  function automatic logic [31:0] merge(input logic [31:0] cur, input logic [31:0] nw,
                                        input logic [3:0] en);
    merge = cur;
    for (int i = 0; i < 4; i++) if (en[i]) merge[8*i+:8] = nw[8*i+:8];
  endfunction

  logic we;
  assign we = sel && (be != 4'b0);

  always_ff @(posedge clk) begin
    if (reset) begin
      reg_led       <= '0;
      reg_display   <= '0;
      reg_disp_ctrl <= '0;
      reg_btn_count <= '0;
      reg_board_led <= '0;
      reg_scratch   <= '0;
      cycles        <= '0;
      buttons_prev  <= '0;
    end else begin
      cycles       <= cycles + 1;
      buttons_prev <= buttons[4:0];
      if (|(buttons[4:0] & ~buttons_prev))  // a new press on any button
        reg_btn_count <= reg_btn_count + 1;

      if (we) begin
        case (addr[5:2])
          4'h1:    reg_led <= merge(reg_led, wdata, be);
          4'h2:    reg_display <= merge(reg_display, wdata, be);
          4'h3:    reg_disp_ctrl <= merge(reg_disp_ctrl, wdata, be);
          4'h6:    reg_btn_count <= '0;
          4'h7:    reg_board_led <= merge(reg_board_led, wdata, be);
          4'h8:    reg_scratch <= merge(reg_scratch, wdata, be);
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    case (addr[5:2])
      4'h0:    rdata = 32'h5256_3332;
      4'h1:    rdata = reg_led;
      4'h2:    rdata = reg_display;
      4'h3:    rdata = reg_disp_ctrl;
      4'h4:    rdata = switches;
      4'h5:    rdata = buttons;
      4'h6:    rdata = reg_btn_count;
      4'h7:    rdata = reg_board_led;
      4'h8:    rdata = reg_scratch;
      4'h9:    rdata = CLK_HZ;
      4'hA:    rdata = cycles;
      default: rdata = 32'b0;
    endcase
  end

  assign led       = reg_board_led[7:0];
  assign btn_press = buttons[4:0] & ~buttons_prev;

  alchitry_io_interface #(
      .CLK_HZ(CLK_HZ)
  ) io_if (
      .clk               (clk),
      .reset             (reset),
      .led_register      (reg_led),
      .display_register  (reg_display),
      .disp_ctrl_register(reg_disp_ctrl),
      .switches_out      (switches),
      .buttons_out       (buttons),
      .io_led            (io_led),
      .io_dip            (io_dip),
      .io_button         (io_button),
      .io_select         (io_select),
      .io_segment        (io_segment)
  );

endmodule
