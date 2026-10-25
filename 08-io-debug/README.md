# I/O + Debug

## Goal

The goal of this project is to add basic input/output functionality and hardware debugging support to the RV64GC-based SoC.

The project provides memory-mapped peripherals for communication and external control, together with a debug architecture intended to allow the processor to be inspected and controlled during development.

The main objectives are:

- Provide UART communication for terminal access and diagnostic output.
- Add GPIO for external digital inputs and outputs.
- Provide timer functionality and time-related interrupts.
- Record processor execution information for later analysis.
- Implement a Wishbone interconnect for memory-mapped I/O.
- Establish a JTAG-based debug transport using the Debug Module Interface (DMI).
- Support processor halt, resume, register access, and memory access.
- Prepare the system for debugging on the target FPGA.

The project is designed to make the SoC easier to operate, test, and debug without relying exclusively on simulation waveforms.

---

## 1. Project Architecture

The project is divided into several modules, each responsible for a specific part of the I/O or debugging system.

### I/O Modules

- debug_uart.v — UART communication for terminal access and diagnostic output.
- debug_gpio.v — Digital input and output for external devices such as buttons, switches, and LEDs.
- debug_timer.v — Timer functionality, including support for machine-mode timer interrupts.
- debug_io_interconnect.v — Wishbone address decoding for memory-mapped I/O peripherals.

### Debug Modules

- debug_trace.v — Ring buffer for recording instruction execution and program-flow information.
- debug_transport.v — JTAG transport and communication with the debug system through DMI.
- debug_registers.v — Debug control and status registers.
- debug_module.v — Core debug functionality, including halt/resume control, register access, and program buffer support.
- debug_bus_access.v — Separate Wishbone master for debugger access to system memory.
- debug_system.v — Integrates the debug module, JTAG transport, and system bus access.

---

## 2. Memory-Mapped I/O

The CPU accesses the UART, GPIO, and timer through memory-mapped registers.

Each peripheral occupies a defined address range in the physical SoC memory map.

Software can interact with these devices using ordinary load and store instructions, provided that the relevant addresses are mapped and the processor's access permissions allow the operations.

The Wishbone interconnect routes each request to the appropriate peripheral.

The I/O implementation must correctly handle:

- Address decoding
- Read and write requests
- Register access
- Wishbone acknowledgements
- Invalid addresses
- Peripheral status
- Access latency

The address map must be consistent with the SoC's existing memory map.

---

## 3. UART Debug Console

The UART provides a simple communication channel between the computer and an external terminal.

Its intended uses include:

- Diagnostic output
- Boot messages
- Error reporting
- Software interaction
- Basic console functionality

The UART is accessed through memory-mapped registers.

Software can write characters to the transmit interface and read incoming characters from the receive interface, depending on the implemented register interface.

The UART is particularly important during FPGA testing because it can expose useful system information without requiring a graphical display.

The existing UART implementation should be reused where possible rather than rebuilt unnecessarily.

---

## 4. GPIO

The GPIO module provides configurable digital inputs and outputs.

Possible applications include:

- Reading external switches
- Reading buttons
- Controlling LEDs
- Monitoring simple external signals
- Testing the processor's physical I/O connections

The CPU accesses GPIO registers through the Wishbone interconnect.

The implementation should distinguish between input values, output values, and any configuration or status registers provided by the design.

GPIO is useful during early FPGA testing because it provides a simple way to verify that the processor can communicate with external hardware.

---

## 5. Timer

The timer module provides time-related functionality for the processor.

It is intended to support machine-mode timer operation and provide the basis for periodic interrupts.

The timer must expose the appropriate registers and signals required by the processor's interrupt architecture.

For compatibility with the RISC-V privileged architecture, the implementation should account for the machine timer registers and interrupt behavior expected by the chosen system design.

The timer must be integrated with the CPU's interrupt and trap logic.

A timer module alone does not guarantee that timer interrupts work correctly: the processor must also implement the corresponding interrupt enable, pending, delegation, and trap-handling behavior required by its supported privilege architecture.

---

## 6. Debug Trace

The trace module provides a ring buffer for storing information about processor execution.

The purpose is to make it possible to inspect recent execution activity after a problem occurs.

Depending on the available signals and implementation, trace records can contain information such as:

- Program counter
- Instruction word
- Instruction completion
- Branch or jump information
- Exception or trap events
- Relevant debug status

