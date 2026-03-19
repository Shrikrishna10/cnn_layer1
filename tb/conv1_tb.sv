// =============================================================================
// Conv1 Testbench — Functional verification + cycle / utilization reporting
// =============================================================================
// - Models external memory (8×8 image + 3×3 kernel)
// - Computes golden reference convolution in software
// - Drives the DUT, captures outputs, auto-checks
// - Reports: cycle count, per-patch cycles, MAC utilization
// =============================================================================
`timescale 1ns / 1ps
`include "pkg_conv1.svh"

module conv1_tb;

    // -----------------------------------------------------------------------
    //  Clock & reset
    // -----------------------------------------------------------------------
    logic clk = 0;
    logic rst_n;
    always #5 clk = ~clk;   // 100 MHz (period = 10 ns)

    // -----------------------------------------------------------------------
    //  DUT signals
    // -----------------------------------------------------------------------
    logic        start, done, result_valid;
    logic [5:0]  ext_pixel_addr;
    logic [3:0]  ext_weight_addr;
    logic        ext_pixel_rd, ext_weight_rd;
    logic signed [DATA_W-1:0] ext_pixel_data, ext_weight_data;
    logic signed [ACC_W-1:0]  result_data;

    state_t      dbg_state;
    logic [3:0]  dbg_patch_count;
    logic [4:0]  dbg_cycle_in_patch;
    logic signed [ACC_W-1:0] dbg_acc [NUM_MACS];

    // -----------------------------------------------------------------------
    //  DUT instantiation
    // -----------------------------------------------------------------------
    conv1_top u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .done             (done),
        .ext_pixel_addr   (ext_pixel_addr),
        .ext_weight_addr  (ext_weight_addr),
        .ext_pixel_rd     (ext_pixel_rd),
        .ext_weight_rd    (ext_weight_rd),
        .ext_pixel_data   (ext_pixel_data),
        .ext_weight_data  (ext_weight_data),
        .result_valid     (result_valid),
        .result_data      (result_data),
        .dbg_state        (dbg_state),
        .dbg_patch_count  (dbg_patch_count),
        .dbg_cycle_in_patch(dbg_cycle_in_patch),
        .dbg_acc          (dbg_acc)
    );

    // -----------------------------------------------------------------------
    //  External memory model
    // -----------------------------------------------------------------------
    // 8×8 image:  small incrementing values (1..64)
    logic signed [DATA_W-1:0] image_mem [0:63];

    // 3×3 kernel: all ones (simple sum-of-window → easy to verify)
    logic signed [DATA_W-1:0] weight_mem [0:8];

    // Combinational read (1-cycle latency modeled by always_ff in DUT)
    assign ext_pixel_data  = ext_pixel_rd  ? image_mem[ext_pixel_addr]   : 8'sd0;
    assign ext_weight_data = ext_weight_rd ? weight_mem[ext_weight_addr] : 8'sd0;

    // -----------------------------------------------------------------------
    //  Golden reference computation
    // -----------------------------------------------------------------------
    logic signed [ACC_W-1:0] golden [0:NUM_PATCHES-1];

    task compute_golden();
        automatic int pr, pc, kr, kc;
        automatic int img_r, img_c;
        automatic logic signed [ACC_W-1:0] acc_val;
        automatic logic signed [DATA_W-1:0] pix, wt;

        for (int p = 0; p < NUM_PATCHES; p++) begin
            pr = p / OUT_SIZE;
            pc = p % OUT_SIZE;
            acc_val = 0;

            for (int k = 0; k < NUM_OPS; k++) begin
                kr = k / KERN_SIZE;
                kc = k % KERN_SIZE;
                img_r = pr * STRIDE - PAD + kr;
                img_c = pc * STRIDE - PAD + kc;

                if (img_r < 0 || img_r >= IMG_SIZE || img_c < 0 || img_c >= IMG_SIZE)
                    pix = 8'sd0;   // padding
                else
                    pix = image_mem[img_r * IMG_SIZE + img_c];

                wt = weight_mem[k];
                acc_val = acc_val + (pix * wt);
            end
            golden[p] = acc_val;
        end
    endtask

    // -----------------------------------------------------------------------
    //  Instrumentation
    // -----------------------------------------------------------------------
    integer total_cycles;
    integer compute_cycles;     // cycles in BATCH/REDUCE states
    integer mac_active_cycles;  // sum across all 4 MACs of active cycles
    integer patches_received;
    integer errors;

    // Track compute cycles (when MACs could be working)
    always @(posedge clk) begin
        if (rst_n && !done && (dbg_state >= S_BATCH0 && dbg_state <= S_REDUCE3)) begin
            compute_cycles = compute_cycles + 1;

            // Count per-MAC activity
            case (dbg_state)
                S_BATCH0: mac_active_cycles = mac_active_cycles + 4;  // all 4
                S_BATCH1: mac_active_cycles = mac_active_cycles + 4;  // all 4
                S_BATCH2: begin
                    mac_active_cycles = mac_active_cycles + 1;  // MAC0
                    if (dbg_cycle_in_patch >= 5'd3) // reduction overlap with MAC2
                        mac_active_cycles = mac_active_cycles + 1;
                end
                S_REDUCE2: mac_active_cycles = mac_active_cycles + 1; // MAC1
                S_REDUCE3: mac_active_cycles = mac_active_cycles + 1; // MAC0
                default: ;
            endcase
        end
    end

    // Total cycle counter
    always @(posedge clk) begin
        if (start && !done)
            total_cycles = total_cycles + 1;
        else if (done && total_cycles > 0)
            ;  // freeze
    end

    // -----------------------------------------------------------------------
    //  Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        // --- Initialize memory ---
        for (int i = 0; i < 64; i++)
            image_mem[i] = i[DATA_W-1:0] + 8'sd1;  // 1, 2, 3, ..., 64

        for (int i = 0; i < 9; i++)
            weight_mem[i] = 8'sd1;                  // all-ones kernel

        compute_golden();

        // Print golden reference
        $display("=== Golden Reference (4x4 output) ===");
        for (int r = 0; r < OUT_SIZE; r++) begin
            for (int c = 0; c < OUT_SIZE; c++)
                $write("%6d ", golden[r * OUT_SIZE + c]);
            $display("");
        end

        // --- Reset ---
        rst_n   = 0;
        start   = 0;
        total_cycles      = 0;
        compute_cycles    = 0;
        mac_active_cycles = 0;
        patches_received  = 0;
        errors  = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // --- Start ---
        start = 1;
        @(posedge clk);
        start = 0;

        // --- Wait for results ---
        while (!done) begin
            @(posedge clk);

            // Capture each output as it arrives
            if (result_valid) begin
                $display("[Patch %2d]  DUT = %6d  |  Golden = %6d  |  %s",
                         patches_received, result_data,
                         golden[patches_received],
                         (result_data == golden[patches_received]) ? "PASS" : "** FAIL **");
                if (result_data !== golden[patches_received])
                    errors = errors + 1;
                patches_received = patches_received + 1;
            end
        end

        // --- Summary ---
        $display("");
        $display("============================================================");
        $display("           CONV1 ACCELERATOR — SIMULATION REPORT");
        $display("============================================================");
        $display("  Patches computed  : %0d / %0d", patches_received, NUM_PATCHES);
        $display("  Total cycles      : %0d", total_cycles);
        $display("  Compute cycles    : %0d  (in BATCH+REDUCE states)", compute_cycles);
        $display("  Cycles per patch  : %0d  (compute only: %0d)",
                 total_cycles / NUM_PATCHES, compute_cycles / NUM_PATCHES);
        $display("  MAC active cycles : %0d  (across all 4 MACs)", mac_active_cycles);
        $display("  MAC utilization   : %0d%%",
                 (mac_active_cycles * 100) / (compute_cycles * NUM_MACS));
        $display("  Errors            : %0d", errors);
        $display("============================================================");
        if (errors == 0 && patches_received == NUM_PATCHES)
            $display("  >>> ALL 16 PATCHES PASSED <<<");
        else
            $display("  >>> FAILURES DETECTED <<<");
        $display("============================================================");

        #100;
        $finish;
    end

    // -----------------------------------------------------------------------
    //  FSM state monitor (for waveform readability)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && dbg_state != S_IDLE && dbg_state != S_DONE) begin
            // Uncomment for verbose cycle trace:
            // $display("T=%0t  state=%-12s  patch=%2d  cyc=%2d  acc=[%6d %6d %6d %6d]",
            //          $time, dbg_state.name(), dbg_patch_count, dbg_cycle_in_patch,
            //          dbg_acc[0], dbg_acc[1], dbg_acc[2], dbg_acc[3]);
        end
    end

endmodule
