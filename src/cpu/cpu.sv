// cpu.sv -- 5-stage pipelined RV32I core (machine mode, with traps)   [M6]
//
//   IF   fetch      the next PC goes to the block RAM's address port
//   ID   decode     the instruction comes out of the block RAM; read registers
//   EX   execute    ALU, branch decision, address, CSRs -- and the COMMIT POINT
//   MEM  memory     load data comes back from the block RAM / peripherals
//   WB   write back register file write
//
// Commit point = EX.  Every exception (illegal, ecall, ebreak, misaligned
// fetch / load / store) and every interrupt is decided in EX.  So when the
// instruction in EX traps, every older instruction (MEM, WB) has already
// committed and can no longer trap, and every younger one (ID) is thrown away:
// traps are precise.  Stores, CSR writes and load side effects happen at the
// end of EX, only if the instruction commits.
//
// Hazards:
//   forwarding   EX takes rs1 / rs2 from MEM or WB when an older instruction is
//                about to write them; ID takes them from WB (same-cycle write)
//   load-use     an instruction right after a load that needs its result waits
//                one cycle in ID (the data only exists in WB)
//   redirect     a taken branch / jump, a trap, mret or fence.i in EX discards
//                the one instruction in ID (1 cycle penalty) and fetches the target
//
// Memory ports (soc.sv):
//   instruction: imem_addr is captured on the clock edge; imem_rdata is that
//                instruction in the next cycle.  imem_en = 0 holds it (stall).
//   RAM data:    loads / stores to 0x0xxx_xxxx: dmem_addr / dmem_be /
//                dmem_wdata are driven from EX, dmem_rdata arrives in MEM.
//   bus:         loads / stores anywhere else go over AXI4-Lite.  The
//                instruction commits in EX like any other; its request then
//                sits in the EX/MEM register and drives bus_* from MEM.  The SoC
//                holds bus_wait = 1 until the AXI response, and the pipeline up
//                to MEM freezes meanwhile (WB gets bubbles).  Because the request
//                and the wait both come from registers, this adds almost nothing
//                to the clock period.   [M7]

