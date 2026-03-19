# MAC-only Design (1-cycle multiply) + Timing Diagrams

**Reference:** user's uploaded notes: `/mnt/data/cnn_issies2.txt`

---

## 1. High-level summary

This document implements the architecture your professor asked for:

- 4 MAC units working in parallel (can accept 4 weights + 4 pixels loaded in one cycle)
- Multiply = 1 cycle (8-bit × 8-bit → 16-bit product)
- Each MAC has a 20-bit internal accumulator (accumulates full precision; no saturation)
- Weights and pixels are streamed in 4-at-a-time; on-chip SRAM limited to **16 bytes** total
- Double-buffering in SRAM to allow fetch-while-compute
- No separate adder tree required — the MACs themselves perform the final reduction
- **Total: 8 cycles per patch** (9 multiplies + accumulations + final reduction + write-out)

---

## 2. On-chip SRAM organization (16 bytes)

```
Address  | Purpose                | Size (bytes)
---------|------------------------|--------------
0x00-0x03:  Buffer A - weights (w_curr batch)   | 4
0x04-0x07:  Buffer A - pixels  (a_curr batch)   | 4
0x08-0x0B:  Buffer B - weights (w_next batch)  | 4
0x0C-0x0F:  Buffer B - pixels  (a_next batch)  | 4
Total = 16 bytes
```

Notes:
- Each weight and pixel is 1 byte (8-bit). The design streams 4 weights + 4 pixels per batch.
- You may reuse buffer space to stage the final single operand (w8,a8) when needed.

---

## 3. MAC datapath (per MAC)

```
Pixel_in [8] --->|                 |--- Product [16] ---> Zero-extend ---> [20]
                 |   8x8 Multiplier|                                   |
Weight_in [8] -->|                 |                                   V
                                                              +------------+
                                                              | 20-bit ADD  |
                                          Acc_in[20] ---------->| (accum)     |
                                                              +------------+
                                                                    |
                                                                    V
                                                              ACC_out[20]
```

Control signals (per MAC):
- `load_inputs` — latch pixel and weight into multiplier input registers
- `mult_en` — 1-cycle multiply (combinational/pipelined)
- `acc_mode` — RESET (first product) or ACCUM (add to accumulator)
- `acc_wr` — write accumulator
- `read_acc` — place ACC on bus for reduction (when acting as source for reduction steps)

Note: MAC internal adder used both for ACC accumulation and for reduction steps (reused in different cycles).

---

## 4. Dataflow summary for one patch (9 operands, k=9) using 4 MACs

- Batches of operands: [0..3], [4..7], [8]
- Step-by-step sequence below is cycle-aligned to meet the 8-cycle constraint.

### 8-cycle plan (per patch)

```
Cycle 0: External load -> SRAM Buffer A (w0-w3,a0-a3)
         Pre-fetch -> SRAM Buffer B (w4-w7,a4-a7)
Cycle 1: MACs compute batch0 (a0..a3 * w0..w3) -> ACC0..ACC3 = partial sums
Cycle 2: MACs compute batch1 (a4..a7 * w4..w7) -> ACC0..ACC3 accumulate
         Pre-load w8,a8 into SRAM (reuse buffer A/B space)
Cycle 3: MAC0 compute last operand (a8*w8) -> ACC0 accumulate (MAC1-3 idle)
Cycle 4: Reduction step 1 -> ACC0 := ACC0 + ACC1
Cycle 5: Reduction step 2 -> ACC0 := ACC0 + ACC2
Cycle 6: Reduction step 3 -> ACC0 := ACC0 + ACC3
Cycle 7: Output write -> Write ACC0 (20-bit) to output FIFO / convert/truncate when egress needed
```

**Total = 8 cycles.**

---

## 5. Cycle-by-cycle control table (detailed)

```
Cycle | External loads        | SRAM layout active   | MAC activity                    | ACC actions
------|------------------------|----------------------|----------------------------------|-------------------------------
0     | Load w0..w3,a0..a3     | A <- curr batch      | none (just loading)              | ACCs reset/idle
      | Pre-fetch w4..w7,a4..a7| B <- next batch      |                                  |
1     | (prefetch continues)    | A active             | MAC0..MAC3: compute batch0       | ACCi <= product (reset first)
2     | Pre-load w8,a8 into B/A| B active             | MAC0..MAC3: compute batch1       | ACCi <= ACCi + product
3     | —                      | small single operand | MAC0: compute a8*w8; MAC1-3 idle | ACC0 <= ACC0 + product
4     | —                      | —                    | MACs idle or reused for adds     | ACC0 <= ACC0 + ACC1
5     | —                      | —                    | MACs idle or reused for adds     | ACC0 <= ACC0 + ACC2
6     | —                      | —                    | MACs idle or reused for adds     | ACC0 <= ACC0 + ACC3
7     | Prepare next patch     | Start loading next   | Output write                      | Write ACC0 to FIFO
```

