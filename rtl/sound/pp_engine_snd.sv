//============================================================================
//  pp_engine_snd.sv -- Pole Position engine (car) sound.
//  Based on MAME src/mame/namco/polepos_a.cpp (polepos_sound_device).
//    8 slots x 0x800 waveform ROM; step = 4*N per 48 kHz tick, N = (msb+1)*64 + lsb + 1 (exact);
//    sample = (rom - 150) * volume_table[slot]; three parallel 2nd-order sections (150 Hz BP, 426 Hz BP,
//    950 Hz HP), each clamped to [-2, +1.5] V, mixed 4.7k/7.5k/10k. Output = volts * 32768 * 0.90 * 0.77.
//  Deviation: MAME designs the filters at 48 kHz but steps them at 24 kHz (halving the corners);
//  here they step at 48 kHz, the board's component corners.
//============================================================================
`default_nettype none

module pp_engine_snd
(
    input  wire        clk,        // CLK_49M 49.152 MHz (poleposition.vhd's clock_18)
    input  wire        reset,
    input  wire        pause,      // PAUSE-GATE: freeze the sample tick, as namco_wsg8 does

    input  wire        clson,      // LS259 q2 (sound_en). Falling edge clears the regs.
    input  wire        lsb_wr,     // 0xA200 write strobe
    input  wire        msb_wr,     // 0xA300 write strobe
    input  wire  [7:0] din,

    output wire [13:0] rom_addr,   // engine ROM: {slot[2:0], index[10:0]} = 0x4000
    input  wire  [7:0] rom_data,

    output reg signed [15:0] audio
);

    // ---- control registers (polepos_a.cpp lsb_w / msb_w) -------------------
    reg [5:0] sample_msb;
    reg [5:0] sample_lsb;
    reg       sample_en;

    // clson acts on its 1->0 edge only; register writes are not gated by it
    reg  clson_r;
    wire clson_fall = clson_r & ~clson;

    always @(posedge clk) begin
        clson_r <= clson;
        if (reset) begin
            sample_msb <= 6'd0;
            sample_lsb <= 6'd0;
            sample_en  <= 1'b0;
        end else begin
            if (lsb_wr) begin
                sample_lsb <= din[5:0] & 6'b111110;   // data & 62
                sample_en  <= din[0];                 // data & 1
            end
            if (msb_wr) sample_msb <= din[5:0];       // data & 63
            if (clson_fall) begin                     // lsb_w(0) + msb_w(0)
                sample_lsb <= 6'd0;
                sample_en  <= 1'b0;
                sample_msb <= 6'd0;
            end
        end
    end

    // ---- rate: N = (msb+1)*64 + lsb + 1 = (msb<<6) + lsb + 65, step = 4*N --
    wire [12:0] n_val = {1'b0, sample_msb, 6'd0} + {7'd0, sample_lsb} + 13'd65;
    wire [14:0] step  = {n_val, 2'b00};

    // ---- 48 kHz sample tick: CLK_49M/1024 = 48,000 Hz exactly --------------
    reg [9:0] ce_div;
    always @(posedge clk) ce_div <= ce_div + 1'b1;
    wire tick = (ce_div == 10'd0) & ~pause;

    // ---- phase accumulator -------------------------------------------------
    //  23 bits: position[22:12] is the 11-bit table index, the wrap is MAME's & 0x7ff
    reg [22:0] position;
    always @(posedge clk) begin
        if (reset)                        position <= 23'd0;
        else if (tick && sample_en)       position <= position + {8'd0, step};
    end

    assign rom_addr = {sample_msb[5:3], position[22:12]};   // {slot, index}

    // ---- volume_table[8], polepos_a.cpp:27-37, as Q8 -----------------------
    //  (R168t + R167t + R166t + 2200)/10000; MAME's R166 in all three shunts is reproduced as-is.
    //    0.28 0.36 0.48 0.56 0.73 0.81 0.93 1.01   (x256, rounded)
    reg [8:0] volq8;
    always @(*) case (sample_msb[5:3])
        3'd0: volq8 = 9'd72;    3'd1: volq8 = 9'd92;
        3'd2: volq8 = 9'd123;   3'd3: volq8 = 9'd143;
        3'd4: volq8 = 9'd187;   3'd5: volq8 = 9'd207;
        3'd6: volq8 = 9'd238;   default: volq8 = 9'd259;
    endcase

    // ---- sample: (rom_data - 150) * volume ---------------------------------
    wire signed [8:0]  raw    = $signed({1'b0, rom_data}) - 9'sd150;   // -150..+105
    wire signed [18:0] scaled = raw * $signed({1'b0, volq8});          // -38850..+27195

    // ---- filter bank: 1 V = 19200 units, 8 extra fraction bits in the state; one shared multiplier,
    // 6 steps per section (18 clocks per tick)
    localparam signed [35:0] CLAMP_HI =  36'sd28800  <<< 8;   // +1.5 V
    localparam signed [35:0] CLAMP_LO = -36'sd38400  <<< 8;   // -2.0 V

    reg signed [23:0] coef;                               // Q20
    reg signed [11:0] wgt;                                // Q12: (r_total/r/2) * out-per-volt / units-per-volt
    reg        [1:0]  f;                                  // filter 0..2
    reg        [2:0]  t;                                  // term 0..5
    reg               busy;
    reg signed [31:0] x0, x1, x2;                         // Q8 units
    reg signed [31:0] y1 [0:2];
    reg signed [31:0] y2 [0:2];
    reg signed [55:0] acc;
    reg signed [31:0] out_acc;

    always @(*) begin
        case ({f, t})
            // F0: MFB bandpass 150 Hz
            {2'd0,3'd0}: coef = -24'sd4938;     {2'd0,3'd1}: coef = 24'sd0;
            {2'd0,3'd2}: coef =  24'sd4938;     {2'd0,3'd3}: coef = 24'sd2085605;   // -a1
            {2'd0,3'd4}: coef = -24'sd1037434;                                         // -a2
            // F1: MFB bandpass 426 Hz
            {2'd1,3'd0}: coef = -24'sd15280;    {2'd1,3'd1}: coef = 24'sd0;
            {2'd1,3'd2}: coef =  24'sd15280;    {2'd1,3'd3}: coef = 24'sd2066160;
            {2'd1,3'd4}: coef = -24'sd1020794;
            // F2: highpass 950 Hz
            {2'd2,3'd0}: coef =  24'sd960292;   {2'd2,3'd1}: coef = -24'sd1920583;
            {2'd2,3'd2}: coef =  24'sd960292;   {2'd2,3'd3}: coef = 24'sd1913139;
            {2'd2,3'd4}: coef = -24'sd879452;
            default:     coef = 24'sd0;
        endcase
        case (f)
            2'd0:    wgt = 12'sd1155;
            2'd1:    wgt = 12'sd724;
            default: wgt = 12'sd543;
        endcase
    end

    reg signed [31:0] operand;
    always @(*) begin
        case (t)
            3'd0:    operand = x0;
            3'd1:    operand = x1;
            3'd2:    operand = x2;
            3'd3:    operand = y1[f];
            default: operand = y2[f];
        endcase
    end

    wire signed [55:0] prod  = coef * operand;
    wire signed [55:0] acc_r = acc + 56'sd524288;                 // round Q20 coefficient product
    wire signed [35:0] y_new = acc_r[55:20];                      // Q8 units
    wire signed [35:0] y_c36 = (y_new > CLAMP_HI) ? CLAMP_HI : (y_new < CLAMP_LO) ? CLAMP_LO : y_new;
    wire signed [27:0] y_cl  = y_c36[27:0];                       // |clamped| < 2^24
    wire signed [39:0] wprod = y_cl * wgt;                        // Q8 units * Q12 weight
    wire signed [31:0] out_next = out_acc + {{12{wprod[39]}}, wprod[39:20]};

    integer k;
    always @(posedge clk) begin
        if (reset) begin
            busy <= 1'b0; f <= 2'd0; t <= 3'd0; acc <= 56'sd0; out_acc <= 32'sd0;
            x0 <= 32'sd0; x1 <= 32'sd0; x2 <= 32'sd0; audio <= 16'sd0;
            for (k = 0; k < 3; k = k + 1) begin y1[k] <= 32'sd0; y2[k] <= 32'sd0; end
        end else if (!busy) begin
            if (tick) begin
                if (sample_en) begin                               // MAME steps only while enabled
                    x0 <= {{5{scaled[18]}}, scaled, 8'd0};
                    busy <= 1'b1; f <= 2'd0; t <= 3'd0; acc <= 56'sd0; out_acc <= 32'sd0;
                end else begin
                    audio <= 16'sd0;                               // MAME: not enabled -> fill with 0
                end
            end
        end else if (t != 3'd5) begin
            acc <= acc + prod;
            t   <= t + 3'd1;
        end else begin
            y2[f] <= y1[f];
            y1[f] <= y_new[31:0];                                  // unclamped, as MAME
            acc   <= 56'sd0;
            t     <= 3'd0;
            if (f == 2'd2) begin
                busy  <= 1'b0;
                x2    <= x1;
                x1    <= x0;
                audio <= (out_next >  32'sd32767) ? 16'sh7FFF :
                         (out_next < -32'sd32768) ? 16'sh8000 : out_next[15:0];
            end else begin
                out_acc <= out_next;
                f       <= f + 2'd1;
            end
        end
    end

endmodule

`default_nettype wire
