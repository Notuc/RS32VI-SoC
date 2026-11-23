// Machine-mode CSRs, trap state and counters.
// Only machine mode is implemented (no S or U mode), so mstatus.MPP always reads 11.
//
//   addr   name      notes
//   0x300  mstatus   MIE (bit 3), MPIE (bit 7), MPP (12:11) reads 11
//   0x301  misa      RV32I, writes ignored
//   0x304  mie       MSIE (3), MTIE (7), MEIE (11)
//   0x305  mtvec     base [31:2]; bit 0 = 1 for vectored interrupts
//   0x310  mstatush  reads 0
//   0x320  mcountinhibit   bit 0 stops mcycle, bit 2 stops minstret
//   0x340  mscratch  free register for the trap handler
//   0x341  mepc      bits 1:0 read 0
//   0x342  mcause
//   0x343  mtval
//   0x344  mip       MSIP (3), MTIP (7), MEIP (11), set by hardware
//   0xB00 / 0xB80  mcycle(h)       64-bit cycle counter
//   0xB02 / 0xB82  minstret(h)     64-bit retired-instruction counter
//   0xC00-0xC82    cycle, time, instret (+h)   read-only user copies
//   all other counters and ID registers (mhpm*, mvendorid, marchid,
//   mimpid, mhartid, mconfigptr) read 0
//
// Any other address, or a write to a read-only CSR (addr[11:10] == 11), is illegal.