Notes:
- "MACs idle or reused for adds" indicates you can reuse the adder portion of MACs to perform the 20-bit adds during reduction cycles. That keeps hardware reuse minimal.
- If you prefer a dedicated 20-bit adder for reduction, you can run levels 1..3 in parallel and shrink reduction latency — but that requires extra adders (contradicts "no extra adder tree").

---

## 6. Timing diagrams (waveform-style ASCII)

### A. Waveform: Inputs, MAC compute, Accumulate, Reduction, Output

```
Time ->   0     1     2     3     4     5     6     7
         ------------------------------------------------
ExtLd    |====|                                     |====|
         ------------------------------------------------
SRAM-A   | W0..W3 | Active |    -    |  W8  |         |
SRAM-B   | W4..W7 | Next   | Active  |  -   |         |

MAC0     | Ld  | X    | X    | X    | ADD  | ADD  | ADD  | WR  |
         |(0) |(1)   |(2)   |(3)   |(4)  |(5)  |(6)  |(7)  |
MAC1     | Ld  | X    | X    | idle | idle | idle | idle | idle|
MAC2     | Ld  | X    | X    | idle | idle | idle | idle | idle|
MAC3     | Ld  | X    | X    | idle | idle | idle | idle | idle|

ACC0     |  0  | p0   | p0+p4| +p8  | +a1  | +a2  | +a3  | OUT |
ACC1     |  0  | p1   | p1+p5| idle | ---  | ---  | ---  | --- |
ACC2     |  0  | p2   | p2+p6| idle | ---  | ---  | ---  | --- |
ACC3     |  0  | p3   | p3+p7| idle | ---  | ---  | ---  | --- |

Legend:
- Ld = load operands into MAC inputs
- X  = execute multiply (1 cycle)
- p0 = product from batch0 (a0*w0), p4 = product a4*w4 etc.
- ADD = reduction add step
- WR  = write final output
```

### B. Waveform: SRAM double-buffering view

```
Cycle:    0        1        2        3        4
         -------  -------  -------  -------  -------
BufA     w0..w3  read     reused  w8,a8   reused
BufB     w4..w7  preload  read    idle    preload(next)
```

This shows how prefetch overlaps compute.

---

## 7. Small-state FSM for per-patch control (pseudocode)

```
state = IDLE
on start_patch:
  state = LOAD0

LOAD0:
  ext_load(bufferA <- next4weights+next4pixels)
  ext_prefetch(bufferB <- nextnext4)
  state = COMPUTE0

COMPUTE0:
  enable_MACs()  // batch0
  wait 1 cycle
  state = COMPUTE1

COMPUTE1:
  enable_MACs()  // batch1
  wait 1 cycle
  state = COMPUTE2

COMPUTE2:
  enable_MAC0()  // final single multiply
  wait 1 cycle
  state = REDUCE1

REDUCE1:
  ACC0 = ACC0 + ACC1
  wait 1 cycle
  state = REDUCE2

REDUCE2:
  ACC0 = ACC0 + ACC2
  wait 1 cycle
  state = REDUCE3

REDUCE3:
  ACC0 = ACC0 + ACC3
  wait 1 cycle
  state = WRITEOUT

WRITEOUT:
  fifo_write(ACC0)
  prepare next patch (start prefetch)
  state = LOAD0 or IDLE
```

---

## 8. Optional variations & trade-offs

- **If multiply > 1 cycle**: then MACs are busy and cannot perform timely reductions; a separate adder tree is recommended to keep overall patch latency low.
- **If you add a dedicated adder tree**: you can perform the 4→2→1 reduction in *2 cycles* (two levels) instead of 3 serial cycles, reducing patch latency to 7 cycles if overlapping is perfect — but that consumes extra 20-bit adders.
- **If you want to compress final write**: keep ACC0 full 20-bit inside and only truncate at system egress if interface requires 16-bit.

---

## 9. Diagrams to include in report

- Single MAC datapath (small schematic)
- SRAM double-buffering layout
- 8-cycle timeline (waveforms) — included above
- Control FSM and cycle-by-cycle control table — included above

---

## 10. Appendix: quick-check math

- 9 multiplies per patch
- 4 multiplies per cycle while 4 MACs active → batches: 3 (4 + 4 + 1)
- Per-batch compute cycles = 3 cycles
- Reduction = 3 cycles (serial within MACs)
- Output write = 1 cycle
- **Total = 8 cycles**

Per image: 16 patches × 8 cycles = 128 cycles per image.

---

If you'd like, I can now:
- produce a neat vector diagram (SVG/PNG) of the datapath for slides,
- or convert the ASCII timing diagrams into a clean plotted waveform (image),
- or reformat the document for a specific slide/paper style.


