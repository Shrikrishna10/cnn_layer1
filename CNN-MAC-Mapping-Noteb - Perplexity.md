# Mapping Convolution Layers to MAC Arrays: A Short Note on LeNet-Based CNN Accelerators

**Author:** Technical Note for Hardware Accelerator Design  
**Date:** November 2024  
**Focus:** Mapping CNN convolution operations to 16 MAC units with 8-bit integer arithmetic

---

## Executive Summary

This note presents a systematic approach to mapping convolutional neural network (CNN) layers, specifically from LeNet-5, to a hardware accelerator comprising 16 Multiply-Accumulate (MAC) units. The design assumes 8-bit integer input data, 256 bytes of local on-chip memory, and 1 GB/s external memory bandwidth. This analysis demonstrates practical mapping strategies, memory optimization techniques, and dataflow considerations for efficient CNN acceleration.

---

## 1. Problem Specification

### Hardware Constraints
- **Compute Resources:** 16 MAC units capable of 16-bit integer operations
- **Local Memory:** 256 bytes on-chip SRAM/buffer
- **External Memory:** 1 GB/s bandwidth (DRAM)
- **Data Format:** 8-bit signed/unsigned integers for inputs, weights, and intermediate results

### Target Network: LeNet-5
LeNet-5 is a classic CNN architecture for handwritten digit recognition (MNIST dataset) with the following layer structure:

| Layer | Type | Input | Kernel | Output | Operations |
|-------|------|-------|--------|--------|------------|
| C1 | Conv | 32×32×1 | 5×5 | 28×28×6 | 117,600 MACs |
| S2 | Pool | 28×28×6 | 2×2 | 14×14×6 | - |
| C3 | Conv | 14×14×6 | 5×5 | 10×10×16 | 240,000 MACs |
| S4 | Pool | 10×10×16 | 2×2 | 5×5×16 | - |
| C5 | FC | 5×5×16 | 5×5×16 | 120 | 48,000 MACs |
| F6 | FC | 120 | - | 84 | 10,080 MACs |
| Output | FC | 84 | - | 10 | 840 MACs |

---

## 2. Convolution-to-MAC Mapping Analysis

### 2.1 Fundamental Convolution Operation

A 2D convolution computes:

```
Output[x,y,k] = Σ Σ Input[x+i, y+j, c] × Weight[i,j,c,k] + Bias[k]
                i j c
```

For a single output pixel with a 5×5 kernel:
- **25 multiply operations** (one per kernel element)
- **24 addition operations** (accumulation)
- **Total: 25 MAC operations per output pixel**

### 2.2 Layer C1 Detailed Analysis

**Input:** 32×32×1 grayscale image  
**Kernel:** 5×5×1 filter (6 filters total)  
**Output:** 28×28×6 feature maps  

**Computation Requirements:**
- MACs per output pixel: 5×5 = 25
- Output pixels per filter: 28×28 = 784
- Total filters: 6
- **Total MACs: 25 × 784 × 6 = 117,600**

**With 16 MAC Units:**
- Cycles required: 117,600 ÷ 16 = **7,350 cycles**
- At 100 MHz: **73.5 μs** computation time

**Memory Requirements (8-bit data):**
- Weights: 6 filters × 25 weights = 150 bytes
- Input feature map: 32×32 = 1,024 bytes
- Output feature map: 28×28×6 = 4,704 bytes
- **Total data movement: 5,878 bytes**

---

## 3. Dataflow Strategies for MAC Array

### 3.1 Output-Stationary (OS) Dataflow

**Principle:** Accumulate partial sums for each output pixel in local registers/memory.

**Implementation for 16 MACs:**
```
1. Load 4 filters (4×25 = 100 bytes) into local memory
2. Stream 5×5 input windows sequentially
3. Each MAC computes one weight×input product
4. Accumulate results locally until window complete
5. Write finished output pixels to external memory
```

