# PLIC + DMA

## Goal

The goal of this project was to implement a Platform-Level Interrupt Controller (PLIC) and a Direct Memory Access (DMA) controller for the RV64GC-based SoC.

The PLIC manages external interrupts, while the DMA controller transfers data between memory addresses without requiring the CPU to handle every individual data transfer.

The system uses the existing 64-bit Wishbone architecture and is designed to allow DMA transfers to take place while keeping the CPU available for other tasks.

The project focuses on:

- Centralized interrupt management
- Multi-channel DMA transfers
- Descriptor-based transfers
- Wishbone bus arbitration
- Error handling
- Simulation and waveform verification

## 1. Project Architecture

The implementation is divided into several modules:

- PLIC: Manages external interrupt sources and interrupt priorities.
- DMA Controller: Configures and tracks multiple DMA channels.
- DMA Engine: Performs memory reads and writes through a 64-bit Wishbone interface.
- Descriptor Module: Provides descriptor-based transfer configuration.
- Bus Arbiters: Manage access to shared Wishbone resources.

The modules are integrated in "plic_dma.v".

This modular structure makes the design easier to test, maintain, and extend.

## 2. PLIC

The Platform-Level Interrupt Controller manages 32 external interrupt sources.

Its main features include:

- 32 interrupt sources
- Interrupt priorities
- Pending registers
- Interrupt enable registers
- Priority threshold
- Claim/complete mechanism

The PLIC allows software to identify and handle interrupts through a centralized interface instead of requiring every peripheral to implement its own complete interrupt-management system.

### Interrupt Handling

The interrupt-handling process consists of:

1. An external device raises an interrupt.
2. The PLIC records the pending interrupt.
3. The PLIC evaluates its priority and enable status.
4. The CPU claims the interrupt.
5. Software handles the interrupt.
6. The interrupt is completed through the claim/complete interface.

This provides the foundation for interrupt-driven peripheral operation.

## 3. DMA Controller

The DMA controller supports four channels for configuring and managing data transfers.

Each channel can be configuerd with transfer information such as:

- Source address
- Destination address
- Transfer length
- Control information
- Transfer status

The controller allows the CPU to configure a transfer and then continue executing other instructions while the DMA engine performs the data movement.

## 4. DMA Engine

The DMA engine performs the actual memory transfers through a 64-bit Wishbone interface.

Its responsibilities include:

- Reading data from source addresses
- Writing data to destination addresses
- Tracking transfer progress
- Handling bus responses
- Detecting transfer errors
- Reporting completion status

The DMA engine supports memory-to-memory transfers and is structured to support transfers involving peripherals.

## 5. Descriptor-Based Transfers

The descriptor module provides a way to configure transfers using descriptors rather than requiring the CPU to configure every individual operation directly.

A descriptor can contain information such as:

- Source address
- Destination address
- Transfer length
- Control flags
- Additional descriptor information

Descriptor-based operation provides a foundation for more advanced transfer sequences and future scatter-gather functionality.

## 6. Wishbone Integration

The DMA subsystem integrates with the existing 64-bit Wishbone architecture.

The DMA engine acts as a bus master when accesing memory, while its configuration interface allows the CPU to control DMA operation.

Because the CPU and DMA can request bus access independently, arbitration is required to prevent conflicting transactions.

The arbitration logic manages access between the CPU and DMA and between competing internal DMA requests.

The design must preserve correct transaction ordering and ensure that bus responses are associated with the appropriate request.

## 7. Error Handling

The implementation includes error handling for failed or invalid transfers.

The DMA subsystem must track unsuccessful bus transactions and report transfer failures through its status and control logic.

Error handling is important because a failed transfer must not leave a DMA channel permanently active or prevent other bus requests from progressing.

Future improvements may include more detailed error reporting, recovery mechanisms, and configurable timeout policies.

## 8. Simulation and Verification

The design was verified through simulation and waveform inspection using GTKWave.

The testbench covered the main functionality of the PLIC and DMA subsystem.

