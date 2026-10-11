//============================================================================
//  namco_06xx.sv -- Namco 06XX bus arbiter: Z80 <-> up to four Namco 5xxx MCUs.
//  Based on MAME src/devices/machine/namco06.cpp.
//
//  Control register: [3:0] chip-select mask (51xx, 53xx, 52xx, 54xx), [4] R/!W, [7:5] clock divider (0 = off).
//  data_r ANDs the selected chips' outputs; data_w broadcasts to the selected chips.
//  The chip-select / NMI timer runs off a 48 kHz tick (clk/1024), divisor 2^ctrl[7:5].
//  ctrl_w / data_w take effect one clock late (MAME defers them to the next scheduler slice).
//============================================================================
`default_nettype none

module namco_06xx
(
    input  wire        clk,        // fabric clock (CLK_49M, 49.152 MHz)
    input  wire        reset,  // system reset (not the LS259 Namco reset)
    input  wire        pause,  // MiSTer pause: freezes the NMI / chip-select timer

    // ---- Z80-side bus (PolePosition_CPU n06_* ports) ----------------------
    input  wire  [7:0] cpu_dout,
    input  wire        data_wr, data_rd,
    input  wire        ctrl_wr, ctrl_rd,
    output wire  [7:0] cpu_din,
    output wire        nmi_n,       // -> Z80 NMI_n (active low)

    // ---- per-chip interconnect (0=51xx 1=53xx 2=52xx[unbuilt] 3=54xx[unbuilt]) --
    output wire  [3:0] chipsel,     // active-high IRQ/select pulse per chip
    output wire        rw0,         // R/!W direction line — MAME binds rw_callback<0> (51xx) ONLY
    input  wire  [7:0] chip0_din, chip1_din, chip2_din, chip3_din,
    output wire  [7:0] chip_dout,   // broadcast write data to selected chip(s)
    output wire  [3:0] chip_wr  // per-chip write strobe (the 53xx has none)
);

    // ---- deferred ctrl_w / data_w ----
    reg [7:0] ctrl_wdata_d;  reg ctrl_apply;
    reg [7:0] data_wdata_d;  reg data_apply;
    always @(posedge clk) begin
        ctrl_apply <= ctrl_wr;
        if (ctrl_wr) ctrl_wdata_d <= cpu_dout;
        data_apply <= data_wr;
        if (data_wr) data_wdata_d <= cpu_dout;
    end

    reg  [7:0] ctrl;
    reg        read_stretch;
    reg  [9:0] base_cnt;
    reg  [6:0] div_cnt;
    reg        timer_state;
    reg  [3:0] chipsel_r;
    reg        rw0_r;
    reg        nmi_n_r;

    wire       wmode     = ~ctrl[4];
    wire       enabled   = |ctrl[7:5];
    // divisor/2 - 1 (ticks between toggles); only evaluated while enabled (ctrl[7:5]>=1)
    wire [6:0] div_limit = (7'd1 << (ctrl[7:5] - 3'd1)) - 7'd1;
    wire       base_ce   = (base_cnt == 10'd1023);

    always @(posedge clk) begin
        if (reset) base_cnt <= 10'd0;
        else       base_cnt <= base_ce ? 10'd0 : base_cnt + 10'd1;
    end

    always @(posedge clk) begin
        if (reset) begin
            ctrl         <= 8'h00;
            read_stretch <= 1'b0;
            div_cnt      <= 7'd0;
            timer_state  <= 1'b0;
            chipsel_r    <= 4'h0;
            rw0_r        <= 1'b0;
            nmi_n_r      <= 1'b1;
        end else if (ctrl_apply) begin
            // ctrl_w_sync equivalent (deferred write commits now)
            ctrl    <= ctrl_wdata_d;
            div_cnt <= 7'd0;
            timer_state <= 1'b0;
            if (ctrl_wdata_d[7:5] == 3'b000) begin
                // disabled: stop timer, clear NMI + all chipsels; RW left as-is (MAME comment)
                chipsel_r <= 4'h0;
                nmi_n_r   <= 1'b1;
            end else if (ctrl_wdata_d[4]) begin
                // entering read mode: NMI cleared immediately, suppress the FIRST pulse
                nmi_n_r      <= 1'b1;
                read_stretch <= 1'b1;
            end else begin
                read_stretch <= 1'b0;
            end
        end else if (enabled && base_ce && !pause) begin
            if (div_cnt == div_limit) begin
                div_cnt      <= 7'd0;
                timer_state  <= ~timer_state;
                read_stretch <= 1'b0;   // MAME clears m_read_stretch on EVERY nmi_generate call
                if (~timer_state) begin
                    // toggling false->true: this is nmi_generate's "m_timer_state==true" branch
                    rw0_r     <= ctrl[4];
                    chipsel_r <= ctrl[3:0];
                    nmi_n_r   <= read_stretch ? 1'b1 : 1'b0;
                end else begin
                    // toggling true->false: NMI + chipsel cleared
                    chipsel_r <= 4'h0;
                    nmi_n_r   <= 1'b1;
                end
            end else begin
                div_cnt <= div_cnt + 7'd1;
            end
        end
    end

    assign chipsel = chipsel_r;
    assign rw0     = rw0_r;
    assign nmi_n   = nmi_n_r;

    // ---- data_r: combinational AND-reduce of selected chips' read() -------
    wire [7:0] d0 = ctrl[0] ? chip0_din : 8'hFF;
    wire [7:0] d1 = ctrl[1] ? chip1_din : 8'hFF;
    wire [7:0] d2 = ctrl[2] ? chip2_din : 8'hFF;
    wire [7:0] d3 = ctrl[3] ? chip3_din : 8'hFF;
    wire [7:0] data_r_val = d0 & d1 & d2 & d3;

    // read-data hold: 0 = live tap of the selected chips (MAME data_r), 1 = capture at window close,
    // 2 = capture at window open.
    localparam HOLD_MODE = 0;

    wire win_close = enabled && base_ce && !pause && (div_cnt == div_limit) &&  timer_state;
    wire win_open  = enabled && base_ce && !pause && (div_cnt == div_limit) && ~timer_state;

    reg [7:0] data_r_hold;
    always @(posedge clk) begin
        if (reset)                                  data_r_hold <= 8'hFF;
        else if (HOLD_MODE == 1 ? win_close : win_open) data_r_hold <= data_r_val;
    end

    wire [7:0] data_r_sel = (HOLD_MODE == 0) ? data_r_val : data_r_hold;

    assign cpu_din = ctrl_rd ? ctrl : (ctrl[4] ? data_r_sel : 8'h00);

    // ---- data_w: deferred broadcast to selected chips in write mode -------
    reg [7:0] chip_dout_r;
    reg [3:0] chip_wr_r;
    always @(posedge clk) begin
        chip_wr_r <= 4'h0;
        if (data_apply && wmode) begin
            chip_dout_r <= data_wdata_d;
            chip_wr_r   <= ctrl[3:0];
        end
    end
    assign chip_dout = chip_dout_r;
    assign chip_wr   = chip_wr_r;

endmodule

`default_nettype wire