module cpu (
    input logic clk,
    input logic reset,

    // instruction port
    output logic [31:0] imem_addr,  // address of the instruction for ID in the next cycle
    output logic        imem_en,    // 0 = keep the current instruction (stall)
    input  logic [31:0] imem_rdata,

    // data port
    // RAM data port (from EX; data back in MEM)
    output logic [31:0] dmem_addr,   // byte address
    output logic [ 3:0] dmem_be,     // byte write enables (non-zero = store)
    output logic [31:0] dmem_wdata,  // store data, already in byte lanes
    input  logic [31:0] dmem_rdata,

    // bus port (from MEM, registered; to the AXI4-Lite bridge)   [M7]
    output logic        bus_req,    // a load or store waiting in MEM
    output logic        bus_write,
    output logic [31:0] bus_addr,
    output logic [ 3:0] bus_be,
    output logic [31:0] bus_wdata,
    input  logic        bus_wait,   // 1 = not finished: freeze up to MEM
    input  logic [31:0] bus_rdata,  // valid in the cycle the access finishes

    // interrupts and time (from the SoC)
    input logic        irq_msip,
    input logic        irq_mtip,
    input logic        irq_meip,
    input logic [63:0] mtime
);

  // =====================================================================
  // control from EX that steers the front of the pipeline
  // =====================================================================
  logic        redirect;  // EX changes the flow: discard ID, fetch redirect_pc
  logic [31:0] redirect_pc;
  logic        stall_id;  // load-use: hold ID, send a bubble to EX
  logic        freeze;  // bus access in MEM not finished: hold IF, ID, EX, MEM
  assign freeze = bus_wait;

  logic [31:0] src_a, fwd_b, src_b;  // EX operands after forwarding (used below)

  // =====================================================================
  // IF -- choose the next PC; the block RAM fetches it on the clock edge
  // =====================================================================
  logic [31:0] pc_id;  // PC of the instruction now in ID
  logic [31:0] pc_next;

  always_comb begin
    if (reset) pc_next = 32'h0000_0000;  // reset vector
    else if (redirect) pc_next = redirect_pc;
    else pc_next = pc_id + 32'd4;
  end

  assign imem_addr = pc_next;
  assign imem_en   = reset || !(stall_id || freeze);

  always_ff @(posedge clk) begin
    if (reset) pc_id <= 32'h0;
    else if (!stall_id && !freeze) pc_id <= pc_next;
  end

  // =====================================================================
  // ID -- decode, read registers
  // =====================================================================
  logic [31:0] instr_id, imm_id, rs1_val_id, rs2_val_id, rf_rd1, rf_rd2;
  logic [4:0] rs1_id, rs2_id, rd_id;
  logic [1:0] pc_src_id;
  logic [2:0] result_src_id, alu_control_id, imm_src_id;
  logic mem_write_id, mem_read_id, alu_src_id, alu_op_5_id, reg_write_id;
  logic illegal_id, ecall_id, ebreak_id, mret_id, csr_access_id, csr_write_id;
  logic fence_i_id, is_branch_id, uses_rs1_id, uses_rs2_id;

  assign instr_id = imem_rdata;
  assign rs1_id   = instr_id[19:15];
  assign rs2_id   = instr_id[24:20];
  assign rd_id    = instr_id[11:7];

  // With branch_taken tied to 1 the decoder reports every possible change of
  // flow in pc_src (01 = branch or jal, 10 = jalr); EX then decides branches.
  decoder ctrl (
      .instr       (instr_id),
      .branch_taken(1'b1),
      .pc_src      (pc_src_id),
      .result_src  (result_src_id),
      .mem_write   (mem_write_id),
      .mem_read    (mem_read_id),
      .alu_control (alu_control_id),
      .alu_op_5    (alu_op_5_id),
      .alu_src     (alu_src_id),
      .imm_src     (imm_src_id),
      .reg_write   (reg_write_id),
      .illegal     (illegal_id),
      .ecall       (ecall_id),
      .ebreak      (ebreak_id),
      .mret        (mret_id),
      .csr_access  (csr_access_id),
      .csr_write   (csr_write_id)
  );

  immediate_generator ext (
      .instr  (instr_id[31:7]),
      .imm_src(imm_src_id),
      .imm_ext(imm_id)
  );

  assign is_branch_id = (instr_id[6:0] == 7'b1100011);
  assign fence_i_id = (instr_id[6:0] == 7'b0001111) && (instr_id[14:12] == 3'b001);
  // which register fields are real sources (others hold immediate bits)
  assign uses_rs1_id = !(instr_id[6:0] == 7'b0110111 ||  // lui
      instr_id[6:0] == 7'b0010111 ||  // auipc
      instr_id[6:0] == 7'b1101111 ||  // jal
      (instr_id[6:0] == 7'b1110011 && instr_id[14]));  // csr…i (uimm)
  assign uses_rs2_id = (instr_id[6:0] == 7'b0110011 ||  // R-type
      instr_id[6:0] == 7'b0100011 ||  // stores
      instr_id[6:0] == 7'b1100011);  // branches

  // register file: written in WB, read here
  logic        reg_write_wb;
  logic [ 4:0] rd_wb;
  logic [31:0] result_wb;

  register_file rf (
      .clk(clk),
      .we3(reg_write_wb),
      .a1 (rs1_id),
      .a2 (rs2_id),
      .a3 (rd_wb),
      .wd3(result_wb),
      .rd1(rf_rd1),
      .rd2(rf_rd2)
  );

  // WB writes at the end of this cycle; pass that value straight through
  assign rs1_val_id = (reg_write_wb && rd_wb != 5'd0 && rd_wb == rs1_id) ? result_wb : rf_rd1;
  assign rs2_val_id = (reg_write_wb && rd_wb != 5'd0 && rd_wb == rs2_id) ? result_wb : rf_rd2;

  // load-use hazard: the instruction in EX is a load that writes a register
  // this instruction reads -> wait one cycle
  logic valid_ex, mem_read_ex;
  logic [4:0] rd_ex;
  logic       load_use;

  assign load_use = valid_ex && mem_read_ex && rd_ex != 5'd0 &&
                      ((uses_rs1_id && rs1_id == rd_ex) || (uses_rs2_id && rs2_id == rd_ex));
  assign stall_id = load_use && !redirect;

  // =====================================================================
  // ID/EX pipeline register
  // =====================================================================
  logic [31:0] pc_ex, instr_ex, imm_ex, rs1_val_ex, rs2_val_ex;
  logic [4:0] rs1_ex, rs2_ex;
  logic [1:0] pc_src_ex;
  logic [2:0] result_src_ex, alu_control_ex;
  logic mem_write_ex, alu_src_ex, alu_op_5_ex, reg_write_ex;
  logic illegal_ex, ecall_ex, ebreak_ex, mret_ex, csr_access_ex, csr_write_ex;
  logic fence_i_ex, is_branch_ex;

  always_ff @(posedge clk) begin
    if (freeze && !reset) begin
      // waiting for the bus: the instruction stays in EX.  Keep its operands
      // as they are now -- the instruction in WB they may be forwarded from
      // is leaving the pipeline while we wait.
      rs1_val_ex <= src_a;
      rs2_val_ex <= fwd_b;
    end else begin
      // a bubble after reset, behind a redirect, and during a load-use stall
      valid_ex       <= !(reset || redirect || stall_id);

      pc_ex          <= pc_id;
      instr_ex       <= instr_id;
      imm_ex         <= imm_id;
      rs1_val_ex     <= rs1_val_id;
      rs2_val_ex     <= rs2_val_id;
      rs1_ex         <= rs1_id;
      rs2_ex         <= rs2_id;
      rd_ex          <= rd_id;
      pc_src_ex      <= pc_src_id;
      result_src_ex  <= result_src_id;
      alu_control_ex <= alu_control_id;
      mem_write_ex   <= mem_write_id;
      mem_read_ex    <= mem_read_id;
      alu_src_ex     <= alu_src_id;
      alu_op_5_ex    <= alu_op_5_id;
      reg_write_ex   <= reg_write_id;
      illegal_ex     <= illegal_id;
      ecall_ex       <= ecall_id;
      ebreak_ex      <= ebreak_id;
      mret_ex        <= mret_id;
      csr_access_ex  <= csr_access_id;
      csr_write_ex   <= csr_write_id;
      fence_i_ex     <= fence_i_id;
      is_branch_ex   <= is_branch_id;
    end
  end

  // =====================================================================
  // EX -- execute, and decide whether the instruction commits
  // =====================================================================
  logic reg_write_mem, mem_read_mem;
  logic [ 4:0] rd_mem;
  logic [31:0] result_mem_ex;  // EX result carried in EX/MEM (not valid for loads)

  // forwarding: the newest value wins (MEM is newer than WB)
  always_comb begin
    if (reg_write_mem && !mem_read_mem && rd_mem != 5'd0 && rd_mem == rs1_ex) src_a = result_mem_ex;
    else if (reg_write_wb && rd_wb != 5'd0 && rd_wb == rs1_ex) src_a = result_wb;
    else src_a = rs1_val_ex;

    if (reg_write_mem && !mem_read_mem && rd_mem != 5'd0 && rd_mem == rs2_ex) fwd_b = result_mem_ex;
    else if (reg_write_wb && rd_wb != 5'd0 && rd_wb == rs2_ex) fwd_b = result_wb;
    else fwd_b = rs2_val_ex;
  end
  assign src_b = alu_src_ex ? imm_ex : fwd_b;

  logic [31:0] alu_result;
  logic branch_taken;

  // Dedicated address adder: loads, stores and jalr always need rs1 + imm.
  // Taking it from here instead of the ALU's output (after the ALU's result
  // mux) keeps the misaligned-address check and the jalr target short --
  // they sit on the longest path (into the trap decision and the next PC).
  logic [31:0] addr_sum;
  assign addr_sum = src_a + imm_ex;

  alu alu_unit (
      .a          (src_a),
      .b          (src_b),
      .alu_control(alu_control_ex),
      .alu_op_5   (alu_op_5_ex),
      .result     (alu_result)
      
  );

  branch_comparator bcmp (
      .a           (src_a),
      .b           (fwd_b),
      .funct3      (instr_ex[14:12]),
      .branch_taken(branch_taken)
  );

  logic [31:0] pc_plus4_ex, pc_target_ex, jump_target;
  logic taken;
  assign pc_plus4_ex  = pc_ex + 32'd4;
  assign pc_target_ex = pc_ex + imm_ex;
  assign jump_target  = (pc_src_ex == 2'b10) ? {addr_sum[31:1], 1'b0} : pc_target_ex;
  assign taken        = (pc_src_ex != 2'b00) && (!is_branch_ex || branch_taken);

  // store data into byte lanes (the load half of this instance is unused)
  logic [31:0] st_wdata, unused_load;
  logic [3:0] st_be;
  load_store_unit lsu_st (
      .funct3    (instr_ex[14:12]),
      .addr_lo   (addr_sum[1:0]),
      .mem_write (mem_write_ex),
      .store_data(fwd_b),
      .mem_wdata (st_wdata),
      .mem_be    (st_be),
      .mem_rdata (32'b0),
      .load_data (unused_load)
  );

  // ---------------- CSRs and traps ----------------
  logic commit, trap, exception, irq_pending, io_access, csr_illegal;
  logic exc_fetch, exc_load, exc_store;
  logic [3:0] exc_code, irq_code, trap_code;
  logic [31:0] trap_tval, trap_pc, mepc, csr_rdata;

  csr_unit csr (
      .clk        (clk),
      .reset      (reset),
      .csr_access (csr_access_ex && valid_ex),
      .csr_write  (csr_write_ex),
      .csr_addr   (instr_ex[31:20]),
      .csr_op     (instr_ex[13:12]),
      .csr_wsrc   (instr_ex[14] ? {27'b0, instr_ex[19:15]} : src_a),  // uimm or rs1
      .csr_rdata  (csr_rdata),
      .csr_illegal(csr_illegal),
      .commit     (commit),
      .trap       (trap),
      .trap_irq   (irq_pending),
      .trap_code  (trap_code),
      .trap_epc   (pc_ex),
      .trap_tval  (trap_tval),
      .trap_pc    (trap_pc),
      .mret       (mret_ex && commit),
      .mepc_out   (mepc),
      .irq_msip   (irq_msip),
      .irq_mtip   (irq_mtip),
      .irq_meip   (irq_meip),
      .irq_pending(irq_pending),
      .irq_code   (irq_code),
      .mtime      (mtime)
  );

  logic [1:0] ls_size;
  assign ls_size = instr_ex[13:12];
  assign exc_fetch = taken && jump_target[1];  // no compressed instructions
  assign exc_load  = mem_read_ex  && ((ls_size == 2'd1 && addr_sum[0]) ||
                                        (ls_size == 2'd2 && addr_sum[1:0] != 2'b00));
  assign exc_store = mem_write_ex && ((ls_size == 2'd1 && addr_sum[0]) ||
                                        (ls_size == 2'd2 && addr_sum[1:0] != 2'b00));

  always_comb begin
    exception = 1'b1;
    exc_code  = 4'd0;
    trap_tval = 32'b0;
    if (illegal_ex || csr_illegal) begin
      exc_code  = 4'd2;
      trap_tval = instr_ex;
    end else if (ebreak_ex) begin
      exc_code  = 4'd3;
      trap_tval = pc_ex;
    end else if (ecall_ex) begin
      exc_code = 4'd11;
    end else if (exc_fetch) begin
      exc_code  = 4'd0;
      trap_tval = jump_target;
    end else if (exc_load) begin
      exc_code  = 4'd4;
      trap_tval = addr_sum;
    end else if (exc_store) begin
      exc_code  = 4'd6;
      trap_tval = addr_sum;
    end else exception = 1'b0;
    if (irq_pending) trap_tval = 32'b0;
  end

  // a load / store outside RAM goes to the AXI bus (from MEM, see above)
  assign io_access = (mem_read_ex || mem_write_ex) && (addr_sum[31:28] != 4'h0);

  // only a real instruction (not a bubble) can trap or commit, and nothing
  // happens in EX while the pipeline is frozen for the bus
  assign trap      = valid_ex && !freeze && (irq_pending || exception);
  assign trap_code = irq_pending ? irq_code : exc_code;
  assign commit    = valid_ex && !freeze && !(irq_pending || exception);

  // change of flow, decided here
  always_comb begin
    redirect    = 1'b1;
    redirect_pc = trap_pc;
    if (trap) redirect_pc = trap_pc;
    else if (commit && mret_ex) redirect_pc = mepc;
    else if (commit && taken) redirect_pc = jump_target;
    else if (commit && fence_i_ex) redirect_pc = pc_plus4_ex;  // refetch after self-modifying code
    else redirect = 1'b0;
  end

  // data port: everything with a side effect only if the instruction commits
  assign dmem_addr  = addr_sum;
  assign dmem_be    = (commit && !io_access) ? st_be : 4'b0000;
  assign dmem_wdata = st_wdata;

  // result of everything except loads
  logic [31:0] result_ex;
  always_comb begin
    case (result_src_ex)
      3'b000:  result_ex = alu_result;  // ALU ops
      3'b010:  result_ex = pc_plus4_ex;  // jal, jalr (return address)
      3'b011:  result_ex = imm_ex;  // lui
      3'b100:  result_ex = pc_target_ex;  // auipc
      3'b101:  result_ex = csr_rdata;  // CSR instructions (old value)
      default: result_ex = 32'b0;  // loads: filled in MEM
    endcase
  end

  // =====================================================================
  // EX/MEM pipeline register
  // =====================================================================
  logic [2:0] funct3_mem;
  logic [1:0] addr_lo_mem;
  logic valid_mem, bus_mem;
  logic [31:0] pc_mem, instr_mem;

  always_ff @(posedge clk) begin
    if (reset) begin
      valid_mem     <= 1'b0;
      reg_write_mem <= 1'b0;
      mem_read_mem  <= 1'b0;
      bus_mem       <= 1'b0;
    end else if (!freeze) begin  // frozen: MEM keeps its bus access
      valid_mem     <= commit;
      reg_write_mem <= commit && reg_write_ex;
      mem_read_mem  <= commit && mem_read_ex;
      bus_mem       <= commit && io_access;
    end
    if (!freeze) begin
      rd_mem        <= rd_ex;
      result_mem_ex <= result_ex;
      funct3_mem    <= instr_ex[14:12];
      addr_lo_mem   <= addr_sum[1:0];
      pc_mem        <= pc_ex;
      instr_mem     <= instr_ex;
      bus_write     <= mem_write_ex;
      bus_addr      <= addr_sum;
      bus_be        <= st_be;
      bus_wdata     <= st_wdata;
    end
  end

  assign bus_req = bus_mem;

  // =====================================================================
  // MEM -- load data arrives; pick the bytes and extend them
  // =====================================================================
  logic [31:0] load_data, unused_wdata, result_mem;
  logic [3:0] unused_be;
  load_store_unit lsu_ld (
      .funct3    (funct3_mem),
      .addr_lo   (addr_lo_mem),
      .mem_write (1'b0),
      .store_data(32'b0),
      .mem_wdata (unused_wdata),
      .mem_be    (unused_be),
      .mem_rdata (bus_mem ? bus_rdata : dmem_rdata),
      .load_data (load_data)
  );

  assign result_mem = mem_read_mem ? load_data : result_mem_ex;

  // =====================================================================
  // MEM/WB pipeline register  ->  WB writes the register file
  // =====================================================================
  logic valid_wb;
  logic [31:0] pc_wb, instr_wb;

  always_ff @(posedge clk) begin
    if (reset) begin
      valid_wb     <= 1'b0;
      reg_write_wb <= 1'b0;
    end else begin  // frozen: a bubble goes to WB
      valid_wb     <= valid_mem && !freeze;
      reg_write_wb <= reg_write_mem && !freeze;
    end
    rd_wb     <= rd_mem;
    result_wb <= result_mem;
    pc_wb     <= pc_mem;
    instr_wb  <= instr_mem;
  end

endmodule
