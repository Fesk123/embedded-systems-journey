# SPI + QSPI Flash Controllers

## Goal

The goal of this project was to implement SPI and QSPI controllers for the future RV64GC-based computer system.

The controllers provide serial communication interfaces and a foundation for connecting external flash memory. This is particularly important for future firmware storage and boot-from-flash functionality.

The project contains two main modules:

- "SPI.v" – A configurable SPI master with a Wishbone register interface.
- "QSPI.v" – A QSPI controller designed for flash communication using command, address, dummy, and data phases.

The implementation also includes simulation testbenches for functional verification and waveform analysis using GTKWave.

The main objectives are to establish reliable serial communication, support configurable transfers, and prepare the storage interface for future integration with the SoC.

---

# 1. Project Overview

The project consists of:

- Configurable SPI master
- Configurable clock polarity and phase
- MSB-first and LSB-first transmission
- Transfer lengths from 1 to 64 bits
- Four chip-select outputs
- Wishbone-based SPI register access
- QSPI command and address phases
- QSPI dummy cycles
- QSPI data transmission and reception
- Transfer buffers supporting up to 64 bytes
- GTKWave waveform testbench
- Basic status and error handling

The SPI and QSPI controllers are separate modules because they serve related but different purposes.

SPI provides a general-purpose serial interface, while QSPI enables more efficient flash communication by using four data lines.

---

# 2. SPI Master

The SPI controller acts as a master and generates the clock and control signals required to communicate with an SPI peripheral.

The implementation supports:

- Configurable clock polarity ("CPOL")
- Configurable clock phase ("CPHA")
- MSB-first transmission
- LSB-first transmission
- Transfer lengths from 1 to 64 bits
- Four chip-select outputs
- Wishbone register interface

The controller is intended to support common SPI peripherals and provide a reusable serial communication interface for the SoC.

---

# 3. SPI Clock Configuration

SPI uses a clock signal to coordinate data transmission and reception.

Two configuration parameters determine the relationship between the clock and data.

### CPOL – Clock Polarity

"CPOL" determines the clock's idle level.

- "CPOL = 0": Clock idles low.
- "CPOL = 1": Clock idles high.

### CPHA – Clock Phase

"CPHA" determines which clock edge is used for sampling and shifting data.

Together, "CPOL" and "CPHA" provide the four standard SPI modes.

The controller must generate the correct clock behavior for the selected mode so that the master and peripheral agree on when data is sampled.

---

# 4. Data Ordering

The SPI master supports both common transmission orders.

### MSB First

The most significant bit is transmitted first.

### LSB First

The least significant bit is transmitted first.

The selected ordering determines how the controller shifts data during transmission and assembles received bits.

Correct handling is important because a mismatch between the controller and peripheral can result in the received data being reversed or interpreted incorrectly.

---

# 5. SPI Transfer Length

The SPI master supports configurable transfer lengths from 1 to 64 bits.

This allows the same controller to handle different peripheral protocols without requiring a separate hardware implementation for each transfer size.

The transfer logic must track:

- Configured transfer length
- Number of bits transmitted
- Number of bits received
- Current clock phase
- Transfer completion
- Chip-select state

The controller must terminate each transaction correctly, regardless of its configured length.

---

# 6. Chip Select

The SPI master provides four chip-select outputs.

These allow the controller to address multiple SPI peripherals independently.

The selected chip-select signal must remain active for the appropriate portion of the transaction and return to its inactive state when the transaction is complete.

Correct chip-select timing is particularly important for peripherals that interpret the end of a transaction as a command boundary.

---

# 7. Wishbone Register Interface

The SPI controller provides a Wishbone register interface.

This allows the CPU to configure and control SPI transactions through the existing SoC bus architecture.

The register interface provides the control boundary between software and the SPI hardware.

Depending on the implemented register map, the interface can be used to configure transfer parameters, provide data, start transfers, and read status.

The exact register addresses and bit assignments should be documented alongside the Verilog implementation.

---

# 8. QSPI Controller

The QSPI controller is designed for communication with flash memory using four data lines.

Unlike a conventional SPI transfer, QSPI can transfer multiple data bits during each clock cycle.

The controller supports the following transaction phases:

- Command
- Address
- Dummy cycles
- Data transmission
- Data reception

These phases allow the controller to support flash operations that require an opcode, an address, an optional wait period, and a data transfer.

The exact command sequences and timing requirements depend on the flash device and protocol configuration.

---

# 9. QSPI Transaction Phases

A QSPI flash transaction commonly consists of several phases.

### Command Phase

The controller sends the opcode that identifies the requested flash operation.

### Address Phase

For operations targeting a memory location, the controller sends the address of the data to access.

### Dummy Phase

Some flash commands require additional clock cycles between the address and data phases.

The controller must generate the configured dummy cycles before continuing.

### Data Phase

The controller transmits data to the flash or receives data from it.

The direction and timing of the data lines depend on the selected operation.

---

# 10. QSPI Data Lines

QSPI uses four data lines for communication.

Depending on the current transaction phase, the lines may be used for output, input, or bidirectional data transfer.

The controller must therefore coordinate:

- Data output
- Data input
- Data-line direction
- Clock generation
- Transaction phase
- Transfer length

Incorrect direction control can cause data corruption or electrical contention when used with physical hardware.

This behavior therefore requires careful verification before connecting the controller to a real flash device.

---

# 11. QSPI Transfer Buffers

