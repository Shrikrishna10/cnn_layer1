// =============================================================================
// Patch Address Generator
// =============================================================================
// Given a patch index (0-15) and an operand index (0-8), compute:
//   - The row and column in the 8×8 input image
//   - Whether the position falls in the padding region (→ feed zero)
//   - The linear pixel address (row*8 + col) for non-padded positions
//
// Convolution parameters:  stride=2, pad=1, kernel=3×3, output=4×4
// =============================================================================
`include "pkg_conv1.svh"

module patch_addr_gen (
    input  logic [3:0]  patch_idx,   // 0–15
    input  logic [3:0]  op_idx,      // 0–8  (operand within 3×3 window)
    output logic [5:0]  pixel_addr,  // 0–63 linear address in 8×8 image
    output logic        is_pad       // 1 = padding position → pixel = 0
);

    // Patch grid position
    logic [1:0] patch_row, patch_col;
    assign patch_row = patch_idx[3:2];   // 0-3
    assign patch_col = patch_idx[1:0];   // 0-3

    // Kernel window offset
    logic [1:0] kern_row, kern_col;
    assign kern_row = op_idx[3:0] / 2'd3;  // 0,1,2
    assign kern_col = op_idx[3:0] % 2'd3;  // 0,1,2

    // Absolute pixel position (signed to detect negative = padding)
    logic signed [4:0] abs_row, abs_col;
    assign abs_row = $signed({1'b0, patch_row}) * STRIDE - PAD + $signed({1'b0, kern_row});
    assign abs_col = $signed({1'b0, patch_col}) * STRIDE - PAD + $signed({1'b0, kern_col});

    // Padding detection
    assign is_pad = (abs_row < 0) || (abs_row >= IMG_SIZE) ||
                    (abs_col < 0) || (abs_col >= IMG_SIZE);

    // Linear address (only valid when !is_pad)
    assign pixel_addr = is_pad ? 6'd0 : (abs_row[3:0] * IMG_SIZE + abs_col[3:0]);

endmodule
