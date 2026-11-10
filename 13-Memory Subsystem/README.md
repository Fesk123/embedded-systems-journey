# Memory Subsystem

## Overview

This project develops and integrates the memory subsystem for the custom RV64GC computer.

The subsystem extends the existing L1 cache and memory architecture with a larger L2 cache, Physical Memory Attribute (PMA) checking, coordinated cache maintenance, and a bridge between the Wishbone and AXI4 bus protocols.

The goal is to provide a more complete memory hierarchy while ensuring that memory accesses follow the correct permissions and attributes. It also provides the interface required to connect the Wishbone-based RV64GC system to the KV260 Processing System's AXI memory infrastructure.

The memory subsystem consists of four main Verilog modules:

- "L2_Cache.v"
- "PMA_Checker.v"
- "Cache_Maintenance_Controller.v"
- "Wishbone_AXI4_Bridge.v"

## Project Goals

- Implement a 256 KiB L2 cache.
- Support four-way set associativity and 64-byte cache lines.
- Provide a 64-bit memory datapath.
- Support write-back and write-allocate policies.
- Implement cache refill and eviction.
- Check Physical Memory Attributes before memory accesses.
- Coordinate cache maintenance between L1 and L2.
- Support cache operations required by DMA and instruction synchronization.
- Bridge Wishbone transactions to AXI4.
- Provide a foundation for connecting the RV64GC system to the KV260 memory infrastructure.

## Architecture

### 1. L2 Cache ("L2_Cache.v")

The L2 cache provides an additional cache level between the existing L1 caches and the external memory system.

Its specifications are:

- Capacity: 256 KiB.
- Associativity: 4-way set associative.
- Cache line size: 64 bytes.
- Datapath width: 64 bits.
- Replacement and refill logic for cache-line management.
- Write-back policy.
- Write-allocate policy.

Its responsibilities include:
- Checking whether requested data is present in the cache.
- Returning data on cache hits.
- Requesting cache-line refills on cache misses.
- Managing dirty cache lines.
- Writing back modified data when necessary.
- Supporting cache maintenance operations.

The L2 cache reduces the number of accesses to external memory by retaining recently used data. Its effectiveness depends on the access patterns of the processor and other system components.

### 2. Physical Memory Attribute Checker ("PMA_Checker.v")

The PMA checker evaluates physical memory addresses and determines the attributes associated with the corresponding memory regions.

It checks properties such as:
- Read permission.
- Write permission.
- Execute permission.
- Whether a memory region is cacheable.
- Whether a region represents device memory.

PMA checking is important because not every physical memory region should be accessed in the same way.

For example, normal DDR memory can be cacheable, while memory-mapped I/O regions generally require device-style access behaviour.

The checker must correctly handle memory boundaries, overlapping regions, and access permissions.

An important correction was made to preserve the relevant region attributes even for certain denied accesses. This ensures that the returned attribute information remains consistent when an access is rejected.

This correction has subsequently been verified through simulation.

### 3. Cache Maintenance Controller ("Cache_Maintenance_Controller.v")

The cache maintenance controller coordinates operations involving the L1 and L2 caches.

Its purpose is to ensure that cache contents remain consistent when the processor or another system component modifies memory.

Supported maintenance operations include:

- "FENCE.I" — instruction-stream synchronization.
- "FLUSH_ALL" — flushing cache contents.
- DMA-related clean operations.
- DMA-related invalidate operations.

DMA transfers introduce an important cache-consistency challenge. For example, if DMA writes new data to DDR while the processor retains an older copy in its cache, the processor may continue reading stale data.

The maintenance controller provides the coordination required for the relevant clean and invalidate operations.

### 4. Wishbone-to-AXI4 Bridge ("Wishbone_AXI4_Bridge.v")

The Wishbone-to-AXI4 bridge connects the existing Wishbone-based SoC to the AXI4 memory infrastructure available on the KV260.