The QSPI controller includes buffers for transfers of up to 64 bytes.

These buffers allow the controller to manage larger data transfers without requiring a separate control operation for every individual byte.

The buffer logic must track the number of bytes transferred and correctly distinguish between transmission and reception.

The maximum buffer capacity is 64 bytes per supported transfer buffer.

The buffer size does not, by itself, guarantee continuous high-speed flash access. Overall performance also depends on the flash protocol, clock frequency, transaction overhead, and how quickly the surrounding system can provide or consume data.

---

# 12. Flash Communication

The QSPI controller is intended to support communication with external flash memory.

Possible future applications include:

- Reading firmware
- Loading software images
- Reading configuration data
- Accessing stored resources
- Supporting a future boot-from-flash process

However, the current implementation has not been verified against a specific physical flash device.

Command compatibility, supported operating modes, timing requirements, and initialization sequences must be checked against the datasheet of the selected flash chip before hardware integration.

---

# 13. Problems Encountered

## SPI Clock and Data Timing

SPI depends on the relationship between the clock edges and data sampling.

Incorrect "CPOL" or "CPHA" handling can cause bits to be sampled at the wrong time.

The controller therefore needs to maintain consistent timing for all four SPI modes.

## QSPI Data-Line Direction

QSPI is more complicated than standard SPI because four data lines are used and their direction can change during a transaction.

The controller must switch between transmitting and receiving without allowing conflicting output drivers or sampling data at incorrect times.

This is especially important when moving from simulation to physical hardware.

## Longer Transfers

Handling longer transfers requires careful management of buffers, counters, and completion conditions.

Incorrect counter updates or buffer indexing can result in truncated transfers, duplicated data, or incorrect transaction termination.

## Error Handling

Serial devices may not respond as expected, and a transaction may fail to complete correctly.

The controller needs clear status and error behavior so that software can determine whether an operation succeeded.

A failed or incomplete transaction must not leave the controller permanently busy.

## SoC Integration

A standalone SPI or QSPI controller can be tested independently, but integration introduces additional requirements.

The controller must work correctly with the Wishbone register interface, the system address map, and the software that configures its operations.

Large transfers will also require an efficient method of supplying and consuming data.

---

# 14. Reflection

This project established a foundation for serial communication and external flash storage in the future RV64GC computer.

The SPI master introduced configurable serial communication with support for multiple clock modes, transfer lengths, bit ordering, and chip-select outputs.

The QSPI controller required more complicated control logic because flash transactions contain distinct command, address, dummy, and data phases. Four data lines also introduce additional direction and timing requirements.

The testbenches are important because serial communication depends on exact signal timing. Inspecting waveforms makes it possible to examine not only the final data but also the clock edges, state transitions, buffer operations, and data-line behavior that produced it.

The project also highlighted the difference between a controller that works in simulation and one that has been verified with real hardware. Simulation can verify the implemented digital behavior, but it cannot establish electrical compatibility or timing compliance with a particular flash device.

The current implementation should therefore be viewed as a foundation for future flash integration rather than a fully validated physical storage interface.

The next major challenge is connecting flash transfers efficiently to the memory system so that larger software images can be loaded without creating unnecessary bottlenecks.

---

# 15. Future Improvements

Possible future improvements include:

- Verification with a specific physical flash device
- FPGA implementation
- Flash identification and initialization
- Additional flash commands
- More robust timeout and error reporting
- XIP (Execute In Place)
- Cache-line prefetching
- DMA integration
- Efficient transfers to DDR
- Boot firmware loading
- Performance benchmarking

### Execute In Place (XIP)

XIP allows a processor to execute code directly from flash rather than first copying the entire code image into RAM.

Implementing XIP would require an appropriate memory-mapped access mechanism and integration with the processor's instruction-fetch and cache paths.

The current QSPI command controller is a foundation for this work, but XIP is not established by the current implementation alone.

### Cache-Line Prefetching

Cache-line prefetching could improve instruction and data access performance when flash is used as an execution or storage source.

This would require coordination between the QSPI interface, cache controller, physical memory access path, and the expected response latency.

### DMA and DDR Integration

DMA could later be used to move larger blocks of data from flash into DDR without requiring the CPU to copy every word.

This would require a suitable connection between the QSPI transfer engine, the DMA architecture, and the Wishbone interconnect.

---

# 16. What's Next

The next step is to implement I/O and Debug Support for the RV64GC-based SoC.

The goal is to make the computer easier to interact with, test, and debug by providing accessible input/output interfaces and better visibility into the processor's internal state.

The project will focus on:

- UART serial console for communication with the computer and outputting debug messages.
- GPIO for connecting external inputs and outputs, such as buttons, switches, and LEDs.
- Memory-mapped I/O for configuring and accessing peripherals through the Wishbone interconnect.
- Interrupt integration to allow I/O peripherals to notify the CPU through the PLIC as that subsystem is integrated.
- Debug and status registers for monitoring system state, errors, and peripheral activity.
- CPU debugging support for inspecting relevant processor state and diagnosing execution problems.
- FPGA testing preparation for making the system easier to observe and control on physical hardware.

The existing UART and GPIO implementations can be reused and adapted to the current RV64GC-based SoC rather than rebuilt from scratch.

The main objective is to establish a reliable way to communicate with the computer and investigate problems without depending exclusively on simulation waveforms.

This will be particularly important during FPGA testing, where serial output, external I/O, and accessible debug information will help identify problems in the processor, memory system, and peripheral integration.