**Advantages:**
- Minimizes output feature map writes
- Good for limited external bandwidth
- Reuses weights across input windows

**Memory Allocation (256 bytes):**
- Weights: 100 bytes (4 filters)
- Input buffer: 50 bytes (2×25 for double buffering)
- Partial sums: 32 bytes (16 accumulators × 2 bytes)
- Control/misc: ~74 bytes

### 3.2 Weight-Stationary (WS) Dataflow

**Principle:** Keep weights fixed in processing elements, stream inputs and accumulate outputs.

**Implementation:**
```
1. Load one complete 5×5 filter (25 bytes) across 16 MACs
2. Remaining 9 weights stored in local buffer
3. Stream input feature map rows
4. Each MAC processes different spatial location
5. Rotate/reload weights for next 16 operations
```

**Advantages:**
- Maximizes weight reuse
- Reduces weight loading from external memory
- Good for weight-dominant computations

### 3.3 Row-Stationary (RS) Dataflow

**Principle:** Optimize for spatial locality by processing rows of feature maps together.

**Implementation:**
```
1. Load filter rows into local memory (5 rows × 5 = 25 bytes)
2. Stream corresponding input rows
3. Process 16 output pixels in parallel
4. Accumulate across multiple input rows
```

**Advantages:**
- Exploits 2D spatial locality
- Balanced data reuse of inputs, weights, and outputs
- Efficient for varying kernel sizes

---

## 4. Memory Hierarchy and Tiling

### 4.1 Challenge: Limited Local Memory

With only 256 bytes local memory and 8-bit data:
- Cannot store entire feature maps (e.g., 28×28×6 = 4,704 bytes)
- Cannot store all weights simultaneously (150 bytes for C1, 2,400 bytes for C3)
- Must tile computations and carefully manage data movement

### 4.2 Tiling Strategy

**Spatial Tiling:**
Divide output feature map into tiles that fit in memory:

```
For C1 layer (28×28 output):
- Tile size: 7×7 = 49 pixels
- Tiles needed: (28÷7)² = 16 tiles
- Memory per tile: 49 + 25 (weights) + 25 (input) = 99 bytes ✓
```

**Channel Tiling:**
Process filters in groups:

```
For C3 layer (16 output channels):
- Process 4 filters at a time
- Iterations: 16÷4 = 4 passes
- Reuse input feature maps across passes
```

### 4.3 Data Reuse Analysis

**Arithmetic Intensity (AI):**
```
AI = Operations / Data Movement
   = (2 × 117,600) / 5,878
   = 40.0 ops/byte
```

This high arithmetic intensity (40:1) indicates the design is **compute-bound** rather than memory-bound, making it well-suited for acceleration.

---

## 5. Architecture Design

### 5.1 MAC Unit Design

Each MAC unit performs:
```
accumulator ← accumulator + (input × weight)
```

**16-bit MAC for 8-bit operands:**
- 8×8 multiplication → 16-bit product
- 16-bit addition to accumulator
- Optional: Include activation function (ReLU) in datapath

### 5.2 System Block Diagram

```
┌─────────────────────────────────────────────┐
│          External Memory (DRAM)             │
│            1 GB/s Bandwidth                 │
└────────────────┬────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────┐
│       DMA Controller / Memory Interface     │
└────────────────┬────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────┐
│      Local Buffer (256 bytes SRAM)          │
│  ┌──────────┬──────────┬───────────────┐   │
│  │ Weights  │  Inputs  │ Partial Sums  │   │
│  │ 100 B    │   50 B   │     32 B      │   │
│  └──────────┴──────────┴───────────────┘   │
└────────────────┬────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────┐
│           MAC Array (4×4 or 16×1)           │
│  ┌────┬────┬────┬────┐                      │
│  │MAC │MAC │MAC │MAC │  Each MAC:           │
│  ├────┼────┼────┼────┤  - 8×8 multiplier    │
│  │MAC │MAC │MAC │MAC │  - 16-bit adder      │
│  ├────┼────┼────┼────┤  - Accumulator reg   │
│  │MAC │MAC │MAC │MAC │                      │
│  ├────┼────┼────┼────┤                      │
│  │MAC │MAC │MAC │MAC │                      │
│  └────┴────┴────┴────┘                      │
└─────────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────┐
│      Activation Function (ReLU/Tanh)        │
└─────────────────────────────────────────────┘
```

