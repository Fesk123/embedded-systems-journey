# System Control & Watchdog

## Overview

This project implements a programmable watchdog timer for the custom RV64GC computer.

A watchdog timer is used to detect situations where a system or software component stops responding. If the watchdog is not serviced within its configured timeout period, it can generate an interrupt and issue a system reset request.

The project currently contains one main Verilog module:

- "Watchdog_Timer.v"

The module provides a 64-bit watchdog timer with a Wishbone register interface, timeout detection, interrupt signalling, and system reset-request functionality.

The goal is to improve system reliability and provide a mechanism for recovering from situations where the computer becomes unresponsive.

## Project Goals

- Implement a programmable 64-bit watchdog timer.
- Provide configuration and status registers through Wishbone.
- Support configurable timeout behaviour.
- Detect when the watchdog timeout expires.
- Generate an interrupt when the timeout condition occurs.
- Provide a system reset request.
- Verify timer operation and timeout handling through simulation.
- Prepare the watchdog for integration into the complete RV64GC SoC.

## Architecture

### 1. Watchdog Timer ("Watchdog_Timer.v")

The watchdog timer monitors whether it is serviced within a configured time period.

Its main characteristics include:
- 64-bit timer counter.
- Programmable timeout configuration.
- Wishbone register interface.
- Timeout detection.
- Interrupt output.
- System reset-request output.

The processor or system software can configure and control the watchdog through its memory-mapped Wishbone interface.

The watchdog then tracks the elapsed time and checks whether the configured timeout has been reached.

### 2. Wishbone Register Interface

The watchdog uses Wishbone for communication with the RV64GC processor.

The interface provides access to the watchdog's configuration and status information.

Its intended functions include:
- Configuring the timeout period.
- Controlling watchdog operation.
- Accessing status information.
- Handling timeout-related conditions.

The exact register layout and access behaviour are defined by the RTL implementation.

### 3. Timeout Detection

The watchdog monitors its 64-bit counter and checks whether the configured timeout condition has occurred.

When the timeout expires, the module can generate the corresponding event signals.

This allows the SoC to detect situations such as:
- Software becoming unresponsive.
- A processing task failing to complete.
- A subsystem becoming stuck.
- The system failing to service the watchdog.

The watchdog provides a recovery mechanism for these situations, but it cannot independently determine why the system stopped responding.

### 4. Interrupt Handling

The watchdog can generate an interrupt when a timeout occurs.

This allows the processor to react to the event through the existing interrupt architecture.

Depending on the system configuration, software may use the interrupt to record diagnostic information or initiate a recovery procedure.

Full interrupt delivery requires integration with the SoC's interrupt controller and CPU interrupt-handling logic.

### 5. System Reset Request

In addition to interrupt signalling, the watchdog can issue a system reset request.

The request is intended to be handled by the SoC's reset infrastructure.

This separation allows the watchdog to identify a timeout condition while the system reset logic controls how the affected components are reset.

The reset-request signal does not by itself guarantee that the entire computer will restart. The final behaviour depends on its connection to the system reset controller and the reset strategy used by the integrated SoC.

## Integration with the RV64GC SoC

The watchdog is designed to connect to the existing Wishbone interconnect.

The RV64GC processor can configure and monitor the watchdog using memory-mapped accesses.

The interrupt and reset-request outputs are intended to connect to the corresponding SoC infrastructure.

The main integration requirements are:
- Assigning a valid Wishbone address range.
- Connecting the watchdog to the appropriate bus interface.
- Connecting the interrupt output to the interrupt architecture.
- Connecting the reset request to the system reset controller.
- Defining appropriate reset behaviour.
- Ensuring that the watchdog itself remains operational when the monitored system becomes unresponsive.

The watchdog should be integrated so that it can provide useful recovery behaviour without being unintentionally disabled by the same failure it is intended to detect.

## Verification

### Text-Based Testbench

The watchdog is tested through the shared testbench:

"text_Sim_Projects_13_16.v"

The testbench includes a dedicated Watchdog test group.

The tests cover:
- Watchdog configuration.
- Timer operation.
- Timeout detection.
- Interrupt generation.
- Reset-request generation.
- Status and control register behaviour.

The testbench checks that the watchdog responds correctly when the configured timeout condition is reached.

### Latest Verification Results

| Test group | Result |
|---|---:|
| Watchdog | 0 errors |

The watchdog test group currently reports zero errors.

## Shared Verification – Projects 13–16

The watchdog is also part of a larger testbench covering all four projects.

The shared testbench contains eight separate test groups covering twelve Verilog modules.

The latest reported results are:

| Test group | Result |
|---|---:|
| PMA | 0 errors |
| PMP | 0 errors |
| PMU | 0 errors |
| Async FIFO + CDC | 0 errors |
| Cache Maintenance | 0 errors |
| L2 Cache | 0 errors |
| Wishbone–AXI4 Bridge | 0 errors |
| Watchdog | 0 errors |

The PMA implementation previously had three failing checks. The code was corrected to preserve region attributes in certain denied-access cases, and the correction has subsequently been verified.

All eight test groups currently report zero errors.

These results demonstrate that the tested module functionality passes the current testbench. They do not yet establish that all modules are fully integrated or verified on physical FPGA hardware.

## Main Challenges

### Timeout Configuration

The watchdog must correctly interpret its configured timeout value and detect when the corresponding period has elapsed.

### Counter Behaviour

A 64-bit counter must operate reliably and handle the configured timeout conditions without incorrect overflow or comparison behaviour.

### Recovery Behaviour

Generating an interrupt or reset request is only part of the recovery process.

The SoC must correctly handle the request and ensure that the reset infrastructure can recover the relevant system components.

### Interrupt Integration

The watchdog interrupt must be connected to the processor's interrupt architecture and handled correctly by software.

### Independent Operation

A watchdog is most useful when it can continue operating even if the subsystem being monitored becomes unresponsive.

Its clock, reset, and integration strategy must therefore be considered carefully.

## Current Status and Limitations

The "Watchdog_Timer.v" module has been developed and tested through the shared text-based testbench.

The latest watchdog test group reports zero errors.

Further work includes:
- Integration into the RV64GC top-level.
- Connecting the watchdog to the Wishbone interconnect.
- Integrating its interrupt with the PLIC.
- Connecting its reset request to the system reset controller.
- Testing timeout recovery on the KV260.
- Verifying behaviour during system-level failures.

The current simulation results verify the tested watchdog functionality, but physical reset and recovery behaviour still require FPGA-level testing.
