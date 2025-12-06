# Design Requirements 
## 1.1 Problem Statement
  - Implement Conv1 layer for simplified LeNet-5
  - Input: 8\*8 grayscale image (single channel)
  - Kernel: 3\*3 convolution
  - Stride: 2
  - Padding: 1
  - Output: 4\*4 feature map (16 values)

## 1.2 Hardware Constraints
  - 4 MAC units (Multiply-Accumulate)
  - Each MAC: 8-bit \* 8-bit signed integer multiplication
  - 16 bytes on-chip SRAM (excluding MAC accumulator registers) - capable of simultaneous 32 bits read writes - dual port
  - External memory bandwidth: 1 KB/s (1024 bytes/second)
  - No additional hardware (reuse MAC adders for reduction)

## 1.3 Design Goals
  - Maximize throughput (images/second)
  - Minimize on-chip memory footprint
  - Efficient bandwidth utilization
  - Scalable to floating-point operations

## 1.4 Data Types
  - Input pixels: 8-bit signed integers [-128, 127]
  - Weights: 8-bit signed integers [-128, 127]
  - Products: 16-bit signed integers
  - Accumulator: 20-bit signed integers (to prevent overflow)
  - Output: 20-bit signed integers (can be quantized if needed) - ReLU / tanh


| Parameter <br>─────────────────────────────────── | Value<br>───────────────────────────────── |
| ------------------------------------------------- | ------------------------------------------ |
| Input dimensions                                  | 8 \* 8 \* 1                                |
| Kernel size                                       | 3 \* 3                                     |
| Stride                                            | 2                                          |
| Padding                                           | 1                                          |
| Output dimensions                                 | 4 \* 4 \* 1                                |
| Parallel MACs                                     | 4                                          |
| On-chip SRAM                                      | 16 bytes                                   |
| External bandwidth                                | 1024 bytes/s                               |
| Data precision                                    | 8-bit signed int                           |
| Accumulator width                                 | 20-bit signed int                          |
# Assumptions

2.1 Timing Assumptions
  - Multiplier latency: 2 cycles (pipelined)
  - Adder latency: 3 cycles (matching FP32 timing)
  - SRAM access: 1 byte of data read/write per cycle
  - Register load: Included in operation timing

2.2 Memory Assumptions
  - External memory is byte-addressable
  - Row-major storage for input image
  - 8-byte parallel read capability from SRAM
  - Input image loaded once, 3×3 windows extracted in hardware
  - Weight read for every patch

2.3 Arithmetic Assumptions
  - Signed multiplication using Booth encoding or similar
  - Two's complement representation
  - 20-bit accumulator sufficient for worst-case:
    * Max value of data per product: 127 × 127 = 16,129
    * Max value of 3 products in ACC0: 3 × 16,129 = 48,387
    * Fits in 20 bits (max value of 20 bits = 524,288)
  - No saturation needed for integer operations

2.4 Control Assumptions
  - Synchronous design, single clock domain
  - Sequential processing of patches (no inter-patch pipelining)
  - Intra-batch operations can overlap (load, multiply, add)
  - Reduction uses MAC adders in ADD-only mode

2.5 Hardware Assumptions
  - MAC units can operate in two modes:
    * MAC mode: multiply-accumulate
    * ADD-only mode: bypass multiplier, add 20-bit inputs
  - MUX overhead is negligible in critical path
  - Multiplier and adder are combinational with stated latencies\


# Theory of Operations

3.1 Convolution Operation Overview
  - Explain sliding 3×3 window
  - Show stride=2 creates 4×4 output grid
  - Padding ensures edge pixels are processed

3.2 Per-Patch Computation
  Each patch requires:
  - 9 multiply-accumulate operations
  - Organized in 3 batches: [0-3], [4-7], [8]
  - Batch 0-1: 4 MACs active
  - Batch 2: 1 MAC active, others can start reduction

3.3 Batch Processing
  Batch timeline (6 cycles each):
    Cycle 0: Load 4 weights + 4 pixels from SRAM
    Cycles 1-2: Multiply (2-cycle pipelined)
    Cycles 3-5: Accumulate (3-cycle adder)

3.4 Reduction Phase
  Combine 4 ACC values → 1 final sum:
  - ACC0 contains: p0 + p4 + p8
  - ACC1 contains: p1 + p5
  - ACC2 contains: p2 + p6
  - ACC3 contains: p3 + p7
  
  Reduction (overlapped with Batch 2):
  - Cycles 15-17: MAC1 adds ACC0 + ACC1 → ACC1
  - Cycles 18-20: MAC2 adds ACC1 + ACC2 → ACC1
  - Cycles 21-23: MAC3 adds ACC1 + ACC3 → ACC1
  Final result in ACC1

3.5 Complete Patch Timeline
  Total: 24 cycles per patch

# COMPLETE PATCH COMPUTATION (24 CYCLES)