Its responsibilities include:
- Accepting Wishbone transactions.
- Translating requests into corresponding AXI4 transactions.
- Handling AXI address, data, and response channels.
- Managing transaction completion.
- Handling backpressure.
- Reporting transaction errors to the Wishbone side.

This bridge is an important part of the future PS–PL memory integration.

The exact performance depends on the supported transaction types, burst handling, buffering, and the AXI infrastructure connected to the bridge.

## Memory Access and Cache Consistency

The memory subsystem must coordinate accesses from several possible sources:

- The RV64GC processor through its L1 caches.
- The L2 cache.
- DMA engines.
- Other system components accessing shared DDR memory.

The cache maintenance controller helps coordinate situations where cached data and external memory may otherwise become inconsistent.

Correct cache maintenance is particularly important when DMA or another bus master modifies memory independently of the CPU.

## Verification

### Text-Based Testbench

The memory subsystem is tested as part of the shared testbench:

"text_Sim_Projects_13_16.v"

The testbench includes separate test groups for PMA checking, cache maintenance, L2 cache behaviour, and the Wishbone-to-AXI4 bridge.

The relevant tests include:

PMA Checker
- Memory-region boundaries.
- Overlapping PMA regions.
- Read, write, and execute permissions.
- Cacheable and device-memory attributes.
- Attribute handling for denied accesses.

Cache Maintenance Controller
- L1 and L2 maintenance coordination.
- DMA-related memory ranges.
- Clean and invalidate operations.
- Error handling.

L2 Cache
- Cache hits and misses.
- Refill operations.
- Write-back behaviour.
- Dirty cache-line eviction.
- Memory transaction handling.

Wishbone-to-AXI4 Bridge
- AXI4 backpressure.
- Burst transfers.
- Invalid or error responses.
- Reset during an active transaction.

### Latest Verification Results

| Test group           | Result   |
|----------------------|----------|
| PMA                  | 0 errors |
| Cache Maintenance    | 0 errors |
| L2 Cache             | 0 errors |
| Wishbone–AXI4 Bridge | 0 errors |

The PMA implementation initially had three failing checks. The code was subsequently corrected to preserve region attributes in certain denied-access cases, and the correction has now been verified.

All four memory-subsystem test groups currently report zero errors.

## Main Challenges

### Cache Consistency

Maintaining consistent data between L1, L2, and external memory is one of the most important challenges.

The system must ensure that dirty or stale cache lines do not cause incorrect results, especially when DMA accesses memory independently of the CPU.

### Memory Attributes and Permissions

The PMA checker must correctly identify memory regions and enforce their access permissions.

Incorrect region matching or attribute reporting could result in invalid accesses or incorrect caching behaviour.

### Bus Protocol Conversion

Wishbone and AXI4 use different transaction and handshake mechanisms.

The bridge must handle the differences correctly, particularly when AXI applies backpressure or returns an error response.

### Memory Performance

Cache misses, write-backs, and external memory latency all affect performance.

The L2 cache should reduce unnecessary memory traffic while maintaining correct behaviour under competing requests.

## Current Status and Limitations

The four modules have been developed and tested through the shared text-based testbench.

All four associated test groups currently report zero errors.

However, successful simulation does not establish that the complete memory subsystem has been integrated with the physical KV260 memory infrastructure.

Further work includes:
- Integration with the existing L1 cache hierarchy.
- Connection to the actual PS–PL AXI memory path.
- Verification with the complete SoC.
- Testing cache consistency with real DMA activity.
- FPGA timing and resource analysis.

## What's Next

The next project is Project 14 – CPU Protection & Performance.

It introduces Physical Memory Protection (PMP) and a Performance Monitoring Unit (PMU).

The goal is to extend the RV64GC processor with hardware-level memory access protection and performance measurement capabilities.

Goal: Provide the RV64GC computer with a more complete memory hierarchy, correct memory attributes, coordinated cache maintenance, and a path toward external DDR memory through AXI4.