module csr_unit (
    input logic clk,
    input logic reset,

    // CSR instruction (csrrw / csrrs / csrrc and immediate forms)
    input logic csr_access,
    input logic csr_write,
    input logic [11:0] csr_addr,
    input logic [1:0] csr_op,  // funct3[1:0]: 01 rw, 10 rs, 11 rc
    input logic [31:0] csr_wsrc,  // rs1 value or zero-extended uimm
    output logic [31:0] csr_rdata,
    output logic csr_illegal,

    input logic commit,  // instruction completes (no trap)

    // trap entry / exit
    input  logic        trap,       // take a trap this cycle
    input  logic        trap_irq,   // 1 = interrupt, 0 = exception
    input  logic [ 3:0] trap_code,  // mcause code
    input  logic [31:0] trap_epc,
    input  logic [31:0] trap_tval,
    output logic [31:0] trap_pc,
    input  logic        mret,       // an mret is completing
    output logic [31:0] mepc_out,

    // interrupts
    input  logic       irq_msip,
    irq_mtip,
    irq_meip,
    output logic       irq_pending,  // an enabled interrupt should be taken now
    output logic [3:0] irq_code,

    // counters
    input logic [63:0] mtime
);

  logic mstatus_mie, mstatus_mpie;
  logic [11:0] mie;
  logic [31:0] mtvec, mscratch, mepc, mcause, mtval;
  logic [63:0] mcycle, minstret;
  logic [ 2:0] mcountinhibit;  // bits 0 (CY) and 2 (IR) are used

  logic [11:0] mip;
  assign mip = {irq_meip, 3'b0, irq_mtip, 3'b0, irq_msip, 3'b0};

  // read
  logic exists, read_only;
  assign read_only = (csr_addr[11:10] == 2'b11);

  always_comb begin
    exists    = 1'b1;
    csr_rdata = 32'b0;
    casez (csr_addr)
      12'h300: csr_rdata = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
      12'h301: csr_rdata = 32'h4000_0100;  // MXL = 32 bit, I
      12'h304: csr_rdata = {20'b0, mie};
      12'h305: csr_rdata = mtvec;
      12'h310: csr_rdata = 32'b0;
      12'h320: csr_rdata = {29'b0, mcountinhibit};
      12'h340: csr_rdata = mscratch;
      12'h341: csr_rdata = mepc;
      12'h342: csr_rdata = mcause;
      12'h343: csr_rdata = mtval;
      12'h344: csr_rdata = {20'b0, mip};
      12'hB00, 12'hC00: csr_rdata = mcycle[31:0];
      12'hB80, 12'hC80: csr_rdata = mcycle[63:32];
      12'hB02, 12'hC02: csr_rdata = minstret[31:0];
      12'hB82, 12'hC82: csr_rdata = minstret[63:32];
      12'hC01: csr_rdata = mtime[31:0];
      12'hC81: csr_rdata = mtime[63:32];
      12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'hF15: csr_rdata = 32'b0;
      default: begin
        // hpm counters / events 3..31: present, read as zero
        if (csr_addr >= 12'h323 && csr_addr <= 12'h33F) csr_rdata = 32'b0;
        else if (csr_addr >= 12'hB03 && csr_addr <= 12'hB1F) csr_rdata = 32'b0;
        else if (csr_addr >= 12'hB83 && csr_addr <= 12'hB9F) csr_rdata = 32'b0;
        else if (csr_addr >= 12'hC03 && csr_addr <= 12'hC1F) csr_rdata = 32'b0;
        else if (csr_addr >= 12'hC83 && csr_addr <= 12'hC9F) csr_rdata = 32'b0;
        else exists = 1'b0;
      end
    endcase
  end

  assign csr_illegal = csr_access && (!exists || (csr_write && read_only));

  // value to write
  logic [31:0] wval;
  always_comb begin
    case (csr_op)
      2'b01:   wval = csr_wsrc;
      2'b10:   wval = csr_rdata | csr_wsrc;
      2'b11:   wval = csr_rdata & ~csr_wsrc;
      default: wval = csr_rdata;
    endcase
  end

  logic do_write, wr_cycle, wr_instret;
  assign do_write   = csr_access && csr_write && commit;
  assign wr_cycle   = do_write && (csr_addr == 12'hB00 || csr_addr == 12'hB80);
  assign wr_instret = do_write && (csr_addr == 12'hB02 || csr_addr == 12'hB82);

  // interrupts
  // priority: external (11) > software (3) > timer (7)
  logic [11:0] active;
  assign active      = mip & mie;
  assign irq_pending = mstatus_mie && (active != 12'b0);
  always_comb begin
    if (active[11]) irq_code = 4'd11;
    else if (active[3]) irq_code = 4'd3;
    else irq_code = 4'd7;
  end

  // trap target
  // Vectored mode only applies to interrupts, and the interrupt cause comes
  // straight from registers -- so the vector address is computed in parallel
  // and the late trap decision only picks between two ready values.
  logic [31:0] tvec_base, tvec_irq;
  assign tvec_base = {mtvec[31:2], 2'b00};
  assign tvec_irq  = tvec_base + {26'b0, irq_code, 2'b00};
  assign trap_pc   = (trap_irq && mtvec[0]) ? tvec_irq : tvec_base;
  assign mepc_out  = mepc;

  // state
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      mstatus_mie   <= 1'b0;
      mstatus_mpie  <= 1'b0;
      mie           <= '0;
      mtvec         <= '0;
      mscratch      <= '0;
      mepc          <= '0;
      mcause        <= '0;
      mtval         <= '0;
      mcycle        <= '0;
      minstret      <= '0;
      mcountinhibit <= '0;
    end else begin
      // Counters
      // A write to either half replaces the count for that cycle
      // (the instruction's own increment is suppressed), as the spec requires.
      if (!mcountinhibit[0] && !wr_cycle) mcycle <= mcycle + 1;
      if (!mcountinhibit[2] && commit && !wr_instret) minstret <= minstret + 1;

      if (trap) begin
        mepc         <= {trap_epc[31:2], 2'b00};
        mcause       <= {trap_irq, 27'b0, trap_code};
        mtval        <= trap_tval;
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
      end else if (mret) begin
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
      end

      if (do_write) begin
        case (csr_addr)
          12'h300: begin
            mstatus_mie  <= wval[3];
            mstatus_mpie <= wval[7];
          end
          12'h304: mie <= wval[11:0] & 12'h888;
          12'h305: mtvec <= {wval[31:2], 1'b0, wval[0]};
          12'h320: mcountinhibit <= {wval[2], 1'b0, wval[0]};
          12'h340: mscratch <= wval;
          12'h341: mepc <= {wval[31:2], 2'b00};
          12'h342: mcause <= wval;
          12'h343: mtval <= wval;
          12'hB00: mcycle[31:0] <= wval;
          12'hB80: mcycle[63:32] <= wval;
          12'hB02: minstret[31:0] <= wval;
          12'hB82: minstret[63:32] <= wval;
          default: ;  // read-only bits / WARL zero
        endcase
      end
    end
  end

endmodule
