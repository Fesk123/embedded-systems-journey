# Sv39 Virtual Memory – MMU, TLB and Page Table Walker

## Goal

The goal of this project is to add Sv39 virtual memory support to the RV64GC processor.

The previous projects established:

- RV64GC processor
- 5-stage pipeline
- Branch prediction
- Hazard handling and forwarding
- CSR support
- Privilege levels
- Exceptions and traps
- Interrupt handling
- 64-bit Wishbone interconnect

This project adds the virtual-memory layer between the CPU and the physical memory system.

The main components are:

- Instruction TLB (ITLB)
- Data TLB (DTLB)
- Sv39 Page Table Walker
- Page-Walk Cache (PWC)
- Virtual-to-physical address translation
- "satp" and ASID support
- Page permission checking
- Accessed and Dirty bit handling
- "SFENCE.VMA"
- Page-fault and access-fault generation
- Wishbone interface for page-table walks
- Separate instruction and data translation paths

The objective is to make the processor capable of translating virtual addresses into physical addresses while maintaining the required protection and privilege checks.

---

# 1. Sv39

Sv39 is the page-based virtual-memory system intended for RV64 systems using a 39-bit virtual address space.

The processor still uses:

XLEN = 64

but only the Sv39 virtual-address space is translated by the page-table mechanism.

An Sv39 virtual address is divided into:


63                  39 38      30 29      21 20      12 11       0
+---------------------+----------+----------+----------+-----------+
| Sign Extension      |   VPN[2] |   VPN[1] |   VPN[0] |  Offset   |
+---------------------+----------+----------+----------+-----------+
                         9 bits     9 bits     9 bits     12 bits

This gives:

Virtual address width = 39 bits
Page offset            = 12 bits
VPN[0]                 = 9 bits
VPN[1]                 = 9 bits
VPN[2]                 = 9 bits

The 12-bit page offset corresponds to a:

4 KiB page

Sv39 can also use larger leaf pages:

- 4 KiB
- 2 MiB
- 1 GiB

---

# 2. Virtual Memory Architecture

The high-level translation path is:

                 +----------------+
                 |    RV64GC CPU  |
                 +--------+-------+
                          |
                 +--------+--------+
                 |                 |
                 v                 v
              ITLB              DTLB
                 |                 |
                 +--------+--------+
                          |
                       TLB Miss
                          |
                          v
                  +---------------+
                  | Page Table    |
                  | Walker        |
                  +-------+-------+
                          |
                          v
                       PTEs
                          |
                          v
                  Physical Address
                          |
                          v
                 Wishbone Interconnect
                          |
                          v
                       Memory

The translation layer therefore sits between the processor and the physical memory system.

---

# 3. ITLB

The Instruction Translation Lookaside Buffer (ITLB) caches virtual-to-physical translations for instruction fetches.

The implementation contains:

16 ITLB entries

Each entry stores the information required to translate an instruction virtual address without performing a new page-table walk.

Conceptually:


Virtual PC
    |
    v
  ITLB
    |
    +---- Hit ----> Physical address
    |
    +---- Miss ---> Page Table Walker


A successful ITLB lookup allows instruction fetching to continue without accessing the page tables.

---

# 4. DTLB

The Data Translation Lookaside Buffer (DTLB) performs the same function for load and store addresses.

The implementation contains:

16 DTLB entries

The DTLB is used for:

- Loads
- Stores
- Atomic memory operations

Conceptually:

Virtual Data Address
        |
        v
      DTLB
      /   \
   Hit    Miss
    |       |
    v       v
Physical   Page
Address    Walker

The ITLB and DTLB are kept separate because instruction and data accesses can occur independently in the pipeline.

---

# 5. Separate Instruction and Data Translation

The processor has separate translation paths for instructions and data.


             RV64GC CPU
             /        \
            /          \
           v            v
        ITLB           DTLB
         |              |
         |              |
         +------\ /-----+
                 |
           Shared Walker


This allows an instruction access and a data access to maintain independent translations while sharing the page-table-walking hardware.

The shared walker is used whenever one of the TLBs misses.

---

