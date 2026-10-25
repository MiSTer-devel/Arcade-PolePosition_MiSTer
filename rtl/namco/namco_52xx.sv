//============================================================================
//  namco_52xx.sv -- Namco 52xx sample-player MCU: MB8843 + 1 KB mask ROM (ioctl index 6, 0xC00)
//  + the external 0x8000-byte voice ROM (ioctl index 5 +0x4000).
//  Based on MAME src/mame/namco/namco52.cpp and polepos.cpp.
//    K = command[3:0], SI = 1, R0/R1 = voice ROM nibbles in, R2/R3/O = voice ROM address out,
//    P = 4-bit sample out (pp_voice52_snd). Write-only over the 06xx (no read callback).
//============================================================================
`default_nettype none

module namco_52xx
(
    input  wire        clk,        // fabric clock (CLK_49M)
    input  wire        ena,        // MCU clock enable = clk_sys/32 = 1.536 MHz (MASTER_CLOCK/8/2)
    input  wire        reset_n,    // = ~system_reset & namco_reset (LS259 q1)

    // ---- 06xx bus-side (write-only from the Z80's perspective; see header) --
    input  wire        chip_sel,   // chipsel[2]: active-high IRQ/select pulse
    input  wire        wr_en,      // 06xx chip_wr[2] strobe (data_w broadcast, write-mode+selected)
    input  wire  [7:0] wr_data,

    // ---- sample output (namco52.cpp P_w) ----
    output wire  [3:0] discrete_p,    // P0-P3 -> NAMCO_52XX_P_DATA

    // ---- external sample ("voice") ROM, 0x8000 bytes, 1-clk sync read ------
    output wire [14:0] sample_addr,
    input  wire  [7:0] sample_data,

    // ---- MCU program ROM (ioctl index 6; this wrapper claims addr[11:10]==
    //      2'b11, i.e. the 0xC00-0xFFF slice) ----------------------------------
    input  wire        rom_wr,
    input  wire [11:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    // ---- command latch (namco52.cpp write()->write_sync(), simple one-way) --
    reg [7:0] latched_cmd;
    always @(posedge clk) begin
        if (!reset_n) latched_cmd <= 8'h00;
        else if (wr_en) latched_cmd <= wr_data;
    end

    // ---- sample-ROM address register (namco52.cpp R2_w/R3_w/O_w) -----------
    reg [15:0] address;
    wire [3:0] r2_out, r3_out;
    wire [3:0] oh_w, ol_w;
    wire [7:0] o_out_w = {oh_w, ol_w};

    always @(posedge clk) begin
        if (!reset_n) address <= 16'h0000;
        else if (ena) address <= { o_out_w, r3_out, r2_out };
    end

    assign sample_addr = address[14:0];
    // MAME bounds-check: `(offset < 0x8000) ? region[offset] : 0xff` -- addr[15]
    // set is exactly "offset >= 0x8000" since the mapped region is 0x8000 bytes.
    wire [7:0] rom_byte = address[15] ? 8'hFF : sample_data;

    // ---- K-port: command lower nibble; SI: hardwired to +5V -----------------
    wire [3:0] k_in  = latched_cmd[3:0];
    wire       si_in = 1'b1;

    // ---- R-ports: R0/R1 = sample ROM byte (in); R2/R3 = address (out) ------
    wire [3:0] r0_in = rom_byte[3:0];
    wire [3:0] r1_in = rom_byte[7:4];
    wire [3:0] r0_out_unused, r1_out_unused;
    wire [3:0] p_out;
    assign discrete_p = p_out;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 u_mcu
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),
        .ram_clr    (1'b0),        // MB88-2026-10-24: fleet mb88 power-on RAM clear, unused here

        .r0_port_in (r0_in), .r1_port_in (r1_in), .r2_port_in (4'h0), .r3_port_in (4'h0),
        .r0_port_out(r0_out_unused), .r1_port_out(r1_out_unused),
        .r2_port_out(r2_out), .r3_port_out(r3_out),
        .k_port_in  (k_in),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .p_port_out (p_out),

        .stby_n     (1'b1),
        .tc_n       (1'b1),      // no external clock source bound for 52xx in polepos.cpp
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (si_in),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // ---- 0x400 internal MCU ROM (ioctl index 6, offset 0xC00-0xFFF) -------
    dpram_dc #(.widthad_a(10)) rom_52xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr & (rom_addr_in[11:10] == 2'b11)), .q_b()
    );

endmodule

`default_nettype wire
