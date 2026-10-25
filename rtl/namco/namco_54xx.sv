//============================================================================
//  namco_54xx.sv -- Namco 54xx noise-generator MCU: MB8844 + 1 KB mask ROM (ioctl index 6, 0x800).
//  Based on MAME src/mame/namco/namco54.cpp and polepos.cpp.
//    K = command[7:4], R0 = command[3:0]; O-port and R1 drive the three 4-bit discrete outputs (pp_noise54_snd).
//  Write-only over the 06xx (no read callback).
//============================================================================
`default_nettype none

module namco_54xx
(
    input  wire        clk,        // fabric clock (CLK_49M)
    input  wire        ena,        // MCU clock enable = clk_sys/32 = 1.536 MHz (MASTER_CLOCK/8/2)
    input  wire        reset_n,    // = ~system_reset & namco_reset (LS259 q1)

    // ---- 06xx bus-side (write-only from the Z80's perspective; see header) --
    input  wire        chip_sel,   // chipsel[3]: active-high IRQ/select pulse
    input  wire        wr_en,      // 06xx chip_wr[3] strobe (data_w broadcast, write-mode+selected)
    input  wire  [7:0] wr_data,

    // ---- discrete circuit outputs (namco54.cpp O_w / R1_w) ----
    output wire  [3:0] discrete_o0,   // O0-O3 (mem_mask 0x0f half) -> NAMCO_54XX_0_DATA
    output wire  [3:0] discrete_o1,   // O4-O7 (mem_mask 0xf0 half) -> NAMCO_54XX_1_DATA
    output wire  [3:0] discrete_r1,   // R1 out                     -> NAMCO_54XX_2_DATA

    // ---- ROM (ioctl index 6; this wrapper claims addr[11:10]==2'b10, i.e.
    //      the 0x800-0xBFF slice) --------------------------------------------
    input  wire        rom_wr,
    input  wire [11:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    // ---- command latch (namco54.cpp write()->write_sync(), simple one-way) --
    reg [7:0] latched_cmd;
    always @(posedge clk) begin
        if (!reset_n) latched_cmd <= 8'h00;
        else if (wr_en) latched_cmd <= wr_data;
    end

    // ---- K-port: command upper nibble; R0: command lower nibble ------------
    wire [3:0] k_in  = latched_cmd[7:4];
    wire [3:0] r0_in = latched_cmd[3:0];
    wire [3:0] r1_in = 4'h0;  // R1 is output-only here (namco54.cpp never sets read_r<1>)
    wire [3:0] r2_in = 4'h0, r3_in = 4'h0;  // unused (no read_r<2>/<3> bound)
    wire [3:0] r0_out_unused, r2_out_unused, r3_out_unused;
    wire [3:0] r1_out;
    wire [3:0] p_out_unused;

    wire [3:0] oh_w, ol_w;
    assign discrete_o0 = ol_w;
    assign discrete_o1 = oh_w;
    assign discrete_r1 = r1_out;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 #(.IRQ_ENTRY_STALL(3)) u_mcu  // MAME-exact IRQ entry stall (see mb88_core.sv)
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),
        .ram_clr    (1'b0),        // MB88-2026-10-24: fleet mb88 power-on RAM clear, unused here

        .r0_port_in (r0_in), .r1_port_in (r1_in), .r2_port_in (r2_in), .r3_port_in (r3_in),
        .r0_port_out(r0_out_unused), .r1_port_out(r1_out),
        .r2_port_out(r2_out_unused), .r3_port_out(r3_out_unused),
        .k_port_in  (k_in),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .p_port_out (p_out_unused),

        .stby_n     (1'b1),
        .tc_n       (1'b1),      // no external clock source bound for 54xx in polepos.cpp
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // ---- 0x400 internal MCU ROM (ioctl index 6, offset 0x800-0xBFF) -------
    dpram_dc #(.widthad_a(10)) rom_54xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr & (rom_addr_in[11:10] == 2'b10)), .q_b()
    );

endmodule

`default_nettype wire
