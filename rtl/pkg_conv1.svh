// =============================================================================
// Conv1 Accelerator — Shared Parameters & Types
// =============================================================================
`ifndef PKG_CONV1_SVH
`define PKG_CONV1_SVH

// ---------- Data widths ----------
parameter DATA_W   = 8;    // pixel / weight width
parameter PROD_W   = 16;   // product width (8×8)
parameter ACC_W    = 20;   // accumulator width

// ---------- Convolution parameters ----------
parameter IMG_SIZE   = 8;   // 8×8 input image
parameter KERN_SIZE  = 3;   // 3×3 kernel
parameter STRIDE     = 2;
parameter PAD        = 1;
parameter OUT_SIZE   = 4;   // 4×4 output
parameter NUM_PATCHES = OUT_SIZE * OUT_SIZE;  // 16
parameter NUM_OPS    = KERN_SIZE * KERN_SIZE; // 9 multiply-accumulates per patch

// ---------- Hardware ----------
parameter NUM_MACS   = 4;
parameter SRAM_BYTES = 16;
parameter SRAM_WORDS = SRAM_BYTES / 4;  // 4 words of 32 bits

// ---------- Timing ----------
parameter MULT_LATENCY = 2;   // multiply pipeline depth
parameter ADD_LATENCY  = 3;   // adder pipeline depth
parameter BATCH_CYCLES = 1 + MULT_LATENCY + ADD_LATENCY;  // 6 cycles per batch
parameter CYCLES_PER_PATCH = 24;

// ---------- FSM states ----------
typedef enum logic [3:0] {
    S_IDLE       = 4'd0,
    S_LOAD_PATCH = 4'd1,
    S_BATCH0     = 4'd2,
    S_BATCH1     = 4'd3,
    S_BATCH2     = 4'd4,
    S_REDUCE1    = 4'd5,
    S_REDUCE2    = 4'd6,
    S_REDUCE3    = 4'd7,
    S_WRITE      = 4'd8,
    S_DONE       = 4'd9
} state_t;

`endif