# 6. Page Table Walker

The Page Table Walker (PTW) performs the hardware page-table traversal required after a TLB miss.

Sv39 uses a three-level page table:

Level 2
   |
   v
Level 1
   |
   v
Level 0
   |
   v
Leaf PTE

The walker uses the virtual page number:

VPN[2]
VPN[1]
VPN[0]

to determine which page-table entry to read at each level.

---

# 7. Sv39 Page Walk

A simplified page walk is:

satp.PPN
    |
    v
Level 2 page table
    |
    | VPN[2]
    v
PTE
    |
    v
Level 1 page table
    |
    | VPN[1]
    v
PTE
    |
    v
Level 0 page table
    |
    | VPN[0]
    v
Leaf PTE
    |
    v
Physical Page Number

The physical page number is then combined with the original page offset.

For a 4 KiB page:

Physical address =
    Physical Page Number
    +
    Virtual Page Offset

---

# 8. Large Pages

Sv39 allows a leaf PTE to occur before the final page-table level.

This allows larger pages:

Level 2 leaf → 1 GiB page
Level 1 leaf → 2 MiB page
Level 0 leaf → 4 KiB page

The walker must therefore determine whether a PTE is:

Non-leaf

or:

Leaf

and construct the physical address accordingly.

Large-page alignment must also be checked.

---

# 9. Page Table Entry

A Sv39 Page Table Entry (PTE) contains control and permission bits together with a physical page number.

Important permission/state bits include:

- V
- R
- W 
- X
- U
- G
- A
- D

The current implementation focuses on the fields necessary for address translation and access checking.

Conceptually:

+---+---+---+---+---+---+------------------+
| V | R | W | X | U |...|       PPN        |
+---+---+---+---+---+---+------------------+

The implementation must also handle unsupported or invalid PTE combinations correctly.

---

# 10. SATP

The "satp" CSR controls the active address-translation mode and identifies the root page table.

For Sv39, the important fields are:

MODE
ASID
PPN

Conceptually:

satp
+----------------+----------+----------------+
|      PPN       |   ASID   |      MODE      |
+----------------+----------+----------------+

The "PPN" identifies the root page table.

The "ASID" identifies the address space.

The "MODE" selects the translation mode.

For this project:

MODE = Sv39

enables Sv39 address translation.

---

# 11. ASID

The Address Space Identifier (ASID) allows translations belonging to different address spaces to coexist in the TLB.

Conceptually:

ASID 1
  |
  +--> Process / Address Space A

ASID 2
  |
  +--> Process / Address Space B

The TLB entries therefore need to store the corresponding ASID when ASID-based matching is implemented.

This avoids having to treat every context switch as a complete TLB invalidation.

---

# 12. Page-Walk Cache

Repeated page walks can still be expensive even when the final translation is not cached.

The project therefore includes a Page-Walk Cache (PWC).

The PWC contains:

8 entries

It stores non-leaf PTE information that can be reused during future page walks.

Conceptually:

TLB Miss
   |
   v
 PWC lookup
 /        \
Hit       Miss
 |          |
 v          v
Skip      Wishbone
levels     Page Walk

The PWC can therefore reduce the number of memory accesses required for repeated translations within the same page-table hierarchy.

---

# 13. Permission Checking

After obtaining a valid PTE, the MMU must determine whether the requested access is permitted.

The relevant permissions include:

R – Read
W – Write
X – Execute
U – User

The access type is determined by the source of the translation:

Instruction fetch → X
Load              → R
Store             → W
Atomic operation  → appropriate read/write permissions

Invalid permission combinations must result in a page fault.

---

# 14. MXR

The "MXR" bit modifies read permissions.

When "MXR=0", a load requires a readable page.

When "MXR=1", an executable page can also be readable by a load.

This behavior is implemented as part of the permission-checking logic.

Conceptually:

MXR = 0

R = 1  → Load allowed
R = 0  → Load fault

MXR = 1

R = 1  → Load allowed
X = 1  → Load allowed
R = 0
X = 0  → Load fault

---

# 15. SUM

The "SUM" bit controls Supervisor-mode access to pages marked as user-accessible.

