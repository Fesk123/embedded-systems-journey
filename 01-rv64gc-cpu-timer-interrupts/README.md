# RV64GC Processor

## Goal

The goal of this project was to extend the processor from RV32IMA to a more capable RV64GC processor.

The final processor combines a 64-bit RISC-V datapath with a pipelined architecture and several features required for more advanced software.

The implemented processor includes:

- RV64 base integer architecture
- M extension for multiplication and division
- A extension for atomic operations
- F extension for single-precision floating-point operations
- D extension for double-precision floating-point operations
- C extension for compressed instructions
- 5-stage pipeline
- Branch prediction
- Hazard detection
- Data forwarding
- Pipeline stalls and flushing
- CSR support
- Privileged architecture
- Exceptions and traps
- Interrupt handling

The processor was verified through simulation and waveform analysis using GTKWave.

---

# 1. RV64GC

RV64GC is a RISC-V architecture configuration consisting of:


RV64I
  +
M
A
F
D
C

The main difference compared with the previous RV32IMA processor is the transition from a 32-bit datapath to a 64-bit datapath.

The processor therefore uses:


XLEN = 64


while RISC-V instructions remain encoded using 32-bit instructions, with the C extension additionally providing 16-bit compressed instructions.

---

# 2. RV64I

The base integer instruction set was extended from RV32I to RV64I.

The processor now operates on 64-bit general-purpose registers:


x0 – x31


Each register contains:


64 bits


x0 remains hardwired to zero.

The program counter is also 64 bits wide.

---

# 3. M Extension

The M extension provides integer multiplication and division instructions.

It includes operations such as:


MUL
MULH
MULHSU
MULHU
DIV
DIVU
REM
REMU


These operations were adapted to the 64-bit datapath.

This required changes to:

- ALU operations
- Multiplication logic
- Division logic
- Result selection
- Sign extension
- Pipeline control

---

# 4. A Extension

The A extension provides atomic memory operations.

Important instructions include:


LR.D
SC.D
AMOSWAP.D
AMOADD.D
AMOXOR.D
AMOAND.D
AMOOR.D
AMOMIN.D
AMOMAX.D
AMOMINU.D
AMOMAXU.D


Atomic operations are important for synchronization between software threads and processors.

The implementation required:

- Reservation tracking
- Atomic memory access
- Load-reserved operations
- Store-conditional operations
- Atomic read-modify-write operations

---

# 5. F and D Extensions

The processor was extended with floating-point support.

The F extension provides single-precision floating-point operations, while D provides double-precision operations.

This introduced a separate floating-point register file and floating-point execution logic.

The processor therefore contains:


Integer Register File
        +
Floating-Point Register File
        +
Integer ALU
        +
Floating-Point Unit


Floating-point operations introduced additional complexity because the calculations use different representations and rounding behavior than normal integer operations.

The implementation therefore had to handle:

- Floating-point addition
- Floating-point subtraction
- Floating-point multiplication
- Floating-point division
- Comparisons
- Conversions
- Floating-point loads and stores
- Rounding
- Special values

---

# 6. C Extension

The C extension adds compressed 16-bit instructions.

Normal RISC-V instructions are:

32 bits

while compressed instructions can be:

16 bits

This reduces instruction memory usage and can improve code density.

Adding compressed instructions required changes to the instruction-fetch and decode logic.

The processor must determine whether the next instruction is:

16-bit compressed

or:

32-bit standard

This also affects program-counter increments and instruction alignment.

---

# 7. 5-Stage Pipeline

The processor uses a 5-stage pipeline:


IF → ID → EX → MEM → WB


### IF – Instruction Fetch

Fetches the next instruction from instruction memory.

This stage also interacts with the branch prediction logic.

---

### ID – Instruction Decode

The instruction is decoded and the required registers and control signals are identified.

This stage must also recognize:

- Integer instructions
- Floating-point instructions
- Atomic instructions
- Compressed instructions
- CSR instructions
- Privileged instructions

---

### EX – Execute

The instruction is executed.

Depending on the instruction, this may involve:

- Integer ALU
- Multiplier
- Divider
- Floating-point unit
- Branch comparison
- Address calculation
- CSR operation

---

### MEM – Memory Access

This stage handles:

- Loads
- Stores
- Atomic operations

---

### WB – Write Back

The calculated result is written back to the appropriate register file.

The result can originate from:

- Integer ALU
- Memory
- Multiplier
- Divider
- FPU
- CSR unit

---

