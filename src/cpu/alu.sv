// alu_control is funct3 for OP / OP-IMM instructions (and 000 = ADD for
// loads, stores, jumps and LUI/AUIPC). alu_op_5 is instr[30]: SUB vs ADD, SRA vs SRL.

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [ 2:0] alu_control,
    input  logic        alu_op_5,
    output logic [31:0] result
);

  always_comb begin
    case (alu_control)
      3'b000: result = alu_op_5 ? a - b : a + b;  // SUB / ADD
      3'b001: result = a << b[4:0];  // SLL
      3'b010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;  // SLT
      3'b011: result = (a < b) ? 32'd1 : 32'd0;  // SLTU
      3'b100: result = a ^ b;  // XOR
      3'b101:
      if (alu_op_5) result = $signed(a) >>> b[4:0];  // SRA
      else result = a >> b[4:0];  // SRL
      3'b110: result = a | b;  // OR
      3'b111: result = a & b;  // AND
    endcase
  end

endmodule