### 5.3 Control Logic

**Key control signals:**
- Weight load enable
- Input streaming control
- Accumulator clear/enable
- Output write-back trigger
- Tiling/loop counters

---

## 6. Performance Analysis

### 6.1 Throughput Calculation

**C1 Layer Performance (100 MHz clock):**
- Computation cycles: 7,350
- Computation time: 73.5 μs
- Memory transfer time: 5,878 bytes ÷ 1 GB/s = 5.9 μs
- **Total latency: ~79.4 μs**

**Throughput:**
- Operations: 117,600 MACs
- Time: 79.4 μs
- **Throughput: 1.48 GOPS (Giga Operations Per Second)**

### 6.2 MAC Utilization

**Ideal utilization:** 100% (all 16 MACs active every cycle)

**Real utilization factors:**
- Edge effects: partial windows at boundaries (~95%)
- Pipeline stalls for data loading (~90%)
- Control overhead (~95%)
- **Effective utilization: ~81%**

### 6.3 Memory Bandwidth Utilization

**Required bandwidth:**
- Data: 5,878 bytes / 79.4 μs = **74 MB/s**
- Available: 1,000 MB/s
- **Utilization: 7.4%** (under-utilized, compute-bound ✓)

### 6.4 Power Efficiency Estimate

Based on similar designs in literature:
- MAC array: ~50 mW (16 MACs @ 100 MHz)
- Memory: ~20 mW
- Control logic: ~10 mW
- **Total: ~80 mW**

**Energy efficiency: 1.48 GOPS / 0.08 W = 18.5 GOPS/W**

---

## 7. Design Optimization Techniques

### 7.1 Loop Tiling and Unrolling

```python
# Pseudo-code for tiled convolution
for out_tile_y in range(0, 28, tile_h):
    for out_tile_x in range(0, 28, tile_w):
        # Load weights for current filters
        load_weights(filter_idx, local_mem)
        
        for y in range(tile_h):
            for x in range(tile_w):
                # Stream 5×5 input window
                window = load_input_window(x, y)
                
                # Parallel MAC operations (16 at a time)
                for mac_id in range(16):
                    mac[mac_id].accumulate(
                        window[mac_id % 25],
                        weights[mac_id % 25]
                    )
                
                # Write output when complete
                if accumulation_complete:
                    write_output(out_tile_y + y, out_tile_x + x)
```

### 7.2 Data Buffering

**Double Buffering:**
- While computing with buffer A, load next tile into buffer B
- Hides memory latency
- Requires: 2 × buffer_size memory

**Advantages:**
- Overlaps computation and data transfer
- Improves effective MAC utilization
- Critical for maintaining 100% utilization

### 7.3 Fixed-Point Optimization

**Quantization-Aware Training:**
- Train network with 8-bit quantization simulation
- Minimal accuracy loss (<1% for LeNet on MNIST)
- Reduces memory footprint by 4× (vs 32-bit float)

**Integer-Only Inference:**
- All operations in integer arithmetic
- No floating-point hardware required
- Faster, lower power, smaller area

---

## 8. Related Work and References

### 8.1 Key Papers on LeNet Accelerators

1. **Park et al. (2018)** - "Digital Neuron: A Hardware Inference Accelerator"
   - 8-bit integer quantization with partial sub-integer multiplication
   - 800 MACs @ 200 MHz achieving 754.7 GMACs/W
   - LeNet-5 implementation: 98.92% accuracy, 2,384 clocks/image
   - Key technique: Barrel-shift based multiplication instead of Booth multipliers
   - **Reference:** [2], [21]

