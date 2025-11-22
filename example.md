# Assumptions

**Input:**  8 * 8 * 1  
 - greyscale image
 - each pixel will be 8-bit int

**Kernel:** 3 * 3
- Stride - 2
- Padding -1 ( to make sure i get all the border values and don't lose data )
- 1 channel - greyscale image 
- 9 bytes of weights - will be stored in the cache(local memory) - Weight Stationary Dataflow

**Constraints:**
- 4 MACs - each 8-bit * 8-bit -> 16-bit accumulate & output - overflow policy - round/clip (assumption)
- 16 bytes local memory - SRAM (cache memory assumption)
- 1 KB/s external memory transfer bandwidth - 1024 B/s
- Inputs and outputs will be streamed 

# Calculations

## Cycles and patch
Number of MAC operations - 16* 9 = 144 
number of MAC - 4
Cycles - 144/4 = 36 cycles + 32 cycles -> 68 cycles
for each output 9 MAC operations,
pairwise reduction with 2 MACs will be used to complete the partial sum calculations and complete the operation - this will take 2 cycles 
2* 16 = 32 cycles 


While reading later i found that i had missed the final accumulate stage in these calculations
therefore MAC cycle frequency is 68* 12.8 = 870.4 = 871 Hz (approx) 

Cycle 0:  MAC0 <- a0*w0    MAC1 <- a1*w1    MAC2 <- a2*w2    MAC3 <- a3*w3   (compute 0..3)
Cycle 1:  MAC0 <- a4*w4    MAC1 <- a5*w5    MAC2 <- a6*w6    MAC3 <- a7*w7   (compute 4..7)
Cycle 2:  MAC0 <- a8*w8    MAC1 idle        MAC2 idle        MAC3 idle      (compute 8)
Cycle 3:  MAC0 <- ACC0+ACC1    MAC1 <- ACC2+ACC3    MAC2/3 idle   (pairwise adds)
Cycle 4:  MAC0 <- MAC0 + MAC1  (final add -> final_sum)*
therefore 4* 16 = 64 cycles 

![[IMG_20251122_155427888 1.jpg]]

## Memory and transfer speeds 
input - 8* 8* 1 = 64 bytes - read
output - 4* 4 = 16 bytes - write
total is = 80 bytes
weights - 3* 3 = 9 bytes - read once and stored in SRAM

bandwidth- 1024/80 = 12.8 images/s

![[IMG_20251122_155509454 (1).jpg]]

## Padding and stride  
There will be 16 patches to ensure all data points are covered 

![[IMG_20251122_155608049.jpg]]


# Architecture


![[Pasted image 20251122184918.png]]


