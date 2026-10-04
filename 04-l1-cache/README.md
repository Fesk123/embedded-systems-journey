# L1 Instruction and Data Cache

## Goal

The goal of this project is to add a Level 1 cache hierarchy to the RV64GC processor.

The caches act as an intermediate layer between the processor and the physical memory system, reducing the latency of repeated memory accesses.

The implementation contains:

- 32 KiB instruction cache
- 32 KiB data cache
- 4-way set associativity
- 64-byte cache lines
- 128 sets
- 64-bit datapath
- Pseudo-LRU replacement
- Instruction cache hit and refill
- Data cache hit and refill
- Write-back and write-allocate for the data cache
- Dirty-bit tracking
- Dirty cache-line writeback
- AMO operations
- LR/SC support
- Uncached/MMIO accesses
- Instruction cache invalidation through "FENCE.I"
- Data-cache flush and invalidate
- WISHBONE master interfaces
- WISHBONE burst transfers
- WISHBONE error/fault handling
- Debug and status signals for cache operation

---

# 1. Cache Organization

Both the instruction and data caches use the same basic organization:

- 32 KiB
- 4-way set associative
- 128 sets
- 64-byte cache lines
- 64-bit datapath

The cache can therefore be viewed as:

             +----------------------+
             |        L1 Cache      |
             |                      |
             |  128 sets            |
             |  4 ways / set        |
             |  64-byte lines       |
             +----------------------+

Each cache contains:

128 sets × 4 ways × 64 bytes
= 32 KiB

The instruction and data caches are separate.

---

# 2. Separate Instruction and Data Caches

The processor uses:

- L1 Instruction Cache
- L1 Data Cache

rather than one unified cache.

The architecture is therefore:

                   RV64GC
                  /      \
                 /        \
                v          v
           L1 I-Cache   L1 D-Cache
                |          |
                |          |
                +----+-----+
                     |
                     v
                  WISHBONE

This allows instruction fetches and data accesses to be handled independently.

---

# 3. Cache Line

Each cache line contains:

64 bytes

Since the datapath is 64 bits:

64 bits = 8 bytes

A complete cache line therefore contains:

64 / 8 = 8

64-bit words.

This also means a complete line refill requires multiple 64-bit memory transfers.

---

# 4. Cache Sets and Ways

Each cache contains:

- 128 sets
- 4 ways per set

A given memory address maps to one cache set and can be stored in any of the four ways of that set.

Conceptually:

                Address
                   |
                   v
             Set Selection
                   |
          +--------+--------+
          |        |        |
          v        v        v
        Way 0    Way 1    Way 2    Way 3
          |        |        |        |
          +--------+--------+--------+
                       |
                       v
                   Hit / Miss

The four-way structure reduces conflict misses compared with a direct-mapped cache.

---

# 5. Cache Line Metadata

Each cache line requires metadata in addition to the actual data.

The exact tag width depends on the physical-address width used by the processor.

---

# 6. Cache Hit

A cache hit occurs when the requested address is already present in the corresponding cache set.

On a hit, the cache can respond without accessing the WISHBONE memory system.

This is the main performance benefit of the cache.

---

# 7. Instruction Cache

The instruction cache stores recently fetched instructions.

The instruction cache is primarily read-only from the CPU's point of view.

Its main operations are:

- Instruction lookup
- Instruction hit
- Cache-line refill
- Invalidation
- "FENCE.I"

---

# 8. Data Cache

The data cache handles:

- Loads
- Stores
- Atomic operations
- LR/SC operations

Unlike the instruction cache, the data cache must support both reads and writes.

---

# 9. Write-Back

The data cache uses a write-back policy.

When the CPU writes to a cached line, the cache is updated first rather than immediately writing the data to memory.

The line is marked:

Dirty = 1

The modified data remains in the cache until the line needs to be written back.

This reduces the number of memory writes.

---

# 10. Write-Allocate

The data cache also uses write-allocate.

This allows future accesses to the same cache line to hit in the data cache.

---

# 11. Dirty Cache Lines

