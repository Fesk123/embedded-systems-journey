# Wishbone Bus System

## Goal

The goal of this project was to develop a more complete Wishbone-based system interconnect for the RV64GC processor.

The design was based on the Wishbone implementation from the previous project, where the bus was only 8 bits wide and primarily demonstrated a simple master-to-slave transaction.

The new implementation extends this design to a 64-bit Wishbone bus and introduces several features required for a more realistic SoC interconnect:

- 64-bit data bus
- Wishbone Master
- Wishbone Interconnect
- Wishbone RAM Slave
- Multiple masters
- Multiple slaves
- Bus arbitration
- Round-robin arbitration
- Address decoding
- Configurable address mapping
- Burst transactions
- "CTI" and "BTE" support
- Byte-select ("SEL")
- Configurable wait states
- "ACK" and "ERR" handling
- Protection against accepting the same transfer multiple times

The purpose is to create a reusable bus system that can later connect the RV64GC processor to memory and peripherals.

---

# 1. Background

The previous Wishbone project implemented a much simpler bus architecture.

The basic structure was:


Wishbone Master
       |
       v
Wishbone Slave


The bus was 8 bits wide and focused mainly on demonstrating how a master could initiate a transaction and receive a response from a slave.

The new design expands this into a complete interconnect:


                  +------------------+
                  | Wishbone Master 0|
                  +--------+---------+
                           |
                           |
                  +--------v---------+
                  |                  |
                  |    Wishbone      |
                  |   Interconnect   |
                  |                  |
                  | Arbitration      |
                  | Address Decode   |
                  | Routing          |
                  |                  |
                  +--+------------+--+
                     |            |
             +-------v----+  +----v-------+
             | Wishbone   |  | Wishbone   |
             | RAM /      |  | Peripheral |
             | Slave      |  | Slave      |
             +------------+  +------------+


This makes the bus suitable as the foundation for a larger SoC.

---

# 2. Main Components

The new Wishbone system consists of three main components:

1. Wishbone Master
2. Wishbone Interconnect
3. Wishbone RAM Slave

---

# 3. Wishbone Master

The Wishbone Master initiates bus transactions.

It supports:

- Read transactions
- Write transactions
- Burst transactions
- Byte-select
- "ACK" handling
- "ERR" handling
- Address and data generation

The master controls signals such as:

- ADR
- DAT_MOSI
- WE
- SEL
- STB
- CYC
- CTI
- BTE

and receives:

- DAT_MISO
- ACK
- ERR

from the selected slave.

---

# 4. 64-bit Data Path

One of the largest changes from the previous project is the bus width.

The old design used:

DATA_WIDTH = 8

The new design uses:

DATA_WIDTH = 64

This allows one normal Wishbone transfer to contain:

64 bits = 8 bytes

The data bus can therefore be represented as:


63                         0
+--------------------------+
|       64-bit DATA        |
+--------------------------+


The wider bus is required for efficient communication with the RV64GC processor.

---

# 5. Byte Select

A 64-bit transfer consists of eight bytes.

The "SEL" signal determines which bytes are active during a transaction.

For a 64-bit bus:

SEL[7:0]

Each bit corresponds to one byte.

For example:

SEL = 11111111

means that all eight bytes are selected.

A partial write can therefore modify only part of a 64-bit memory word.

For example:

SEL = 00001111

selects only part of the 64-bit word.

This is important because RISC-V supports accesses smaller than the full 64-bit datapath width.

---

# 6. Wishbone Interconnect

The interconnect is responsible for connecting multiple masters and slaves.

It performs three main tasks:

- Arbitration
- Address decoding
- Signal routing

Conceptually:


                 Master 0
                    |
                    |
                 Master 1
                    |
                    v
          +-------------------+
          | Wishbone          |
          | Interconnect      |
          |                   |
          | Arbitration       |
          | Address Decode    |
          | Routing           |
          +---+-----------+---+
              |           |
              v           v
           Slave 0      Slave 1


---

# 7. Multiple Masters

The new system supports two bus masters.

- Master 0
- Master 1

Both masters may request access to the bus.

