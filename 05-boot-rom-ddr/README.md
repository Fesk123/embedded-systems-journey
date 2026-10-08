# Boot ROM + DDR

## Goal

The goal of this project is to implement the next part of the memory architecture for the RV64GC computer: a Boot ROM for startup code and a DDR memory controller for the main memory system.

The project builds on the previously developed architecture, including:

- RV64GC processor
- Sv39 MMU and TLB
- L1 instruction and data caches
- 64-bit Wishbone interconnect
- SoC memory architecture
- Planned PLIC and DMA functionality

The purpose of this project is to give the CPU a defined starting point after reset and provide a much larger physical memory backend.

The main components are:

- 16 KiB Boot ROM
- Boot/reset code
- DDR initialization handling
- DDR status register
- Boot transfer from ROM to DDR
- Wishbone slave interface for the Boot ROM
- 64-bit DDR datapath
- 512 MiB DDR address space
- Burst transfers
- Byte enables
- Read/write latency
- Periodic DDR refresh
- Timeout and error handling
- Simulated DDR memory model
- Generic DDR command/PHY interface for future FPGA implementation

---

## 1. Memory Architecture

The Boot ROM and DDR controller are integrated into the existing physical memory system.

The intended memory path is:

RV64GC
   
   ↓

Sv39

   ↓

L1 I/D Cache

   ↓

Wishbone

   ↓

Boot ROM / DDR Controller

   ↓

DDR RAM


Sv39 translates virtual addresses into physical addresses, while the cache hierarchy handles frequently accessed data and instructions before requests reach the physical memory system.

The Boot ROM and DDR controller therefore operate on the physical side of the memory architecture.


## 2. Boot ROM

The Boot ROM provides a fixed region of memory containing the first code executed after reset.

The ROM contains:

16 KiB

of storage.

Its main purpose is to:

Provide reset/boot code
Check DDR initialization status
Wait until DDR is ready
Transfer execution to code located in DDR

The Boot ROM is intentionally kept small so that it can be used as a simple and reliable first-stage boot environment.


## 3. Reset and Boot Process

After reset, the processor starts executing from the configured Boot ROM address.

The boot process is:

Reset

  ↓
  
Start execution from Boot ROM

  ↓
  
Check DDR status

  ↓
  
Wait while DDR is initializing

  ↓

DDR becomes ready

  ↓
  
Jump to DDR entry point

  ↓
  
Continue execution from DDR


This provides a deterministic startup sequence.

The Boot ROM therefore acts as the first stage of the software execution environment.


## 4. DDR Initialization

DDR memory requires initialization before it can be used normally.

The DDR controller therefore has an initialization process that runs after reset.

The controller keeps track of its initialization state and exposes this state to the Boot ROM.

The basic states are:

Reset

  ↓
  
Initialization

  ↓
  
Ready


The Boot ROM must not transfer execution to DDR until the controller reports that the memory system is ready.


## 5. DDR Status Register

The DDR controller provides a status register that allows the boot code to determine whether initialization has completed.

The status information can include:

- Initialization state
- Ready state
- Error state

The boot code can therefore perform a simple polling loop:

while DDR is not ready:
    wait

continue boot

This keeps the initial boot implementation simple while allowing the DDR controller to perform its own initialization.


## 6. Boot Transfer to DDR

Once DDR initialization is complete, the Boot ROM transfers execution to a predefined DDR entry address.

The sequence is:

Boot ROM

   ↓
   
DDR ready

   ↓
   
Load/prepare DDR entry point

   ↓
   
Jump to DDR


After this point, normal software can execute from DDR rather than from the small Boot ROM.

This creates the basic foundation for loading larger firmware and eventually operating-system software.


## 7. Boot ROM Wishbone Interface

The Boot ROM is connected to the existing Wishbone interconnect through a Wishbone slave interface.

This allows the CPU to access the ROM using the same bus architecture used by the other memory and peripheral devices.

The interface supports the normal Wishbone transaction signals required for instruction and memory accesses.

The ROM itself does not initiate bus transactions.


## 8. Boot ROM Memory Mapping

The Boot ROM occupies a dedicated physical address range in the SoC memory map.

A conceptual example is:

Boot ROM:
0x0000_0000 – 0x0000_3FFF

This corresponds to:

16 KiB

The exact address can be changed later if the final SoC memory map requires a different location.


## 9. DDR Controller

The DDR controller provides the main memory backend of the system.

The implementation uses:

64-bit datapath
512 MiB addressable DDR memory

The controller converts Wishbone memory transactions into operations on the DDR memory model and provides the interface required for a future physical DDR implementation.


## 10. 64-bit Datapath

The DDR controller uses a 64-bit data path to match the RV64GC processor and the rest of the 64-bit memory architecture.

A single transfer contains:

64 bits = 8 bytes

