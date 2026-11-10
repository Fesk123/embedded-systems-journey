# Clock & Reset Infrastructure

## Overview

This project implements infrastructure for reliable communication between different clock domains in the RV64GC computer.

As the SoC grows, its components may operate at different clock frequencies or use independent clocks. Directly transferring signals between asynchronous clock domains can cause metastability, corrupted data, or missed events.

The clock and reset infrastructure provides dedicated modules for synchronizing signals, transferring pulses, coordinating multi-bit data, and buffering data between different clock domains.

The project contains two main Verilog files:

- "Async_FIFO.v"
- "CDC_Synchronizers.v"

Together, they provide the foundation for safe clock-domain crossing (CDC) and reset handling throughout the system.

## Project Goals

- Implement an asynchronous FIFO.
- Support data transfers between independent clock domains.
- Use Gray-coded pointers for safe pointer synchronization.
- Implement signal synchronization.
- Implement reset synchronization.
- Support pulse transfers between clock domains.
- Support multi-bit transfers using request/acknowledge handshaking.
- Handle backpressure during data transfers.
- Verify FIFO behaviour under different clock frequencies.
- Establish reusable CDC infrastructure for the complete SoC.

## Architecture

### 1. Asynchronous FIFO ("Async_FIFO.v")

The asynchronous FIFO provides temporary storage for data transferred between two independent clock domains.

Unlike a conventional synchronous FIFO, the write and read sides use separate clocks.

The module is designed to:
- Accept data using a write-domain clock.
- Provide data using a separate read-domain clock.
- Maintain independent read and write pointers.
- Detect full and empty conditions.
- Support pointer wraparound.
- Synchronize pointers between clock domains.

#### Gray-Coded Pointers

The FIFO uses Gray-coded pointers to reduce the risk of incorrect pointer sampling when signals cross between asynchronous clock domains.

In Gray code, consecutive pointer values differ by only one bit. This reduces the possibility of sampling an inconsistent multi-bit binary pointer during a clock transition.

The synchronized pointers are used to determine whether the FIFO is full or empty.

Asynchronous FIFO structures are particularly useful when two subsystems operate at different frequencies but must exchange data reliably.

### 2. CDC Synchronizers ("CDC_Synchronizers.v")

This file contains four synchronization modules.

#### Clock Synchronizer ("Clock_Synchronizer")

The clock synchronizer transfers single-bit signals into another clock domain.

Its purpose is to reduce metastability risks when asynchronous control signals are sampled by a destination clock.

#### Reset Synchronizer ("Reset_Synchronizer")

The reset synchronizer provides controlled reset behaviour for a clock domain.

It supports:
- Asynchronous reset assertion.
- Synchronous reset deassertion.

This allows a reset to be applied immediately while ensuring that the release is synchronized to the destination clock.

#### Pulse Synchronizer ("Pulse_Synchronizer")

The pulse synchronizer transfers event pulses between different clock domains.

A short pulse in one clock domain may otherwise be missed if the receiving clock is slower or has an unfavourable phase relationship.

The module provides a synchronization mechanism so that the event can be detected in the destination domain.

#### Handshake Synchronizer ("Handshake_Synchronizer")

The handshake synchronizer transfers multi-bit data between clock domains using a request/acknowledge protocol.

Its intended behaviour includes:
- Request signalling.
- Data transfer.
- Acknowledgement.
- Backpressure when the receiving side is not ready.
- Completion signalling.

The handshake ensures that data is held stable for the required transfer interval instead of relying on independently synchronized data bits.

## Clock-Domain Crossing in the RV64GC SoC

The clock and reset modules are intended to be reused throughout the growing SoC.

Potential applications include:
- Communication between the processor and peripheral subsystems.
- Transfers between AXI and Wishbone-related clock domains.
- Communication with PS-side interfaces.
- Data movement between graphics and memory subsystems.
- External interface buffering.
- Reset distribution to independent clock domains.

Not every interface requires an asynchronous FIFO. Single-bit signals, pulses, and multi-bit data transfers require different synchronization strategies.

The appropriate module must therefore be selected according to the type of signal and the requirements of the interface.

## Reset Strategy

Reset handling is an important part of reliable system integration.

Different components may use different clocks, and their clocks may not become active simultaneously.

The reset synchronizer provides a controlled way to release reset within each destination clock domain.

The complete SoC must still ensure that:
- Each subsystem receives the correct reset.
- Reset release is synchronized to its local clock.
- Reset behaviour is consistent across connected interfaces.
- Outstanding transactions are handled safely when a reset occurs.

## Verification

### Text-Based Testbench

The modules are tested through the shared testbench:

"text_Sim_Projects_13_16.v"

The relevant test group is:

Async FIFO + CDC

The testbench covers:

- FIFO full and empty conditions.
- Read and write pointer wraparound.
- Transfers between different clock frequencies.
- Asynchronous FIFO data integrity.
- Synchronization behaviour.
- Handshake request and acknowledgement.
- Backpressure.
- Reset-related behaviour.

Testing with different clock speeds is important because CDC errors may not appear when both clock domains operate at the same frequency.

### Latest Verification Results

| Test group | Result |
|---|---:|
| Async FIFO + CDC | 0 errors |

The combined asynchronous FIFO and CDC test group currently reports zero errors.

## Main Challenges

### Metastability

Signals crossing between asynchronous clock domains may violate the receiving registers' setup or hold requirements.

Synchronization structures reduce the risk of metastability propagating through the system, but they do not eliminate the physical possibility of metastability.

### Multi-Bit Data Transfers

Synchronizing each bit of a data bus independently is not sufficient to guarantee that the destination receives a consistent word.

The handshake synchronizer addresses this by coordinating data stability with request and acknowledgement signals.

### FIFO Pointer Synchronization

The asynchronous FIFO must safely compare pointers generated in different clock domains.

Gray-coded pointers and synchronizer stages are used to make pointer information safer to transfer between the domains.

### Reset Behaviour

Asynchronous reset assertion and synchronous deassertion must be handled correctly.

Incorrect reset release can cause a subsystem to begin operating in an inconsistent state.

### Backpressure

The receiving subsystem may not always be ready to accept new data.

The synchronization and FIFO logic must handle this without losing data or generating duplicate transfers.

## Current Status and Limitations

The asynchronous FIFO and four CDC synchronization modules have been tested through the shared text-based testbench.

The latest reported test group result is zero errors.

Further work includes:
- Integrating CDC modules into the relevant SoC interfaces.
- Identifying all actual clock-domain crossings in the complete design.
- Verifying reset distribution on the KV260.
- Testing asynchronous interfaces under FPGA clock conditions.
- Reviewing synchronization depth and timing requirements for each interface.

Successful simulation is an important verification step, but physical timing analysis and FPGA testing are still necessary for the integrated system.

## What's Next

The next project is Project 16 – System Control & Watchdog.

It introduces a programmable watchdog timer connected through Wishbone.

The goal is to detect situations where the system stops responding and provide timeout, interrupt, and reset-request functionality.

Goal: Provide reusable clock-domain crossing and reset infrastructure so that the RV64GC computer can safely connect subsystems operating with different clocks.