The MMU therefore checks:

Current privilege level
        +
PTE.U
        +
SUM

when performing supervisor data accesses.

This allows the processor to enforce the separation between supervisor and user memory.

---

# 16. Accessed and Dirty Bits

The implementation handles the PTE:

A = Accessed
D = Dirty

bits.

The "A" bit records that a page has been accessed.

The "D" bit records that a page has been written.

Conceptually:

First access
    |
    v
A = 1

Write access
    |
    v
D = 1

The MMU therefore needs logic to update these bits when required.

---

# 17. A/D Bit Updates

A translation cannot simply be cached after checking the PTE.

The implementation must also consider whether the required state bits are already set.

For example:

Load:
    A must be valid

Store:
    A must be valid
    D must be valid

When the required state is missing, the implementation must update the PTE or generate the corresponding fault behavior according to the chosen Sv39 implementation strategy.

---

# 18. SFENCE.VMA

"SFENCE.VMA" is used to synchronize software modifications to page tables with the processor's address-translation caches.

The processor therefore uses it to invalidate relevant:

ITLB
DTLB
PWC

entries.

Conceptually:


Software modifies page table
          |
          v
     SFENCE.VMA
          |
          v
Invalidate translations
          |
     +----+----+
     |         |
    ITLB      DTLB
     |
    PWC

The invalidation can be scoped using the instruction's virtual-address and ASID operands.

---

# 19. TLB Invalidation

The TLBs must be invalidated when a cached translation is no longer guaranteed to match the page tables.

Examples include:

* Page-table changes
* Address-space changes
* ASID reuse
* "SFENCE.VMA"

The implementation therefore provides an explicit invalidation path for:


ITLB
DTLB
PWC

---

# 20. Page Faults

A page fault is generated when the requested virtual-memory access cannot legally be translated.

Examples include:

* Invalid PTE
* Read permission violation
* Write permission violation
* Execute permission violation
* User/supervisor permission violation
* Invalid page alignment
* Required PTE state not available

The MMU reports the corresponding fault to the CPU's existing trap system.

---

# 21. Access Faults

Access faults are different from normal page-permission faults.

An access fault can occur when the physical-memory access itself is not permitted or cannot be completed by the memory system.

The translation system therefore needs to distinguish:

Page fault

from:

Access fault

The resulting exception is forwarded to the existing CSR and trap-handling logic.

---

# 22. Cause and TVAL

When a translation-related exception occurs, the processor must provide the appropriate trap information.

The existing trap system uses:

cause
tval

to report the exception.

For address-related faults, "tval" is associated with the faulting virtual address.

Conceptually:

Virtual access
      |
      v
     MMU
      |
   Fault
      |
      +--> cause
      |
      +--> tval
      |
      v
    Trap

This integrates the MMU with the existing "mcause", "mepc", and "mtval" infrastructure.

---

# 23. Wishbone Master

The Page Table Walker uses a dedicated Wishbone master interface.

Importantly, this interface is used only for reading and updating page-table structures during page walks.

Normal instruction and data memory accesses do not use this master directly.

The translation flow is:

CPU virtual address
        |
        v
      TLB
        |
   Hit / Miss
        |
       Miss
        |
        v
Page Table Walker
        |
        v
Wishbone Master
        |
        v
Physical page-table memory

Once the translation has been completed, the CPU receives a physical address.

The normal memory access can then continue through the physical memory system.

---

# 24. Page Walk Memory Accesses

The page-table walker uses Wishbone to access page tables stored in physical memory.

A typical walk may require several memory accesses:

Root PTE
   |
   v
Level 1 PTE
   |
   v
Level 0 PTE
   |
   v
Leaf

The walker must therefore handle:

- Wishbone request
- Wait states
- "ACK"
- "ERR"
- Address calculation
- PTE parsing
- Walk completion

The existing 64-bit Wishbone design is therefore reused rather than creating a separate memory protocol.

---

# 25. Shared Page Table Walker

The ITLB and DTLB share the same page-table walker.

Conceptually:

                 +-------+