The interconnect must therefore determine which master is allowed to perform a transaction.

Example:

Master 0 ──┐
           ├──> Arbitration ──> Bus
Master 1 ──┘

Only one master should control the shared bus at a time.

---

# 8. Arbitration

The interconnect contains arbitration logic.

Each master can request the bus.

Conceptually:

Master 0 ── bus request ──┐
                          |
                          v
                    +-----------+
                    | Arbiter   |
                    +-----------+
                          |
                          v
                     Bus Grant

If only one master requests the bus, it can be granted immediately.

If both request the bus simultaneously, an arbitration policy is required.

---

# 9. Round-Robin Arbitration

When both masters request the bus at the same time, the system uses round-robin arbitration.

The arbiter remembers which master was previously served.

For example:

Current priority:
Master 0 → Master 1

After Master 0 is served:

Next priority:
Master 1 → Master 0

This prevents one master from permanently dominating the bus when both continuously request access.

The basic idea is:

Request M0 + Request M1
          |
          v
   Round-Robin Arbiter
       /        \
      v          v
   Grant M0    Grant M1

---

# 10. Address Decoding

The interconnect determines which slave should receive a transaction based on the requested address.

For example:

Address
   |
   v
Address Decoder
   |
   +----> RAM
   |
   +----> Peripheral 0
   |
   +----> Peripheral 1

The address map is configurable so that different slaves can be assigned to different memory regions.

A conceptual example is:

0x0000_0000 – 0x000F_FFFF    RAM
0x1000_0000 – 0x1000_00FF    UART
0x1000_0100 – 0x1000_01FF    GPIO
...

The actual address map can be changed as the SoC develops.

---

# 11. Multiple Slaves

The interconnect supports multiple slave devices.

The current project uses a RAM slave as the main example, but the architecture is designed so that additional peripherals can be connected later.

For example:


                    Interconnect
                         |
        +----------------+----------------+
        |                |                |
        v                v                v
       RAM              UART             GPIO


This allows the same bus to be used for both memory and memory-mapped peripherals.

---

# 12. Wishbone RAM Slave

The RAM module acts as a Wishbone slave.

It responds to transactions from the selected master.

The RAM supports:

- Read operations
- Write operations
- Byte-select
- "ACK"
- "ERR"
- Configurable wait states
- Burst transactions

Conceptually:

Wishbone Bus
     |
     v
+-----------+
| RAM Slave |
+-----------+
     |
     v
 Memory

---

# 13. Wait States

The RAM slave supports configurable wait states.

A slave does not necessarily have to respond immediately.

For example:

Cycle 1: Request
Cycle 2: Wait
Cycle 3: Wait
Cycle 4: ACK

This makes the simulation more realistic and allows the bus architecture to support slower memory or peripherals.

The master must remain in the transaction until the slave responds.

---

# 14. ACK

"ACK" indicates that a transaction has completed successfully.

A simplified read transaction looks like:

Master
  |
  | CYC + STB + ADR
  v
Slave
  |
  | wait
  |
  | ACK + DATA
  v
Master

The master can then accept the returned data.

---

# 15. ERR

The new design also supports error responses.

If a transaction targets an invalid or unmapped address, the interconnect can return:

ERR = 1

instead of allowing the transaction to remain unresolved.

Conceptually:

Invalid address
      |
      v
Address decoder
      |
      v
No matching slave
      |
      v
ERR

This is important for making the bus behave predictably when software accesses an invalid address.

---

# 16. Burst Transactions

The new Wishbone implementation supports burst transactions.

Instead of performing:

- Read
- ACK
- Read
- ACK
- Read
- ACK

for every individual transfer, multiple transfers can be grouped into one bus cycle.

Conceptually:

CYC
+---------------------------------------+

STB
+----+----+----+----+

DATA
  A    B    C    D

ACK
     ^    ^    ^    ^


This can reduce transaction overhead and improve memory throughput.

---

# 17. CTI

The Wishbone "CTI" signal describes the type of cycle being performed.

It is used to distinguish between normal transfers and burst transfers.

The master can therefore communicate whether a transfer is:

- A classic cycle
- A continuing burst
- The end of a burst

