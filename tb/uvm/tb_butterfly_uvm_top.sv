`timescale 1ns/1ps

module tb_butterfly_uvm_top;

    import uvm_pkg::*;
    import butterfly_uvm_pkg::*;

    localparam time CLK_PERIOD = 10ns;

    butterfly_if vif();

    butterfly_pipe dut (
        .clk       (vif.clk),
        .rst       (vif.rst),
        .valid_in  (vif.valid_in),
        .a_re      (vif.a_re),
        .a_im      (vif.a_im),
        .b_re      (vif.b_re),
        .b_im      (vif.b_im),
        .w_re      (vif.w_re),
        .w_im      (vif.w_im),
        .valid_out (vif.valid_out),
        .y0_re     (vif.y0_re),
        .y0_im     (vif.y0_im),
        .y1_re     (vif.y1_re),
        .y1_im     (vif.y1_im),
        .sat_y0_re (vif.sat_y0_re),
        .sat_y0_im (vif.sat_y0_im),
        .sat_y1_re (vif.sat_y1_re),
        .sat_y1_im (vif.sat_y1_im)
    );

    initial begin
        vif.clk = 1'b0;
        forever #(CLK_PERIOD / 2) vif.clk = ~vif.clk;
    end

    initial begin
        vif.rst = 1'b1;
        vif.valid_in = 1'b0;
        vif.a_re = '0;
        vif.a_im = '0;
        vif.b_re = '0;
        vif.b_im = '0;
        vif.w_re = '0;
        vif.w_im = '0;
        repeat (3) @(posedge vif.clk);
        @(negedge vif.clk);
        vif.rst = 1'b0;
    end

    initial begin
        uvm_config_db#(virtual butterfly_if)::set(null, "uvm_test_top*", "vif", vif);
        run_test("butterfly_test");
    end

    initial begin
        #1ms;
        $fatal(1, "UVM simulation timeout");
    end

endmodule
