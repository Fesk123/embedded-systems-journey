# USB HID and Audio Interface

## Overview

The USB project introduces support for USB input devices and audio on the custom RV64GC computer.

The goal is to allow the computer to use standard USB peripherals, such as keyboards, mice, and audio devices, through the existing USB capabilities of the AMD Kria KV260 platform.

Instead of implementing a complete USB host controller in Verilog, this project provides a hardware interface between the RV64GC SoC and the KV260's Processing System (PS). The PS's existing xHCI controller handles USB enumeration and physical communication, while software running on the PS forwards HID events and audio data to the custom SoC.

The Verilog implementation provides FIFO buffering, a 64-bit Wishbone interface, control and status registers, and interrupt signalling.

The long-term goal is to give the RV64GC computer standard input and audio capabilities without requiring a separate USB controller implementation in the programmable logic (PL).

## Projects Goals

- Provide USB keyboard and mouse support for the RV64GC computer.
- Support USB audio data transfer.
- Connect the USB interface to the existing Wishbone interconnect.
- Provide FIFO buffering for HID events and audio data.
- Implement control and status registers.
- Support interrupt signalling for HID events and audio buffer conditions.
- Use the KV260's existing PS xHCI controller for physical USB communication.
- Establish a hardware-software interface for forwarding data between the PS and the RV64GC SoC.
- Verify FIFO operation, register access, and interrupt behaviour through simulation.

## Hardware Architecture

The USB subsystem consists of five Verilog modules.

### 1. Main USB Module ("USB.v")

The main module connects the USB-related components and provides the interface to the RV64GC SoC.

Its responsibilities include:
- Connecting the HID and audio FIFO interfaces.
- Providing the 64-bit Wishbone interface.
- Coordinating access to control and status registers.
- Exposing data and status information to the processor.
- Supporting interrupt signalling.

The module acts as the hardware-side connection between the RV64GC system and the PS software responsible for USB communication.

### 2. General FIFO ("usb_fifo.v")

The general FIFO module provides temporary data buffering between different parts of the USB subsystem.

Its responsibilities include:
- Storing data temporarily.
- Managing read and write operations.
- Tracking the number of stored entries.
- Indicating full and empty conditions.
- Handling differences in data-processing rates.

FIFO buffering helps prevent data loss when the producer and consumer operate at different speeds.

### 3. HID FIFO ("usb_hid_fifo.v")

The HID FIFO buffers events received from Human Interface Devices, such as keyboards and mice.

HID data is transferred as 32-bit events.

Its responsibilities include:
- Buffering incoming HID events.
- Making events available to the RV64GC processor.
- Tracking available entries.
- Reporting FIFO status.
- Supporting interrupt generation when HID events are available.

The PS software is responsible for receiving HID reports from the USB host controller and forwarding the relevant events to this FIFO interface.

### 4. Audio FIFO ("usb_audio_fifo.v")

The audio FIFO buffers digital audio data before it is consumed by the relevant audio subsystem.

The intended audio format is:
- Stereo audio.
- 16 bits per channel.
- 32 bits per stereo frame.
- 48 kHz sample rate.

Each 32-bit stereo frame contains one 16-bit sample for the left channel and one 16-bit sample for the right channel.

Its responsibilities include:
- Buffering audio frames.
- Managing read and write operations.
- Tracking buffer occupancy.
- Reporting full and empty conditions.
- Signalling high buffer occupancy where configured.

The PS software must forward audio data from the USB host controller to the audio FIFO. Actual audio playback also requires a suitable audio output path.

### 5. USB Control Registers ("usb_control_regs.v")

This module provides the memory-mapped control and status registers accessible through the Wishbone interface.

The registers are intended to provide:
- HID and audio enable controls.
- Connection status.
- FIFO status and occupancy information.
- Interrupt status.
- Interrupt control.
- Relevant subsystem configuration.

The register interface allows the RV64GC processor to monitor and control the USB subsystem without directly accessing the internal FIFO implementation.

## Wishbone Interface

The USB subsystem communicates with the RV64GC processor through a 64-bit Wishbone interface.

The interface provides access to:
- Control registers.
- Status registers.
- HID event data.
- Audio data.
- Interrupt status.

This allows the USB subsystem to be connected to the existing SoC interconnect and accessed through the processor's normal memory-mapped I/O mechanism.

The Wishbone interface handles communication between the processor and the USB bridge. It does not directly perform USB enumeration or physical USB transactions.

## Data Formats

### HID Events

HID events are transferred as 32-bit values.

These events represent input information received from devices such as keyboards and mice. The exact event encoding must be consistent between the PS software and the hardware interface.

### Audio Data