The interconnect and slave must preserve the required behavior throughout the burst.

---

# 18. BTE

The "BTE" signal controls the burst addressing mode.

This determines how the address changes between beats of a burst.

For example, an incrementing burst may produce:


Address 0
Address 8
Address 16
Address 24
...

for a 64-bit bus with 8-byte data beats.

The exact addressing behavior depends on the selected burst mode.

---

# 19. Burst Transfer Protection

One problem encountered during burst implementation was the possibility of accepting the same transfer more than once.

To prevent this, the design uses internal state such as:

- pending_transfer
- accepted_transfer

These signals help distinguish between a new request and a request that is still being processed.

This prevents the slave from accidentally accepting the same transfer multiple times during a burst.

---

# 20. Transaction Flow

A typical read transaction can be represented as:

1. Master requests bus
        |
        v
2. Arbiter grants master
        |
        v
3. Master presents address
        |
        v
4. Interconnect decodes address
        |
        v
5. Slave is selected
        |
        v
6. Slave waits if necessary
        |
        v
7. Slave returns DATA + ACK
        |
        v
8. Master accepts result
        |
        v
9. Transaction completes


For an invalid address:

Master
  |
  v
Interconnect
  |
  v
No matching slave
  |
  v
ERR
  |
  v
Master handles error

---

# 21. Write Transaction

A 64-bit write transaction contains:

- Address
- Write data
- Write enable
- Byte select
- Cycle
- Strobe

Conceptually:

Master
  |
  +--> ADR
  +--> DAT_MOSI
  +--> WE
  +--> SEL
  +--> CYC
  +--> STB
       |
       v
   Interconnect
       |
       v
      RAM


The RAM uses "SEL" to determine which bytes should actually be modified.

---

# 22. Read Transaction

A read transaction follows a similar path.

Master
  |
  +--> ADR
  +--> CYC
  +--> STB
       |
       v
   Interconnect
       |
       v
      RAM
       |
       v
    DAT_MISO
       |
       v
      ACK
       |
       v
     Master

The returned data is transferred through the interconnect back to the requesting master.

---

# 23. Design Comparison

The main difference between the old and new Wishbone implementations is the increase in both bus width and system complexity.

| Feature             | Previous Wishbone   | New Wishbone     |
| ------------------- | ------------------- | ---------------- |
| Data width          | 8-bit               | 64-bit           |
| Masters             | 1                   | 2                |
| Slaves              | Simple single slave | Multiple slaves  |
| Arbitration         | No                  | Yes              |
| Round-robin         | No                  | Yes              |
| Address decoding    | Basic               | Configurable     |
| Burst support       | No                  | Yes              |
| "CTI" / "BTE"       | No                  | Yes              |
| Byte select         | Limited / basic     | 8-byte "SEL"     |
| Wait states         | No / basic          | Configurable     |
| Error handling      | Limited             | "ERR"            |
| Transfer protection | No                  | Yes              |
| Intended use        | Bus demonstration   | SoC interconnect |

The new implementation therefore represents a significant expansion of the original design rather than simply changing the data width from 8 to 64 bits.

---

# 24. Relation to the RV64GC Processor

The new Wishbone bus is intended to become the main communication interface between the RV64GC CPU and the rest of the SoC.

The high-level architecture can therefore become:


                  RV64GC CPU
                       |
                       v
               Wishbone Master
                       |
                       v
             +-------------------+
             | Wishbone          |
             | Interconnect      |
             +----+----+----+----+
                  |    |    |
                  v    v    v
                 RAM  UART GPIO


The 64-bit bus matches the datapath width of the RV64GC processor.

This allows the processor to communicate with memory and peripherals using a standardized bus interface.

---

# 25. Verification

The Wishbone components were tested using simulation.

Important things to verify include:

### Master

- Read transactions
- Write transactions
- Burst transactions
- Correct "CTI"
- Correct "BTE"
- Correct "SEL"
- ACK handling
- ERR handling

### Interconnect

- Address decoding
- Master arbitration
- Round-robin behavior
- Correct master-to-slave routing
- Correct response routing
- Invalid address handling

