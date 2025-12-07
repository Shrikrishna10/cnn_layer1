`timescale 1ns/1ps

module tb;

    // Signals you care about
    reg         clk;
    reg         rst;
    reg  [15:0] in_a;
    reg  [15:0] in_w;
    reg  [19:0] in_ad;
    reg         sel_acc;     // 0 = clear, 1 = feedback acc
    reg         sel_bypass;  // 0 = MAC, 1 = ADD-only

    wire [19:0] out_mac;
    wire [19:0] out_add;

    // internal valid (not dumped)
    reg         valid;

    // DUT
    mac_core dut (
        .clk       (clk),
        .rst       (rst),
        .sel_acc   (sel_acc),
        .sel_bypass(sel_bypass),
        .valid     (valid),
        .in_a      (in_a),
        .in_w      (in_w),
        .in_ad     (in_ad),
        .acc_out   (out_mac)   // main output
    );

    // For your diagram, out_add is the same value (post-ADD)
    assign out_add = out_mac;

    // Clock: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer cycle;

    initial begin
        $dumpfile("mac_timing.vcd");
        $dumpvars(0,
            clk,
            rst,
            in_a,
            in_w,
            in_ad,
            sel_acc,
            sel_bypass,
            out_mac,
            out_add
        );

        // defaults
        rst        = 1;
        in_a       = 0;
        in_w       = 0;
        in_ad      = 0;
        sel_acc    = 0;
        sel_bypass = 0;
        valid      = 0;
        cycle      = -1;

        // 15 cycles total
        repeat (15) begin
            @(posedge clk);
            cycle = cycle + 1;

            case (cycle)
                // 0–1 : reset
                0,1: begin
                    rst   <= 1;
                    valid <= 0;
                end

                // 2 : release reset
                2: begin
                    rst <= 0;
                end

                // -------- MAC: 3 * 5, 5-cycle delay --------
                // start at cycle 3
                3: begin
                    sel_bypass <= 0;   // use in_a * in_w
                    sel_acc    <= 0;   // start from 0
                    in_a       <= 16'd3;
                    in_w       <= 16'd5;
                    valid      <= 1;
                end
                4: begin
                    valid <= 0;        // one-cycle pulse
                end
                // result (15) will appear 5 cycles after start, at cycle 8

                // -------- ADD-only: +7, 3-cycle delay --------
                // start at cycle 9
                9: begin
                    sel_bypass <= 1;   // bypass mul, use in_ad
                    sel_acc    <= 1;   // accumulate on 15
                    in_ad      <= 20'd7;
                    valid      <= 1;
                end
                10: begin
                    valid <= 0;
                end
                // result (22) will appear 3 cycles after start, at cycle 12

                default: begin
                    // idle
                end
            endcase
        end

        @(posedge clk);
        $finish;
    end

endmodule

