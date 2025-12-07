`timescale 1ns/1ps

//======================================================
//  Pipelined MAC (DUT)
//    - 16x16 multiplier, 2-cycle pipeline
//    - 20-bit adder, 3-cycle pipeline
//    - mode_add = 0 : MAC (mul+add)
//    - mode_add = 1 : ADD-only (bypass mul, use add_in)
//    - acc_out always shows current accumulated value
//======================================================
module pipelined_mac (
    input         clk,
    input         rst,        // active high

    // control
    input         mode_add,   // 0 = MAC, 1 = ADD-only (bypass mul)
    input         mux_sel,    // 0 = use 0, 1 = use ACC feedback
    input         in_valid,   // start a MAC operation
    input         add_valid,  // start an ADD-only operation

    // data
    input  [15:0] a,
    input  [15:0] b,
    input  [19:0] add_in,

    // output: current accumulated value
    output [19:0] acc_out
);

    // ---------------- Multiplier: 2-cycle pipeline ----------------
    reg [15:0] a_reg, b_reg;
    reg [31:0] mul_s1, mul_s2;

    // ---------------- Adder: 3-cycle pipeline --------------------
    reg [19:0] add_s1, add_s2, add_s3;

    // ---------------- Accumulator + valid pipelines --------------
    reg [19:0] acc;
    reg [4:0]  mac_valid_pipe;   // 5-cycle MAC latency
    reg [2:0]  add_valid_pipe;   // 3-cycle ADD-only latency

    assign acc_out = acc;

    // Operand into adder: either mul result or external addend
    wire [19:0] op_sel  = mode_add ? add_in : mul_s2[19:0];

    // ACC feedback vs 0
    wire [19:0] acc_src = mux_sel ? acc : 20'd0;

    always @(posedge clk) begin
        if (rst) begin
            a_reg          <= 16'd0;
            b_reg          <= 16'd0;
            mul_s1         <= 32'd0;
            mul_s2         <= 32'd0;
            add_s1         <= 20'd0;
            add_s2         <= 20'd0;
            add_s3         <= 20'd0;
            acc            <= 20'd0;
            mac_valid_pipe <= 5'd0;
            add_valid_pipe <= 3'd0;
        end else begin
            // shift valid bits
            mac_valid_pipe <= {mac_valid_pipe[3:0], in_valid};
            add_valid_pipe <= {add_valid_pipe[1:0], add_valid};

            // multiplier pipeline (2 cycles)
            if (in_valid) begin
                a_reg <= a;
                b_reg <= b;
            end
            mul_s1 <= a_reg * b_reg;
            mul_s2 <= mul_s1;

            // adder pipeline (3 cycles)
            add_s1 <= acc_src + op_sel;
            add_s2 <= add_s1;
            add_s3 <= add_s2;

            // write ACC only when a valid result emerges
            if (mac_valid_pipe[4] || add_valid_pipe[2]) begin
                acc <= add_s3;
            end
        end
    end

endmodule