# 8. Pipeline Hazards

Pipelining introduces dependencies between instructions.

For example:

asm
add x5, x1, x2
sub x6, x5, x3

The second instruction needs the result of the first instruction.

Without additional hardware, the result may not yet have reached the register file.

The processor therefore implements hazard handling.

---

# 9. Forwarding

Forwarding allows a result to be sent directly from a later pipeline stage to an earlier stage without waiting for normal write-back.

Conceptually:

EX/MEM
   |
   | forwarding
   v
  EX

and:

MEM/WB
   |
   | forwarding
   v
  EX

This reduces unnecessary pipeline stalls.

Forwarding had to be implemented for the relevant integer datapath operations and carefully integrated with the rest of the pipeline.

---

# 10. Pipeline Stalls

Some dependencies cannot be solved using forwarding alone.

A common example is a load-use dependency:

asm
ld  x5, 0(x1)
add x6, x5, x2

The loaded value may not be available soon enough for the following instruction.

The hazard detection logic can therefore insert a stall or bubble:

Instruction 1
Instruction 2
    ↓
STALL
    ↓
Instruction 2

This prevents the processor from using invalid or unavailable data.

---

# 11. Branch Prediction

Branch instructions can change the program counter.

Without prediction, the pipeline may have to wait until the branch is resolved before fetching the correct instruction.

The processor therefore includes branch prediction.

Conceptually:

Branch instruction
       |
       v
Prediction
   /       \
Taken     Not Taken
  |           |
  v           v
Target      Next PC

If the prediction is incorrect, the incorrectly fetched instructions must be flushed and execution redirected to the correct address.

Branch prediction therefore interacts closely with:

- PC generation
- Pipeline control
- Branch resolution
- Pipeline flushing
- Hazard handling

---

# 12. CSR Support

The processor contains Control and Status Registers.

Important CSRs include:

- mstatus
- mtvec
- mepc
- mcause
- mtval
- mie
- mip

CSR instructions allow software to:

- Read CSRs
- Write CSRs
- Set bits
- Clear bits

The CSR system is also used during exception and interrupt handling.

---

# 13. Privileged Architecture

The processor supports privileged execution mechanisms.

The architecture distinguishes between privilege levels such as:

- Machine mode
- Supervisor mode
- User mode

The implementation provides the mechanisms required to change processor behavior depending on the current privilege level.

This is important for operating-system software, where privileged code needs access to resources that normal application code should not have.

---

# 14. Exceptions and Traps

The processor can detect exceptional conditions and transfer execution to a trap handler.

Examples include:

- Illegal instructions
- Environment calls
- Breakpoints
- Memory access faults
- Instruction access faults
- Address misalignment where supported

When a trap occurs, the processor saves the relevant information in CSRs.

Conceptually:

Exception
    |
    v
mepc
mcause
mtval
    |
    v
PC ← mtvec
    |
    v
Trap Handler

The pipeline must also be flushed so that younger instructions do not incorrectly modify the processor state.

---

# 15. Interrupts

Interrupt support allows external or internal events to request processor attention.

The interrupt system is connected to the privileged architecture and CSR system.

Conceptually:


Interrupt Source
       |
       v
Interrupt Logic
       |
       v
CPU
       |
       v
Trap Handling
       |
       v
Interrupt Handler


The processor distinguishes interrupts from synchronous exceptions through the trap cause information.

---

# 16. MRET

The MRET instruction is used to return from a Machine-mode trap handler.

Conceptually:

Trap Handler
     |
     | MRET
     v
Restore privilege state
     |
     v
PC ← mepc
     |
     v
Normal execution

Correct implementation of MRET required coordination between:

- CSR logic
- Privilege state
- Program counter
- Pipeline control
- Trap handling

---

# 17. Floating-Point Unit

The floating-point unit was one of the more complex additions to the processor.

Unlike ordinary integer operations, floating-point calculations require handling different numerical representations and special cases.

The FPU therefore needs to account for:

- Sign
- Exponent
- Fraction
- Zero
- Infinity
- NaN
- Rounding

The F and D extensions also introduced additional data paths and register state into the processor.

---

# 18. Instruction Decode

The decoder became significantly more complex as more extensions were added.

The processor now needs to distinguish between:

- RV64I
- M
- A
- F
- D
- C
- CSR
- Privileged instructions

The decode logic determines:

- Instruction type
- Source registers
- Destination register
- Immediate values
- ALU operation
- Memory operation
- Register-file selection
- Floating-point operation
- CSR operation
- Branch/jump operation
- Atomic operation

