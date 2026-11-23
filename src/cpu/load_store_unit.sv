//  funct3  load   store
//  000     lb     sb
//  001     lh     sh
//  010     lw     sw
//  100     lbu    -
//  101     lhu    -
//
// Byte lanes (LE): address ...00 -> bits [7:0], ...01 -> [15:8],
//                             ...10 -> [23:16], ...11 -> [31:24]

module load_store_unit (
    input logic [2:0] funct3,  // instr[14:12]
    input logic [1:0] addr_lo,  // ALUResult[1:0]
    input logic mem_write,  // from decoder

    // store path: CPU to RAM
    input  logic [31:0] store_data,  // rs2 (RD2 / WriteData)
    output logic [31:0] mem_wdata,   // rs2 moved into the right byte lanes
    output logic [ 3:0] mem_be,      // byte write enables

    // load path: RAM to CPU
    input  logic [31:0] mem_rdata,  // whole word from RAM
    output logic [31:0] load_data   // extracted + sign/zero-extended value
);

  //  stores 
  always_comb begin
    mem_wdata = 32'b0;
    mem_be    = 4'b0000;
    if (mem_write) begin
      case (funct3[1:0])
        2'b00: begin  // sb
          mem_wdata = {4{store_data[7:0]}};  // copy byte to every lane
          mem_be    = 4'b0001 << addr_lo;  // enable only one lane
        end
        2'b01: begin  // sh
          mem_wdata = {2{store_data[15:0]}};
          mem_be    = addr_lo[1] ? 4'b1100 : 4'b0011;
        end
        default: begin  // sw
          mem_wdata = store_data;
          mem_be    = 4'b1111;
        end
      endcase
    end
  end

  // loads 
  logic [ 7:0] byte_sel;
  logic [15:0] half_sel;

  assign byte_sel = mem_rdata >> (8 * addr_lo);  // addressed byte
  assign half_sel = addr_lo[1] ? mem_rdata[31:16] : mem_rdata[15:0];

  always_comb begin
    case (funct3)
      3'b000:  load_data = {{24{byte_sel[7]}}, byte_sel};  // lb  (sign-extend)
      3'b001:  load_data = {{16{half_sel[15]}}, half_sel};  // lh  (sign-extend)
      3'b100:  load_data = {24'b0, byte_sel};  // lbu (zero-extend)
      3'b101:  load_data = {16'b0, half_sel};  // lhu (zero-extend)
      default: load_data = mem_rdata;  // lw
    endcase
  end

endmodule