2. **Locharla & Pogiri (2019)** - "Hardware Accelerator Design Approach for CNN"
   - Generalized pipelined architecture for LeNet-5
   - Quantitative analysis of MAC requirements per layer
   - C1: 25×24×6 multiplications, C3: 25×6×16 multiplications
   - Configurable kernel buffer and pooling strategies
   - **Reference:** [2]

3. **Zhao et al. (2019)** - "Accelerating CNNs Using Dynamic Network Surgery"
   - FPGA-based LeNet-5 with pruning and 8-bit quantization
   - LUT-based accelerator (no DSP resources)
   - Peak performance: 33.6 GMACS @ 1.758W
   - 98.9% accuracy on MNIST (Xilinx ZC702 @ 100MHz)
   - **Reference:** [91]

4. **Rongshi & Yongming (2019)** - "LeNet-5 Accelerator Implementation on FPGA with HLS"
   - High-level synthesis approach for rapid prototyping
   - Convolution optimization through loop pipelining
   - Data throughput and energy efficiency focus
   - **Reference:** [55]

### 8.2 Systolic Array Architectures

5. **Ahmad et al. (2018)** - "Systolic Array based LeNet-CNN Accelerator"
   - Processing Element (PE) array design for LeNet-1
   - Configurable systolic architecture: 128×2, 64×4, 32×8, 16×16
   - Weight-stationary dataflow implementation
   - Cluster-based reconfigurable design
   - **Reference:** [46]

6. **Yang et al. (2018)** - "Systolic Array Based Accelerator"
   - 256×256 MAC systolic array (inspired by Google TPU)
   - LeNet-5 first layer performance: 7.6 MOPS @ 100MHz
   - Data mapping methodology for CNN/RNN models
   - **Reference:** [28]

7. **Xu et al. (2021)** - "Configurable Multi-directional Systolic Array (CMSA)"
   - Addresses small-scale and depthwise convolution inefficiency
   - PE utilization improvements: 1.6× for small kernels, 14.8× for depthwise
   - Mathematical model for PE utilization rate
   - **Reference:** [26]

### 8.3 Dataflow and Memory Optimization

8. **Ma et al. (2017)** - "Optimizing Loop Operation and Dataflow in FPGA Accelerators"
   - Loop unrolling, tiling, and interchange techniques
   - Four-level convolution loop optimization
   - Design objectives: throughput vs memory bandwidth
   - **Reference:** [64], [67]

9. **Cheng et al. (2021)** - "Reconfigurable Architecture and Dataflow"
   - Layer-by-layer PE array configuration
   - Buffer assignment for ifmap and filters
   - Reduces DRAM access through adaptive dataflow
   - **Reference:** [92]

10. **Zheng et al. (2023)** - "TileFlow: Tree-based Fusion Dataflow Analysis"
    - 3D design space: compute ordering, resource binding, loop tiling
    - Performance metrics: data movement and resource usage
    - 1.85× speedup for self-attention, 1.28× for convolution chains
    - **Reference:** [58]

### 8.4 8-bit Quantization Studies

11. **Silva et al. (2022)** - "Customizable FPGA Accelerator with 8-bit Quantization"
    - DSP48E optimization for dual 8-bit MACs
    - Parameter sharing and quantization impact study
    - 40-50% resource reduction, 50% speedup
    - **Reference:** [93]

12. **Intel oneDNN (2024)** - "CNN int8 Inference Example"
    - AlexNet conv3/relu3 with int8 datatype
    - u8 (unsigned 8-bit) for source/destination
    - s8 (signed 8-bit) for weights
    - Scaling factors for quantization: src=1.8, weight=2.0, dst=0.55
    - **Reference:** [24]