A ring buffer retains a limited history of recent events by overwriting older entries when it becomes full.

This is useful when investigating unexpected control flow, incorrect instruction execution, or failures that occur before the system can report an error through UART.

The trace interface must be connected to signals that accurately represent the processor's execution state.

---

## 7. JTAG and DMI Transport

The debug transport provides the communication path between an external debugger and the on-chip debug logic.

The intended interface uses JTAG for physical transport and the Debug Module Interface (DMI) for accessing debug registers.

An external debugging tool can use this interface to issue debug requests and inspect the processor.

The design is intended to provide a foundation for integration with tools such as OpenOCD and GDB.

However, implementing JTAG and DMI signals alone does not guarantee compatibility with these tools. The transport, register map, debug module, and CPU debug behavior must follow the applicable RISC-V Debug Specification.

---

## 8. Debug Registers

The debug register module provides control and status information for the debug system.

Its responsibilities include exposing the state needed to coordinate debug operations.

Depending on the implemented debug architecture, this can include:

- Debug control
- Halt status
- Resume status
- Command status
- Register access control
- Program buffer control
- Debug operation completion
- Error status

The register layout and supported operations must match the debug module's implementation and the requirements of the external debugging software.

The debug registers should be verified independently before integrating the complete JTAG-to-CPU debug path.

---

## 9. Debug Module

The debug module implements the central control logic for processor debugging.

Its intended functions include:

- Requesting that the CPU halt
- Detecting when the CPU has entered debug mode
- Requesting that execution resume
- Accessing CPU registers
- Executing supported debug operations
- Providing program buffer functionality

The module must coordinate with the processor's five-stage pipeline.

Halting a pipelined CPU is more complicated than stopping a single-cycle processor because several instructions may be in different execution stages simultaneously.

The design must define how outstanding instructions and memory transactions are handled when a halt request is received.

The processor must also preserve enough state to resume execution correctly.

---

## 10. CPU Debug Integration

The debug module cannot independently guarantee correct debugging unless the RV64GC processor implements the required CPU-side behavior.

The processor must provide suitable support for operations such as:

- Entering Debug Mode
- Halting at a defined execution boundary
- Preserving architectural state
- Reading and writing general-purpose registers
- Resuming execution
- Handling debug-related exceptions and control flow
- Coordinating outstanding pipeline operations

The implementation must also distinguish debug entry from ordinary architectural traps and interrupts.

If the current CPU does not yet implement all required debug functionality, the integration should be treated as an incremental development task rather than assuming that the external debugger can already control the processor.

---

## 11. Debug Bus Access

The debug_bus_access.v module provides a separate Wishbone master for debugger access to system memory.

This allows the debug system to request memory operations independently of the CPU's normal instruction execution.

Potential uses include:

- Reading memory contents
- Writing memory contents
- Inspecting program data
- Examining software state
- Supporting debug commands that require system-bus access

The debugger's bus access must be integrated with the existing Wishbone interconnect.

The implementation must ensure that debug requests do not corrupt active CPU or DMA transactions.

The exact memory-access mechanism must also be compatible with the selected debug architecture.

---

## 12. Bus Arbitration

The CPU, DMA subsystem, and debugger may all need access to shared system resources.

The Wishbone arbitration logic must therefore manage competing requests.

The design should aim for fair access while ensuring that one master cannot permanently prevent another from making progress.

The arbitration mechanism must preserve transaction correctness, including:

- Correct request selection
- Correct response routing
- Handling of outstanding transactions
- Wait states
- Error responses
- Reset behavior

Debug functionality should not unnecessarily interfere with normal processor execution.

At the same time, debug requests must not be starved indefinitely when access is required to diagnose a system failure.

---

## 13. Cache Consistency and Debug Memory Access

One of the most important integration challenges is maintaining consistency between debugger memory accesses and the CPU's L1 caches.

The debugger's Wishbone master accesses the system memory path independently of the CPU's normal load and store operations.

If the debugger writes to DDR while the CPU holds a cached copy of the same memory location, the cache may continue to contain stale data.

Similarly, dirty cache lines may later overwrite data that the debugger has modified directly in memory.

The system must therefore define how debug memory accesses interact with cached memory.

Possible approaches include:

