`timescale 1ns/1ps

// File-driven self-checking testbench for butterfly_comb.
//
// By default, vectors are read from tb/test_vectors/butterfly_common.csv
// relative to the project root. Use +VECTOR_FILE=<path> to override this path.
module tb_butterfly_comb;

    logic signed [15:0] a_re;
    logic signed [15:0] a_im;
    logic signed [15:0] b_re;
    logic signed [15:0] b_im;
    logic signed [15:0] w_re;
    logic signed [15:0] w_im;

    logic signed [15:0] y0_re;
    logic signed [15:0] y0_im;
    logic signed [15:0] y1_re;
    logic signed [15:0] y1_im;
    logic               sat_y0_re;
    logic               sat_y0_im;
    logic               sat_y1_re;
    logic               sat_y1_im;

    integer vector_file;
    integer scan_count;
    integer vector_count;
    integer error_count;
    integer line_number;

    logic signed [15:0] in_a_re;
    logic signed [15:0] in_a_im;
    logic signed [15:0] in_b_re;
    logic signed [15:0] in_b_im;
    logic signed [15:0] in_w_re;
    logic signed [15:0] in_w_im;
    integer exp_y0_re;
    integer exp_y0_im;
    integer exp_y1_re;
    integer exp_y1_im;
    integer exp_y0_sat;
    integer exp_y1_sat;
    integer exp_sat_y0_re;
    integer exp_sat_y0_im;
    integer exp_sat_y1_re;
    integer exp_sat_y1_im;

    string vector_path;
    string csv_line;
    string numeric_fields;
    string case_name;
    integer comma_index;

    butterfly_comb dut (
        .a_re   (a_re),
        .a_im   (a_im),
        .b_re   (b_re),
        .b_im   (b_im),
        .w_re   (w_re),
        .w_im   (w_im),
        .y0_re  (y0_re),
        .y0_im  (y0_im),
        .y1_re  (y1_re),
        .y1_im  (y1_im),
        .sat_y0_re (sat_y0_re),
        .sat_y0_im (sat_y0_im),
        .sat_y1_re (sat_y1_re),
        .sat_y1_im (sat_y1_im)
    );

    task automatic report_value_mismatch;
        input string signal_name;
        input logic signed [15:0] actual_value;
        input integer expected_value;
        begin
            // Case inequality ensures that X or Z values are reported as failures.
            if (actual_value !== expected_value[15:0]) begin
                $error(
                    "line %0d case %s: %s actual=%0d expected=%0d",
                    line_number,
                    case_name,
                    signal_name,
                    actual_value,
                    expected_value
                );
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic report_flag_mismatch;
        input string signal_name;
        input logic actual_value;
        input integer expected_value;
        begin
            if (actual_value !== expected_value[0]) begin
                $error(
                    "line %0d case %s: %s actual=%0b expected=%0d",
                    line_number,
                    case_name,
                    signal_name,
                    actual_value,
                    expected_value
                );
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        a_re        = '0;
        a_im        = '0;
        b_re        = '0;
        b_im        = '0;
        w_re        = '0;
        w_im        = '0;
        vector_count = 0;
        error_count  = 0;
        line_number  = 1;

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            vector_path = "tb/test_vectors/butterfly_common.csv";
        end

        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0) begin
            $fatal(1, "cannot open vector file: %s", vector_path);
        end

        // Discard the header. Fail immediately on an empty file to prevent a
        // false pass with zero executed vectors.
        if ($fgets(csv_line, vector_file) == 0) begin
            $fatal(1, "vector file is empty: %s", vector_path);
        end

        while ($fgets(csv_line, vector_file) != 0) begin
            line_number = line_number + 1;

            comma_index = 0;
            while ((comma_index < csv_line.len()) &&
                   (csv_line.getc(comma_index) != 8'h2c)) begin
                comma_index = comma_index + 1;
            end

            if ((comma_index == 0) || (comma_index >= csv_line.len() - 1)) begin
                $fatal(1, "CSV parse failure at line %0d: missing case name or numeric fields", line_number);
            end

            case_name      = csv_line.substr(0, comma_index - 1);
            numeric_fields = csv_line.substr(comma_index + 1, csv_line.len() - 1);

            scan_count = $sscanf(
                numeric_fields,
                "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
                in_a_re,
                in_a_im,
                in_b_re,
                in_b_im,
                in_w_re,
                in_w_im,
                exp_y0_re,
                exp_y0_im,
                exp_y1_re,
                exp_y1_im,
                exp_y0_sat,
                exp_y1_sat,
                exp_sat_y0_re,
                exp_sat_y0_im,
                exp_sat_y1_re,
                exp_sat_y1_im
            );

            if (scan_count != 16) begin
                $fatal(
                    1,
                    "CSV parse failure at line %0d: parsed %0d of 16 numeric fields",
                    line_number,
                    scan_count
                );
            end else begin
                a_re = in_a_re;
                a_im = in_a_im;
                b_re = in_b_re;
                b_im = in_b_im;
                w_re = in_w_re;
                w_im = in_w_im;

                #1;
                vector_count = vector_count + 1;

                report_value_mismatch("y0_re", y0_re, exp_y0_re);
                report_value_mismatch("y0_im", y0_im, exp_y0_im);
                report_value_mismatch("y1_re", y1_re, exp_y1_re);
                report_value_mismatch("y1_im", y1_im, exp_y1_im);
                report_flag_mismatch("sat_y0_re", sat_y0_re, exp_sat_y0_re);
                report_flag_mismatch("sat_y0_im", sat_y0_im, exp_sat_y0_im);
                report_flag_mismatch("sat_y1_re", sat_y1_re, exp_sat_y1_re);
                report_flag_mismatch("sat_y1_im", sat_y1_im, exp_sat_y1_im);
                report_flag_mismatch(
                    "derived_y0_sat",
                    sat_y0_re | sat_y0_im,
                    exp_y0_sat
                );
                report_flag_mismatch(
                    "derived_y1_sat",
                    sat_y1_re | sat_y1_im,
                    exp_y1_sat
                );
            end
        end

        $fclose(vector_file);

        if (vector_count == 0) begin
            $fatal(1, "no test vectors were executed");
        end

        if (error_count == 0) begin
            $display("PASS: %0d vectors checked with no mismatches", vector_count);
            $finish;
        end else begin
            $fatal(
                1,
                "FAIL: %0d mismatches found across %0d vectors",
                error_count,
                vector_count
            );
        end
    end

endmodule