Every data-cache line contains a dirty bit.

The dirty bit indicates that the cache line contains data that is newer than the corresponding memory location.

When a dirty line is replaced, its contents must first be written back to memory.

---

# 12. Cache Refill

A cache miss triggers a cache-line refill.

The refill retrieves the complete 64-byte cache line from the memory system.

With a 64-bit datapath, this requires eight 64-bit transfers.

---

# 13. Dirty Writeback

When a dirty cache line must be replaced, the line is written back to physical memory before the new line is installed.

The writeback uses WISHBONE burst transfers to efficiently send the complete line back to memory.

---

# 14. WISHBONE Master Interfaces

The caches use WISHBONE as the interface to the physical memory system.

The architecture provides separate memory paths for instruction and data traffic.

The WISHBONE interfaces are used for:

- Cache-line refills
- Dirty-line writebacks
- Required memory accesses
- Error reporting

---

# 15. WISHBONE Burst Refill

Because a cache line is 64 bytes and the datapath is 64 bits wide, a refill consists of eight data beats.

Conceptually:

Beat 0 → Word 0
Beat 1 → Word 1
Beat 2 → Word 2
Beat 3 → Word 3
Beat 4 → Word 4
Beat 5 → Word 5
Beat 6 → Word 6
Beat 7 → Word 7

These transfers use WISHBONE burst functionality.

This reduces the overhead compared with performing eight completely independent memory transactions.

---

# 16. WISHBONE Burst Writeback

Dirty cache lines use the same principle when written back.

The address advances by the 64-bit word size between beats.

---

# 17. Pseudo-LRU Replacement

Because each set contains four ways, the cache needs a replacement policy to determine which way should be replaced on a miss.

The implementation uses Pseudo-LRU.

The replacement logic tracks which ways have been used most recently and selects a less recently used way when a replacement is required.

Pseudo-LRU provides a good approximation of LRU while requiring less hardware state than a full exact LRU implementation.

---

# 18. Atomic Operations

The data cache supports RISC-V atomic memory operations.

This is required because the RV64GC processor includes the A extension.

Examples include:

- AMOADD
- AMOSWAP
- AMOXOR
- AMOAND
- AMOOR
- AMOMIN
- AMOMAX
- LR
- SC

Atomic operations must preserve their required memory semantics even when the data is cached.

---

# 19. AMO Handling

An AMO operation performs a read-modify-write sequence.

The cache must ensure that the operation is performed atomically from the processor's point of view.

The cache interface therefore needs dedicated handling for AMO accesses rather than treating them as unrelated normal loads and stores.

---

# 20. LR/SC Support

Load-reserved ("LR") and store-conditional ("SC") are implemented through the cache interface.

The cache must therefore track the reservation state associated with the relevant memory address.

This reservation mechanism must remain consistent with cache line replacement, writes, and other accesses.

---

# 21. Uncached and MMIO Accesses

Not every memory access should use the cache.

Memory-mapped I/O devices generally need to be accessed without normal cache behavior.

The cache therefore supports an uncached/MMIO path.

An uncached access bypasses the normal cache lookup and refill mechanism.

This prevents peripheral accesses from being incorrectly stored inside the cache.

The exact address ranges used for uncached/MMIO accesses are defined by the SoC memory map.

---

# 22. Instruction Cache Invalidation

The instruction cache supports invalidation through "FENCE.I".

This is required when software modifies instruction memory and then needs the processor to observe the updated instructions.

The invalidation ensures that stale instruction-cache lines are not used after instruction memory has changed.

---

# 23. Data Cache Flush and Invalidate

The data cache supports flush and invalidate operations.

A flush causes dirty cache lines to be written back to memory.

An invalidate removes cached lines from the cache.

This provides a mechanism for keeping the cache and external memory consistent when required.

---

# 24. Cache State Machine

The cache controllers use internal state machines to coordinate hits, misses, refills, writebacks, and uncached accesses.

The actual implementation can contain additional states for:

