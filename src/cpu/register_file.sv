// 32 x 32-bit registers. Two combinational read ports, one clocked write port.
// x0 is hard-wired to zero.

module register_file (
    input  logic        clk,
    input  logic        we3,  // RegWrite
    input  logic [ 4:0] a1,   // rs1  = instr[19:15]
    input  logic [ 4:0] a2,   // rs2  = instr[24:20]
    input  logic [ 4:0] a3,   // rd   = instr[11:7]
    input  logic [31:0] wd3,  // Result
    output logic [31:0] rd1,
    output logic [31:0] rd2
);

  logic [31:0] regs[0:31];

  initial begin
    for (int i = 0; i < 32; i++) regs[i] = 32'b0;
  end

  // write on the rising edge, never to x0
  always_ff @(posedge clk) begin
    if (we3 && a3 != 5'd0) regs[a3] <= wd3;
  end

  // read any time
  assign rd1 = (a1 == 5'd0) ? 32'b0 : regs[a1];
  assign rd2 = (a2 == 5'd0) ? 32'b0 : regs[a2];

endmodule
