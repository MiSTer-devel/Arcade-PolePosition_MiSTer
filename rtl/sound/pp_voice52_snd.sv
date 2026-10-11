//============================================================================
//  pp_voice52_snd.sv -- Namco 52xx voice analog output stage: R1-ladder DAC + filters + level.
//  Based on MAME src/mame/namco/polepos_a.cpp CHANL4 (DAC 100K/47K/22K/10K at 4 V, minus 2 V VREF,
//  100 Hz highpass, 1200 Hz lowpass, gain 0.5, DISCRETE_OUTPUT 32767/2).
//  Deviation: 1-pole highpass (~120 Hz) and two 1-pole lowpasses (~1020 Hz each) instead of MAME's
//  2nd-order sections, so no multipliers are needed.
//============================================================================
`default_nettype none

module pp_voice52_snd
(
    input  wire        clk,        // CLK_49M 49.152 MHz (poleposition.vhd's clock_18)
    input  wire        reset,
    input  wire        pause,      // PAUSE-GATE: freeze the tick, as the other voices do

    input  wire  [3:0] p_data,     // namco_52xx discrete_p — OUT0-OUT3, 4-bit PCM

    output reg signed [15:0] audio
);

    // ---- filter coefficients + level, all in one place ---------------------
    localparam HP_SHIFT  = 6;   // DC blocker,  alpha = 1/64
    localparam LP_SHIFT  = 3;   // 2x 1-pole,   alpha = 1/8
    // level: Q12 volts >>> 11 = MAME's gain 0.5 * 32767/2 (+-2 V -> +-16384)
    localparam OUT_SHIFT = 11;

    // ---- 48 kHz output tick: CLK_49M / 1024 --------------------------------
    reg [9:0] tick_div;
    reg       tick;
    always @(posedge clk) begin
        tick <= 1'b0;
        if (reset) begin
            tick_div <= 10'd0;
        end
        else if (!pause) begin
            tick_div <= tick_div + 10'd1;
            if (tick_div == 10'd1023) tick <= 1'b1;
        end
    end

    // ---- R1 ladder DAC, 4 V, offset by VREF, in Q12 volts ------------------
    //  value(v) = 4.0 * SUM(bit_i * g_i)/SUM(g_i) - 2.0,  g = 1/{100,47,22,10}K
    reg signed [15:0] dac_q12;
    always @(*) begin
        case (p_data)
            4'h0: dac_q12 = -16'sd8192;   // -2.000 V
            4'h1: dac_q12 = -16'sd7265;   // -1.774 V
            4'h2: dac_q12 = -16'sd6220;   // -1.518 V
            4'h3: dac_q12 = -16'sd5293;   // -1.292 V
            4'h4: dac_q12 = -16'sd3978;   // -0.971 V
            4'h5: dac_q12 = -16'sd3051;   // -0.745 V
            4'h6: dac_q12 = -16'sd2006;   // -0.490 V
            4'h7: dac_q12 = -16'sd1079;   // -0.263 V
            4'h8: dac_q12 =  16'sd1079;   // +0.263 V
            4'h9: dac_q12 =  16'sd2006;   // +0.490 V
            4'hA: dac_q12 =  16'sd3051;   // +0.745 V
            4'hB: dac_q12 =  16'sd3978;   // +0.971 V
            4'hC: dac_q12 =  16'sd5293;   // +1.292 V
            4'hD: dac_q12 =  16'sd6220;   // +1.518 V
            4'hE: dac_q12 =  16'sd7265;   // +1.774 V
            4'hF: dac_q12 =  16'sd8192;   // +2.000 V
        endcase
    end

    // ---- filter state, Q12 volts carried with 12 extra fraction bits -------
    // extra fraction bits keep the shift-based IIRs from stalling on small signals
    reg signed [27:0] hp_acc, lp1_acc, lp2_acc;

    wire signed [27:0] dac_ext = $signed({dac_q12, 12'd0});
    wire signed [27:0] hp_out  = dac_ext - hp_acc;   // x - LP(x) = HP(x)

    // |lp2_acc| <= 8192<<12 = 2^25, so >>>11 peaks at 2^14 = 16384 and the low
    // 16 bits carry the sign correctly with room to spare.
    wire signed [27:0] out_shifted = lp2_acc >>> OUT_SHIFT;

    always @(posedge clk) begin
        if (reset) begin
            hp_acc  <= 28'sd0;
            lp1_acc <= 28'sd0;
            lp2_acc <= 28'sd0;
            audio   <= 16'sd0;
        end
        else if (tick) begin
            hp_acc  <= hp_acc  + ((dac_ext - hp_acc)  >>> HP_SHIFT);
            lp1_acc <= lp1_acc + ((hp_out  - lp1_acc) >>> LP_SHIFT);
            lp2_acc <= lp2_acc + ((lp1_acc - lp2_acc) >>> LP_SHIFT);
            audio   <= out_shifted[15:0];
        end
    end

endmodule

`default_nettype wire