### PLIC Tests

- Interrupt source detection
- Pending status
- Interrupt priorities
- Interrupt enable behavior
- Claim/complete handling

### DMA Tests

- Memory-to-memory transfers
- Data reads and writes
- Four-channel configuration
- Descriptor-based transfers
- Transfer completion
- Error handling

### Integration Tests

The integrated testbench checked interactions between the PLIC, DMA controller, DMA engine, and bus arbitration logic.

All implemented tests passed.

GTKWave was used to inspect control signals, transfer progress, interrupt behavior, and error conditions.

Three useful waveform views for documenting the project are:

1. PLIC interrupt handling: Shows an interrupt becoming pending, being claimed, and subsequently completed.
2. DMA data transfer: Shows Wishbone read and write transactions during a memory copy.
3. Descriptor DMA: Shows descriptor-based operation together with completion interrupts and error handling.

These waveform captures can be added to the project documentation to demonstrate the behavior of the implemented modules.

## 9. Problems Encountered

### Bus Arbitration

Supporting both CPU and DMA bus requests introduces additional arbitration requirements.

The arbiter must only ensure that the selected master controls the shared bus and that requests are not accidentally lost or accepted more than once.

### DMA Transaction State

A DMA transfer consists of multiple dependent operations. The engine must preserve its current address, remaining transfer length, and state while waiting for Wishbone responses.

Incorrect state transitions can cause duplicated transfers, incorrect addresses, or incomplete operations.

### Descriptor Handling

Descriptor-based transfers introduce additional state and control requirements compared with a single memory copy.

The descriptor module and DMA engine must agree on when a descriptor is valid, when a transfer starts, and how completion or errors are reported.

### Interrupt Timing

The PLIC must correctly track pending interrupts and coordinate claim/complete operations.

Incorrect handling can result in repeated interrupts, missed events, or incorrect interrupt identification.

### Error Handling

Failed bus transactions must be handled without leaving the DMA engine or arbitration logic in an invalid state.

The error path must also preserve enough status information for software or the testbench to identify the failure.

## 10. Reflection

This project extended the SoC with two important capabilities: centralized interrupt management and hardware-controlled data movement.

The PLIC provides a structured way to manage external interrupts. As the number of peripherals grows, a centralized controller becomes increasingly useful because it separates interrupt prioritization and delivery from the individual peripheral implementations.

The DMA controller introduces a different improvement. Instead of requiring the CPU to perform every memory read and write, the CPU can configure a transfer and allow dedicated hardware to perform the data movement.

The project also demonstrated how system-level complexity increases when several independent components share a bus. Arbitration, transaction state, error reporting, and interrupt timing must all work together for the system to behave correctly.

Passing the implemented simulation tests provides confidence in the current design, but it does not establish that every possible arbitration sequence or future hardware integration scenario has been verified.

The design can therefore be treated as a functional foundation for further SoC development rather than a final, fully optimized DMA subsystem.

## 11. Future Improvements

Possible future improvements include:

- More advanced bus arbitration
- Improved fairness between competing masters
- More comprehensive timeout and recovery handling
- Full scatter-gather DMA support
- Additional DMA performance measurements
- Cache-coherence or explicit cache-maintenance support
- Integration with UART, SPI, Ethernet, USB, or SD/eMMC
- FPGA implementation and hardware verification
- More extensive randomized and stress testing

Cache maintenance is particularly important for future integration. Since DMA can access physical memory independently of the CPU:s L1 caches, software or hardware must ensure that cached data and memory contents remain consistent.

## 12. What's Next

The next step is to continue developing the SPI/QSPI Flash interface.

The goal is to add non-volatile storage to the SoC, providing a foundation for persistent firmware storage and future boot-from-flash functionality.

The SPI/QSPI interface will need to integrate with the existing bus architecture and account for the relationship between flash storage, the Boot ROM, and DDR memory.

This will move the project closer to a computer capable of loading software from persistent storage rather than relying only on code already present in ROM or RAM.
