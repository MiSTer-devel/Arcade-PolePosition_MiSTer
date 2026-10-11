//============================================================================
//  gen_ram.sv -- SystemVerilog port of gen_ram.vhd (Syntiac generic RAM, modified by Dar):
//  single-port synchronous RAM, registered old-data read.
//  rAddrReg / qReg are unused (removed by the 2016 edit below).
// -----------------------------------------------------------------------
//
// Syntiac's generic VHDL support files.
//
// -----------------------------------------------------------------------
// Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
// http://www.syntiac.com/fpga64.html
//
// Modified April 2016 by Dar (darfpga@aol.fr)
// http://darfpga.blogspot.fr
//   Remove address register when writing
//
// -----------------------------------------------------------------------
//
// gen_rwram.vhd
//
// -----------------------------------------------------------------------
//
// generic ram.
//
// -----------------------------------------------------------------------
`default_nettype none

module gen_ram #(
    parameter integer dWidth = 8,
    parameter integer aWidth = 10
)(
    input  wire                clk,
    input  wire                we,
    input  wire [aWidth-1:0]   addr,
    input  wire [dWidth-1:0]   d,
    output logic [dWidth-1:0]  q
);

    logic [dWidth-1:0] ram [0:(2**aWidth)-1];

    logic [aWidth-1:0] rAddrReg;  // unused
    logic [dWidth-1:0] qReg;  // unused

    // -----------------------------------------------------------------------
    // Signals to entity interface
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // Memory write
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (we) begin
            ram[addr] <= d;
        end
    end

    // -----------------------------------------------------------------------
    // Memory read
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        q <= ram[addr];
    end

endmodule

`default_nettype wire
