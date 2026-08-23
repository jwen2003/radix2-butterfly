`timescale 1ns/1ps

// Saturate a 17-bit signed value with 15 fractional bits to 16-bit Q1.15.
// No rounding is required because the input and output use the same number
// of fractional bits.
module sat_q15 (
    input  logic signed [16:0] in_value,
    output logic signed [15:0] out_value,
    output logic               saturated
);

    always_comb begin
        saturated = 1'b0;

        if (in_value > 17'sd32767) begin
            out_value = 16'sh7fff;
            saturated = 1'b1;
        end else if (in_value < -17'sd32768) begin
            out_value = 16'sh8000;
            saturated = 1'b1;
        end else begin
            out_value = in_value[15:0];
        end
    end

endmodule
