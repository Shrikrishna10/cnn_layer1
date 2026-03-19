// =============================================================================
// MAC Array — 4 MAC units + reduction crossbar
// =============================================================================
`include "pkg_conv1.svh"

module mac_array (
    input  logic                       clk,
    input  logic                       rst_n,

    // --- per-MAC data inputs (directly from control unit) ---
    input  logic signed [DATA_W-1:0]   pixel_in   [NUM_MACS],
    input  logic signed [DATA_W-1:0]   weight_in  [NUM_MACS],

    // --- per-MAC control (directly from control unit) ---
    input  logic [NUM_MACS-1:0]        acc_en,
    input  logic [NUM_MACS-1:0]        acc_clear,
    input  logic [NUM_MACS-1:0]        mode_add_only,

    // Reduction source select per MAC: which other MAC's ACC feeds ext_acc_in
    // 0 = none (zero), 1 = ACC0, 2 = ACC1, 3 = ACC2, 4 = ACC3
    input  logic [2:0]                 red_sel [NUM_MACS],

    // --- outputs ---
    output logic signed [ACC_W-1:0]    acc_out [NUM_MACS],
    output logic signed [ACC_W-1:0]    final_result
);

    // --- Reduction crossbar: route selected ACC to ext_acc_in ---
    logic signed [ACC_W-1:0] ext_acc [NUM_MACS];

    // Generate the crossbar MUX for each MAC
    generate
        for (genvar m = 0; m < NUM_MACS; m++) begin : gen_red_mux
            always_comb begin
                case (red_sel[m])
                    3'd1:    ext_acc[m] = acc_out[0];
                    3'd2:    ext_acc[m] = acc_out[1];
                    3'd3:    ext_acc[m] = acc_out[2];
                    3'd4:    ext_acc[m] = acc_out[3];
                    default: ext_acc[m] = '0;
                endcase
            end
        end
    endgenerate

    // --- Instantiate 4 MAC units ---
    generate
        for (genvar m = 0; m < NUM_MACS; m++) begin : gen_mac
            mac_unit u_mac (
                .clk           (clk),
                .rst_n         (rst_n),
                .pixel_in      (pixel_in[m]),
                .weight_in     (weight_in[m]),
                .ext_acc_in    (ext_acc[m]),
                .mode_add_only (mode_add_only[m]),
                .acc_en        (acc_en[m]),
                .acc_clear     (acc_clear[m]),
                .acc_out       (acc_out[m])
            );
        end
    endgenerate

    // Final result sits in ACC0 after reduction
    assign final_result = acc_out[0];

endmodule
