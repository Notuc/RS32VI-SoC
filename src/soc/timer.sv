//   offset  name          access  meaning
//   0x00    MTIME         R/W     low 32 bits of a 64-bit counter, +1 every CPU clock
//   0x04    MTIMEH        R/W     high 32 bits
//   0x08    MTIMECMP      R/W     low 32 bits of the compare value
//   0x0C    MTIMECMPH     R/W     high 32 bits
//   0x10    MSIP          R/W     bit 0: software interrupt request
//
// Timer interrupt (MTIP) is high while MTIME >= MTIMECMP.  Software clears it
// by writing a later MTIMECMP.  MTIMECMP resets to all ones (never fires).
// Writes are whole 32-bit words.

module timer (
    input logic clk,
    input logic reset,

    input  logic        sel,
    input  logic [ 4:0] addr,
    input  logic [ 3:0] be,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    output logic [63:0] mtime,
    output logic        irq_mtip,
    output logic        irq_msip
);

  logic [63:0] mtimecmp;
  logic        msip;
  logic        we;
  assign we = sel && (be != 4'b0);

  always_ff @(posedge clk) begin
    if (reset) begin
      mtime    <= '0;
      mtimecmp <= '1;
      msip     <= 1'b0;
    end else begin
      mtime <= mtime + 1;
      if (we) begin
        case (addr[4:2])
          3'd0:    mtime[31:0] <= wdata;
          3'd1:    mtime[63:32] <= wdata;
          3'd2:    mtimecmp[31:0] <= wdata;
          3'd3:    mtimecmp[63:32] <= wdata;
          3'd4:    msip <= wdata[0];
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    case (addr[4:2])
      3'd0:    rdata = mtime[31:0];
      3'd1:    rdata = mtime[63:32];
      3'd2:    rdata = mtimecmp[31:0];
      3'd3:    rdata = mtimecmp[63:32];
      3'd4:    rdata = {31'b0, msip};
      default: rdata = 32'b0;
    endcase
  end

  assign irq_mtip = (mtime >= mtimecmp);
  assign irq_msip = msip;

endmodule
