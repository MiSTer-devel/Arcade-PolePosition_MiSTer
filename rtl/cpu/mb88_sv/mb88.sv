// ============================================================================
//  mb88.sv -- wrapper giving mb88_core the darfpga / Xevious `mb88` port list;
//  generates the /32 timer tick internally from ena.
// ============================================================================

module mb88 #(parameter IRQ_ENTRY_STALL = 0)  // 54xx IRQ entry stall, see mb88_core.sv
(
    input  wire        clock,
    input  wire        ena,
    input  wire        reset_n,

    input  wire [3:0]  r0_port_in,  r1_port_in,  r2_port_in,  r3_port_in,
    output wire [3:0]  r0_port_out, r1_port_out, r2_port_out, r3_port_out,
    input  wire [3:0]  k_port_in,
    output wire [3:0]  ol_port_out, oh_port_out,
    output wire        o_wr,  // pulses on every outO
    output wire [3:0]  p_port_out,

    input  wire        stby_n,
    input  wire        tc_n,
    input  wire        irq_n,
    input  wire        sc_in_n,
    input  wire        si_n,
    output wire        sc_out_n,
    output wire        so_n,
    output wire        to_n,

    output wire [10:0] rom_addr,
    input  wire [7:0]  rom_data
);
    wire [15:0]  r_in  = {r3_port_in, r2_port_in, r1_port_in, r0_port_in};
    wire [15:0]  r_out;
    wire [7:0]   o_out;

    assign {r3_port_out, r2_port_out, r1_port_out, r0_port_out} = r_out;
    assign ol_port_out = o_out[3:0];
    assign oh_port_out = o_out[7:4];

    // serial/handshake outputs — mb88_core serial is a stub (as was darfpga's "Todo: Serial")
    assign sc_out_n = 1'b1;
    assign so_n     = 1'b1;
    assign to_n     = 1'b1;

    // ---- internal timer prescaler (mb88_core wants ena_timer PRE-÷32) ----
    // one ena_timer pulse per 32 ena (MAME mb88 timer prescale); the core gates it with pio7
    reg [4:0] tdiv;
    reg       ena_timer_int;
    always @(posedge clock) begin
        if (!reset_n) begin
            tdiv          <= 5'd0;
            ena_timer_int <= 1'b0;
        end else begin
            ena_timer_int <= 1'b0;
            if (ena) begin
                tdiv <= tdiv + 5'd1;
                if (tdiv == 5'd31) ena_timer_int <= 1'b1;
            end
        end
    end

    mb88_core #(.IRQ_ENTRY_STALL(IRQ_ENTRY_STALL)) core
    (
        .clk       (clock),
        .ce        (ena),
        .ena_timer (ena_timer_int),
        .reset_n   (reset_n),

        .prog_addr (rom_addr),
        .prog_data (rom_data),

        .k_in      (k_port_in),
        .r_in      (r_in),
        .r_out     (r_out),
        .p_out     (p_port_out),
        .o_out     (o_out),
        .o_wr      (o_wr),
        .si_in     (si_n),
        .so_out    (),
        .irq_n     (irq_n),
        .tc_in     (tc_n),

        .int_req   (1'b0),        // trace injection off on hardware
        .int_vec   (6'd0),

        .dbg_pc(), .dbg_fetch_pc(), .dbg_a(), .dbg_x(), .dbg_y(),
        .dbg_st(), .dbg_zf(), .dbg_cf(), .dbg_retire(), .dbg_int_ack(),
        .dbg_illegal(), .dbg_ram()
    );

    // silence unused inputs (stby_n / sc_in_n not modeled)
    // verilator lint_off UNUSED
    wire _wunused = &{1'b0, stby_n, sc_in_n};
    // verilator lint_on UNUSED
endmodule
