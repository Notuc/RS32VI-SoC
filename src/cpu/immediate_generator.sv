//   000  I   loads, addi/xori/..., slli/srli/srai, jalr
//   001  S   sb, sh, sw
//   010  B   beq, bne, blt, bge, bltu, bgeu
//   011  J   jal
//   100  U   lui, auipc  (upper 20 bits, low 12 bits zero)

module immediate_generator (
    input  logic [31:7] instr,
    input  logic [ 2:0] imm_src,
    output logic [31:0] imm_ext
);

  always_comb begin
    case (imm_src)
      3'b000:  imm_ext = {{20{instr[31]}}, instr[31:20]};  // I
      3'b001:  imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};  // S
      3'b010:  imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};  // B
      3'b011:  imm_ext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};  // J
      3'b100:  imm_ext = {instr[31:12], 12'b0};  // U
      default: imm_ext = 32'bx;
    endcase
  end

endmodule