This is also well suited to the L1 cache hierarchy, where cache lines are transferred using multiple 64-bit beats.


## 11. DDR Address Space

The simulated DDR system provides:

512 MiB

of addressable memory.

This gives the processor a substantially larger working-memory region than the Boot ROM.

The exact physical base address of the DDR region is determined by the final SoC memory map.


## 12. DDR Read and Write Operations

The controller supports both:

- Read
- Write

operations.

A simplified read transaction is:

Wishbone request -> DDR controller -> DDR read operation -> Read latency -> Data returned -> Wishbone ACK

A write follows the same general structure but transfers data into memory.


## 13. Burst Transfers

The DDR controller supports burst transfers.

This is important because the L1 caches use burst transactions for cache-line refills and writebacks.

With:

64-byte cache line
64-bit datapath

a complete cache line consists of:

8 × 64-bit transfers

The DDR controller must therefore be able to process multiple consecutive data beats as part of a larger transaction.


## 14. Byte Enables

The 64-bit interface supports byte enables.

The controller uses:

SEL[7:0]

to determine which bytes in a 64-bit transfer are active.

This allows smaller accesses to be represented correctly even though the memory datapath is 64 bits wide.

The mechanism supports accesses such as:

- Byte
- Halfword
- Word
- Doubleword

were appropriate.


## 15. Read and Write Latency

The DDR controller models non-zero memory latency.

A memory request can therefore remain active for multiple cycles before the result is available.

For example:

Request

   ↓
   
Wait

   ↓
   
Wait

   ↓
   
Data / completion


This provides a more realistic memory model than a simple zero-latency RAM.

The controller must maintain the transaction state correctly throughout the waiting period.


## 16. DDR Refresh

DDR memory requires periodic refresh operations.

The controller therefore includes a refresh mechanism that periodically pauses normal memory activity to perform the necessary refresh operation.

The controller must ensure that refreshes do not interfere incorrectly with active reads, writes, or bursts.

The internal control logic therefore has to distinguish between:

- Normal memory access
- Refresh

and return to normal operation after the refresh is complete.


## 17. DDR Controller State Machine

The controller uses internal state to keep track of initialization and memory operations.

A simplified state structure is:

- RESET
- INIT
- READY
- READ
- WRITE
- BURST
- REFRESH
- TIMEOUT
- ERROR

Additional states may be used where necessary for individual implementation details.

The state machine is responsible for coordinating:

- Wishbone requests
- DDR operations
- Latency
- Burst transfers
- Refresh
- Error handling
- Completion


## 18. Timeout Handling

The DDR controller includes timeout handling so that a transaction cannot remain active indefinitely.

A simplified sequence is:

Memory request -> Wait for completion
      
ACK → successful transaction

ERR → failed transaction

Timeout → controller error


This is especially important when the controller is later connected to a real memory PHY.


## 19. Error Handling

Memory-system errors must be reported through the Wishbone interface.

A successful transaction results in:

ACK

while a failed transaction can result in:

ERR

The CPU or other Wishbone master can then handle the resulting error through the existing system architecture.

The controller must avoid returning invalid data as if a failed transaction had completed successfully.

20. Simulated DDR Model

The current DDR implementation is intended to be tested in simulation.

A simulated DDR model provides a controlled environment where the following can be tested:

- Memory reads
- Memory writes
- Burst transfers
- Byte enables
- Read/write latency
- Initialization
- Refresh
- Errors
- Timeouts

This makes it possible to verify the controller before connecting it to physical DDR hardware.

## 21. Generic DDR Command / PHY Interface

The DDR controller is separated from the physical DDR implementation through a generic command/PHY interface.

The structure is conceptually:
 
Wishbone -> DDR Controller -> Generic DDR Command / PHY Interface -> Physical DDR

The purpose of this separation is to keep the main controller logic independent of the specific FPGA and DDR hardware used later.

The generic interface can eventually be adapted to the PHY provided by the selected FPGA platform.

## 22. Integration with Sv39

The DDR controller operates on physical addresses.

The full memory path is therefore:

Virtual Address -> Sv39 Translation -> Physical Address -> L1 Cache -> Wishbone -> DDR Controller -> DDR


The DDR controller does not perform virtual-address translation itself.

This keeps the responsibilities of the memory hierarchy separated.

## 23. Integration with L1 Cache

The L1 caches sit between the CPU and the DDR controller.

A cache hit can be completed without accessing DDR.

A cache miss can cause a Wishbone burst to travel through the DDR controller.

For example:

CPU load

   ↓
   
L1 D-Cache

   ↓
   
Miss

   ↓
   
Wishbone burst

   ↓
   
DDR Controller

   ↓
   
DDR

   ↓
   
Cache refill

   ↓
   
CPU


The same general mechanism applies to instruction-cache refills.

## 24. Integration with Other SoC Components