### 8.5 Memory Hierarchy Frameworks

13. **Bause et al. (2024)** - "Configurable Memory Hierarchy for Neural Accelerators"
    - 1-5 level configurable hierarchy with SRAM
    - Input buffer alignment and dual-ported memory
    - MCU synchronization across clock domains
    - **Reference:** [94]

14. **Li et al. (2016)** - "Optimizing Memory Efficiency for Deep CNNs on GPUs"
    - Data layout impact: up to 6.9× performance variation
    - NCHW vs CHWN layouts for different layer types
    - Multi-dimension layout transformation methods
    - Bandwidth utilization up to 27.9× improvement
    - **Reference:** [40]

### 8.6 Additional Resources

15. **Gudaparthi et al. (2019)** - "Wire-Aware CNN Accelerator Architecture"
    - Deep distributed memory hierarchy
    - Short-distance data movement optimization
    - **Reference:** [97]

16. **Asgari et al. (2019)** - "Efficiently Running DNNs Using Systolic Arrays"
    - Eridanus structured pruning for systolic arrays
    - Locally-dense model compatible with data-reuse patterns
    - LeNet, CifarNet, VGG16 evaluations
    - **Reference:** [95]

---

## 9. Implementation Considerations

### 9.1 Challenges

**1. Memory Bottleneck:**
- Limited 256-byte local memory restricts tiling granularity
- Careful scheduling needed to maximize reuse
- Double/triple buffering trades memory for throughput

**2. Load Imbalance:**
- Edge pixels require partial window processing
- Idle MACs during boundary conditions
- Padding strategies can help (zero-padding)

**3. Quantization Accuracy:**
- 8-bit integer arithmetic introduces quantization error
- Requires quantization-aware training
- Scaling factors must be carefully chosen

**4. Control Complexity:**
- Multiple nested loops for tiling
- Synchronization between data loading and computation
- FSM (Finite State Machine) becomes complex

### 9.2 Verification Strategy

**1. Reference Model:**
- Python/NumPy implementation with same 8-bit quantization
- Golden reference for bit-exact comparison

**2. Layer-by-Layer Testing:**
- Verify each layer independently
- Check intermediate feature maps
- Accumulate errors across layers

**3. Hardware Simulation:**
- Cycle-accurate RTL simulation
- Memory access pattern verification
- Timing analysis and pipeline hazards

### 9.3 FPGA vs ASIC Trade-offs

**FPGA Implementation:**
- Advantages: Rapid prototyping, reconfigurability, shorter design cycle
- Disadvantages: Lower clock frequency (~100-200 MHz), higher power
- Tools: Xilinx Vivado HLS, Intel Quartus Prime

**ASIC Implementation:**
- Advantages: Higher frequency (~1+ GHz), lower power per operation
- Disadvantages: Fixed functionality, long design cycle, high NRE cost
- Target: 28nm, 16nm, or 7nm process nodes

---

## 10. Conclusion and Future Directions

### 10.1 Summary

This note has presented a comprehensive analysis of mapping LeNet convolution layers to a 16-MAC hardware accelerator with 8-bit integer arithmetic. Key findings:

1. **Computational Efficiency:** 7,350 cycles for C1 layer (117,600 MACs)
2. **Memory Constraints:** 256-byte local buffer is sufficient with proper tiling
3. **Bandwidth:** Design is compute-bound (7.4% bandwidth utilization)
4. **Performance:** ~1.48 GOPS at 100 MHz, 18.5 GOPS/W efficiency
5. **Dataflow:** Output-stationary recommended for limited memory scenario

### 10.2 Extensions and Future Work

**1. Dynamic Reconfiguration:**
- Adaptive MAC array size per layer
- Runtime dataflow switching
- Power gating for unused MACs

**2. Advanced Quantization:**
- Mixed-precision (4-bit/8-bit/16-bit)
- Dynamic quantization ranges
- Logarithmic quantization

