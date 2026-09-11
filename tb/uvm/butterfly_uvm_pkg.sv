`timescale 1ns/1ps

package butterfly_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `uvm_analysis_imp_decl(_input)
    `uvm_analysis_imp_decl(_output)

    class butterfly_item extends uvm_sequence_item;
        rand logic signed [15:0] a_re;
        rand logic signed [15:0] a_im;
        rand logic signed [15:0] b_re;
        rand logic signed [15:0] b_im;
        rand logic signed [15:0] w_re;
        rand logic signed [15:0] w_im;

        logic                     rst;
        logic                     valid_out;
        logic signed [15:0]       y0_re;
        logic signed [15:0]       y0_im;
        logic signed [15:0]       y1_re;
        logic signed [15:0]       y1_im;
        logic                     sat_y0_re;
        logic                     sat_y0_im;
        logic                     sat_y1_re;
        logic                     sat_y1_im;
        int unsigned              cycle;
        string                    item_name;

        `uvm_object_utils_begin(butterfly_item)
            `uvm_field_int(a_re, UVM_DEFAULT)
            `uvm_field_int(a_im, UVM_DEFAULT)
            `uvm_field_int(b_re, UVM_DEFAULT)
            `uvm_field_int(b_im, UVM_DEFAULT)
            `uvm_field_int(w_re, UVM_DEFAULT)
            `uvm_field_int(w_im, UVM_DEFAULT)
            `uvm_field_int(rst, UVM_DEFAULT)
            `uvm_field_int(valid_out, UVM_DEFAULT)
            `uvm_field_int(y0_re, UVM_DEFAULT)
            `uvm_field_int(y0_im, UVM_DEFAULT)
            `uvm_field_int(y1_re, UVM_DEFAULT)
            `uvm_field_int(y1_im, UVM_DEFAULT)
            `uvm_field_int(sat_y0_re, UVM_DEFAULT)
            `uvm_field_int(sat_y0_im, UVM_DEFAULT)
            `uvm_field_int(sat_y1_re, UVM_DEFAULT)
            `uvm_field_int(sat_y1_im, UVM_DEFAULT)
            `uvm_field_int(cycle, UVM_DEFAULT)
            `uvm_field_string(item_name, UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "butterfly_item");
            super.new(name);
            item_name = name;
        endfunction
    endclass

    class butterfly_sequence extends uvm_sequence #(butterfly_item);
        `uvm_object_utils(butterfly_sequence)

        function new(string name = "butterfly_sequence");
            super.new(name);
        endfunction

        task send_directed(
            string name,
            integer a_re,
            integer a_im,
            integer b_re,
            integer b_im,
            integer w_re,
            integer w_im
        );
            butterfly_item req;
            req = butterfly_item::type_id::create(name);
            start_item(req);
            req.item_name = name;
            req.a_re = a_re[15:0];
            req.a_im = a_im[15:0];
            req.b_re = b_re[15:0];
            req.b_im = b_im[15:0];
            req.w_re = w_re[15:0];
            req.w_im = w_im[15:0];
            finish_item(req);
        endtask

        task body();
            // A compact directed set exercises pass-through behavior, both Y0
            // saturation directions, nontrivial complex arithmetic, Y1
            // saturation, and consecutive II=1 traffic.
            send_directed("all_zero",       0,      0,      0,      0,      0,      0);
            send_directed("pass_a",     12345, -12345,      0,      0,  32767,      0);
            send_directed("equal_inputs",8192,  -8192,   8192,  -8192,      0, -32768);
            send_directed("y0_pos_sat", 32767,      0,      1,      0,  32767,      0);
            send_directed("y0_neg_sat",-32768,      0,     -1,      0,  32767,      0);
            send_directed("max_opposed",32767, -32768, -32768,  32767, -32768, -32768);
            send_directed("mixed_signs",-16384,  8192,   4096, -24576,  23170, -23170);
        endtask
    endclass

    class butterfly_sequencer extends uvm_sequencer #(butterfly_item);
        `uvm_component_utils(butterfly_sequencer)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class butterfly_driver extends uvm_driver #(butterfly_item);
        `uvm_component_utils(butterfly_driver)

        virtual butterfly_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual butterfly_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "butterfly_driver did not receive the virtual interface")
        endfunction

        task drive_idle();
            vif.driver_cb.valid_in <= 1'b0;
            vif.driver_cb.a_re     <= '0;
            vif.driver_cb.a_im     <= '0;
            vif.driver_cb.b_re     <= '0;
            vif.driver_cb.b_im     <= '0;
            vif.driver_cb.w_re     <= '0;
            vif.driver_cb.w_im     <= '0;
        endtask

        task run_phase(uvm_phase phase);
            butterfly_item req;

            @(vif.driver_cb);
            drive_idle();
            while (vif.driver_cb.rst !== 1'b0) begin
                @(vif.driver_cb);
                drive_idle();
            end

            forever begin
                seq_item_port.get_next_item(req);
                vif.driver_cb.valid_in <= 1'b1;
                vif.driver_cb.a_re     <= req.a_re;
                vif.driver_cb.a_im     <= req.a_im;
                vif.driver_cb.b_re     <= req.b_re;
                vif.driver_cb.b_im     <= req.b_im;
                vif.driver_cb.w_re     <= req.w_re;
                vif.driver_cb.w_im     <= req.w_im;
                seq_item_port.item_done();
                @(vif.driver_cb);
                drive_idle();
            end
        endtask
    endclass

    class butterfly_input_monitor extends uvm_component;
        `uvm_component_utils(butterfly_input_monitor)

        virtual butterfly_if vif;
        uvm_analysis_port #(butterfly_item) ap;
        int unsigned cycle_count;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual butterfly_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "butterfly_input_monitor did not receive the virtual interface")
        endfunction

        task run_phase(uvm_phase phase);
            butterfly_item tr;
            cycle_count = 0;
            forever begin
                @(vif.monitor_cb);
                cycle_count++;
                if ((vif.monitor_cb.rst === 1'b0) &&
                    (vif.monitor_cb.valid_in === 1'b1)) begin
                    tr = butterfly_item::type_id::create("observed_input");
                    tr.cycle = cycle_count;
                    tr.a_re = vif.monitor_cb.a_re;
                    tr.a_im = vif.monitor_cb.a_im;
                    tr.b_re = vif.monitor_cb.b_re;
                    tr.b_im = vif.monitor_cb.b_im;
                    tr.w_re = vif.monitor_cb.w_re;
                    tr.w_im = vif.monitor_cb.w_im;
                    tr.item_name = $sformatf("observed_input_%0d", cycle_count);
                    ap.write(tr);
                end
            end
        endtask
    endclass

    class butterfly_output_monitor extends uvm_component;
        `uvm_component_utils(butterfly_output_monitor)

        virtual butterfly_if vif;
        uvm_analysis_port #(butterfly_item) ap;
        int unsigned cycle_count;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual butterfly_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "butterfly_output_monitor did not receive the virtual interface")
        endfunction

        task run_phase(uvm_phase phase);
            butterfly_item tr;
            cycle_count = 0;
            forever begin
                @(vif.monitor_cb);
                cycle_count++;
                tr = butterfly_item::type_id::create("observed_output");
                tr.cycle = cycle_count;
                tr.rst = vif.monitor_cb.rst;
                tr.valid_out = vif.monitor_cb.valid_out;
                tr.y0_re = vif.monitor_cb.y0_re;
                tr.y0_im = vif.monitor_cb.y0_im;
                tr.y1_re = vif.monitor_cb.y1_re;
                tr.y1_im = vif.monitor_cb.y1_im;
                tr.sat_y0_re = vif.monitor_cb.sat_y0_re;
                tr.sat_y0_im = vif.monitor_cb.sat_y0_im;
                tr.sat_y1_re = vif.monitor_cb.sat_y1_re;
                tr.sat_y1_im = vif.monitor_cb.sat_y1_im;
                ap.write(tr);
            end
        endtask
    endclass

    class butterfly_scoreboard extends uvm_component;
        `uvm_component_utils(butterfly_scoreboard)

        uvm_analysis_imp_input  #(butterfly_item, butterfly_scoreboard) input_export;
        uvm_analysis_imp_output #(butterfly_item, butterfly_scoreboard) output_export;

        butterfly_item expected_queue[$];
        int unsigned inputs_seen;
        int unsigned outputs_checked;
        int unsigned error_count;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            input_export = new("input_export", this);
            output_export = new("output_export", this);
        endfunction

        function automatic logic signed [15:0] saturate_q15(
            input longint signed value,
            output logic saturated
        );
            saturated = 1'b0;
            if (value > 32767) begin
                saturated = 1'b1;
                return 16'sh7fff;
            end
            if (value < -32768) begin
                saturated = 1'b1;
                return 16'sh8000;
            end
            return value[15:0];
        endfunction

        function automatic longint signed round_q30_to_q15(input longint signed value);
            longint signed base_value;
            logic guard_bit;
            logic sticky_bit;
            logic kept_lsb;

            base_value = value >>> 15;
            guard_bit = (value >>> 14) & 64'sd1;
            sticky_bit = (value & 64'sh0000_0000_0000_3fff) != 0;
            kept_lsb = (value >>> 15) & 64'sd1;
            return base_value + (guard_bit && (sticky_bit || kept_lsb));
        endfunction

        function automatic butterfly_item make_expected(input butterfly_item observed);
            butterfly_item exp;
            logic signed [16:0] sum_re;
            logic signed [16:0] sum_im;
            logic signed [16:0] diff_re;
            logic signed [16:0] diff_im;
            logic signed [32:0] diff_re_ext;
            logic signed [32:0] diff_im_ext;
            logic signed [32:0] w_re_ext;
            logic signed [32:0] w_im_ext;
            logic signed [32:0] m0;
            logic signed [32:0] m1;
            logic signed [32:0] m2;
            logic signed [32:0] m3;
            logic signed [33:0] p_re;
            logic signed [33:0] p_im;
            logic signed [19:0] rounded_re;
            logic signed [19:0] rounded_im;

            exp = butterfly_item::type_id::create("expected");
            exp.cycle = observed.cycle + 2;
            exp.item_name = observed.item_name;

            sum_re = {observed.a_re[15], observed.a_re}
                   + {observed.b_re[15], observed.b_re};
            sum_im = {observed.a_im[15], observed.a_im}
                   + {observed.b_im[15], observed.b_im};
            diff_re = {observed.a_re[15], observed.a_re}
                    - {observed.b_re[15], observed.b_re};
            diff_im = {observed.a_im[15], observed.a_im}
                    - {observed.b_im[15], observed.b_im};

            diff_re_ext = {{16{diff_re[16]}}, diff_re};
            diff_im_ext = {{16{diff_im[16]}}, diff_im};
            w_re_ext = {{17{observed.w_re[15]}}, observed.w_re};
            w_im_ext = {{17{observed.w_im[15]}}, observed.w_im};

            // Each multiplication is mathematically a signed 17-by-16-bit
            // operation, whose complete result is 33 bits.
            m0 = diff_re_ext * w_re_ext;
            m1 = diff_im_ext * w_im_ext;
            m2 = diff_re_ext * w_im_ext;
            m3 = diff_im_ext * w_re_ext;

            // Both operands remain full 33-bit products before the 34-bit
            // complex add/subtract operation.
            p_re = {m0[32], m0} - {m1[32], m1};
            p_im = {m2[32], m2} + {m3[32], m3};

            rounded_re = round_q30_to_q15(p_re);
            rounded_im = round_q30_to_q15(p_im);

            exp.y0_re = saturate_q15(sum_re, exp.sat_y0_re);
            exp.y0_im = saturate_q15(sum_im, exp.sat_y0_im);
            exp.y1_re = saturate_q15(rounded_re, exp.sat_y1_re);
            exp.y1_im = saturate_q15(rounded_im, exp.sat_y1_im);
            exp.valid_out = 1'b1;
            return exp;
        endfunction

        function void write_input(butterfly_item tr);
            butterfly_item exp;
            exp = make_expected(tr);
            expected_queue.push_back(exp);
            inputs_seen++;
        endfunction

        function void report_mismatch(
            string field_name,
            logic signed [15:0] actual,
            logic signed [15:0] expected,
            int unsigned cycle
        );
            if (actual !== expected) begin
                error_count++;
                `uvm_error("MISMATCH", $sformatf(
                    "cycle %0d %s actual=%0d expected=%0d",
                    cycle, field_name, $signed(actual), $signed(expected)))
            end
        endfunction

        function void report_flag_mismatch(
            string field_name,
            logic actual,
            logic expected,
            int unsigned cycle
        );
            if (actual !== expected) begin
                error_count++;
                `uvm_error("MISMATCH", $sformatf(
                    "cycle %0d %s actual=%0b expected=%0b",
                    cycle, field_name, actual, expected))
            end
        endfunction

        function void write_output(butterfly_item tr);
            butterfly_item exp;

            if (tr.rst === 1'b1) begin
                expected_queue.delete();
                return;
            end

            while ((expected_queue.size() != 0) &&
                   (expected_queue[0].cycle < tr.cycle)) begin
                exp = expected_queue.pop_front();
                error_count++;
                `uvm_error("LATENCY", $sformatf(
                    "missing output for input due at cycle %0d", exp.cycle))
            end

            if ((expected_queue.size() != 0) &&
                (expected_queue[0].cycle == tr.cycle)) begin
                exp = expected_queue.pop_front();
                if (tr.valid_out !== 1'b1) begin
                    error_count++;
                    `uvm_error("LATENCY", $sformatf(
                        "valid_out was not asserted at required cycle %0d", tr.cycle))
                    return;
                end

                report_mismatch("y0_re", tr.y0_re, exp.y0_re, tr.cycle);
                report_mismatch("y0_im", tr.y0_im, exp.y0_im, tr.cycle);
                report_mismatch("y1_re", tr.y1_re, exp.y1_re, tr.cycle);
                report_mismatch("y1_im", tr.y1_im, exp.y1_im, tr.cycle);
                report_flag_mismatch("sat_y0_re", tr.sat_y0_re, exp.sat_y0_re, tr.cycle);
                report_flag_mismatch("sat_y0_im", tr.sat_y0_im, exp.sat_y0_im, tr.cycle);
                report_flag_mismatch("sat_y1_re", tr.sat_y1_re, exp.sat_y1_re, tr.cycle);
                report_flag_mismatch("sat_y1_im", tr.sat_y1_im, exp.sat_y1_im, tr.cycle);
                outputs_checked++;
            end else if (tr.valid_out === 1'b1) begin
                error_count++;
                `uvm_error("ORDER", $sformatf(
                    "unexpected or out-of-order valid output at cycle %0d", tr.cycle))
            end
        endfunction

        function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (expected_queue.size() != 0) begin
                error_count++;
                `uvm_error("NOT_EMPTY", $sformatf(
                    "expected queue contains %0d transaction(s) at end of test",
                    expected_queue.size()))
            end
            if (outputs_checked != inputs_seen) begin
                error_count++;
                `uvm_error("COUNT", $sformatf(
                    "observed %0d inputs but checked %0d outputs",
                    inputs_seen, outputs_checked))
            end
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            if (error_count == 0)
                `uvm_info("PASS", $sformatf(
                    "checked %0d transactions with two-cycle latency",
                    outputs_checked), UVM_LOW)
        endfunction
    endclass

    class butterfly_agent extends uvm_agent;
        `uvm_component_utils(butterfly_agent)

        butterfly_sequencer sequencer;
        butterfly_driver driver;
        butterfly_input_monitor input_monitor;
        butterfly_output_monitor output_monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = butterfly_sequencer::type_id::create("sequencer", this);
            driver = butterfly_driver::type_id::create("driver", this);
            input_monitor = butterfly_input_monitor::type_id::create("input_monitor", this);
            output_monitor = butterfly_output_monitor::type_id::create("output_monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class butterfly_env extends uvm_env;
        `uvm_component_utils(butterfly_env)

        butterfly_agent agent;
        butterfly_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = butterfly_agent::type_id::create("agent", this);
            scoreboard = butterfly_scoreboard::type_id::create("scoreboard", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.input_monitor.ap.connect(scoreboard.input_export);
            agent.output_monitor.ap.connect(scoreboard.output_export);
        endfunction
    endclass

    class butterfly_test extends uvm_test;
        `uvm_component_utils(butterfly_test)

        butterfly_env env;
        virtual butterfly_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = butterfly_env::type_id::create("env", this);
            if (!uvm_config_db#(virtual butterfly_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "butterfly_test did not receive the virtual interface")
        endfunction

        task run_phase(uvm_phase phase);
            butterfly_sequence seq;
            phase.raise_objection(this);
            seq = butterfly_sequence::type_id::create("seq");
            seq.start(env.agent.sequencer);

            // Allow the final accepted input to traverse the two-cycle core,
            // plus additional monitor cycles before ending the run phase.
            repeat (5) @(vif.monitor_cb);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