This makes the decoder an important central component of the processor.

---

# 19. Pipeline Flushes

Several events can require a pipeline flush.

Examples include:

- Incorrect branch prediction
- Taken branches
- Jumps
- Exceptions
- Interrupts
- Trap entry
- Trap return

A flush prevents instructions that should no longer execute from reaching the write-back or memory stages.

Conceptually:

Pipeline

IF → ID → EX → MEM → WB
          |
          | redirect
          v
        FLUSH
          |
          v
       New PC

Correct flush behavior was especially important for trap and branch handling.

---

# 20. Verification

The processor was verified through simulation and waveform analysis using GTKWave.

The waveforms were used to inspect signals such as:

- Clock
- Reset
- Program counter
- Instructions
- Register-file activity
- ALU results
- Pipeline registers
- Forwarding signals
- Hazard signals
- Branch signals
- CSR signals
- Trap signals
- Interrupt signals
- Memory accesses

This made it possible to inspect the internal behavior of the processor cycle by cycle.

---

# 21. Problems Encountered

Several significant problems were encountered during development.

### Pipeline Hazards

Adding more complex instructions increased the number of possible dependencies between instructions.

The hazard detection and forwarding logic had to correctly determine when data was available and when the pipeline needed to stall.

---

### Forwarding

Forwarding was particularly important for maintaining pipeline performance.

Incorrect forwarding could result in an instruction receiving an old value instead of the result from an earlier instruction.

Debugging these problems required inspecting pipeline registers and data paths cycle by cycle in GTKWave.

---

### Floating-Point Calculations

Floating-point operations were more complicated than normal integer operations.

Issues included:

- Different numerical representations
- Rounding
- Special values
- Wider datapaths
- Additional registers
- Correct operation sequencing

This made the F and D extensions some of the more challenging parts of the processor.

---

### Trap Handling

Trap handling required multiple parts of the processor to work together.

A trap must correctly:

1. Detect the event
2. Save the correct PC
3. Update the cause
4. Update the relevant CSR state
5. Flush the pipeline
6. Redirect the PC
7. Execute the handler
8. Return using MRET

A mistake in any of these steps can result in incorrect execution.

---

### Interrupt Handling

Interrupts introduced additional timing and control challenges because they are asynchronous to normal instruction execution.

The processor must accept the interrupt at the correct point while preserving architectural state and preventing incorrect instructions from completing.

---

### Compressed Instructions

The C extension introduced additional complexity into instruction fetching because instructions are no longer always 32 bits long.

The processor must correctly determine instruction length and update the PC accordingly.

This also affects alignment, decoding, and pipeline behavior.

---

# 22. Reflection

The transition from RV32IMA to RV64GC significantly changed the complexity of the processor.

The most important realization from this project was that adding instruction-set extensions is only one part of processor development. The difficult part is making all of the extensions work correctly together inside the same pipeline.

The 5-stage pipeline made performance improvements possible, but it also introduced hazards, forwarding requirements, stalls, and pipeline flushes. Branch prediction added another layer of control logic because an incorrect prediction requires the pipeline to recover without changing the architectural state incorrectly.

The floating-point extensions showed how different an execution unit can be from the normal integer datapath. Floating-point calculations require additional representations, operations, rounding behavior, and special cases.

The privileged architecture also demonstrated how closely hardware and software are connected. CSRs, exceptions, traps, interrupts, and privilege levels provide mechanisms that software and operating systems can use to control and interact with the processor.

Using GTKWave for verification was particularly useful because many of the problems could not easily be understood by only looking at the final output. Looking at the internal signals cycle by cycle made it possible to identify where incorrect values entered the pipeline and how they propagated through the processor.

Overall, the processor has evolved from a basic RV32I CPU into a much more complete RV64GC processor with pipelining, prediction, privileged execution, interrupts, atomic operations, floating-point support, and compressed instructions.

---

# 23. Future Improvements

Possible future improvements include:

- More extensive RV64GC compliance testing
- More comprehensive instruction tests
- Improved branch prediction
- Further pipeline optimization
- Performance benchmarking
- More complete interrupt support
- More complete Supervisor-mode support
- Virtual memory
- TLB support
- Physical Memory Protection
- Improved debugging support
- FPGA implementation
- SoC integration
- Linux-compatible memory and peripheral system

The next stages will focus on integrating the processor with the rest of the computer system and testing it on actual FPGA hardware.

---
