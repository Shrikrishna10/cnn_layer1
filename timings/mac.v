`timescale 1ns/1ps

//======================================================
// Simple delayed MAC core for timing diagrams
//  - Uses * and + operators
//  - 5-cycle delay for MAC (mul+add)
//  - 3-cycle delay for ADD-only (bypass multiplier)
//  - sel_bypass = 0 -> use in_a * in_w
//  - sel_bypass = 1 -> use in_ad
//  - sel_acc    = 0 -> start from 0
//  - sel_acc    = 1 -> accumulate on previous acc_out
//======================================================
module mac_core (
    input         clk,
    input         rst,         // active high

    // control
    input         sel_acc,     // 0 = clear, 1 = feedback acc_out
    input         sel_bypass,  // 0 = MAC (use product), 1 = ADD-only (use in_ad)
    input         valid,       // one-cycle start pulse

    // data
    input  [15:0] in_a,
    input  [15:0] in_w,
    input  [19:0] in_ad,

    // output
    output reg [19:0] acc_out  // current accumulated value
);

    reg        busy;
    reg [2:0]  cnt;           // enough for max 5 cycles
    reg [19:0] base_acc;
    reg [19:0] pending_add;

    always @(posedge clk) begin
        if (rst) begin
            acc_out     <= 20'd0;
            busy        <= 1'b0;
            cnt         <= 3'd0;
            base_acc    <= 20'd0;
            pending_add <= 20'd0;
        end else begin
            // start a new operation if not busy
            if (valid && !busy) begin
                busy     <= 1'b1;
                base_acc <= sel_acc ? acc_out : 20'd0;
                if (sel_bypass) begin
                    // ADD-only: ACC + in_ad, 3-cycle delay
                    pending_add <= in_ad;
                    cnt         <= 3'd3;
                end else begin
                    // MAC: ACC + in_a * in_w, 5-cycle delay
                    pending_add <= in_a * in_w;
                    cnt         <= 3'd5;
                end
            end else if (busy) begin
                if (cnt > 3'd1) begin
                    cnt <= cnt - 3'd1;
                end else if (cnt == 3'd1) begin
                    // final cycle: update accumulator
                    acc_out <= base_acc + pending_add;
                    cnt     <= 3'd0;
                    busy    <= 1'b0;
                end
            end
        end
    end

endmodule

