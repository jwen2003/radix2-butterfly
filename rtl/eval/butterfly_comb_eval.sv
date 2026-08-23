`timescale 1ns/1ps

// Registered evaluation wrapper for the V0 combinational butterfly.
//
// This module is used only for synthesis, timing, and physical-design
// comparisons. It adds explicit input and output register boundaries so that
// every timed datapath is register-to-register. The wrapped butterfly core is
// unchanged.
//
// An input accepted with valid_in=1 on rising edge t produces its corresponding
// output with valid_out=1 on rising edge t+1. The initiation interval is II=1.
module butterfly_comb_eval (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     valid_in,

    input  logic signed [15:0]       a_re,
    input  logic signed [15:0]       a_im,
    input  logic signed [15:0]       b_re,
    input  logic signed [15:0]       b_im,
    input  logic signed [15:0]       w_re,
    input  logic signed [15:0]       w_im,

    output logic                     valid_out,
    output logic signed [15:0]       y0_re,
    output logic signed [15:0]       y0_im,
    output logic signed [15:0]       y1_re,
    output logic signed [15:0]       y1_im,
    output logic                     sat_y0_re,
    output logic                     sat_y0_im,
    output logic                     sat_y1_re,
    output logic                     sat_y1_im
);

    logic                     valid_in_q;
    logic signed [15:0]       a_re_q;
    logic signed [15:0]       a_im_q;
    logic signed [15:0]       b_re_q;
    logic signed [15:0]       b_im_q;
    logic signed [15:0]       w_re_q;
    logic signed [15:0]       w_im_q;

    logic signed [15:0]       core_y0_re;
    logic signed [15:0]       core_y0_im;
    logic signed [15:0]       core_y1_re;
    logic signed [15:0]       core_y1_im;
    logic                     core_sat_y0_re;
    logic                     core_sat_y0_im;
    logic                     core_sat_y1_re;
    logic                     core_sat_y1_im;

    // Common evaluation input boundary. Invalid cycles propagate as bubbles;
    // wide data registers retain their previous values to reduce switching.
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_in_q <= 1'b0;
        end else begin
            valid_in_q <= valid_in;

            if (valid_in) begin
                a_re_q <= a_re;
                a_im_q <= a_im;
                b_re_q <= b_re;
                b_im_q <= b_im;
                w_re_q <= w_re;
                w_im_q <= w_im;
            end
        end
    end

    butterfly_comb u_core (
        .a_re      (a_re_q),
        .a_im      (a_im_q),
        .b_re      (b_re_q),
        .b_im      (b_im_q),
        .w_re      (w_re_q),
        .w_im      (w_im_q),
        .y0_re     (core_y0_re),
        .y0_im     (core_y0_im),
        .y1_re     (core_y1_re),
        .y1_im     (core_y1_im),
        .sat_y0_re (core_sat_y0_re),
        .sat_y0_im (core_sat_y0_im),
        .sat_y1_re (core_sat_y1_re),
        .sat_y1_im (core_sat_y1_im)
    );

    // Common evaluation output boundary. Data outputs retain their previous
    // values during bubbles, while saturation flags are cleared.
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            sat_y0_re <= 1'b0;
            sat_y0_im <= 1'b0;
            sat_y1_re <= 1'b0;
            sat_y1_im <= 1'b0;
        end else begin
            valid_out <= valid_in_q;

            if (valid_in_q) begin
                y0_re     <= core_y0_re;
                y0_im     <= core_y0_im;
                y1_re     <= core_y1_re;
                y1_im     <= core_y1_im;
                sat_y0_re <= core_sat_y0_re;
                sat_y0_im <= core_sat_y0_im;
                sat_y1_re <= core_sat_y1_re;
                sat_y1_im <= core_sat_y1_im;
            end else begin
                sat_y0_re <= 1'b0;
                sat_y0_im <= 1'b0;
                sat_y1_re <= 1'b0;
                sat_y1_im <= 1'b0;
            end
        end
    end

endmodule
