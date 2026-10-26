# SD/eMMC Storage Interface

## Overview

The SD/eMMC project introduces storage support for the RV64GC computer by connecting the processor to the existing microSD controller in the KV260's Processing System (PS).

Instead of implementing a complete SD card controller in Verilog, this design uses a hardware-software bridge between the RV64GC SoC and the PS. The PS software will handle SD card operations using the existing platform capabilities, while the RV64GC processor communicates with the bridge through its Wishbone bus.

The initial implementation focuses on microSD card support because the KV260 Starter Kit provides a microSD card slot but does not include built-in eMMC storage.

The long-term goal is to allow the RV64GC computer to load programs, access files, and eventually use SD storage as part of its own Linux system.

## Project Goals

- Connect the RV64GC SoC to the KV260's existing microSD functionality.
- Provide a Wishbone interface for storage requests from the processor.
- Bridge storage requests between the programmable logic (PL) and the Processing System (PS).
- Use AXI4-Lite for communication between the PL-side bridge and PS software.
- Implement request and completion FIFOs.
- Provide status registers and interrupt signalling.
- Support shared DDR memory for storage data.
- Establish a foundation for loading software and accessing files from an SD card.

## Architecture

### 1. SD/eMMC Bridge ("sd_emmc.v")

The main module connects the RV64GC processor's Wishbone interface to the PS-side storage service.

Its responsibilities include:
- Accepting storage requests from the RV64GC SoC.
- Passing requests to the PS software through the AXI4-Lite interface.
- Reporting operation status and completion.
- Handling errors and request timeouts where implemented.
- Coordinating access to shared buffers in DDR memory.

The bridge avoids the need to implement the complete SD card protocol in the programmable logic.

### 2. Request and Completion FIFOs ("sd_emmc_fifo.v")

The FIFO module provides queues for storage requests and their completion results.

The queues separate the processor's request generation from the PS software's processing of those requests.

Planned responsibilities include:
- Buffering pending read and write requests.
- Tracking completed operations.
- Preventing requests from being overwritten before they are handled.
- Reporting full and empty conditions.
- Supporting safe coordination between the hardware interface and software service.

The exact FIFO depth and behaviour depend on the implementation.

### 3. Wishbone Interface

The Wishbone interface allows the RV64GC processor to access the storage bridge.

The processor can use the interface to:
- Submit read and write requests.
- Specify storage addresses and transfer lengths.
- Access controller status.
- Check whether operations have completed.
- Handle errors reported by the storage subsystem.

The Wishbone interface provides a consistent connection to the existing SoC interconnect.

### 4. AXI4-Lite Interface

The AXI4-Lite interface connects the programmable-logic bridge to software running on the KV260's Processing System.

The intended communication flow is:

1. The RV64GC processor submits a storage request.
2. The bridge places the request in a queue.
3. PS software retrieves the request through the AXI4-Lite interface.
4. The PS software performs the SD card operation using the existing platform driver.
5. The software reports the result to the bridge.
6. The bridge makes the completion status available to the RV64GC processor and signals an interrupt when appropriate.

AXI4-Lite is intended for control and status communication. It is not designed to carry large storage payloads efficiently.

### 5. Shared DDR Memory and Data Transfers

Storage data should be transferred through shared DDR memory rather than through the control registers.

This allows larger blocks of data to move between the SD card, the Processing System, and the RV64GC SoC without requiring every byte to pass through the request interface.

A separate data-transfer path between the programmable logic and DDR memory is still required.

Important considerations include:
- Correct buffer addresses and transfer lengths.
- Access permissions and memory ownership.
- Coordination between the PS and the RV64GC processor.
- Cache flushing and invalidation where necessary.
- Completion reporting and error recovery.
- Avoiding conflicts between simultaneous memory accesses.

The exact transfer mechanism will depend on the selected AXI and DDR integration.

## Hardware-Software Interface

The design separates storage control from storage execution.

RV64GC processor:
- Submits storage requests over Wishbone.
- Reads status and completion information.
- Handles completion interrupts when integrated.
- Uses the returned data for program loading and file access.

Programmable logic:
- Buffers requests and completion results.
- Bridges Wishbone requests to the PS-facing interface.
- Exposes control and status registers.
- Coordinates the data-transfer mechanism.

Processing System:
- Runs the software service responsible for processing requests.
- Uses the existing platform SD driver.
- Performs SD card reads and writes.
- Reports operation results to the programmable logic.

