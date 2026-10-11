//============================================================================
//  namco_51xx.sv -- Namco 51xx I/O MCU (coins / switches): MB8843 + 1 KB mask ROM (ioctl index 6, 0x000).
//  Based on MAME src/devices/machine/namco51.cpp and polepos.cpp.
//    R0/R1 = DSWB low/high nibble, R2/R3 = IN0 low/high nibble; K3 = 06xx R/!W, K2:0 = mailbox[2:0].
//  The mailbox (MAME m_portO) is one byte written by both the Z80 (06xx write) and the MCU (outO).
//============================================================================
`default_nettype none

module namco_51xx
(
    input  wire        clk,        // fabric clock (CLK_49M)
    input  wire        ena,        // MCU clock enable = clk_sys/32 = 1.536 MHz (MASTER_CLOCK/8/2)
    input  wire        reset_n,    // = ~system_reset & namco_reset (LS259 q1, MAME reset(state))

    // ---- 06xx bus-side (per-chip signals from namco_06xx) ------------------
    input  wire        chip_sel,   // chipsel[0]: active-high IRQ/select pulse
    input  wire        rw_in,      // 06xx rw0 (R/!W direction, mirrors ctrl[4])
    output wire  [7:0] data_out,   // -> namco_06xx chip0_din (data_r AND-reduce input)
    input  wire        wr_en,      // 06xx chip_wr[0] strobe (data_w broadcast, write-mode+selected)
    input  wire  [7:0] wr_data,

    // ---- polepos I/O mapping (namco51.cpp R_r<0..3>) -----------------------
    input  wire  [7:0] dswb,       // DSWB: input<0>=dswb[3:0] input<1>=dswb[7:4]
    input  wire  [7:0] in0,        // IN0:  input<2>=in0[3:0]  input<3>=in0[7:4]

    output wire  [3:0] p_port_out, // MAME P_w -> output_callback (coin counters) — unwired downstream

    // ---- ROM (ioctl index 6; this wrapper claims addr[11:10]==2'b00, i.e.
    //      the 0x000-0x3FF slice) --------------------------------------------
    input  wire        rom_wr,
    input  wire [11:0] rom_addr_in,
    input  wire  [7:0] rom_data_in,

    // ---- vblank -> mb88 TC (external-counter) pin --------------------------
    //   MAME: vblank drives MB88XX_TC_LINE (falling edge = vblank start)
    input  wire        vblank
);

    // ---- shared mailbox (see header) ---------------------------------------
    // MAME re-latches the mailbox on every outO, even an unchanged value.
    wire [7:0] o_out_w;
    wire       o_wr_w;
    reg  [7:0] mailbox;

    // o_wr stays high for a whole MCU cycle: gate with ena so each outO latches exactly once.
    always @(posedge clk) begin
        if (!reset_n) begin
            mailbox <= 8'h00;
        end else begin
            if (wr_en)                mailbox <= wr_data;   // Z80 write wins (matches MAME order)
            else if (o_wr_w && ena)   mailbox <= o_out_w;   // MCU outO: ONE latch per instruction
        end
    end

    assign data_out = mailbox;

    // ---- K-port: K3=rw (external), K2:0 = mailbox low nibble bits ----------
    wire [3:0] k_in = {rw_in, mailbox[2:0]};

    // ---- R-ports: DSWB (R0/R1), IN0 (R2/R3) --------------------------------
    wire [3:0] r0_in = dswb[3:0];
    wire [3:0] r1_in = dswb[7:4];
    wire [3:0] r2_in = in0[3:0];
    wire [3:0] r3_in = in0[7:4];
    wire [3:0] r0_out, r1_out, r2_out, r3_out;  // unused (51xx doesn't drive R as outputs in polepos)

    wire [3:0] oh_w, ol_w;
    assign o_out_w = {oh_w, ol_w};

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
        .o_wr       (o_wr_w),
        .p_port_out (p_port_out),

        .stby_n     (1'b1),
        // TC = ~vblank: the external-counter timer ticks at vblank start
        .tc_n       (~vblank),
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // ---- 0x400 internal MCU ROM (ioctl index 6, offset 0x000-0x3FF) -------
    // 10-bit mask ROM; the core's 11-bit address top bit is unused
    dpram_dc #(.widthad_a(10)) rom_51xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr & (rom_addr_in[11:10] == 2'b00)), .q_b()
    );

endmodule

`default_nettype wire