- Restricting certain debug operations while the CPU is running
- Halting the CPU before memory modification
- Using explicit cache maintenance operations
- Providing a suitable cache-coherence mechanism
- Restricting direct bus access to regions that do not require cache coherence

The appropriate solution depends on the cache architecture and the supported debug operations.

A separate debug Wishbone master does not automatically make cached memory accesses coherent.

---

## 14. Problems Encountered

### Pipelined CPU Halt and Resume

The five-stage pipeline may contain multiple in-flight instructions when a halt request arrives.

The design must determine when the CPU can safely enter Debug Mode and how it will preserve architectural state.

If pipeline control is incorrect, instructions may be lost, executed twice, or partially completed.

### Debug Command Handling

Debug commands must be decoded and executed consistently.

The debug module must distinguish valid requests from unsupported commands and report completion or errors correctly.

Incorrect command sequencing can leave the debug interface waiting indefinitely or produce inconsistent state.

### Register Access

External register access requires coordination between the debug transport, debug module, and processor register file.

The implementation must prevent debug accesses from interfering with ordinary CPU operations.

### Wishbone Arbitration

The debugger introduces another possible bus master.

Arbitration must correctly handle requests from the CPU, DMA, and debugger without losing transactions or routing responses to the wrong requester.

### Cache Consistency

Direct debugger writes to DDR can conflict with data held in the L1 caches.

Without an explicit cache-maintenance or coherence strategy, software may observe stale data or later overwrite debugger modifications.

### OpenOCD and GDB Compatibility

OpenOCD and GDB expect specific debug behavior and register conventions.

A working internal testbench is not sufficient to establish compatibility with these tools.

The complete transport, debug module, CPU integration, and supported debug features must be validated against the relevant RISC-V debug requirements.

### FPGA Integration

Simulation cannot fully verify the physical JTAG interface, board-level signal connections, clocking, or the interaction with the target FPGA's debug infrastructure.

These aspects require hardware testing once the relevant implementation is connected to the FPGA platform.

---

## 15. Reflection

This project extends the SoC beyond processor execution and memory access by adding practical ways to interact with and diagnose the system.

UART and GPIO provide accessible external I/O, while the timer supports time-related operations and interrupt-driven behavior.

The debug architecture introduces a more complex challenge because it must interact with a processor that already contains a five-stage pipeline, caches, virtual memory, and a shared system bus.

The debug module cannot be treated as an independent peripheral alone. Correct processor halt, resume, register access, and memory access require cooperation between the debug transport, CPU control logic, memory system, and bus arbitration.

Cache consistency is particularly important because direct memory access by the debugger can conflict with the CPU's cached state. This demonstrates that debugging support must be designed as part of the complete computer architecture.

The implementation provides a foundation for more accessible FPGA testing, but successful simulation does not automatically demonstrate complete OpenOCD/GDB compatibility or correct operation on physical hardware.

Those capabilities require dedicated integration tests and, eventually, testing with the selected FPGA platform and debugging tools.

---

## 16. Future Improvements

Possible future improvements include:

- Full OpenOCD integration
- GDB remote debugging
- Verification against the RISC-V Debug Specification
- Improved trace functionality
- More detailed exception and interrupt tracing
- Breakpoints and watchpoints
- Additional debug commands
- Improved bus arbitration
- Explicit cache-maintenance support for debug memory access
- FPGA-based JTAG verification
- UART console testing on hardware
- GPIO testing with physical inputs and outputs
- Automated regression tests for debug operations

The scope of future work depends on which debug features are already implemented and which still require CPU-side support.

---

## 17. What's Next

The next project is SD/eMMC Storage Support.

The goal is to implement storage interfaces that allow the RV64GC computer to read and write data using an SD card or eMMC device. This is an important step toward booting a complete operating system and providing persistent storage for Linux, applications, and user files.

Planned features include:

- SD card communication and initialization.
- SD/eMMC controller logic and command handling.
- Data transfer between the storage device and the SoC.
- Wishbone interface for CPU access to storage-controller registers.
- Status reporting and error handling.
- Integration with the existing I/O and debug infrastructure.
- Simulation and waveform-based verification.

The initial focus will be on implementing and verifying the controller logic in simulation. Physical SD card testing can follow when the relevant FPGA interfaces and hardware connections are available.

Goal: Give the RV64GC computer persistent storage, providing a foundation for loading software and eventually booting Linux from an SD card or eMMC device.