The overall SoC will eventually contain additional components such as:

- PLIC
- DMA
- SPI/QSPI
- UART
- GPIO
- Other peripherals

These components are part of the wider planned SoC architecture.

At this stage, the main focus of this project is the Boot ROM and DDR memory path.

The PLIC and DMA functionality should therefore be treated as ongoing parts of the overall SoC development, rather than assumed to be fully completed by this project.

## 25. Uncached and MMIO Accesses

The DDR controller is not intended to handle every physical address in the system.

The Wishbone interconnect determines which slave receives a particular physical address.

This allows the system to separate:

Cacheable memory

from:

Uncached / MMIO regions

For example, a peripheral access can be routed directly to its peripheral instead of being sent to DDR.


## 26. Problems Encountered

### Boot Sequencing

The CPU cannot assume that DDR is immediately available after reset.

The Boot ROM and DDR controller therefore need a reliable ready/status mechanism.

### Wishbone and Memory Latency

The DDR controller introduces more latency than the simpler memory models used in earlier projects.

The controller must keep track of active transactions until the memory operation has actually completed.

### Burst Handling

The L1 cache uses burst transfers for refills and writebacks.

The DDR controller therefore has to maintain the correct address, data, and transaction state across multiple consecutive beats.

### Refresh

Periodic refresh introduces additional controller states and can temporarily interrupt normal memory accesses.

The controller must ensure that pending requests are not lost or corrupted when a refresh occurs.

### Byte Enable Handling

The wider 64-bit datapath makes byte-enable handling more important because smaller CPU accesses still have to be represented correctly inside the wider memory interface.

### Timeout and Error Recovery

A failed or non-responsive memory transaction must not permanently block the Wishbone bus.

Explicit timeout and error handling are therefore required.

### Simulation vs FPGA Hardware

The simulated DDR model can verify the controller logic, but it cannot completely reproduce the timing requirements of a real FPGA DDR interface.

The generic command/PHY layer therefore provides a boundary between the logic verified in simulation and the physical DDR implementation that will be required later.

## 27. Reflection

This project connects several previously separate parts of the computer into a more complete memory system.

The Boot ROM gives the processor a defined starting point after reset, while DDR provides the large working-memory region required for normal software execution.

One of the main lessons is that memory initialization has to be treated as part of the boot process. The processor cannot simply jump directly into DDR code before the memory controller has established that the memory is ready.

The DDR controller also introduces more realistic memory behavior than a simple RAM module. Latency, bursts, refresh, byte enables, errors, and timeouts all affect how the processor interacts with memory.

The existing L1 cache hierarchy fits naturally with this design because complete cache lines can be transferred through the 64-bit memory system using bursts. This creates a continuous path from the virtual address generated by the CPU to the physical DDR memory.

Another important aspect is the separation between the logical DDR controller and the physical DDR interface. By using a generic command/PHY interface, the controller can first be verified in simulation and later adapted to the actual DDR hardware available on the selected FPGA.

This project therefore moves the computer from a collection of processor and memory components toward a system that has an actual reset and boot path together with a realistic main-memory backend.

## 28. Future Improvements

Possible future improvements include:

- FPGA-specific DDR PHY implementation
- Real DDR hardware testing
- More accurate DDR timing
- Memory initialization improvements
- More advanced Boot ROM code
- SPI/QSPI-based boot
- Firmware loading
- OpenSBI integration
- Device tree loading
- DDR performance benchmarking
- Linux memory-system testing

The existing PLIC and DMA work can also be integrated further as those parts of the larger SoC continue to develop.


## 29. What's Next

The next step is to continue developing the PLIC + DMA subsystem.

The goal is to add centralized interrupt handling and efficient hardware-controlled data transfers to the SoC.

The PLIC will provide:

- 32 external interrupt sources
- Interrupt priorities
- Pending and enable status
- Priority threshold
- Claim/complete
- Support structure for multiple harts

The DMA will provide:

- 4 DMA channels
- 64-bit datapath
- Memory-to-memory transfers
- Memory-to-peripheral transfers
- Peripheral-to-memory transfers
- Burst transfers
- Byte enables
- DMA interrupts
- Error and timeout handling
- Descriptor-based transfers
- Foundation for scatter-gather transfers

The planned relationship with the rest of the SoC is:

RV64GC

   ↓
   
Sv39

   ↓
   
L1 I/D Cache

   ↓
   
Wishbone

   ├── DDR
   
   ├── Boot ROM
   
   ├── PLIC
   
   └── DMA
   

A later integration step will connect the DMA interrupt output to the PLIC so that completed or failed DMA transfers can notify the CPU through the existing interrupt and trap infrastructure.

The PLIC + DMA project is therefore the next major step toward a more complete SoC with interrupt-driven peripherals and hardware-assisted data movement.
