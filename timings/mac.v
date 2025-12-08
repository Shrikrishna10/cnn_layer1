module mac (
    input clk,
    input rst,
    input [7:0] a,
    input [7:0] w,
    input [19:0] in_ad,
    input mux_sel_g,      // 1: bypass multiplier, use in_ad; 0: use multiplier output
    input mux_sel,        // 1: use accumulator feedback; 0: clear (use 0)
    output reg [19:0] accumulate
);

reg [2:0] count;
wire [2:0] next_count;

assign next_count = (count == 3'd4) ? 3'b000 : count + 1'b1;


reg [19:0] out_mult;
wire [19:0] next_acc,acc_check;
wire [19:0] in_add, next_mult;

always@(posedge clk) begin
    if (rst) begin
        count <= 3'b0;
    end else begin
        count <= next_count;
    end
end

assign next_mult  = (count == 3'd1) ? {4'b0000,(a * w)} : out_mult;
assign next_acc   = (count == 3'd4) ? in_add + acc_check : accumulate;

always@(posedge clk) begin
    if (rst) begin
        out_mult <= 20'b0;
    end else begin
        out_mult <= next_mult;
    end
end

always@(posedge clk) begin
    if (rst) begin
        accumulate <= 20'b0;
    end else begin
        accumulate <= next_acc;
    end
end

assign acc_check = mux_sel ? accumulate : 20'b0;
assign in_add = mux_sel_g? in_ad : out_mult;

endmodule