# Design Requirements 
## 1.1 Problem Statement
  - Implement Conv1 layer for simplified LeNet-5
  - Input: 8×8 grayscale image (single channel)
  - Kernel: 3×3 convolution
  - Stride: 2
  - Padding: 1
  - Output: 4×4 feature map (16 values)

## 1.2 Hardware Constraints
  - 4 MAC units (Multiply-Accumulate)
  - Each MAC: 8-bit × 8-bit signed integer multiplication
  - 16 bytes on-chip SRAM (excluding MAC accumulator registers)
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
| Input dimensions                                  | 8 × 8 × 1                                  |
| Kernel size                                       | 3 × 3                                      |
| Stride                                            | 2                                          |
| Padding                                           | 1                                          |
| Output dimensions                                 | 4 × 4 × 1                                  |
| Parallel MACs                                     | 4                                          |
| On-chip SRAM                                      | 16 bytes                                   |
| External bandwidth                                | 1024 bytes/s                               |
| Data precision                                    | 8-bit signed int                           |
| Accumulator width                                 | 20-bit signed int                          |




