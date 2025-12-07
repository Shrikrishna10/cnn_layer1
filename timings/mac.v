`timescale 1ns/1ps

// =======================================================
//  Pipelined MAC (DUT)
//    - 16x16 multiplier, 2-cycle pipeline
//    - 20-bit adder, 3-cycle pipeline
//    - ADD-only mode bypasses multiplier
// =======================================================
module pipelined_mac (
    input         clk,
    input         rst,        // active high

    // control
    input         mode_add,   // 0 = MAC (mul+add), 1 = ADD-only
    input         mux_sel,    // 0 = use 0, 1 = use ACC feedback
    input         in_valid,   // start a MAC operation
    input         add_valid,  // start an ADD-only operation

    // data
    input  [15:0] a,
    input  [15:0] b,
    input  [19:0] add_in,

    output reg [19:0] acc,          // accumulate register
    output reg        mac_done,     // 1 when MAC result writes ACC
    output reg        add_done      // 1 when ADD result writes ACC
);

    // ---------------- Multiplier: 2-cycle pipeline ----------------
    reg [15:0] a_reg, b_reg;
    reg [31:0] mul_s1, mul_s2;

    // ---------------- Adder: 3-cycle pipeline --------------------
    reg [19:0] add_s1, add_s2, add_s3;

    // Valid pipelines
    reg [4:0] mac_valid_pipe;   // 5-cycle MAC latency
    reg [2:0] add_valid_pipe;   // 3-cycle ADD-only latency

    // Operand select going into adder
    wire [19:0] op_sel    = mode_add ? add_in : mul_s2[19:0];

    // ACC feedback or zero
    wire [19:0] acc_src   = mux_sel ? acc : 20'd0;

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
            mac_done       <= 1'b0;
            add_done       <= 1'b0;
        end else begin
            // valid shift registers
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

            // pop valid bits
            mac_done <= mac_valid_pipe[4];
            add_done <= add_valid_pipe[2];

            // write ACC
            if (mac_valid_pipe[4] || add_valid_pipe[2]) begin
                acc <= add_s3;
            end
        end
    end

endmodule

