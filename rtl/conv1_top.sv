// =============================================================================
// Conv1 Top Level — Convolution Accelerator
// =============================================================================
`include "pkg_conv1.svh"

module conv1_top (
    input  logic        clk,
    input  logic        rst_n,

    // --- control ---
    input  logic        start,
    output logic        done,

    // --- external memory interface ---
    output logic [5:0]  ext_pixel_addr,
    output logic [3:0]  ext_weight_addr,
    output logic        ext_pixel_rd,
    output logic        ext_weight_rd,
    input  logic signed [DATA_W-1:0] ext_pixel_data,
    input  logic signed [DATA_W-1:0] ext_weight_data,

    // --- output ---
    output logic                     result_valid,
    output logic signed [ACC_W-1:0]  result_data,

    // --- instrumentation (directly exposed for testbench) ---
    output state_t      dbg_state,
    output logic [3:0]  dbg_patch_count,
    output logic [4:0]  dbg_cycle_in_patch,
    output logic signed [ACC_W-1:0]  dbg_acc [NUM_MACS]
);

    // -----------------------------------------------------------------------
    //  Internal wires
    // -----------------------------------------------------------------------
    // Control → SRAM
    logic [1:0]  sram_wr_addr, sram_rd_addr;
    logic        sram_wr_en,   sram_rd_en;
    logic [31:0] sram_wr_data, sram_rd_data;

    // Control → MAC array
    logic signed [DATA_W-1:0] mac_pixel  [NUM_MACS];
    logic signed [DATA_W-1:0] mac_weight [NUM_MACS];
    logic [NUM_MACS-1:0]      mac_acc_en;
    logic [NUM_MACS-1:0]      mac_acc_clear;
    logic [NUM_MACS-1:0]      mac_mode_add_only;
    logic [2:0]               mac_red_sel [NUM_MACS];

    // MAC array outputs
    logic signed [ACC_W-1:0]  mac_acc_out [NUM_MACS];
    logic signed [ACC_W-1:0]  final_result;

    // Control → patch_addr_gen
    logic [3:0] pag_patch_idx, pag_op_idx;
    logic [5:0] pag_pixel_addr;
    logic       pag_is_pad;

    // -----------------------------------------------------------------------
    //  Patch Address Generator
    // -----------------------------------------------------------------------
    patch_addr_gen u_pag (
        .patch_idx   (pag_patch_idx),
        .op_idx      (pag_op_idx),
        .pixel_addr  (pag_pixel_addr),
        .is_pad      (pag_is_pad)
    );

    // -----------------------------------------------------------------------
    //  Dual-Port SRAM (16 bytes)
    // -----------------------------------------------------------------------
    sram_dp u_sram (
        .clk      (clk),
        .rd_addr  (sram_rd_addr),
        .rd_en    (sram_rd_en),
        .rd_data  (sram_rd_data),
        .wr_addr  (sram_wr_addr),
        .wr_en    (sram_wr_en),
        .wr_data  (sram_wr_data)
    );

    // -----------------------------------------------------------------------
    //  MAC Array (4 units)
    // -----------------------------------------------------------------------
    mac_array u_mac_array (
        .clk            (clk),
        .rst_n          (rst_n),
        .pixel_in       (mac_pixel),
        .weight_in      (mac_weight),
        .acc_en         (mac_acc_en),
        .acc_clear      (mac_acc_clear),
        .mode_add_only  (mac_mode_add_only),
        .red_sel        (mac_red_sel),
        .acc_out        (mac_acc_out),
        .final_result   (final_result)
    );

    // -----------------------------------------------------------------------
    //  Control Unit (FSM)
    // -----------------------------------------------------------------------
    control_unit u_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .done             (done),
        .result_valid     (result_valid),

        .ext_pixel_addr   (ext_pixel_addr),
        .ext_weight_addr  (ext_weight_addr),
        .ext_pixel_rd     (ext_pixel_rd),
        .ext_weight_rd    (ext_weight_rd),
        .ext_pixel_data   (ext_pixel_data),
        .ext_weight_data  (ext_weight_data),

        .sram_wr_addr     (sram_wr_addr),
        .sram_wr_en       (sram_wr_en),
        .sram_wr_data     (sram_wr_data),
        .sram_rd_addr     (sram_rd_addr),
        .sram_rd_en       (sram_rd_en),
        .sram_rd_data     (sram_rd_data),

        .mac_pixel        (mac_pixel),
        .mac_weight       (mac_weight),
        .mac_acc_en       (mac_acc_en),
        .mac_acc_clear    (mac_acc_clear),
        .mac_mode_add_only(mac_mode_add_only),
        .mac_red_sel      (mac_red_sel),

        .pag_patch_idx    (pag_patch_idx),
        .pag_op_idx       (pag_op_idx),
        .pag_pixel_addr   (pag_pixel_addr),
        .pag_is_pad       (pag_is_pad),

        .fsm_state        (dbg_state),
        .patch_count      (dbg_patch_count),
        .cycle_in_patch   (dbg_cycle_in_patch)
    );

    // -----------------------------------------------------------------------
    //  Result output
    // -----------------------------------------------------------------------
    assign result_data = final_result;   // ACC0 after reduction

    // Debug: expose all accumulator values
    assign dbg_acc = mac_acc_out;

endmodule
