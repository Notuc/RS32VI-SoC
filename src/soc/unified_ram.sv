// One memory for code AND data, built from block RAM.
//
//   port A : instruction fetch   (read only)
//   port B : loads and stores    (byte write enables)
//
// Both reads are SYNCHRONOUS: the addr is captured on a rising clock edge
// and the data comes just after that edger.  
// The pipelined CPU is built around that delay.
//
// Port B is read-first: a store returns the old word (nobody uses it).
// Addresses wrap at the RAM size (the SoC only sends 0x0xxx_xxxx here).

module unified_ram #(
    parameter int WORDS    = 16384,         // 16384 words = 64 KB
    parameter     MEM_FILE = "program.mem"  // one 32-bit hex word per line
) (
    input logic clk,

    // port A: instruction fetch
    input  logic        a_en,    // 0 = keep the previous output (pipeline stall)
    input  logic [31:0] a_addr,  // byte address
    output logic [31:0] a_rdata, // word at the address from the previous edge

    // port B: data
    input  logic [31:0] b_addr,   // byte address
    input  logic [ 3:0] b_be,     // byte write enables (0 = no write)
    input  logic [31:0] b_wdata,  // already placed in byte lanes
    output logic [31:0] b_rdata   // word at the address from the previous edge
);

  localparam int AW = $clog2(WORDS);

  (* ram_style = "block" *) logic [31:0] mem[0:WORDS-1];

  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = 32'b0;  // unused space reads as 0, not X
    $readmemh(MEM_FILE, mem);
  end

  logic [AW-1:0] a_idx, b_idx;
  assign a_idx = a_addr[AW+1:2];
  assign b_idx = b_addr[AW+1:2];

  always_ff @(posedge clk) begin
    if (a_en) a_rdata <= mem[a_idx];
  end

  always_ff @(posedge clk) begin
    for (int i = 0; i < 4; i++) if (b_be[i]) mem[b_idx][8*i+:8] <= b_wdata[8*i+:8];
    b_rdata <= mem[b_idx];
  end

endmodule
