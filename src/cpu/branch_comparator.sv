// Compares rs1 and rs2 directly and decides whether a branch is taken.
//   funct3  instr  taken when
//   000     beq    rs1 == rs2
//   001     bne    rs1 != rs2
//   100     blt    rs1 <  rs2  (signed)
//   101     bge    rs1 >= rs2  (signed)
//   110     bltu   rs1 <  rs2  (unsigned)
//   111     bgeu   rs1 >= rs2  (unsigned)

module branch_comparator (
    input  logic [31:0] a,            // RD1 (rs1)
    input  logic [31:0] b,            // RD2 (rs2)
    input  logic [ 2:0] funct3,       // instr[14:12]
    output logic        branch_taken
);

  logic eq, lt, ltu;

  assign eq  = (a == b);
  assign lt  = ($signed(a) < $signed(b));
  assign ltu = (a < b);

  always_comb begin
    case (funct3)
      3'b000:  branch_taken = eq;
      3'b001:  branch_taken = ~eq;
      3'b100:  branch_taken = lt;
      3'b101:  branch_taken = ~lt;
      3'b110:  branch_taken = ltu;
      3'b111:  branch_taken = ~ltu;
      default: branch_taken = 1'b0;  // 010, 011 are not valid branches
    endcase
  end

endmodule
