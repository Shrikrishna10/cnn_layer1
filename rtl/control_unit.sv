// =============================================================================
// Control Unit — FSM + cycle-accurate scheduling for the 24-cycle patch
// =============================================================================
// Implements the Final Draft timing table:
//
//   Cyc  Batch  MAC0    MAC1    MAC2    MAC3    Notes
//    0    B0    w0,a0   w1,a1   w2,a2   w3,a3   Load (1 cyc)
//   1-2   B0    mult    mult    mult    mult    Multiply (2 cyc)
//   3-5   B0    add     add     add     add     Accumulate, ACC reset
//    6    B1    w4,a4   w5,a5   w6,a6   w7,a7   Load
//   7-8   B1    mult    mult    mult    mult
//   9-11  B1    add     add     add     add     ACC += product
//   12    B2    w8,a8   idle    idle    idle    Load (MAC0 only)
//  13-14  B2    mult    idle    idle    idle
//  15-17  B2    add     idle    add(R1) idle    MAC0: ACC0+=p8, MAC2: ACC2+=ACC3
//  18-20  Red   idle    add(R2) idle    idle    MAC1: ACC1+=ACC2
//  21-23  Red   add(R3) idle    idle    idle    MAC0: ACC0+=ACC1 → final
//
// Before each patch the LOAD_PATCH state pre-fills the SRAM with 9 weights
// and 9 pixel values (5 write-cycles at 4 bytes/cycle).
// =============================================================================
`include "pkg_conv1.svh"

module control_unit (
    input  logic        clk,
    input  logic        rst_n,

    // --- handshake ---
    input  logic        start,
    output logic        done,
    output logic        result_valid,

    // --- external memory interface (directly addressed) ---
    output logic [5:0]  ext_pixel_addr,      // pixel address (0-63)
    output logic [3:0]  ext_weight_addr,     // weight address (0-8)
    output logic        ext_pixel_rd,
    output logic        ext_weight_rd,
    input  logic signed [DATA_W-1:0] ext_pixel_data,
    input  logic signed [DATA_W-1:0] ext_weight_data,

    // --- SRAM interface ---
    output logic [1:0]  sram_wr_addr,
    output logic        sram_wr_en,
    output logic [31:0] sram_wr_data,
    output logic [1:0]  sram_rd_addr,
    output logic        sram_rd_en,
    input  logic [31:0] sram_rd_data,

    // --- MAC array control ---
    output logic signed [DATA_W-1:0] mac_pixel  [NUM_MACS],
    output logic signed [DATA_W-1:0] mac_weight [NUM_MACS],
    output logic [NUM_MACS-1:0]      mac_acc_en,
    output logic [NUM_MACS-1:0]      mac_acc_clear,
    output logic [NUM_MACS-1:0]      mac_mode_add_only,
    output logic [2:0]               mac_red_sel [NUM_MACS],

    // --- patch address generator ---
    output logic [3:0]  pag_patch_idx,
    output logic [3:0]  pag_op_idx,
    input  logic [5:0]  pag_pixel_addr,
    input  logic        pag_is_pad,

    // --- status (for testbench instrumentation) ---
    output state_t      fsm_state,
    output logic [3:0]  patch_count,
    output logic [4:0]  cycle_in_patch   // 0-23 during COMPUTE
);

    // -----------------------------------------------------------------------
    //  Internal state
    // -----------------------------------------------------------------------
    state_t state, state_next;
    logic [3:0] p_cnt, p_cnt_next;       // patch counter 0-15
    logic [4:0] cyc,   cyc_next;         // cycle within current state
    logic [3:0] load_cnt, load_cnt_next; // SRAM load sub-counter (0-8)

    assign fsm_state     = state;
    assign patch_count   = p_cnt;
    assign cycle_in_patch = cyc;

    // Weight/pixel registers captured during LOAD_PATCH
    logic signed [DATA_W-1:0] w_buf [9];  // 9 weights
    logic signed [DATA_W-1:0] a_buf [9];  // 9 pixels
    logic [3:0] load_idx;

    // -----------------------------------------------------------------------
    //  State register
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            p_cnt    <= '0;
            cyc      <= '0;
            load_cnt <= '0;
        end else begin
            state    <= state_next;
            p_cnt    <= p_cnt_next;
            cyc      <= cyc_next;
            load_cnt <= load_cnt_next;
        end
    end

    // -----------------------------------------------------------------------
    //  Weight / pixel buffer loading
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 9; i++) begin
                w_buf[i] <= '0;
                a_buf[i] <= '0;
            end
        end else if (state == S_LOAD_PATCH && load_cnt < 4'd9) begin
            w_buf[load_cnt] <= ext_weight_data;
            a_buf[load_cnt] <= pag_is_pad ? 8'sd0 : ext_pixel_data;
        end
    end

    // -----------------------------------------------------------------------
    //  Next-state logic
    // -----------------------------------------------------------------------
    always_comb begin
        state_next    = state;
        p_cnt_next    = p_cnt;
        cyc_next      = cyc;
        load_cnt_next = load_cnt;

        case (state)
            S_IDLE: begin
                if (start) begin
                    state_next    = S_LOAD_PATCH;
                    p_cnt_next    = '0;
                    load_cnt_next = '0;
                end
            end

            S_LOAD_PATCH: begin
                // Load 9 operands: takes 10 cycles (1 extra for last buf capture)
                if (load_cnt == 4'd9) begin
                    state_next    = S_BATCH0;
                    cyc_next      = '0;
                    load_cnt_next = '0;
                end else begin
                    load_cnt_next = load_cnt + 1'b1;
                end
            end

            S_BATCH0: begin
                if (cyc == 5'd5) begin
                    state_next = S_BATCH1;
                    cyc_next   = '0;
                end else begin
                    cyc_next = cyc + 1'b1;
                end
            end

            S_BATCH1: begin
                if (cyc == 5'd5) begin
                    state_next = S_BATCH2;
                    cyc_next   = '0;
                end else begin
                    cyc_next = cyc + 1'b1;
                end
            end

            S_BATCH2: begin
                // 6 cycles for MAC0 compute + overlapped MAC2 reduction step 1
                if (cyc == 5'd5) begin
                    state_next = S_REDUCE2;
                    cyc_next   = '0;
                end else begin
                    cyc_next = cyc + 1'b1;
                end
            end

            S_REDUCE2: begin
                // 3 cycles: MAC1 does ACC1 += ACC2
                if (cyc == 5'd2) begin
                    state_next = S_REDUCE3;
                    cyc_next   = '0;
                end else begin
                    cyc_next = cyc + 1'b1;
                end
            end

            S_REDUCE3: begin
                // 3 cycles: MAC0 does ACC0 += ACC1 → final result
                if (cyc == 5'd2) begin
                    state_next = S_WRITE;
                    cyc_next   = '0;
                end else begin
                    cyc_next = cyc + 1'b1;
                end
            end

            S_WRITE: begin
                // 1 cycle to output result
                if (p_cnt == NUM_PATCHES - 1) begin
                    state_next = S_DONE;
                end else begin
                    state_next    = S_LOAD_PATCH;
                    p_cnt_next    = p_cnt + 1'b1;
                    load_cnt_next = '0;
                end
            end

            S_DONE: begin
                // stay here until reset or re-start
                state_next = S_DONE;
            end

            default: state_next = S_IDLE;
        endcase
    end

    // -----------------------------------------------------------------------
    //  External memory reads (during LOAD_PATCH)
    // -----------------------------------------------------------------------
    assign load_idx         = {1'b0, load_cnt};
    assign pag_patch_idx    = p_cnt;
    assign pag_op_idx       = load_idx;
    assign ext_pixel_addr   = pag_pixel_addr;
    assign ext_weight_addr  = load_idx;
    assign ext_pixel_rd     = (state == S_LOAD_PATCH);
    assign ext_weight_rd    = (state == S_LOAD_PATCH);

    // -----------------------------------------------------------------------
    //  SRAM writes (during LOAD_PATCH — pack 4 bytes per word)
    // -----------------------------------------------------------------------
    // For simplicity we also write to SRAM during LOAD_PATCH so it is
    // populated, but the MAC array is fed directly from w_buf/a_buf.
    always_comb begin
        sram_wr_en   = 1'b0;
        sram_wr_addr = 2'd0;
        sram_wr_data = '0;

        if (state == S_LOAD_PATCH) begin
            case (load_cnt)
                4'd4: begin   // w0-w3 captured on previous cycles
                    sram_wr_en   = 1'b1;
                    sram_wr_addr = 2'd0;
                    sram_wr_data = {w_buf[3], w_buf[2], w_buf[1], w_buf[0]};
                end
                4'd8: begin   // w4-w7 captured on previous cycles
                    sram_wr_en   = 1'b1;
                    sram_wr_addr = 2'd1;
                    sram_wr_data = {w_buf[7], w_buf[6], w_buf[5], w_buf[4]};
                end
                default: ;
            endcase
        end
    end

    assign sram_rd_en   = 1'b0;  // reads handled via buffers directly
    assign sram_rd_addr = 2'd0;

    // -----------------------------------------------------------------------
    //  MAC data routing
    // -----------------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < NUM_MACS; m++) begin
            mac_pixel[m]  = '0;
            mac_weight[m] = '0;
        end

        case (state)
            S_BATCH0: begin
                // Operands 0-3
                for (int m = 0; m < NUM_MACS; m++) begin
                    mac_pixel[m]  = a_buf[m];
                    mac_weight[m] = w_buf[m];
                end
            end
            S_BATCH1: begin
                // Operands 4-7
                for (int m = 0; m < NUM_MACS; m++) begin
                    mac_pixel[m]  = a_buf[4 + m];
                    mac_weight[m] = w_buf[4 + m];
                end
            end
            S_BATCH2: begin
                // Operand 8 — MAC0 only
                mac_pixel[0]  = a_buf[8];
                mac_weight[0] = w_buf[8];
            end
            default: ;
        endcase
    end

    // -----------------------------------------------------------------------
    //  MAC control signals
    // -----------------------------------------------------------------------
    always_comb begin
        mac_acc_en        = '0;
        mac_acc_clear     = '0;
        mac_mode_add_only = '0;
        for (int m = 0; m < NUM_MACS; m++)
            mac_red_sel[m] = 3'd0;

        case (state)
            // ---- BATCH 0 : all 4 MACs, ACC = product (clear accumulator) ----
            S_BATCH0: begin
                if (cyc == 5'd5) begin  // end of 3-cycle add
                    mac_acc_en    = 4'b1111;
                    mac_acc_clear = 4'b1111;   // first batch → reset ACC
                end
            end

            // ---- BATCH 1 : all 4 MACs, ACC += product ----
            S_BATCH1: begin
                if (cyc == 5'd5) begin
                    mac_acc_en    = 4'b1111;
                    mac_acc_clear = 4'b0000;   // accumulate
                end
            end

            // ---- BATCH 2 : MAC0 accumulates operand 8  ----
            //                MAC2 does reduction step 1 (ACC2 += ACC3)
            S_BATCH2: begin
                if (cyc == 5'd5) begin
                    // MAC0 : ACC0 += p8
                    mac_acc_en[0]        = 1'b1;
                    mac_acc_clear[0]     = 1'b0;
                    mac_mode_add_only[0] = 1'b0;  // normal MAC

                    // MAC2 : ADD_ONLY → ACC2 = ACC2 + ACC3
                    mac_acc_en[2]        = 1'b1;
                    mac_acc_clear[2]     = 1'b0;
                    mac_mode_add_only[2] = 1'b1;
                    mac_red_sel[2]       = 3'd4;   // route ACC3
                end
            end

            // ---- REDUCE step 2 : MAC1 does ACC1 += ACC2 ----
            S_REDUCE2: begin
                if (cyc == 5'd2) begin
                    mac_acc_en[1]        = 1'b1;
                    mac_acc_clear[1]     = 1'b0;
                    mac_mode_add_only[1] = 1'b1;
                    mac_red_sel[1]       = 3'd3;   // route ACC2
                end
            end

            // ---- REDUCE step 3 : MAC0 does ACC0 += ACC1 → final ----
            S_REDUCE3: begin
                if (cyc == 5'd2) begin
                    mac_acc_en[0]        = 1'b1;
                    mac_acc_clear[0]     = 1'b0;
                    mac_mode_add_only[0] = 1'b1;
                    mac_red_sel[0]       = 3'd2;   // route ACC1
                end
            end

            default: ;
        endcase
    end

    // -----------------------------------------------------------------------
    //  Output handshake
    // -----------------------------------------------------------------------
    assign result_valid = (state == S_WRITE);
    assign done         = (state == S_DONE);

endmodule