### RAM

- Reads
- Writes
- Partial writes
- Wait states
- Burst transfers
- ACK generation
- Error behavior

---

# 26. Problems Encountered

### Increasing the Bus Width

Changing from an 8-bit bus to a 64-bit bus affected more than just the data signals.

Addressing, byte-select, memory organization, burst behavior, and testbench expectations all had to be reconsidered.

---

### Arbitration

Supporting multiple masters introduced the problem of deciding who owns the bus.

The arbitration logic had to ensure that only one master could perform a transaction at a time.

Round-robin arbitration was added to provide fair access when both masters continuously request the bus.

---

### Burst Transactions

Burst transfers introduced significantly more state than simple single transfers.

The system needs to keep track of:

- Current transfer
- Current burst
- Address progression
- Transfer acceptance
- ACK responses
- End-of-burst conditions

This made the control logic more complex than in the original Wishbone implementation.

---

### Duplicate Transfer Acceptance

During development, there was a risk that the same transfer could be accepted more than once while a burst was still active.

The "pending_transfer" and "accepted_transfer" logic was introduced to distinguish a new transfer from a transfer that had already been accepted.

This was important for ensuring correct memory behavior.

---

### Wait States

Adding configurable wait states changed the assumption that a request would always receive an immediate response.

The master and interconnect therefore had to maintain the correct transaction state until the slave returned "ACK" or "ERR".

---

### Invalid Addresses

Multiple slaves and configurable address mapping introduced the possibility of accessing an address that does not belong to any slave.

"ERR" handling was therefore added so that invalid accesses do not leave the bus waiting indefinitely.

---

# 27. Reflection

This project showed how much more complex a bus becomes when moving from a simple master-to-slave connection to a real interconnect.

The previous Wishbone project was useful as a starting point because the basic transaction model was already understood. Instead of designing the protocol from scratch, the previous implementation could be expanded and adapted to the requirements of the RV64GC system.

The transition from 8-bit to 64-bit also demonstrated that increasing a datapath width affects much more than the data signals. Byte selection, memory organization, burst addressing, and verification all need to be adapted to the wider bus.

The biggest conceptual change was moving from:

Master → Slave

to:

Multiple Masters
       |
       v
   Arbitration
       |
       v
 Interconnect
       |
       v
 Multiple Slaves

This makes the new Wishbone implementation much closer to the type of bus architecture required in a complete SoC.

The project also highlighted the importance of handling realistic conditions such as wait states and invalid addresses. A bus cannot assume that every memory access is immediately successful.

The resulting Wishbone system provides a reusable communication layer for the rest of the computer and creates a foundation for connecting the RV64GC processor to RAM, boot memory, and peripherals.

---

# 28. Future Improvements

Possible future improvements include:

- Connecting the RV64GC CPU directly to the Wishbone master
- Connecting multiple real SoC peripherals
- Connecting external memory
- Improving burst performance
- Adding more masters
- Adding more advanced arbitration
- Formal Wishbone verification
- More extensive error testing
- FPGA testing
- Measuring bus throughput and latency
- Integrating the bus into the complete SoC

The next step is to use the Wishbone system as the main interconnect for the processor and memory system.

---

# 29. What's Next

The next step is to implement Sv39 Virtual Memory, the MMU, and the TLB.

The goal is to add virtual memory support to the RV64GC processor and establish the address-translation mechanisms required for a more complete operating-system-capable system.

The next project will focus on:

- Sv39 virtual memory
- Three-level page tables
- Virtual-to-physical address translation
- Memory Management Unit (MMU)
- Translation Lookaside Buffer (TLB)
- Page-table walking
- Page faults
- Access permissions
- Integration with the existing CSR and privilege architecture

The intended architecture is:

RV64GC CPU
     |
     v
    MMU
     |
     +----> TLB
     |
     +----> Page Table Walker
     |
     v
Physical Address
     |
     v
Wishbone Interconnect
     |
     +--------+--------+
     |                 |
     v                 v
   RAM              Peripherals


This will add the virtual-memory layer required for more advanced software and is an important step toward a Linux-capable RV64GC system.
