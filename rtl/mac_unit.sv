// =============================================================================
// MAC Unit — Multiply-Accumulate with ADD_ONLY mode for reduction
// =============================================================================
// Pipeline latency is modelled by the control FSM (which asserts acc_en
// only after the correct number of wait cycles).  The datapath itself is
// combinational multiply + add with a registered accumulator.
// This keeps the RTL small while giving cycle-accurate waveforms.
// =============================================================================
`include "pkg_conv1.svh"

module mac_unit (
    input  logic                    clk,
    input  logic                    rst_n,

    // --- data inputs ---
    input  logic signed [DATA_W-1:0]  pixel_in,
    input  logic signed [DATA_W-1:0]  weight_in,
    input  logic signed [ACC_W-1:0]   ext_acc_in,   // external ACC for reduction

    // --- control ---
    input  logic                    mode_add_only,  // 0 = MAC, 1 = ADD-only (bypass mult)
    input  logic                    acc_en,         // write-enable for accumulator
    input  logic                    acc_clear,      // 1 = reset ACC term to 0 (first batch)

    // --- output ---
    output logic signed [ACC_W-1:0]   acc_out
);

    // ----- Combinational multiply -----
    logic signed [PROD_W-1:0] product;
    assign product = pixel_in * weight_in;

    // ----- Adder input MUXes -----
    logic signed [ACC_W-1:0] add_a, add_b, sum;

    // Input A : sign-extended product  OR  external ACC value
    assign add_a = mode_add_only ? ext_acc_in
                                 : {{(ACC_W-PROD_W){product[PROD_W-1]}}, product};

    // Input B : current accumulator  OR  zero (when clearing)
    assign add_b = acc_clear ? {ACC_W{1'b0}} : acc_out;

    assign sum = add_a + add_b;

    // ----- Accumulator register -----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc_out <= '0;
        else if (acc_en)
            acc_out <= sum;
    end

endmodule
