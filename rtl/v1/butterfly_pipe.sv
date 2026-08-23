`timescale 1ns/1ps

// V1 three-stage pipelined implementation of a Radix-2 DIF butterfly.
//
// Mathematical definition:
//   Y0 = A + B
//   Y1 = (A - B) * W
//
// All top-level input and output components use 16-bit signed Q1.15.
// An input accepted with valid_in=1 on rising edge t produces its corresponding
// output with valid_out=1 on rising edge t+2. The initiation interval is II=1.
module butterfly_pipe (
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

    // Q1.15 output limits represented in the 20-bit post-rounding Y1 format.
    localparam logic signed [19:0] Q15_MIN_EXT = -20'sd32768;
    localparam logic signed [19:0] Q15_MAX_EXT =  20'sd32767;

    // Stage 1: 17-bit Q2.15 sums and differences, plus the aligned W value.
    logic                     valid_s1;
    logic signed [16:0]       sum_re_s1;
    logic signed [16:0]       sum_im_s1;
    logic signed [16:0]       diff_re_s1;
    logic signed [16:0]       diff_im_s1;
    logic signed [15:0]       w_re_s1;
    logic signed [15:0]       w_im_s1;

    // Stage 2: four 33-bit Q3.30 products and the aligned Y0 bypass.
    logic                     valid_s2;
    logic signed [32:0]       m0_s2;
    logic signed [32:0]       m1_s2;
    logic signed [32:0]       m2_s2;
    logic signed [32:0]       m3_s2;
    logic signed [16:0]       sum_re_s2;
    logic signed [16:0]       sum_im_s2;

    // Combinational signals that explicitly carry the full products.
    logic signed [32:0]       m0_next;
    logic signed [32:0]       m1_next;
    logic signed [32:0]       m2_next;
    logic signed [32:0]       m3_next;
    logic signed [32:0]       diff_re_mul_ext;
    logic signed [32:0]       diff_im_mul_ext;
    logic signed [32:0]       w_re_mul_ext;
    logic signed [32:0]       w_im_mul_ext;

    // Stage 3 combinational path: 34-bit Q4.30 product addition/subtraction.
    logic signed [33:0]       p_re_full;
    logic signed [33:0]       p_im_full;

    // Base values after a 15-bit arithmetic right shift of Q4.30 data,
    // together with the RNE control bits.
    logic signed [18:0]       p_re_base;
    logic signed [18:0]       p_im_base;
    logic                     p_re_guard;
    logic                     p_re_sticky;
    logic                     p_re_kept_lsb;
    logic                     p_re_round_up;
    logic                     p_im_guard;
    logic                     p_im_sticky;
    logic                     p_im_kept_lsb;
    logic                     p_im_round_up;

    // Extend the 19-bit base value to 20 bits before adding the rounding
    // increment so that rounding cannot wrap the result.
    logic signed [19:0]       p_re_rounded;
    logic signed [19:0]       p_im_rounded;

    logic signed [15:0]       y0_re_next;
    logic signed [15:0]       y0_im_next;
    logic signed [15:0]       y1_re_next;
    logic signed [15:0]       y1_im_next;
    logic                     sat_y0_re_next;
    logic                     sat_y0_im_next;
    logic                     sat_y1_re_next;
    logic                     sat_y1_im_next;

    // Stage 1 updates wide data only for valid inputs. The valid bit advances
    // every cycle so that an invalid cycle propagates as a bubble.
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_s1 <= 1'b0;
        end else begin
            valid_s1 <= valid_in;

            if (valid_in) begin
                sum_re_s1  <= {a_re[15], a_re} + {b_re[15], b_re};
                sum_im_s1  <= {a_im[15], a_im} + {b_im[15], b_im};
                diff_re_s1 <= {a_re[15], a_re} - {b_re[15], b_re};
                diff_im_s1 <= {a_im[15], a_im} - {b_im[15], b_im};
                w_re_s1    <= w_re;
                w_im_s1    <= w_im;
            end
        end
    end

    // Explicitly sign-extend both operands to 33 bits so that each multiplication
    // uses 33-bit signed semantics instead of relying on the destination width.
    always_comb begin
        diff_re_mul_ext = {{16{diff_re_s1[16]}}, diff_re_s1};
        diff_im_mul_ext = {{16{diff_im_s1[16]}}, diff_im_s1};
        w_re_mul_ext    = {{17{w_re_s1[15]}}, w_re_s1};
        w_im_mul_ext    = {{17{w_im_s1[15]}}, w_im_s1};

        m0_next = diff_re_mul_ext * w_re_mul_ext;
        m1_next = diff_im_mul_ext * w_im_mul_ext;
        m2_next = diff_re_mul_ext * w_im_mul_ext;
        m3_next = diff_im_mul_ext * w_re_mul_ext;
    end

    // Stage 2 updates the wide data registers only when stage 1 carries a
    // valid transaction.
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_s2 <= 1'b0;
        end else begin
            valid_s2 <= valid_s1;

            if (valid_s1) begin
                m0_s2     <= m0_next;
                m1_s2     <= m1_next;
                m2_s2     <= m2_next;
                m3_s2     <= m3_next;
                sum_re_s2 <= sum_re_s1;
                sum_im_s2 <= sum_im_s1;
            end
        end
    end

    // Stage 3 combinational logic: full-width product addition/subtraction,
    // RNE, range checking, and saturation.
    always_comb begin
        // Explicitly sign-extend to 34 bits before combining the complex products.
        p_re_full = {m0_s2[32], m0_s2} - {m1_s2[32], m1_s2};
        p_im_full = {m2_s2[32], m2_s2} + {m3_s2[32], m3_s2};

        // The arithmetic right shift produces the floor-rounded base value.
        // Retain the 19 bits above the discarded 15-bit fraction and preserve
        // signed interpretation explicitly.
        p_re_base     = $signed(p_re_full[33:15]);
        p_re_guard    = p_re_full[14];
        p_re_sticky   = |p_re_full[13:0];
        p_re_kept_lsb = p_re_full[15];
        p_re_round_up = p_re_guard & (p_re_sticky | p_re_kept_lsb);
        p_re_rounded  = {p_re_base[18], p_re_base}
                      + {{19{1'b0}}, p_re_round_up};

        p_im_base     = $signed(p_im_full[33:15]);
        p_im_guard    = p_im_full[14];
        p_im_sticky   = |p_im_full[13:0];
        p_im_kept_lsb = p_im_full[15];
        p_im_round_up = p_im_guard & (p_im_sticky | p_im_kept_lsb);
        p_im_rounded  = {p_im_base[18], p_im_base}
                      + {{19{1'b0}}, p_im_round_up};

        // Defaults provide complete assignments on every combinational path.
        y0_re_next     = sum_re_s2[15:0];
        y0_im_next     = sum_im_s2[15:0];
        y1_re_next     = p_re_rounded[15:0];
        y1_im_next     = p_im_rounded[15:0];
        sat_y0_re_next = 1'b0;
        sat_y0_im_next = 1'b0;
        sat_y1_re_next = 1'b0;
        sat_y1_im_next = 1'b0;

        // Y0 retains 15 fractional bits and therefore needs only range checking
        // and saturation.
        if (sum_re_s2 > 17'sd32767) begin
            y0_re_next     = 16'sh7fff;
            sat_y0_re_next = 1'b1;
        end else if (sum_re_s2 < -17'sd32768) begin
            y0_re_next     = 16'sh8000;
            sat_y0_re_next = 1'b1;
        end

        if (sum_im_s2 > 17'sd32767) begin
            y0_im_next     = 16'sh7fff;
            sat_y0_im_next = 1'b1;
        end else if (sum_im_s2 < -17'sd32768) begin
            y0_im_next     = 16'sh8000;
            sat_y0_im_next = 1'b1;
        end

        // Check the Y1 range at the extended width after RNE has completed.
        if (p_re_rounded > Q15_MAX_EXT) begin
            y1_re_next     = 16'sh7fff;
            sat_y1_re_next = 1'b1;
        end else if (p_re_rounded < Q15_MIN_EXT) begin
            y1_re_next     = 16'sh8000;
            sat_y1_re_next = 1'b1;
        end

        if (p_im_rounded > Q15_MAX_EXT) begin
            y1_im_next     = 16'sh7fff;
            sat_y1_im_next = 1'b1;
        end else if (p_im_rounded < Q15_MIN_EXT) begin
            y1_im_next     = 16'sh8000;
            sat_y1_im_next = 1'b1;
        end
    end

    // Stage 3 output registers. During a bubble, retain the data outputs and
    // clear the saturation flags.
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            sat_y0_re <= 1'b0;
            sat_y0_im <= 1'b0;
            sat_y1_re <= 1'b0;
            sat_y1_im <= 1'b0;
        end else begin
            valid_out <= valid_s2;

            if (valid_s2) begin
                y0_re    <= y0_re_next;
                y0_im    <= y0_im_next;
                y1_re    <= y1_re_next;
                y1_im    <= y1_im_next;
                sat_y0_re <= sat_y0_re_next;
                sat_y0_im <= sat_y0_im_next;
                sat_y1_re <= sat_y1_re_next;
                sat_y1_im <= sat_y1_im_next;
            end else begin
                sat_y0_re <= 1'b0;
                sat_y0_im <= 1'b0;
                sat_y1_re <= 1'b0;
                sat_y1_im <= 1'b0;
            end
        end
    end

endmodule
