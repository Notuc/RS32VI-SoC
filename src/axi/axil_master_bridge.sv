// axil_master_bridge -- CPU data port -> AXI4-Lite master
//
// The CPU's MEM stage raises cpu_req (held until done). The bridge runs one
// AXI4-Lite transaction and holds cpu_wait = 1 until the B or R handshake;
// read data is on cpu_rdata in that same cycle.
//
// Protocol rules followed (checked in sim by src/sim/axil_checker.sv):
//   - VALID stays high, with a stable payload, until READY
//   - VALID never waits for READY; READY may wait for VALID
//   - AW and W are issued together and may be accepted in either order
//   - one transaction at a time
//
// Not handled: SLVERR / DECERR responses are ignored. A later version could
// turn them into load / store access faults (mcause 5 / 7).

module axil_master_bridge (
    input logic clk,
    input logic reset,

    // CPU side
    input  logic        cpu_req,    // a load or store for the bus, this cycle
    input  logic        cpu_write,  // 1 = store (cpu_be != 0)
    input  logic [31:0] cpu_addr,
    input  logic [ 3:0] cpu_be,
    input  logic [31:0] cpu_wdata,
    output logic        cpu_wait,   // 1 = not finished yet
    output logic [31:0] cpu_rdata,  // load data, in the completing cycle

    // AXI4-Lite master
    output logic [31:0] m_awaddr,
    output logic [ 2:0] m_awprot,
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [31:0] m_wdata,
    output logic [ 3:0] m_wstrb,
    output logic        m_wvalid,
    input  logic        m_wready,
    input  logic [ 1:0] m_bresp,
    input  logic        m_bvalid,
    output logic        m_bready,
    output logic [31:0] m_araddr,
    output logic [ 2:0] m_arprot,
    output logic        m_arvalid,
    input  logic        m_arready,
    input  logic [31:0] m_rdata,
    input  logic [ 1:0] m_rresp,
    input  logic        m_rvalid,
    output logic        m_rready
);

  typedef enum logic [1:0] {
    IDLE,
    WRITE,
    READ
  } state_t;
  state_t state;

  logic [31:0] addr_q;
  assign m_awaddr  = addr_q;  // held for the whole transaction, so the
  assign m_araddr  = addr_q;  // interconnect can route the response
  assign m_awprot  = 3'b000;  // unprivileged, secure, data
  assign m_arprot  = 3'b000;

  assign m_bready  = (state == WRITE);  // always ready for our own response
  assign m_rready  = (state == READ);
  assign cpu_rdata = m_rdata;

  logic done;
  assign done = (state == WRITE && m_bvalid) || (state == READ && m_rvalid);

  // busy from the first cycle of a request until the response handshake
  assign cpu_wait = (state == IDLE) ? cpu_req : !done;

  always_ff @(posedge clk) begin
    if (reset) begin
      state     <= IDLE;
      addr_q    <= 32'b0;  // defined decode before the first transfer
      m_awvalid <= 1'b0;
      m_wvalid  <= 1'b0;
      m_arvalid <= 1'b0;
    end else begin
      case (state)
        IDLE:
        if (cpu_req) begin
          addr_q <= cpu_addr;
          if (cpu_write) begin
            m_wdata   <= cpu_wdata;
            m_wstrb   <= cpu_be;
            m_awvalid <= 1'b1;
            m_wvalid  <= 1'b1;
            state     <= WRITE;
          end else begin
            m_arvalid <= 1'b1;
            state     <= READ;
          end
        end
        WRITE: begin
          if (m_awvalid && m_awready) m_awvalid <= 1'b0;
          if (m_wvalid && m_wready) m_wvalid <= 1'b0;
          if (m_bvalid) state <= IDLE;  // bready = 1 here
        end
        READ: begin
          if (m_arvalid && m_arready) m_arvalid <= 1'b0;
          if (m_rvalid) state <= IDLE;  // rready = 1 here
        end
        default: state <= IDLE;
      endcase
    end
  end

endmodule
