`timescale 1ns/1ps

interface butterfly_if;

    logic                     clk;
    logic                     rst;
    logic                     valid_in;
    logic signed [15:0]       a_re;
    logic signed [15:0]       a_im;
    logic signed [15:0]       b_re;
    logic signed [15:0]       b_im;
    logic signed [15:0]       w_re;
    logic signed [15:0]       w_im;

    logic                     valid_out;
    logic signed [15:0]       y0_re;
    logic signed [15:0]       y0_im;
    logic signed [15:0]       y1_re;
    logic signed [15:0]       y1_im;
    logic                     sat_y0_re;
    logic                     sat_y0_im;
    logic                     sat_y1_re;
    logic                     sat_y1_im;

    // Driving on the falling edge leaves a half cycle of setup time before
    // the DUT samples inputs on the next rising edge.
    clocking driver_cb @(negedge clk);
        default input #1step output #0;
        input  rst;
        output valid_in;
        output a_re;
        output a_im;
        output b_re;
        output b_im;
        output w_re;
        output w_im;
    endclocking

    // The falling-edge sample observes stable values from the preceding DUT
    // rising edge and cannot race nonblocking assignments in the DUT.
    clocking monitor_cb @(negedge clk);
        default input #1step output #0;
        input rst;
        input valid_in;
        input a_re;
        input a_im;
        input b_re;
        input b_im;
        input w_re;
        input w_im;
        input valid_out;
        input y0_re;
        input y0_im;
        input y1_re;
        input y1_im;
        input sat_y0_re;
        input sat_y0_im;
        input sat_y1_re;
        input sat_y1_im;
    endclocking

endinterface