| Cycle | Batch | Operation            | MAC0  | MAC1  | MAC2  | MAC3  | Notes                              |
| ----: | :---: | :------------------- | :---- | :---- | :---- | :---- | :--------------------------------- |
|       |   -   | Loading SRAM         |       |       |       |       | Loading weights                    |
|       |   -   | Loading SRAM         |       |       |       |       | Loading patch values               |
|     0 |   0   | Load from SRAM       | w0,a0 | w1,a1 | w2,a2 | w3,a3 | Parallel load                      |
|     1 |   0   | Multiply (cycle 1/2) | ×     | ×     | ×     | ×     | Pipeline stage 1                   |
|     2 |   0   | Multiply (cycle 2/2) | ×     | ×     | ×     | ×     | Products ready                     |
|     3 |   0   | Add (cycle 1/3)      | +     | +     | +     | +     | Start accumulate                   |
|     4 |   0   | Add (cycle 2/3)      | +     | +     | +     | +     | Continue                           |
|     5 |   0   | Add (cycle 3/3)      | +     | +     | +     | +     | ACC updated (reset)                |
|     6 |   1   | Load from SRAM       | w4,a4 | w5,a5 | w6,a6 | w7,a7 | Next batch                         |
|     7 |   1   | Multiply (cycle 1/2) | ×     | ×     | ×     | ×     |                                    |
|     8 |   1   | Multiply (cycle 2/2) | ×     | ×     | ×     | ×     |                                    |
|     9 |   1   | Add (cycle 1/3)      | +     | +     | +     | +     | Accumulate mode                    |
|    10 |   1   | Add (cycle 2/3)      | +     | +     | +     | +     |                                    |
|    11 |   1   | Add (cycle 3/3)      | +     | +     | +     | +     | ACC += product                     |
|    12 |   2   | Load from SRAM       | w8,a8 | idle  | idle  | idle  | Last operand                       |
|    13 |   2   | Multiply (cycle 1/2) | ×     | idle  | idle  | idle  | MAC0 only                          |
|    14 |   2   | Multiply (cycle 2/2) | ×     | idle  | idle  | idle  |                                    |
|    15 |   2   | Add (cycle 1/3)      | +     | LOAD  | idle  | idle  | MAC1 starts reduction/load overlap |
|    16 |   2   | Add (cycle 2/3)      | +     | +     | idle  | idle  | Overlapped!                        |
|    17 |   2   | Add (cycle 3/3)      | +     | +     | idle  | idle  | ACC0 final                         |
|    18 |  Red  | Reduction step 2     | idle  | +     | LOAD  | idle  | ACC1 + ACC2                        |
|    19 |  Red  | (cycle 2/3)          | idle  | +     | +     | idle  |                                    |
|    20 |  Red  | (cycle 3/3)          | idle  | done  | +     | idle  | ACC1 updated                       |
|    21 |  Red  | Reduction step 3     | idle  | idle  | +     | LOAD  | ACC1 + ACC3                        |
|    22 |  Red  | (cycle 2/3)          | idle  | idle  | done  | +     |                                    |
|    23 |  Red  | (cycle 3/3)          | idle  | idle  | idle  | +     | Final sum ready                    |

**Result:** Final sum in ACC1 (or ACC3 depending on design choice).  
Can write to output FIFO / memory in cycle 24.(+3 for loading initial values)
  
**Key:** `×` = Multiply in progress · `+` = Add/accumulate in progress · `LOAD` = Loading external ACC value for ADD-only mode · `idle` = MAC not active

## Summary of operations
Per image computation:
  - 16 patches (4×4 output grid)
  - Each patch: 24 cycles
  - Total: 16 × 24 = 384 cycles per image

Memory access per image:
  - Input pixels: 64 bytes (8×8, loaded once)
  - Outputs: 16 patches × 3 bytes = 48 bytes
  - Total: 64 + 9 + 48 = 121 bytes per image

Throughput:
  - Bandwidth: 1024 bytes/s
  - Images/s: 1024 / 121 ≈ 8.46 images/s
  
Clock frequency:
  - Cycles per image: 384
  - Required clock: 384 × 8.46 ≈ 3,249 Hz ≈ 3.25 **kHz**





# Architecture 
4.1 System-Level Block Diagram
![[Pasted image 20251205101514.png]]



4.2 MAC Unit Architecture (Your diagram!)
 ![[Pasted image 20251205101630.png]]

4.3 MAC Array (4 units)
![[Pasted image 20251205101745.png]]

4.4 Control Unit
  - Generates control signals based on current cycle
  - Manages batch sequencing (0, 1, 2)
  - Switches MAC modes (MAC vs ADD-only)
  - Handles SRAM addressing
  - Coordinates external memory access

  High-level FSM states:
  ┌──────────┐
  │   IDLE   │
  └────┬─────┘
       ↓
  ┌──────────┐
  │LOAD_WTPX │ ← Load weights and image
  └────┬─────┘
       ↓
  ┌──────────┐
  │ COMPUTE  │ ← Process patches (18 cycles)
  │  BATCH   │
  └────┬─────┘
       ↓
  ┌──────────┐
  │ REDUCE   │ ← Combine ACCs (6 cycles, overlapped)
  └────┬─────┘
       ↓
  ┌──────────┐
  │  OUTPUT  │ ← Write result
  └────┬─────┘
       ↓
  (Repeat for 16 patches)

4.5 Data Flow
  Explain step-by-step with arrows:
  
  1. External memory → SRAM (weights + pixels)
  2. SRAM → MAC input registers
  3. Registers → Multiplier → Product
  4. Product → Adder (with ACC feedback)
  5. Adder → ACC register
  6. For reduction: ACC → MUX → Adder (bypass mult)
  7. Final ACC → Output

4.6 Critical Signals
  List main control signals:
  - clk: System clock (~3.25 kHz)
  - reset: Global reset
  - mode[1:0]: MAC operation mode
  - mux_sel_G[3:0]: MUX select for each MAC
  - acc_reset[3:0]: Clear accumulator
  - sram_addr[3:0]: SRAM address
  - sram_we: SRAM write enable
  - ext_mem_rd: External memory read
  - ext_mem_wr: External memory write
  