**3. Sparse Acceleration:**
- Zero-skipping logic
- Compressed weight storage
- Structured pruning support

**4. Multi-Layer Fusion:**
- Conv-ReLU-Pool fusion
- Reduced intermediate storage
- Higher effective throughput

**5. Larger Networks:**
- Scale to VGG, ResNet, MobileNet
- Depthwise separable convolution support
- Attention mechanism acceleration

---

## Appendix: Calculation Examples

### A.1 Single Convolution Window

**Problem:** Compute one 5×5 convolution with 16 MACs

**Approach:**
```
Cycle 0-1:   MACs 0-15 compute products 0-15 (16 products)
Cycle 2:     MACs 0-8  compute products 16-24 (9 products)
Cycle 3:     Accumulate all 25 products
Total: 4 cycles per output pixel
```

**For entire C1 layer:**
- Output pixels: 28×28×6 = 4,704
- Cycles: 4,704 × 4 = 18,816 cycles (with accumulation overhead)
- Optimized: 7,350 cycles (parallel filter processing)

### A.2 Memory Partitioning Example

**256-byte local memory allocation:**
```
┌────────────────────────────────┐
│ Weight Buffer: 100 bytes       │  4 filters × 25 weights
├────────────────────────────────┤
│ Input Buffer A: 25 bytes       │  Current 5×5 window
├────────────────────────────────┤
│ Input Buffer B: 25 bytes       │  Next 5×5 window (double buffer)
├────────────────────────────────┤
│ Partial Sum Registers: 32 B    │  16 accumulators × 2 bytes
├────────────────────────────────┤
│ Output Buffer: 32 bytes        │  16 outputs × 2 bytes
├────────────────────────────────┤
│ Control/Status: 42 bytes       │  Counters, pointers, flags
└────────────────────────────────┘
Total: 256 bytes
```

---

## References

[2] Locharla & Pogiri, "Hardware Accelerator Design Approach for CNN-based Low Power Applications," IJITEE, 2019

[21] Park et al., "Digital Neuron: A Hardware Inference Accelerator for Convolutional Deep Neural Networks," IEEE, 2018

[24] Intel, "CNN int8 inference example," oneDNN Documentation, 2024

[26] Xu et al., "Configurable Multi-directional Systolic Array Architecture," ACM TODAES, 2021

[28] Yang et al., "Systolic Array Based Accelerator and Algorithm Mapping," NPC, 2018

[40] Li et al., "Optimizing Memory Efficiency for Deep CNNs on GPUs," ICCD, 2016

[46] Ahmad et al., "Systolic Array Based LeNet-CNN-Accelerator-for-FPGA," GitHub/arXiv, 2018

[55] Rongshi & Yongming, "Accelerator Implementation of Lenet-5 CNN Based on FPGA," ICSAI, 2019

[58] Zheng et al., "TileFlow: A Framework for Modeling Fusion Dataflow," MICRO, 2023

[64] Ma et al., "Optimizing Loop Operation and Dataflow in FPGA Accelerators," FPGA, 2017

[91] Zhao et al., "A Method for Accelerating CNNs Using Dynamic Network Surgery," IEEE IJCNN, 2019

[92] Cheng et al., "Reconfigurable Architecture and Dataflow for Memory Efficient CNN," Sensors, 2021

[93] Silva et al., "Customizable FPGA-Based Hardware Accelerator," Sensors, 2022

[94] Bause et al., "A Configurable Memory Hierarchy for Neural Accelerators," arXiv, 2024

[95] Asgari et al., "Efficiently Running Inference of DNNs Using Systolic Arrays," IEEE Micro, 2019

[97] Gudaparthi et al., "Wire-Aware Architecture and Dataflow for CNN Accelerators," MICRO, 2019

---

**Document Version:** 1.0  
**Last Updated:** November 2024  
**Contact:** For questions or collaborations on CNN hardware acceleration
