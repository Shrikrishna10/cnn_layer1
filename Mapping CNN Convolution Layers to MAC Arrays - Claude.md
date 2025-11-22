## System Specifications
- **MAC Units**: 16 multiply-accumulate units
- **MAC Precision**: 16-bit integer operations
- **Input Data Format**: 8-bit integers
- **Local Memory**: 256 bytes
- **External Memory Bandwidth**: 1 GB/second

---

## 1. Understanding Convolution Operations

A convolutional layer performs the following computation:

**Output(x, y, k) = Σ Σ Σ Input(x+i, y+j, c) × Weight(i, j, c, k) + Bias(k)**

Where the summations are over:
- **i, j**: Filter spatial dimensions (e.g., 3×3, 5×5)
- **c**: Input channels
- **k**: Output channels (filters)

### Example: LeNet-5 First Convolutional Layer
- Input: 32×32×1 (grayscale image)
- Filter: 5×5×1 (6 filters)
- Output: 28×28×6
- Stride: 1, No padding

**Computational Requirements**:
- Per output pixel: 5 × 5 × 1 = 25 MAC operations
- Total MACs: 28 × 28 × 6 × 25 = **117,600 MAC operations**

---

## 2. Mapping Strategies to 16 MAC Units

### 2.1 Dataflow Choices

There are several established dataflow patterns for mapping convolutions to MAC arrays:

#### **Weight Stationary (WS)**
- Filter weights remain in the MAC unit's local register
- Input activations are streamed through
- Partial sums are accumulated and forwarded between PEs
- **Advantage**: Maximizes weight reuse, reduces weight memory accesses
- **Challenge**: Requires efficient partial sum accumulation network

#### **Output Stationary (OS)**
- Each MAC unit accumulates one output pixel completely
- Weights and inputs are broadcast to the MAC unit
- **Advantage**: Minimizes partial sum traffic, no accumulation network needed
- **Challenge**: Limited by the number of concurrent outputs (16 in our case)

#### **Row Stationary (RS)**
- Hybrid approach that maximizes reuse of all data types
- Processes filter rows and keeps them stationary
- **Advantage**: Balanced data reuse across weights, activations, and partial sums
- **Challenge**: More complex control logic

### 2.2 Recommended Mapping for 16 MACs

For your 16-MAC system, I recommend a **spatial unrolling with output stationary** approach:

**Configuration**: 4×4 MAC array arrangement

```
Mapping Strategy:
- Spatial dimension: Process 4 output pixels horizontally
- Filter dimension: Process 4 filters simultaneously
- Temporal dimension: Loop over remaining dimensions

For LeNet Conv1 (5×5 kernel, 6 output channels):
Cycle 1-25: MAC[0-3] compute outputs for filters 0-3
Cycle 26-50: MAC[4-7] compute outputs for filters 4-5
(2 MACs idle during second phase)
```

---

## 3. Memory Constraints Analysis

### 3.1 Local Memory (256 Bytes)

With 8-bit input data, your 256-byte local memory can store:
- **256 input activations** (8-bit each), OR
- **128 weights** (8-bit) + **128 input activations**, OR
- **64 weights + 64 inputs + 64 partial sums** (16-bit)

### 3.2 Memory Allocation Strategy

For LeNet Conv1 with 5×5 filters:

```
Local Memory Layout (256 bytes):
├── Weight Buffer: 100 bytes (5×5×4 filters at a time)
├── Input Buffer: 100 bytes (5×5 window × 4 positions)
└── Partial Sum Buffer: 56 bytes (14 × 16-bit partial sums)
```

**Tiling Strategy**: 
- Process 4 output positions at a time
- Load 4 filter kernels (5×5 = 25 weights each)
- Maintain a 5×5 sliding window of input data
- This fits within 256 bytes

### 3.3 Bandwidth Requirements

**Data Movement per Layer**:
- **Weights**: 6 filters × 5×5 × 8 bits = 1,200 bits = 150 bytes
- **Input Feature Map**: 32×32 × 8 bits = 8,192 bits = 1,024 bytes
- **Output Feature Map**: 28×28×6 × 16 bits (before quantization) = 37,632 bits ≈ 4,704 bytes

**Total Data Movement**: ~5,878 bytes

**Time Required** (at 1 GB/s bandwidth):
- Data transfer: 5,878 bytes / (1×10^9 bytes/s) = **5.878 microseconds**

**Computation Time** (at 16 MACs):
- Total MACs: 117,600
- Cycles needed: 117,600 / 16 = 7,350 cycles
- At 100 MHz: 7,350 cycles / 100×10^6 = **73.5 microseconds**

**Conclusion**: The system is **compute-bound** (computation time >> data transfer time), which is ideal for efficient utilization.

---

## 4. Data Precision and Accumulation

### 4.1 8-bit × 8-bit Multiplication
- Input: 8-bit signed/unsigned integer
- Weight: 8-bit signed integer
- Product: 16-bit result
- Accumulator: Must be wider (typically 32-bit) to prevent overflow

### 4.2 Overflow Prevention