This approach reuses the KV260's existing storage capabilities instead of recreating the entire SD controller.

## Current Implementation

The project defines the hardware-software bridge required to connect the RV64GC SoC to the KV260's storage functionality.

The main design components are:
- "sd_emmc.v": main storage bridge.
- "sd_emmc_fifo.v": request and completion queues.
- Wishbone interface: processor-side access.
- AXI4-Lite interface: PS-side control and status communication.
- Status and interrupt signalling.
- Planned shared-DDR data-transfer path.

The existence of these modules does not by itself establish that the complete storage system is operational. Full functionality depends on the PS software, DDR data path, and integration with the existing SoC.

## Challenges

### Hardware-Software Coordination

The RV64GC processor and PS software operate through separate interfaces. Requests must be transferred reliably, processed in the correct order, and matched with their corresponding results.

### Data Transfer Performance

Passing large data blocks through control registers would create unnecessary overhead. A separate DDR data path is needed for efficient transfers.

### Cache Consistency

The PS and RV64GC subsystem may access the same DDR buffers. If either side caches the data, stale or dirty cache lines can cause incorrect results unless cache maintenance or an appropriate coherent-access mechanism is used.

### Interrupt Integration

The bridge must notify the processor when operations complete or fail. This requires correct status handling and integration with the SoC's interrupt architecture.

### Error Handling

The design must handle invalid requests, failed SD operations, unavailable resources, and incomplete transfers without leaving the processor waiting indefinitely.

### Platform Integration

The PS software must be able to access the bridge and use the KV260 platform's existing SD driver. The hardware interfaces, address mappings, and software configuration must agree.

## Verification and Testing

The project should be verified in stages.

### RTL Simulation
- Test Wishbone register reads and writes.
- Verify request FIFO behaviour.
- Verify completion FIFO behaviour.
- Test request acceptance and completion.
- Test status updates and error reporting.
- Check interrupt signalling.
- Inspect timing and handshakes in GTKWave.

### PS Software Testing
- Verify that software can retrieve requests.
- Test SD card initialization.
- Test block reads and writes.
- Verify that completion results are returned correctly.
- Test error conditions and timeouts.

### DDR Data-Path Testing
- Verify data transfers between the PL and DDR memory.
- Check buffer addressing and transfer lengths.
- Test cache-maintenance requirements.
- Confirm that transferred data is correct.

### Full SoC Integration
- Submit storage requests from the RV64GC processor.
- Read data from an SD card into DDR.
- Write data from DDR to an SD card.
- Verify interrupt delivery and error handling.
- Test the interface on the KV260 hardware.

Passing RTL simulation alone does not establish that the PS software, DDR data path, and physical SD card are fully operational.

## Current Limitations

- The initial target is microSD card support, not built-in eMMC storage.
- PS software for executing storage requests remains necessary.
- A dedicated AXI data-transfer path between the PL and DDR must be completed.
- Full integration with the RV64GC SoC remains necessary.
- Cache consistency must be addressed before sharing data buffers between subsystems.
- Booting Linux from the SD card requires additional boot, firmware, and software integration.

## Future Improvements

Potential improvements include:
- Direct block transfers between the SD subsystem and DDR.
- More efficient request scheduling.
- Multiple outstanding requests, if supported by the software and hardware interfaces.
- Improved error recovery and timeout handling.
- Integration with the boot process.
- Support for additional storage interfaces where suitable hardware is available.

## What's Next

The next project is Ethernet Networking.

The goal is to give the RV64GC computer network connectivity, allowing it to communicate with other devices over a wired Ethernet connection. This is an important step toward downloading software, accessing network services, and eventually using the computer as a more complete Linux-capable system.

Planned features include:
- Ethernet MAC interface for transmitting and receiving frames.
- Integration with the existing SoC interconnect.
- Access to Ethernet controller registers through a memory-mapped interface.
- Transmit and receive buffering.
- DMA support for transferring packet data between the Ethernet subsystem and DDR memory, where appropriate.
- Interrupt signalling for packet events and errors.
- Hardware and software integration for network communication.
- Simulation and verification of packet transmission, reception, and error handling.

The initial focus will be on implementing and verifying the Ethernet interface and its connection to the SoC. Integration with a suitable Ethernet PHY and the KV260's available hardware interfaces will be addressed as part of hardware testing.