- WISHBONE requests
- Burst beats
- Errors
- AMOs
- LR/SC
- Uncached accesses
- Invalidation

---

# 25. Error and Fault Handling

The WISHBONE interface can return an error during a refill, writeback, or uncached transaction.

The cache therefore has to propagate memory-system faults back toward the processor.

A cache miss must not silently turn a failed memory access into valid data.

---

# 26. Debug Signals

The cache implementation contains debug signals to simplify simulation and debugging.

Useful signals include:

- Cache state
- Hit
- Miss
- Refill
- Writeback
- Dirty state
- Replacement way
- Uncached access
- WISHBONE request
- WISHBONE response
- Burst progress
- AMO operation
- LR/SC state
- Invalidate operation
- Fault/error state

These signals make it possible to inspect cache behavior directly in GTKWave.

---

# 27. Problems Encountered

### Verilog Syntax Errors

Some implementation issues were caused by syntax errors in the Verilog source.

These had to be corrected before meaningful simulation results could be obtained.

---

### 64-bit Constants

The transition to a 64-bit processor introduced problems with hexadecimal constants that were not represented with the expected width.

This was especially important when testing:

- Physical addresses
- Cache tags
- Test data
- WISHBONE transactions

The testbench therefore had to use correctly sized 64-bit values.

---

### Testbench Addressing

Some simulation failures were caused by incorrect assumptions in the testbench about how addresses mapped to cache sets and cache lines.

Because the cache contains 128 sets and 64-byte lines, the testbench had to deliberately select addresses that exercised:

- Different lines
- The same set
- Different ways
- Replacement conditions

---

### Replacement Testing

Testing pseudo-LRU was more complicated than testing simple cache hits.

The testbench had to generate access patterns that filled the same set and then caused a replacement.

This required careful construction of addresses and access sequences.

---

### Cache Control Complexity

The combination of:

- Refill
- Writeback
- Burst transfer
- Dirty state
- AMO
- LR/SC
- Uncached access

makes the cache controller significantly more complex than a simple cache lookup module.

Each operation needs to interact correctly with the state machine and memory interface.

---

# 28. Reflection

This project was an important step because the processor now has an actual memory hierarchy rather than accessing the external memory system directly for every operation.

The most important architectural change is the separation between:

Instruction path
and
Data path

with independent 32 KiB L1 caches.

The cache design also demonstrated that memory performance is not only determined by the processor's clock frequency. The amount of data that can be reused locally, the probability of a cache hit, refill latency, writeback traffic, and bus bandwidth all affect the effective performance of the system.

The choice of 4-way set associativity and 64-byte cache lines provides a reasonable balance between capacity, conflict misses, and hardware complexity.

Implementing write-back and write-allocate also showed how much state a data cache needs to maintain. The dirty bit, replacement logic, refill process, and writeback mechanism all have to work together.

The support for AMOs and LR/SC was particularly important because the cache cannot simply optimize normal loads and stores while ignoring the atomic semantics of the RISC-V architecture.

Another important lesson was the value of a dedicated waveform testbench. Several problems were not obvious from the final output alone. Inspecting addresses, tags, cache states, replacement decisions, and WISHBONE signals in GTKWave made it possible to identify and correct the underlying problems.

After the corrections, the cache simulation successfully passed the functional tests, making the current L1 cache implementation a suitable memory layer between the RV64GC/Sv39 processor and the rest of the SoC.

---

# 29. Future Improvements

Possible future improvements include:

- Cache performance benchmarking
- More extensive replacement-policy testing
- Cache coherency support if multiple processors are added
- Prefetching
- Larger cache levels
- L2 cache
- More advanced replacement policies
- Formal verification
- FPGA timing and resource analysis
- Linux workload testing
- Memory-system performance measurements

---

# 30. What's Next

The next step is to implement Boot ROM and DDR memory support.

The goal is to build the physical memory system that the MMU and caches will access after address translation and cache lookup.

This will provide the processor with persistent boot code and significantly larger main memory, moving the project closer to a complete computer capable of booting software beyond simulation.
