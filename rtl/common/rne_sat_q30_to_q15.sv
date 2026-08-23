`timescale 1ns/1ps

// Convert a 34-bit Q4.30 value to 16-bit Q1.15:
// 1. apply round-to-nearest, ties-to-even;
// 2. check the range of the rounded result;
// 3. saturate values outside the Q1.15 range.
module rne_sat_q30_to_q15 (
    input  logic signed [33:0] in_value,
    output logic signed [15:0] out_value,
    output logic               saturated
);

    localparam logic signed [19:0] Q15_MIN_EXT = -20'sd32768;
    localparam logic signed [19:0] Q15_MAX_EXT =  20'sd32767;

    logic signed [18:0] base_value;
    logic               guard;
    logic               sticky;
    logic               kept_lsb;
    logic               round_increment;
    logic signed [19:0] rounded_value;

    always_comb begin
        // This is equivalent to an arithmetic right shift by 15 bits. The
        // guard bit, sticky bit, and retained LSB determine the ties-to-even
        // increment. The same rule applies to both positive and negative values.
        base_value      = $signed(in_value[33:15]);
        guard           = in_value[14];
        sticky          = |in_value[13:0];
        kept_lsb        = in_value[15];
        round_increment = guard & (sticky | kept_lsb);
        rounded_value   = {base_value[18], base_value}
                        + {{19{1'b0}}, round_increment};

        saturated = 1'b0;

        if (rounded_value > Q15_MAX_EXT) begin
            out_value = 16'sh7fff;
            saturated = 1'b1;
        end else if (rounded_value < Q15_MIN_EXT) begin
            out_value = 16'sh8000;
            saturated = 1'b1;
        end else begin
            out_value = rounded_value[15:0];
        end
    end

endmodule
