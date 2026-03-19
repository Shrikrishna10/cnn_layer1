// =============================================================================
// Dual-Port SRAM — 16 bytes (4 × 32-bit words)
// =============================================================================
// Port A : 32-bit synchronous READ  (feeds MAC array)
// Port B : 32-bit synchronous WRITE (loaded from external memory)
// Both ports can be active in the same cycle (true dual-port).
// =============================================================================
`include "pkg_conv1.svh"

module sram_dp (
    input  logic        clk,

    // --- Port A : READ ---
    input  logic [1:0]  rd_addr,    // word address (0-3)
    input  logic        rd_en,
    output logic [31:0] rd_data,

    // --- Port B : WRITE ---
    input  logic [1:0]  wr_addr,    // word address (0-3)
    input  logic        wr_en,
    input  logic [31:0] wr_data
);

    // 4 words × 32 bits = 16 bytes
    logic [31:0] mem [0:SRAM_WORDS-1];

    // Port A — synchronous read
    always_ff @(posedge clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

    // Port B — synchronous write
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

endmodule