For a 5×5×1 filter with 8-bit operands:
- Maximum accumulation: 25 multiplications
- Each product: max value = 127 × 127 = 16,129 (14 bits)
- Sum of 25: 25 × 16,129 = 403,225 (~19 bits required)

**Recommendation**: Use 32-bit accumulators internally, then quantize back to 8-bit for the next layer.

---

## 5. Example: Complete LeNet-5 Mapping

### LeNet-5 Architecture
1. **Conv1**: 32×32×1 → 28×28×6 (5×5 filter)
2. **Pool1**: 28×28×6 → 14×14×6 (2×2 avg pool)
3. **Conv2**: 14×14×6 → 10×10×16 (5×5 filter)
4. **Pool2**: 10×10×16 → 5×5×16 (2×2 avg pool)
5. **FC1**: 400 → 120
6. **FC2**: 120 → 84
7. **FC3**: 84 → 10

### Computational Breakdown

| Layer | MACs | Data In | Data Out | Compute Cycles (16 MACs) |
|-------|------|---------|----------|-------------------------|
| Conv1 | 117,600 | 1 KB | 4.7 KB | 7,350 |
| Conv2 | 240,000 | 1.2 KB | 1.6 KB | 15,000 |
| FC1 | 48,000 | 400 B | 120 B | 3,000 |
| FC2 | 10,080 | 120 B | 84 B | 630 |
| FC3 | 840 | 84 B | 10 B | 53 |

**Total MACs**: 416,520  
**Total Cycles**: 26,033 (at 100% utilization)  
**Latency** (at 100 MHz): **260 microseconds per image**

---

## 6. Optimization Strategies

### 6.1 Improve MAC Utilization
- Use intelligent tiling to keep all 16 MACs busy
- Process multiple output pixels in parallel when filter count < 16
- Batch processing: process multiple images concurrently

### 6.2 Reduce Memory Bandwidth
- Data reuse through local buffers
- Weight sharing across output pixels (slide input window)
- Activation reuse across different filters

### 6.3 Pipelining
- Overlap data fetch with computation
- Double-buffer local memory (128 bytes for compute, 128 bytes for DMA)
- Pipeline different layers when possible

---

## 7. Hardware Architecture Block Diagram

```
┌─────────────────────────────────────────────────────┐
│                External DRAM (1 GB/s)                │
└──────────────────────┬──────────────────────────────┘
                       │ DMA
┌──────────────────────▼──────────────────────────────┐
│          Local Memory (256 Bytes)                    │
│  ┌──────────┬──────────┬─────────────┐              │
│  │ Weights  │ Inputs   │ Partial Sums│              │
│  │ 100 B    │ 100 B    │ 56 B        │              │
│  └──────────┴──────────┴─────────────┘              │
└──────────────┬─────────────────┬─────────────────────┘
               │                 │
               ▼                 ▼
┌──────────────────────────────────────────────────────┐
│         16 MAC Units (4×4 Array)                      │
│  ┌────┬────┬────┬────┐                               │
│  │MAC │MAC │MAC │MAC │ ← Process 4 outputs           │
│  │ 0  │ 1  │ 2  │ 3  │                               │
│  ├────┼────┼────┼────┤                               │
│  │MAC │MAC │MAC │MAC │                               │
│  │ 4  │ 5  │ 6  │ 7  │                               │
│  ├────┼────┼────┼────┤                               │
│  │MAC │MAC │MAC │MAC │                               │
│  │ 8  │ 9  │ 10 │ 11 │                               │
│  ├────┼────┼────┼────┤                               │
│  │MAC │MAC │MAC │MAC │                               │
│  │ 12 │ 13 │ 14 │ 15 │                               │
│  └────┴────┴────┴────┘                               │
│                                                       │
│  Each MAC: 8-bit × 8-bit → 16-bit product            │
│            32-bit accumulator                         │
└───────────────────────┬───────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│         Control Unit & Sequencer                     │
│  - Address generation                                │
│  - Loop control (spatial, channel, filter)           │
│  - DMA scheduling                                    │
└─────────────────────────────────────────────────────┘
```

---

## 8. Key Takeaways

1. **The system is compute-bound**: With 1 GB/s bandwidth and only 16 MACs, data transfer time is much smaller than computation time, which is good for efficiency.

2. **Local memory is the critical resource**: At 256 bytes, careful management is needed. Tiling and double-buffering are essential.

3. **8-bit quantization is effective**: It reduces memory footprint by 4× compared to 32-bit floating point, with minimal accuracy loss when done properly.

4. **Dataflow choice matters**: Output stationary or weight stationary dataflows are recommended for small MAC arrays like this one.

5. **Expected performance**: For LeNet-5, you can achieve approximately 260 microseconds per image, giving you ~3,800 images per second throughput (assuming 100 MHz clock and perfect utilization).

---

## References and Further Reading

The concepts presented here draw from established research in CNN accelerator design, including work on dataflow architectures (Eyeriss, MAERI), quantization techniques, and memory hierarchy optimization. See the recommended papers section for detailed citations.