# CPU Protection & Performance

## Overview

This project adds hardware-level memory protection and performance monitoring capabilities to the custom RV64GC processor.

It consists of two main Verilog modules:

- "PMP_RV64.v" — Physical Memory Protection.
- "PMU_RV64.v" — Performance Monitoring Unit.

The Physical Memory Protection unit controls which physical memory regions can be accessed by software running at different privilege levels.

The Performance Monitoring Unit provides counters for observing processor activity, including clock cycles, retired instructions, and selected microarchitectural events.

Together, these modules improve the processor's protection mechanisms and make it possible to analyse its performance during simulation and future hardware testing.

## Project Goals

- Implement Physical Memory Protection for RV64.
- Support TOR, NA4, and NAPOT region configurations.
- Support locked protection regions.
- Check memory access permissions.
- Apply protection according to processor privilege modes.
- Implement a Performance Monitoring Unit.
- Provide "mcycle" and "minstret" counters.
- Support additional hardware performance counters (HPM).
- Make performance information accessible through CSRs.
- Verify protection and counter behaviour through simulation.

## Architecture

### 1. Physical Memory Protection ("PMP_RV64.v")

The PMP module provides hardware-level protection for physical memory accesses.

It allows the processor to divide its physical address space into regions with different access permissions.

Depending on the configured PMP entry, a memory region can have permissions for:

- Read ("R").
- Write ("W").
- Execute ("X").

The module supports three address-matching modes.

TOR – Top of Range

TOR defines a memory region using the address of the current PMP entry and the address of the preceding entry.

This makes it possible to specify memory ranges using boundaries.

NA4 – Naturally Aligned Four-Byte Region

NA4 defines a naturally aligned four-byte protection region.

NAPOT – Naturally Aligned Power-of-Two Region

NAPOT allows the definition of naturally aligned regions with power-of-two sizes.

The PMP implementation also supports locked regions and different processor privilege modes.

The purpose is to prevent software from accessing physical memory regions for which it does not have the required permissions.

### 2. Performance Monitoring Unit ("PMU_RV64.v")

The PMU provides hardware counters for measuring processor activity.

Its main counters include:

"mcycle"

Counts processor clock cycles. This can be used to measure how long a program or operation takes to execute.

"minstret"

Counts retired instructions. This provides information about the amount of completed instruction work.

HPM Counters

Hardware Performance Monitoring counters provide support for measuring additional events.

Examples of relevant events include:
- Cache misses.
- TLB events.
- Pipeline stalls.

The PMU exposes performance information through control and status registers (CSRs).

Software and verification environments can use these counters to analyse processor behaviour and identify performance bottlenecks.

## Integration with the RV64GC Processor

The PMP and PMU are designed to extend the existing RV64GC processor architecture.

The PMP participates in physical memory access checking, while the PMU observes processor activity.

The modules therefore serve different purposes:

- PMP controls which physical memory accesses are permitted.
- PMU measures processor activity and performance-related events.

Their integration requires correct connections to the processor's privilege information, memory access signals, event signals, and CSR infrastructure.

## Verification

### Text-Based Testbench

Both modules are tested through the shared testbench:

"text_Sim_Projects_13_16.v"

The testbench contains separate test groups for PMP and PMU.

PMP tests include:
- TOR region configuration.
- NA4 region configuration.
- NAPOT region configuration.
- Region boundaries.
- Read, write, and execute permissions.
- Different privilege modes.
- Locked protection regions.

PMU tests include:
- "mcycle" counting.
- "minstret" counting.
- HPM counter operation.
- Counter overflow.
- CSR access and handling.

### Latest Verification Results

| Test group | Result |
|---|---:|
| PMP | 0 errors |
| PMU | 0 errors |

Both modules currently pass their reported test groups without errors.

## Main Challenges

### PMP Region Matching

TOR, NA4, and NAPOT use different methods to define memory regions.

The implementation must correctly determine whether an access belongs to a configured region, including accesses near region boundaries.

### Privilege-Based Protection

Access permissions must be evaluated according to the processor's privilege mode and the configuration of the corresponding PMP entries.

Incorrect permission handling could allow unintended memory access or block valid operations.

### Counter Accuracy

Performance counters must update correctly when their corresponding events occur.

The implementation must also handle counter overflow and ensure that CSR operations behave as expected.

### Event Integration

The PMU can only measure events that are correctly connected to its event inputs.

For example, measuring cache misses or TLB events requires the corresponding subsystems to provide accurate event signals.

## Current Status and Limitations

Both modules have been developed and tested through the shared text-based testbench.

The latest reported results show:
- PMP: 0 errors.
- PMU: 0 errors.

Further work includes:
- Integration into the complete RV64GC processor top-level.
- Verification of PMP behaviour during actual processor memory accesses.
- Connecting performance events from the MMU, caches, and pipeline.
- Testing CSR access through running software.
- FPGA verification on the KV260.

The current test results establish the behaviour covered by the testbench, but full processor-level verification is still required.

## What's Next

The next project is Project 15 – Clock & Reset Infrastructure.

It introduces asynchronous FIFO buffering and synchronization modules for safely transferring signals and data between different clock domains.

The goal is to establish reliable clock-domain crossing and reset behaviour before integrating more of the RV64GC computer on the FPGA.

Goal: Extend the RV64GC processor with memory access protection and performance monitoring, providing stronger isolation and the ability to measure and analyse processor behaviour.
