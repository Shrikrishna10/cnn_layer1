`timescale 1ns/1ps

module tb;

    // ---- Signals you care about in the waveform ----
    reg         clk;
    reg         rst;
    reg  [15:0] in_a;
    reg  [15:0] in_w;
    reg  [19:0] in_ad;
    reg         sel_acc;     // 0 = use 0, 1 = feedback ACC
    reg         sel_bypass;  // 0 = MAC (mul), 1 = bypass mul and use in_ad

    wire [19:0] out_mac;
    wire [19:0] out_add;

    // internal control for starting ops
    reg         in_valid;
    reg         add_valid;

    // DUT connection
    wire [19:0] acc_out;

    pipelined_mac dut (
        .clk      (clk),
        .rst      (rst),
        .mode_add (sel_bypass), // ADD-only / bypass control
        .mux_sel  (sel_acc),    // ACC feedback vs zero
        .in_valid (in_valid),
        .add_valid(add_valid),
        .a        (in_a),
        .b        (in_w),
        .add_in   (in_ad),
        .acc_out  (acc_out)
    );

    // For your diagram, both out_mac and out_add just show acc_out
    assign out_mac = acc_out;
    assign out_add = acc_out;

    // ---------------- Clock ----------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 10 ns period
    end

    integer cycle;

    // ---------------- Stimulus ----------------
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
        in_valid   = 0;
        add_valid  = 0;
        cycle      = -1;

        // 15 cycles total
        repeat (15) begin
            @(posedge clk);
            cycle = cycle + 1;

            case (cycle)
                // 0–1: reset asserted
                0,1: begin
                    rst        <= 1;
                    sel_acc    <= 0;
                    sel_bypass <= 0;
                    in_valid   <= 0;
                    add_valid  <= 0;
                end

                // 2: release reset
                2: begin
                    rst <= 0;
                end

                // -------- ONE MAC OP: mul+add --------
                // Start at cycle 3: ACC = 0 + (3 * 5)
                3: begin
                    sel_bypass <= 0;      // MAC mode (use multiplier)
                    sel_acc    <= 0;      // ACC source = 0 (clear)
                    in_a       <= 16'd3;
                    in_w       <= 16'd5;
                    in_valid   <= 1;
                end

                4: begin
                    in_valid <= 0;        // let pipeline run
                end

                // 5–8: just pipeline latency for MAC

                // -------- ONE ADD-ONLY OP --------
                // Start at cycle 9: ACC_new = ACC + 7
                9: begin
                    sel_bypass <= 1;      // bypass mul, use in_ad
                    sel_acc    <= 1;      // ACC feedback
                    in_ad      <= 20'd7;
                    add_valid  <= 1;
                end

                10: begin
                    add_valid <= 0;       // let ADD-only pipeline run
                end

                // 11: pipeline latency for ADD-only

                // -------- small reset window --------
                12: rst <= 1;
                13: rst <= 0;

                // 14: idle
                14: begin
                    sel_bypass <= 0;
                    sel_acc    <= 0;
                    in_valid   <= 0;
                    add_valid  <= 0;
                end
            endcase
        end

        @(posedge clk);
        $finish;
    end

endmodule

