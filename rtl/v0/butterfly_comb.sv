`timescale 1ns/1ps

// V0 combinational implementation of a Radix-2 DIF butterfly.
//
// Mathematical definition:
//   Y0 = A + B
//   Y1 = (A - B) * W
//
// All top-level complex components use 16-bit signed Q1.15.
module butterfly_comb (
    input  logic signed [15:0] a_re,
    input  logic signed [15:0] a_im,
    input  logic signed [15:0] b_re,
    input  logic signed [15:0] b_im,
    input  logic signed [15:0] w_re,
    input  logic signed [15:0] w_im,

    output logic signed [15:0] y0_re,
    output logic signed [15:0] y0_im,
    output logic signed [15:0] y1_re,
    output logic signed [15:0] y1_im,
    output logic               sat_y0_re,
    output logic               sat_y0_im,
    output logic               sat_y1_re,
    output logic               sat_y1_im
);

    // Explicitly sign-extend the 16-bit inputs before addition or subtraction
    // to produce 17-bit Q2.15 results.
    logic signed [16:0] sum_re;
    logic signed [16:0] sum_im;
    logic signed [16:0] diff_re;
    logic signed [16:0] diff_im;

    // The four parallel real products are 33-bit Q3.30 values.
    logic signed [32:0] product_0;
    logic signed [32:0] product_1;
    logic signed [32:0] product_2;
    logic signed [32:0] product_3;

    // Explicitly extend both multiplication operands so that each expression
    // is evaluated with 33-bit signed semantics.
    logic signed [32:0] diff_re_mul_ext;
    logic signed [32:0] diff_im_mul_ext;
    logic signed [32:0] w_re_mul_ext;
    logic signed [32:0] w_im_mul_ext;

    // Extend the products to 34 bits before the final add/subtract operations
    // to prevent intermediate overflow in a 33-bit expression.
    logic signed [33:0] product_re;
    logic signed [33:0] product_im;

    assign sum_re  = {a_re[15], a_re} + {b_re[15], b_re};
    assign sum_im  = {a_im[15], a_im} + {b_im[15], b_im};
    assign diff_re = {a_re[15], a_re} - {b_re[15], b_re};
    assign diff_im = {a_im[15], a_im} - {b_im[15], b_im};

    assign diff_re_mul_ext = {{16{diff_re[16]}}, diff_re};
    assign diff_im_mul_ext = {{16{diff_im[16]}}, diff_im};
    assign w_re_mul_ext    = {{17{w_re[15]}}, w_re};
    assign w_im_mul_ext    = {{17{w_im[15]}}, w_im};

    assign product_0 = diff_re_mul_ext * w_re_mul_ext;
    assign product_1 = diff_im_mul_ext * w_im_mul_ext;
    assign product_2 = diff_re_mul_ext * w_im_mul_ext;
    assign product_3 = diff_im_mul_ext * w_re_mul_ext;

    assign product_re = {product_0[32], product_0} -
                        {product_1[32], product_1};
    assign product_im = {product_2[32], product_2} +
                        {product_3[32], product_3};

    sat_q15 u_sat_y0_re (
        .in_value  (sum_re),
        .out_value (y0_re),
        .saturated (sat_y0_re)
    );

    sat_q15 u_sat_y0_im (
        .in_value  (sum_im),
        .out_value (y0_im),
        .saturated (sat_y0_im)
    );

    rne_sat_q30_to_q15 u_quant_y1_re (
        .in_value  (product_re),
        .out_value (y1_re),
        .saturated (sat_y1_re)
    );

    rne_sat_q30_to_q15 u_quant_y1_im (
        .in_value  (product_im),
        .out_value (y1_im),
        .saturated (sat_y1_im)
    );

endmodule
