//   loads:      lb, lh, lw, lbu, lhu
//   stores: sb, sh, sw
//   R-type:     add, sub, sll, slt, sltu, xor, srl, sra, or, and
//   I-type ALU: addi, slti, sltiu, xori, ori, andi, slli, srli, srai
//   branches:   beq, bne, blt, bge, bltu, bgeu
//   jumps: jal, jalr   upper imm: lui, auipc
//   fence, fence.i, wfi:             no-ops on this core
//   csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci
//   ecall, ebreak, mret

module decoder (
    input logic [31:0] instr,
    input logic        branch_taken, // from branch_comparator

    output logic [1:0] pc_src,       // 00: PC+4  01: PCTarget  10: ALUResult & ~1 (jalr)
    output logic [2:0] result_src,   // 000: ALUResult  001: LoadData  010: PC+4
                                     // 011: ImmExt (lui)  100: PCTarget (auipc)  101: CSR
    output logic       mem_write,
    output logic       mem_read,
    output logic [2:0] alu_control,
    output logic       alu_op_5,     // 1: sub / sra   0: add / srl
    output logic       alu_src,      // 0: RD2       1: ImmExt
    output logic [2:0] imm_src,      // 000 I, 001 S, 010 B, 011 J, 100 U
    output logic       reg_write,

    // system
    output logic illegal,
    output logic ecall,
    output logic ebreak,
    output logic mret,
    output logic csr_access,  // a CSR instruction
    output logic csr_write    // that writes (csrrw always; csrrs/c only if rs1/uimm != 0)
);

  logic [6:0] op;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rs1;
  assign op     = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];
  assign rs1    = instr[19:15];

  logic branch, jump, jalr;
  logic [1:0] alu_op;

  // main decoder 
  always_comb begin
    // safe defaults: nothing gets written, PC just advances
    reg_write  = 1'b0;
    imm_src    = 3'b000;
    alu_src    = 1'b0;
    mem_write  = 1'b0;
    mem_read   = 1'b0;
    result_src = 3'b000;
    alu_op     = 2'b00;
    branch     = 1'b0;
    jump       = 1'b0;
    jalr       = 1'b0;
    illegal    = 1'b0;
    ecall      = 1'b0;
    ebreak     = 1'b0;
    mret       = 1'b0;
    csr_access = 1'b0;
    csr_write  = 1'b0;

    case (op)
      7'b0000011: begin  // loads: lb lh lw lbu lhu
        reg_write = 1;
        imm_src = 3'b000;
        alu_src = 1;
        mem_read = 1;
        result_src = 3'b001;
        alu_op = 2'b00;
        illegal = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
      end
      7'b0100011: begin  // stores: sb sh sw
        imm_src = 3'b001;
        alu_src = 1;
        mem_write = 1;
        alu_op = 2'b00;
        illegal = funct3[2] || (funct3 == 3'b011);
      end
      7'b0110011: begin  // R-type
        reg_write = 1;
        alu_src = 0;
        result_src = 3'b000;
        alu_op = 2'b10;
        // funct7 must be 0, or 0x20 for sub / sra
        illegal = !((funct7 == 7'h00) ||
                            (funct7 == 7'h20 && (funct3 == 3'b000 || funct3 == 3'b101)));
      end
      7'b0010011: begin  // I-type ALU
        reg_write = 1;
        imm_src = 3'b000;
        alu_src = 1;
        result_src = 3'b000;
        alu_op = 2'b10;
        // shifts: imm[11:5] must be 0 (slli, srli) or 0x20 (srai); shamt[5] must be 0
        if (funct3 == 3'b001) illegal = (funct7 != 7'h00);
        if (funct3 == 3'b101) illegal = !(funct7 == 7'h00 || funct7 == 7'h20);
      end
      7'b1100011: begin  // branches
        imm_src = 3'b010;
        alu_src = 0;
        branch  = 1;
        alu_op  = 2'b01;
        illegal = (funct3 == 3'b010) || (funct3 == 3'b011);
      end
      7'b1101111: begin  // jal:  rd = PC+4,  PC = PC + imm
        reg_write = 1;
        imm_src = 3'b011;
        result_src = 3'b010;
        jump = 1;
      end
      7'b1100111: begin  // jalr: rd = PC+4,  PC = (rs1 + imm) & ~1
        reg_write = 1;
        imm_src = 3'b000;
        alu_src = 1;
        result_src = 3'b010;
        alu_op = 2'b00;
        jalr = 1;
        illegal = (funct3 != 3'b000);
      end
      7'b0110111: begin  // lui:  rd = imm << 12
        reg_write = 1;
        imm_src = 3'b100;
        result_src = 3'b011;
      end
      7'b0010111: begin  // auipc: rd = PC + (imm << 12)
        reg_write = 1;
        imm_src = 3'b100;
        result_src = 3'b100;
      end
      7'b0001111: begin  // fence (000), fence.i (001): nothing to do on this core
        illegal = (funct3[2:1] != 2'b00);
      end
      7'b1110011: begin  // SYSTEM
        if (funct3 == 3'b000) begin
          case (instr)
            32'h0000_0073: ecall = 1;
            32'h0010_0073: ebreak = 1;
            32'h3020_0073: mret = 1;
            32'h1050_0073: ;  // wfi: allowed to be a no-op
            default:       illegal = 1;
          endcase
        end else if (funct3 == 3'b100) begin
          illegal = 1;
        end else begin  // csrrw/s/c(i)
          csr_access = 1;
          reg_write  = 1;
          result_src = 3'b101;
          csr_write  = (funct3[1:0] == 2'b01) || (rs1 != 5'd0);
        end
      end
      default: illegal = 1;
    endcase

    if (illegal) begin  // illegal instruction
      reg_write = 0;
      mem_write = 0;
      mem_read = 0;
      branch = 0;
      jump = 0;
      jalr = 0;
      csr_access = 0;
    end
  end

  //next-PC select
  always_comb begin
    if (jalr) pc_src = 2'b10;
    else if (jump | (branch & branch_taken)) pc_src = 2'b01;
    else pc_src = 2'b00;
  end

  // ALU decoder
  logic use_funct7_5;
  assign use_funct7_5 = op[5] | (funct3 == 3'b101);

  always_comb begin
    case (alu_op)
      2'b00: begin  // loads / stores / jalr: address add
        alu_control = 3'b000;
        alu_op_5    = 1'b0;
      end
      2'b01: begin  // branches: comparator decides,
        alu_control = 3'b000;  // ALU result unused (sub kept
        alu_op_5    = 1'b1;  // so zero still means rs1==rs2)
      end
      default: begin  // R-type / I-type ALU
        alu_control = funct3;
        alu_op_5    = funct7[5] & use_funct7_5;
      end
    endcase
  end

endmodule