Instruction ---> | ITLB  |
                 +---+---+
                     |
                   Miss
                     |
                     v
              +-------------+
              |             |
              | Page Table  |
              |   Walker    |
              |             |
              +-------------+
                     ^
                     |
                   Miss
                     |
                 +---+---+
Data ----------> | DTLB  |
                 +-------+

The walker must arbitrate internally when both the instruction and data side request a translation simultaneously.

---

# 26. MMU Integration

The MMU sits directly between the CPU pipeline and the physical memory interface.

Conceptually:

                RV64GC CPU
                    |
             Virtual Addresses
              /           \
             v             v
           ITLB           DTLB
             \             /
              \           /
               +---------+
               |   MMU   |
               +----+----+
                    |
             Physical Address
                    |
                    v
           Wishbone Interconnect
                    |
          +---------+---------+
          |                   |
          v                   v
        Memory             Devices

The MMU therefore becomes responsible for producing the physical address used by the downstream memory system.

---

# 27. Pipeline Integration

Because the RV64GC processor is pipelined, address translation must be integrated into the existing 5-stage pipeline.

The relevant flow is:

IF → ID → EX → MEM → WB

Instruction translation primarily affects the fetch side.

Data translation primarily affects the memory stage.

A TLB miss can stall the affected pipeline path while the page-table walker performs the translation.

---

# 28. TLB Miss Handling

A typical data TLB miss looks like:


Virtual address
      |
      v
     DTLB
      |
     MISS
      |
      v
Pipeline waits
      |
      v
Page Table Walker
      |
      v
Wishbone
      |
      v
PTE resolution
      |
      v
DTLB refill
      |
      v
Physical address
      |
      v
Resume pipeline

The same mechanism is used for instruction translation through the ITLB.

---

# 29. TLB Entry Structure

A TLB entry must contain enough information to determine whether a translation matches.

A conceptual entry can contain:

+-------------------------------+
| Valid                         |
| Virtual Page Number           |
| Physical Page Number          |
| ASID                          |
| Page size                     |
| R / W / X / U                 |
| Global                        |
| Other required state          |
+-------------------------------+

The page size is important because a 1 GiB or 2 MiB leaf does not use all three VPN levels in the same way as a 4 KiB page.

---

# 30. TLB Lookup

A TLB lookup compares the requested virtual address against cached entries.

For example:

Virtual Address
       |
       v
Extract VPN
       |
       v
 Compare against TLB
       |
    +--+--+
    |     |
   Hit   Miss
    |      |
    v      v
Physical  Walker
Address

A successful hit avoids a page-table walk.

---

# 31. PWC Lookup

The Page-Walk Cache is checked during a page walk.

For example:

TLB miss
   |
   v
PWC lookup
   |
 +--+--+
 |     |
Hit   Miss
 |      |
 |      v
 |   Wishbone
 |      |
 +------+
    |
    v
Continue walk

The purpose is to avoid rereading frequently used non-leaf page-table entries.

---

# 32. Translation Permissions

Translation is only successful if both address translation and permission checking succeed.

The overall process is:

Virtual Address
      |
      v
TLB lookup
      |
      +---- Hit ----+
      |             |
     Miss           v
      |         Permission
      v           Check
Page Walk           |
      |             |
      +------+------+
             |
        +----+----+
        |         |
      Valid     Fault
        |         |
        v         v
Physical      Trap
Address

---

# 33. Error Handling

The walker and MMU must correctly handle invalid states.

Examples include:

- Invalid PTE
- Reserved PTE encoding
- Permission violation
- Misaligned large page
- Wishbone "ERR"
- Invalid physical address
- Fault during page-table access

These conditions must not leave the CPU waiting indefinitely.

Instead, they must produce a defined fault or bus error.

---

# 34. Verification

Verification is performed using simulation and waveform analysis.

Important signals include:

- Virtual address
- Physical address
- ITLB hit/miss
- DTLB hit/miss
- TLB replacement
- PWC hit/miss
- Page-walk state
- PTE address
- PTE data
- "satp"
- ASID
- Page permissions
- "A"
- "D"
- "SFENCE.VMA"
- Page-fault signals
- Access-fault signals
- Wishbone signals
- Pipeline stall signals

