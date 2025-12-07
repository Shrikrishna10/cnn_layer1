`timescale 1ns/1ps

module tb;

    reg         clk;
    reg         rst;
    reg         mode_add;
    reg         mux_sel;
    reg         in_valid;
    reg         add_valid;
    reg  [15:0] a;
    reg  [15:0] b;
    reg  [19:0] add_in;

    wire [19:0] acc;
    wire        mac_done;
    wire        add_done;

    // ---------------- Instantiate DUT ----------------
    pipelined_mac dut (
        .clk(clk),
        .rst(rst),
        .mode_add(mode_add),
        .mux_sel(mux_sel),
        .in_valid(in_valid),
        .add_valid(add_valid),
        .a(a),
        .b(b),
        .add_in(add_in),
        .acc(acc),
        .mac_done(mac_done),
        .add_done(add_done)
    );

    // ---------------- Clock ----------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 10 ns clock
    end

    integer cycle;

    // ---------------- Stimulus ----------------
    initial begin
        $dumpfile("mac_timing.vcd");
        $dumpvars(0, tb);

        // defaults
        rst       = 1;
        mode_add  = 0;
        mux_sel   = 0;
        in_valid  = 0;
        add_valid = 0;
        a         = 0;
        b         = 0;
        add_in    = 0;
        cycle     = -1;

        repeat (15) begin
            @(posedge clk);
            cycle = cycle + 1;

            case (cycle)
                // 0–1 : reset high
                0,1: begin
                    rst       <= 1;
                    in_valid  <= 0;
                    add_valid <= 0;
                    mux_sel   <= 0;
                    mode_add  <= 0;
                end

                // 2 : release reset
                2: begin
                    rst <= 0;
                end

                // -------- MAC OPERATION (mul+add) --------
                // Start MAC at cycle 3: ACC = (3 * 5)
                3: begin
                    mode_add  <= 0;     // MAC mode
                    mux_sel   <= 0;     // ACC reset
                    in_valid  <= 1;
                    a         <= 16'd3;
                    b         <= 16'd5;
                end

                4: in_valid <= 0;       // pipelining continues

                // 5–8: internal pipeline running (mult+adder)
                5,6,7,8: begin end

                // -------- ADD-ONLY OP (ACC + 7) --------
                9: begin
                    mode_add  <= 1;
                    mux_sel   <= 1;
                    add_in    <= 20'd7;
                    add_valid <= 1;
                end

                10: add_valid <= 0;

                // pipeline 11

                // -------- small reset section --------
                12: rst <= 1;
                13: rst <= 0;

                // 14: idle
                14: begin
                    mode_add  <= 0;
                    mux_sel   <= 0;
                    in_valid  <= 0;
                    add_valid <= 0;
                end
            endcase
        end

        @(posedge clk);
        $finish;
    end

endmodule

