//============================================================================
//  namco_53xx.sv -- Namco 53xx I/O MCU (steering / DSWA): MB8843 + 1 KB mask ROM (ioctl index 6, 0x400).
//  Based on MAME src/devices/machine/namco53.cpp and polepos.cpp (steering_changed_r / steering_delta_r).
//    K = 0 (hardwired), R0/R1 = steering changed / delta, R2/R3 = DSWA low/high nibble. Read-only over the 06xx.
//  The steering accumulator updates every MCU clock rather than on each R0 poll.
//============================================================================
`default_nettype none

module namco_53xx
(
    input  wire        clk,        // fabric clock (CLK_49M)
    input  wire        ena,        // MCU clock enable = clk_sys/32 = 1.536 MHz (MASTER_CLOCK/8/2)
    input  wire        reset_n,    // = ~system_reset & namco_reset (LS259 q1)

    // ---- 06xx bus-side ------------------------------------------------------
    input  wire        chip_sel,   // chipsel[1]: active-high IRQ/select pulse
    output wire  [7:0] data_out,   // -> namco_06xx chip1_din (data_r AND-reduce input)

    // ---- polepos I/O mapping ------------------------------------------------
    input  wire  [7:0] dswa,       // DSWA: input<2>=dswa[3:0] input<3>=dswa[7:4]
    input  wire  [7:0] steer_in,   // raw 8-bit dial position (MAME m_steer_io->read())

    // ---- ROM (ioctl index 6; this wrapper claims addr[11:10]==2'b01, i.e.
    //      the 0x400-0x7FF slice) --------------------------------------------
    input  wire        rom_wr,
    input  wire [11:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    // ---- steering accumulator (polepos.cpp steering_changed_r, verbatim
    reg  [7:0]       steer_last;
    reg  signed [8:0] steer_accum;
    reg              steer_delta;

    wire signed [8:0] diff2 = ($signed({1'b0, steer_in}) - $signed({1'b0, steer_last})) <<< 1;
    wire signed [8:0] accum_pre = steer_accum + diff2;

    always @(posedge clk) begin
        if (!reset_n) begin
            steer_last  <= 8'h00;
            steer_accum <= 9'sd0;
            steer_delta <= 1'b0;
        end else if (ena) begin
            steer_last <= steer_in;
            if (accum_pre < 0) begin
                steer_delta <= 1'b0;
                steer_accum <= accum_pre + 9'sd1;
            end else if (accum_pre > 0) begin
                steer_delta <= 1'b1;
                steer_accum <= accum_pre - 9'sd1;
            end else begin
                steer_accum <= accum_pre;
            end
        end
    end

    wire steer_changed_bit = steer_accum[0];

    // ---- K-port: hardwired to 0 in polepos.cpp -----------------------------
    wire [3:0] k_in = 4'h0;

    // ---- R-ports: steering (R0/R1), DSWA (R2/R3) ---------------------------
    wire [3:0] r0_in = {3'b000, steer_changed_bit};
    wire [3:0] r1_in = {3'b000, steer_delta};
    wire [3:0] r2_in = dswa[3:0];
    wire [3:0] r3_in = dswa[7:4];
    wire [3:0] r0_out, r1_out, r2_out, r3_out;  // unused (53xx doesn't drive R as outputs)
    wire [3:0] p_out_unused;

    wire [3:0] oh_w, ol_w;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 u_mcu
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),

        .r0_port_in (r0_in), .r1_port_in (r1_in), .r2_port_in (r2_in), .r3_port_in (r3_in),
        .r0_port_out(r0_out), .r1_port_out(r1_out), .r2_port_out(r2_out), .r3_port_out(r3_out),
        .k_port_in  (k_in),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .p_port_out (p_out_unused),

        .stby_n     (1'b1),
        .tc_n       (1'b1),
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // read() returns the O-port directly (no shared mailbox)
    assign data_out = {oh_w, ol_w};

    // ---- 0x400 internal MCU ROM (ioctl index 6, offset 0x400-0x7FF) -------
    dpram_dc #(.widthad_a(10)) rom_53xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr & (rom_addr_in[11:10] == 2'b01)), .q_b()
    );

endmodule

`default_nettype wire