GTKWave can be used to inspect the complete translation process cycle by cycle.

---

# 35. Problems Encountered

### TLB and Pipeline Timing

The TLB operates directly on addresses generated by the pipeline.

A miss therefore cannot simply return a result immediately.

The affected pipeline path needs to stall while the page-table walker performs the required memory accesses.

Incorrect stall timing can cause:

- Repeated requests
- Lost requests
- Incorrect physical addresses
- Instructions or loads advancing too early

---

### Shared Walker

The ITLB and DTLB share one page-table walker.

This means simultaneous misses require arbitration.

The walker must ensure that:

Instruction request

and:

Data request

are never mixed together.

---

### Page Sizes

Supporting 4 KiB, 2 MiB, and 1 GiB pages increases the complexity of physical-address generation.

The walker must correctly determine which VPN fields come from the virtual address and which come from the PTE.

Large-page alignment must also be checked.

---

### PWC Consistency

The Page-Walk Cache introduces another cached copy of page-table information.

If page tables change, stale PWC entries can result in incorrect translations.

This makes "SFENCE.VMA" handling particularly important.

---

### Permission Checking

Permission checking depends on several conditions at once:

- Access type
- Privilege level
- R/W/X
- U
- MXR
- SUM

An error in one of these checks can allow an invalid access or incorrectly generate a page fault.

---

### A/D Bit Updates

Updating the Accessed and Dirty bits introduces writes into what would otherwise mainly be a read-only page walk.

The walker therefore needs to handle additional memory transactions while preserving the original translation request.

---

### Page-Walk Wishbone Transactions

The page-table walker uses the existing 64-bit Wishbone master.

Wait states and "ERR" responses therefore have to be handled correctly inside the walker state machine.

This adds additional states to the page-walk control logic.

---

### Trap Integration

A page fault does not only belong to the MMU.

It must travel through the existing trap infrastructure:

MMU
 ↓
Exception
 ↓
Pipeline Flush
 ↓
mcause / mtval / mepc
 ↓
mtvec
 ↓
Trap Handler

This requires the virtual-memory system and the previously implemented privileged architecture to work together correctly.

---

# 36. Reflection

This project introduces one of the biggest architectural changes to the processor so far because memory accesses are no longer simply physical addresses generated by the CPU.

The processor now works with:

Virtual Address
      |
      v
Translation
      |
      v
Physical Address

This required several new hardware structures to work together.

The ITLB and DTLB provide fast access to previously translated addresses, while the page-table walker handles misses by traversing the three-level Sv39 page tables. The PWC adds another level of caching by keeping frequently used non-leaf page-table entries available during future walks.

The project also builds directly on previous work. The CSR and trap implementation is required for page faults, while the 64-bit Wishbone interconnect provides the physical memory interface used by the page-table walker.

This makes Sv39 a major connection point between the CPU, memory system, privilege architecture, and bus architecture.

---

# 37. Future Improvements

Possible future improvements include:

- More complete Sv39 compliance testing
- TLB replacement policies
- Larger TLBs
- More advanced PWC structures
- More efficient page-walk caching
- TLB prefetching
- Improved walker arbitration
- Full Supervisor-mode testing
- Physical Memory Protection
- More advanced memory attributes
- Cache integration
- L1 instruction cache
- L1 data cache
- Linux-specific virtual-memory testing

The next stages can build on the MMU by adding caches between the processor and the physical memory system.

---

# 38. What's Next

The next step is to implement L1 Instruction Cache and L1 Data Cache.

The caches will be placed after virtual-address translation and before the physical memory system:


RV64GC CPU
     |
     +----------------+
     |                |
    ITLB             DTLB
     |                |
     +-------+--------+
             |
            MMU
             |
     +-------+-------+
     |               |
   L1 I-Cache      L1 D-Cache
     |               |
     +-------+-------+
             |
             v
    Wishbone / Memory System


The goal is to reduce the latency of repeated memory accesses while building the cache hierarchy required for a more complete RV64GC computer system.
