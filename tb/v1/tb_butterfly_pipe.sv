`timescale 1ns/1ps

// File-driven self-checking testbench for butterfly_pipe.
//
// Coverage:
//   - consecutive valid transactions at II=1;
//   - bubbles between valid transactions;
//   - a fixed two-cycle interval from input sampling to valid output;
//   - four data components and four component-level saturation flags;
//   - retained output data and cleared saturation flags during bubbles;
//   - synchronous reset while transactions are in flight, which discards them;
//   - immediate acceptance of the first valid transaction after reset release.
module tb_butterfly_pipe;

    localparam time CLK_PERIOD = 10ns;

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

    integer vector_file;
    integer scan_count;
    integer vector_count;
    integer error_count;
    integer line_number;
    integer cycle_count;

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

    // Two-slot scoreboard. pipe[1] identifies the transaction expected at the
    // output immediately after the current rising edge.
    logic   exp_valid_pipe [0:1];
    integer exp_y0_re_pipe [0:1];
    integer exp_y0_im_pipe [0:1];
    integer exp_y1_re_pipe [0:1];
    integer exp_y1_im_pipe [0:1];
    integer exp_sat_y0_re_pipe [0:1];
    integer exp_sat_y0_im_pipe [0:1];
    integer exp_sat_y1_re_pipe [0:1];
    integer exp_sat_y1_im_pipe [0:1];
    string  exp_case_pipe [0:1];

    logic signed [15:0] last_y0_re;
    logic signed [15:0] last_y0_im;
    logic signed [15:0] last_y1_re;
    logic signed [15:0] last_y1_im;
    logic               have_last_output;

    string vector_path;
    string csv_line;
    string numeric_fields;
    string case_name;
    integer comma_index;

    butterfly_pipe dut (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (valid_in),
        .a_re      (a_re),
        .a_im      (a_im),
        .b_re      (b_re),
        .b_im      (b_im),
        .w_re      (w_re),
        .w_im      (w_im),
        .valid_out (valid_out),
        .y0_re     (y0_re),
        .y0_im     (y0_im),
        .y1_re     (y1_re),
        .y1_im     (y1_im),
        .sat_y0_re (sat_y0_re),
        .sat_y0_im (sat_y0_im),
        .sat_y1_re (sat_y1_re),
        .sat_y1_im (sat_y1_im)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task automatic clear_scoreboard;
        begin
            exp_valid_pipe[0] = 1'b0;
            exp_valid_pipe[1] = 1'b0;
            exp_case_pipe[0]  = "bubble";
            exp_case_pipe[1]  = "bubble";
        end
    endtask

    task automatic record_error;
        input string message;
        begin
            $error("cycle %0d: %s", cycle_count, message);
            error_count = error_count + 1;
        end
    endtask

    task automatic check_value;
        input string signal_name;
        input logic signed [15:0] actual_value;
        input integer expected_value;
        begin
            if (actual_value !== expected_value[15:0]) begin
                $error(
                    "cycle %0d case %s: %s actual=%0d expected=%0d",
                    cycle_count,
                    exp_case_pipe[1],
                    signal_name,
                    actual_value,
                    expected_value
                );
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_flag;
        input string signal_name;
        input logic actual_value;
        input integer expected_value;
        begin
            if (actual_value !== expected_value[0]) begin
                $error(
                    "cycle %0d case %s: %s actual=%0b expected=%0d",
                    cycle_count,
                    exp_case_pipe[1],
                    signal_name,
                    actual_value,
                    expected_value
                );
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_current_output;
        begin
            if (valid_out !== exp_valid_pipe[1]) begin
                $error(
                    "cycle %0d: valid_out actual=%0b expected=%0b for case %s",
                    cycle_count,
                    valid_out,
                    exp_valid_pipe[1],
                    exp_case_pipe[1]
                );
                error_count = error_count + 1;
            end

            if (exp_valid_pipe[1]) begin
                check_value("y0_re", y0_re, exp_y0_re_pipe[1]);
                check_value("y0_im", y0_im, exp_y0_im_pipe[1]);
                check_value("y1_re", y1_re, exp_y1_re_pipe[1]);
                check_value("y1_im", y1_im, exp_y1_im_pipe[1]);
                check_flag("sat_y0_re", sat_y0_re, exp_sat_y0_re_pipe[1]);
                check_flag("sat_y0_im", sat_y0_im, exp_sat_y0_im_pipe[1]);
                check_flag("sat_y1_re", sat_y1_re, exp_sat_y1_re_pipe[1]);
                check_flag("sat_y1_im", sat_y1_im, exp_sat_y1_im_pipe[1]);

                last_y0_re      = y0_re;
                last_y0_im      = y0_im;
                last_y1_re      = y1_re;
                last_y1_im      = y1_im;
                have_last_output = 1'b1;
            end else begin
                // V1 requires saturation flags to be cleared during bubbles.
                if ({sat_y0_re, sat_y0_im, sat_y1_re, sat_y1_im} !== 4'b0000) begin
                    record_error("saturation flags must be zero when valid_out=0");
                end

                // After the first valid output, all four data outputs must remain
                // unchanged during subsequent bubbles.
                if (have_last_output &&
                    ({y0_re, y0_im, y1_re, y1_im} !==
                     {last_y0_re, last_y0_im, last_y1_re, last_y1_im})) begin
                    record_error("output data changed during an invalid cycle");
                end
            end
        end
    endtask

    task automatic shift_scoreboard;
        input logic slot_valid;
        input string slot_case;
        input integer slot_y0_re;
        input integer slot_y0_im;
        input integer slot_y1_re;
        input integer slot_y1_im;
        input integer slot_sat_y0_re;
        input integer slot_sat_y0_im;
        input integer slot_sat_y1_re;
        input integer slot_sat_y1_im;
        begin
            exp_valid_pipe[1]     = exp_valid_pipe[0];
            exp_case_pipe[1]      = exp_case_pipe[0];
            exp_y0_re_pipe[1]     = exp_y0_re_pipe[0];
            exp_y0_im_pipe[1]     = exp_y0_im_pipe[0];
            exp_y1_re_pipe[1]     = exp_y1_re_pipe[0];
            exp_y1_im_pipe[1]     = exp_y1_im_pipe[0];
            exp_sat_y0_re_pipe[1] = exp_sat_y0_re_pipe[0];
            exp_sat_y0_im_pipe[1] = exp_sat_y0_im_pipe[0];
            exp_sat_y1_re_pipe[1] = exp_sat_y1_re_pipe[0];
            exp_sat_y1_im_pipe[1] = exp_sat_y1_im_pipe[0];

            exp_valid_pipe[0]     = slot_valid;
            exp_case_pipe[0]      = slot_case;
            exp_y0_re_pipe[0]     = slot_y0_re;
            exp_y0_im_pipe[0]     = slot_y0_im;
            exp_y1_re_pipe[0]     = slot_y1_re;
            exp_y1_im_pipe[0]     = slot_y1_im;
            exp_sat_y0_re_pipe[0] = slot_sat_y0_re;
            exp_sat_y0_im_pipe[0] = slot_sat_y0_im;
            exp_sat_y1_re_pipe[0] = slot_sat_y1_re;
            exp_sat_y1_im_pipe[0] = slot_sat_y1_im;
        end
    endtask

    task automatic drive_slot;
        input logic slot_valid;
        input string slot_case;
        input logic signed [15:0] slot_a_re;
        input logic signed [15:0] slot_a_im;
        input logic signed [15:0] slot_b_re;
        input logic signed [15:0] slot_b_im;
        input logic signed [15:0] slot_w_re;
        input logic signed [15:0] slot_w_im;
        input integer slot_y0_re;
        input integer slot_y0_im;
        input integer slot_y1_re;
        input integer slot_y1_im;
        input integer slot_sat_y0_re;
        input integer slot_sat_y0_im;
        input integer slot_sat_y1_re;
        input integer slot_sat_y1_im;
        begin
            @(negedge clk);
            valid_in = slot_valid;
            if (slot_valid) begin
                a_re = slot_a_re;
                a_im = slot_a_im;
                b_re = slot_b_re;
                b_im = slot_b_im;
                w_re = slot_w_re;
                w_im = slot_w_im;
            end

            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;
            check_current_output();
            shift_scoreboard(
                slot_valid,
                slot_case,
                slot_y0_re,
                slot_y0_im,
                slot_y1_re,
                slot_y1_im,
                slot_sat_y0_re,
                slot_sat_y0_im,
                slot_sat_y1_re,
                slot_sat_y1_im
            );
        end
    endtask

    task automatic drive_bubble;
        begin
            drive_slot(
                1'b0,
                "bubble",
                0, 0, 0, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 0, 0
            );
        end
    endtask

    task automatic apply_reset;
        input integer reset_cycles;
        integer index;
        begin
            @(negedge clk);
            rst      = 1'b1;
            valid_in = 1'b0;

            for (index = 0; index < reset_cycles; index = index + 1) begin
                @(posedge clk);
                #1;
                cycle_count = cycle_count + 1;
                clear_scoreboard();
                if (valid_out !== 1'b0) begin
                    record_error("valid_out must be zero during synchronous reset");
                end
                if ({sat_y0_re, sat_y0_im, sat_y1_re, sat_y1_im} !== 4'b0000) begin
                    record_error("saturation flags must be zero during reset");
                end
                if (index + 1 < reset_cycles) begin
                    @(negedge clk);
                end
            end

            // Release reset after its final rising edge. The caller drives inputs
            // on the following falling edge, making the next rising edge the first
            // sampling edge with rst=0.
            rst = 1'b0;
        end
    endtask

    initial begin
        rst              = 1'b1;
        valid_in         = 1'b0;
        a_re             = '0;
        a_im             = '0;
        b_re             = '0;
        b_im             = '0;
        w_re             = '0;
        w_im             = '0;
        vector_count     = 0;
        error_count      = 0;
        line_number      = 1;
        cycle_count      = 0;
        have_last_output = 1'b0;
        clear_scoreboard();

        apply_reset(2);

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            vector_path = "tb/test_vectors/butterfly_common.csv";
        end

        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0) begin
            $fatal(1, "cannot open vector file: %s", vector_path);
        end

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
                // The common vectors retain both aggregate and component-level
                // saturation flags. Verify their consistency before enqueueing.
                if (exp_y0_sat != (exp_sat_y0_re | exp_sat_y0_im)) begin
                    $fatal(1, "CSV y0 saturation flags disagree at line %0d", line_number);
                end
                if (exp_y1_sat != (exp_sat_y1_re | exp_sat_y1_im)) begin
                    $fatal(1, "CSV y1 saturation flags disagree at line %0d", line_number);
                end

                // Insert a bubble before every eleventh vector while retaining
                // long runs of consecutive transactions.
                if ((vector_count != 0) && ((vector_count % 11) == 0)) begin
                    drive_bubble();
                end

                drive_slot(
                    1'b1,
                    case_name,
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
                    exp_sat_y0_re,
                    exp_sat_y0_im,
                    exp_sat_y1_re,
                    exp_sat_y1_im
                );
                vector_count = vector_count + 1;
            end
        end

        $fclose(vector_file);

        // Drain the final two scoreboard slots.
        drive_bubble();
        drive_bubble();

        // Reset immediately after launching two valid transactions. Neither
        // transaction may reach the output.
        drive_slot(
            1'b1, "reset_discard_0",
            0, 0, 0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        );
        drive_slot(
            1'b1, "reset_discard_1",
            0, 0, 0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        );
        apply_reset(1);

        // Send a valid transaction in the first test slot after reset release.
        drive_slot(
            1'b1, "post_reset_accept",
            0, 0, 0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        );
        drive_bubble();
        drive_bubble();

        if (vector_count == 0) begin
            $fatal(1, "no file vectors were executed");
        end

        if (error_count == 0) begin
            $display(
                "PASS: %0d file vectors checked; latency, bubbles, flags and reset passed",
                vector_count
            );
            $finish;
        end else begin
            $fatal(
                1,
                "FAIL: %0d mismatches found across %0d file vectors",
                error_count,
                vector_count
            );
        end
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end

endmodule
