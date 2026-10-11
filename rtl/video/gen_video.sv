//============================================================================
//  gen_video.sv -- Pole Position H/V counters and sync, SystemVerilog port of gen_video.vhd
//  by Dar (darfpga@aol.fr, http://darfpga.blogspot.fr). csync is not driven (as in the original).
//============================================================================
`default_nettype none

module gen_video (
    input  wire        clk,
    input  wire        enable,
    output wire [8:0]  hcnt,
    output wire [8:0]  vcnt,
    output wire         hsync,
    output logic        vsync,
    output wire         csync,  // composite sync, not driven
    output wire         blank_h,
    output wire         blank_v,
    output logic        blankn,
    input  wire signed [5:0] h_offset,
    input  wire signed [3:0] v_offset
);

    logic [1:0] hclkReg;  // unused
    logic       hblank;
    logic       vblank;
    logic [8:0] hcntReg = 9'd0;   // VHDL: hcntReg := to_unsigned(0,9)
    logic [8:0] vcntReg = 9'd15;  // VHDL: vcntReg := to_unsigned(15,9)

    logic hsync0;
    logic hsync1;
    logic hsync2;

    integer hsync_base;
    integer hsync_end;
    integer vsync_base;

    // 32-bit views for the unsigned-vs-integer compares (as numeric_std does)
    wire [31:0] hcnt32 = 32'(hcntReg);
    wire [31:0] vcnt32 = 32'(vcntReg);

    assign blank_h = hblank;
    assign blank_v = vblank;

    assign hcnt  = hcntReg;
    assign vcnt  = vcntReg;
    assign hsync = ~hsync0;

    // Horizontal counter: 511-128+1=384 pixels (48 tiles)
    // 128 to 191: 64 pixels, start of line (8 tiles, of which the last 2 tiles are displayed)
    // 192 to 447: 256 pixels, center of line (32 tiles displayed)
    // 448 to 511: 64 pixels, end of line (8 tiles, of which the first 2 tiles are displayed)

    // Vertical counter: 263-000+1=264 lines (33 tiles)
    // 000 to 015: 16 lines, start of frame (2 tiles)
    // 016 to 239: 224 lines, center lines (28 tiles displayed)
    // 240 to 263: 24 lines, end of frame (3 tiles)

    // Horizontal sync: hcnt=[495-511/128-140] (29 pixels)
    // Vertical sync:   vcnt=[260-263/000-003] (8 lines)

    always_ff @(posedge clk) begin
        if (enable) begin    // clk & ena at 6MHz

            if (hcntReg == 511) begin
                hcntReg <= 128;
                if (vcntReg == 263) begin
                    vcntReg <= 0;
                end else begin
                    vcntReg <= vcntReg + 1;
                end
            end else begin
                hcntReg <= hcntReg + 1;
            end

            // sync inside blanking (hcnt 128..255): front porch 49 / sync 29 / back porch 50; h_offset sign-extended
            hsync_base <= 177 + int'(h_offset);
            hsync_end  <= ((177 + int'(h_offset) + 29) > 511)
                        ?  (177 + int'(h_offset) + 29 - 384)
                        :  (177 + int'(h_offset) + 29);
            if (hcnt32 == hsync_base) begin
                hsync0 <= 1'b0;
            end else if (hcnt32 == hsync_end) begin
                hsync0 <= 1'b1;
            end

            if (hcnt32 == hsync_base) begin
                hsync1 <= 1'b0;
            end else if (hcnt32 == (hsync_base+13)) begin
                hsync1 <= 1'b1;    // 11
            end else if (hcnt32 == (hsync_base+192-384)) begin
                hsync1 <= 1'b0;
            end else if (hcnt32 == (hsync_base+13+192-384)) begin
                hsync1 <= 1'b1;    // 11
            end

            if (hcnt32 == hsync_base) begin
                hsync2 <= 1'b0;
            end else if (hcnt32 == (hsync_base-28)) begin
                hsync2 <= 1'b1;
            end

            vsync_base <= 250 + int'(v_offset);
            if ((vcnt32 == (vsync_base+10)) && (int'(v_offset) < (263-250-10))) begin
                vsync <= 1'b1;
            end else if ((vcnt32 == (vsync_base+10-263)) && (int'(v_offset) >= (263-250-10))) begin
                vsync <= 1'b1;
            end else if ((vcnt32 == (vsync_base+17)) && (int'(v_offset) < (263-250-17))) begin
                vsync <= 1'b0;
            end else if ((vcnt32 == (vsync_base+17-263)) && (int'(v_offset) >= (263-250-17))) begin
                vsync <= 1'b0;
            end

            // visible window: active hcnt 256..511 (256 px), blanking 128..255; vertical as original
            if (hcntReg == (448+16+8+40-384)) begin        // = 128
                hblank <= 1'b1;
            end else if (hcntReg == (192-16+8+32+40)) begin // = 256
                hblank <= 1'b0;
            end

            if (vcntReg == (240+0)) begin
                vblank <= 1'b1;
            end else if (vcntReg == (016+0)) begin
                vblank <= 1'b0;
            end

            blankn <= ~(hblank | vblank);
        end
    end

endmodule

`default_nettype wire