Audio data is transferred as 32-bit stereo frames.

Each frame contains:
- 16-bit left-channel sample.
- 16-bit right-channel sample.

The target format is 48 kHz stereo audio.

FIFO buffering is used to accommodate differences between the incoming audio stream and the rate at which the audio subsystem consumes data.

## Processing System Integration

The USB subsystem is designed as a bridge to the KV260's Processing System rather than a complete USB host controller.

The responsibilities are divided between the PS and the programmable logic.

KV260 Processing System:
- Uses the existing xHCI USB host controller.
- Handles USB enumeration.
- Handles communication with physical USB devices.
- Receives keyboard and mouse reports.
- Receives USB audio data.
- Runs software that forwards HID events and audio data to the custom SoC.

Programmable Logic:
- Provides the USB hardware bridge.
- Buffers HID events and audio frames.
- Exposes control and status registers.
- Provides the Wishbone interface.
- Generates relevant interrupts.

RV64GC processor:
- Reads HID events.
- Processes keyboard and mouse input.
- Accesses USB control and status registers.
- Receives audio data through the relevant interface.
- Uses the input and audio information in the operating system and applications.

The PS software is therefore an essential part of the complete USB solution. The Verilog modules alone do not provide direct USB host functionality.

## Interrupt Handling

The USB subsystem supports interrupt signalling for relevant events.

The intended interrupt sources include:
- New HID events.
- High audio FIFO occupancy.
- Other relevant status conditions.

Interrupts allow the processor to react to USB events without continuously polling every register.

Correct operation requires the USB interrupt signals to be connected to the RV64GC SoC's interrupt architecture. Full interrupt delivery depends on the integration with the processor and interrupt controller.

## Main Challenges

### USB Host Functionality

The Verilog design does not implement a complete USB host controller. It relies on the KV260's existing PS xHCI controller and requires software to forward data to the programmable logic.

The software and hardware interfaces must therefore agree on the data format, transfer protocol, and buffer handling.

### FIFO Management

The HID and audio FIFOs must handle differences in processing speed without losing data.

The design must correctly handle full and empty conditions, including situations where incoming data arrives faster than the RV64GC system can consume it.

### Audio Timing

Audio data must be delivered at a sufficiently consistent rate to avoid interruptions.

The 48 kHz stereo format requires predictable buffer handling and coordination between the PS software, audio FIFO, and audio output subsystem.

### Clock-Domain Crossing

The PS and PL may operate using different clock domains.

If data or control signals cross between asynchronous clock domains, suitable synchronization or asynchronous FIFO mechanisms are required to avoid metastability and data corruption.

### Device Disconnection

The system must handle situations where a USB device is disconnected while data is being transferred.

This is particularly important for audio devices, where an interrupted stream must not leave the FIFO or handshake logic in an invalid state.

### Interrupt Integration

The USB subsystem must communicate relevant events to the processor through the SoC's interrupt architecture.

Correct interrupt generation, acknowledgement, and clearing must be verified during integration.

## Current Limitations

- The module is a bridge to the KV260's PS, not a complete USB host controller.
- USB enumeration and physical communication are handled by the PS xHCI controller.
- PS software must forward HID events and audio data.
- Complete communication with the PS software remains to be verified.
- The latest corrected HID FIFO counter test has not yet been confirmed.
- Audio disconnection and FIFO-full behaviour require further testing.
- Potential clock-domain crossings must be handled correctly.
- Actual audio playback requires a suitable audio output path.
- Full functionality depends on integration with the RV64GC SoC and its software.

## Future Improvements

Potential improvements include:
- Completing and verifying the PS-side USB forwarding software.
- Improving FIFO overflow and underflow handling.
- Verifying clock-domain crossing behaviour.
- Improving audio stream management.
- Integrating the USB subsystem with the SoC interrupt controller.
- Testing real USB keyboards and mice.
- Testing USB audio devices on the KV260.
- Developing the required software interfaces and drivers for the RV64GC system.

## What's Next — New Development Plan

The development strategy is now shifting from building individual hardware modules toward integrating and testing the complete RV64GC computer on the KV260.

The first step will be "KV260_FPGA_Bringup", focusing on the Vivado environment, clocks, reset, GPIO/Pmod, counters, and ILA debugging.

After that, the existing processor, MMU, Wishbone interconnect, caches, DDR, peripherals, networking, USB, and graphics will be integrated incrementally into a growing top-level design.

The final stages will combine all hardware into "RV64GC_Full_SoC", followed by boot firmware, Linux support, drivers, and complete system verification.
Goal: Move from individually developed and simulated components toward a fully integrated, FPGA-verified RV64GC computer capable of running its own software and eventually Linux.

