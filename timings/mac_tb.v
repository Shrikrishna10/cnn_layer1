// Testbench for MAC module
`timescale 1ns/1ps

module mac_tb;
    reg clk;
    reg rst;
    reg [7:0] a;
    reg [7:0] w;
    reg [19:0] in_ad;
    reg mux_sel_g;
    reg mux_sel;
    wire [19:0] accumulate;

    integer cycle_count;

    // Instantiate MAC module (match ports in mac.v)
    mac dut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .w(w),
        .in_ad(in_ad),
        .mux_sel_g(mux_sel_g),
        .mux_sel(mux_sel),
        .accumulate(accumulate)
    );

    // Clock generation (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Cycle counter
    initial begin
        cycle_count = 0;
        forever @(posedge clk) cycle_count = cycle_count + 1;
    end

    // Test sequence: exercise multiply, accumulate, and bypass paths
    initial begin
        // Initialize
        rst = 1;
        a = 0;
        w = 0;
        in_ad = 0;
        mux_sel_g = 0;
        mux_sel = 0;

        // Hold reset for a couple cycles
        @(posedge clk);
        @(posedge clk);
        rst = 0;

        // --- Test 1: simple multiply (3 * 5) with accumulator cleared ---
        // Set mux_sel_g=0 (use multiplier), mux_sel=0 (clear accumulator)
        a = 8'd3;
        w = 8'd5;
        mux_sel_g = 0;
        mux_sel = 0;

        // Wait enough cycles for pipeline (mult and two-stage add pipeline -> 4-5 cycles)
        repeat (5) @(posedge clk);
        $display("[Test1] Expected product=15 (shifted into 20-bit), accumulate=%0d", accumulate);

        // --- Test 2: accumulate second product (2 * 3) on top of previous ---
        // First ensure pipeline cleared input, then feed second product with mux_sel=1
        a = 8'd2;
        w = 8'd3;
        mux_sel_g = 0; // still use multiplier
        mux_sel = 1;   // use accumulator feedback

        // Wait pipeline
        repeat (5) @(posedge clk);
        $display("[Test2] After accumulating 2*3, accumulate=%0d (expected previous + 6)", accumulate);

        // --- Test 3: bypass adder input using in_ad ---
        // Provide a direct addend of 4 via in_ad and keep mux_sel=1 to add to current accumulator
        in_ad = 20'd4;
        mux_sel_g = 1; // bypass multiplier, use in_ad
        mux_sel = 1;   // keep accumulating

        repeat (5) @(posedge clk);
        $display("[Test3] After bypass add of 4, accumulate=%0d (expected previous + 4)", accumulate);

        // --- Test 4: reset and verify accumulate cleared ---
        repeat (3) @(posedge clk);
        $display("[Test4] After reset, accumulate=%0d (expected 0)", accumulate);

        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("mac_timing.vcd");
        $dumpvars(0, mac_tb, dut);
    end

    // Monitor
    always @(posedge clk) begin
        $display("C=%0d T=%0t rst=%b a=%0d w=%0d in_ad=%0d mux_sel_g=%b mux_sel=%b acc=%0d",
                 cycle_count, $time, rst, a, w, in_ad, mux_sel_g, mux_sel, accumulate);
    end

endmodule
