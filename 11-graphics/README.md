# Graphics Processing Unit (GPU)

## Overview

This project develops a custom graphics processing unit (GPU) in Verilog for the RV64GC computer.

The goal is to provide the computer with hardware-accelerated graphics capabilities, creating a foundation for a graphical Linux environment, web browsing, 2D graphics, and basic 3D applications.

The GPU is designed as a modular system connected to external DDR memory through an AXI interface. It includes framebuffer storage, DMA transfers, memory arbitration, a 2D graphics engine, display scanout, and a 3D graphics pipeline.

Rather than relying entirely on the CPU to generate and transfer every pixel, the GPU performs graphics-related operations in dedicated hardware. This reduces the amount of work the processor must perform and allows graphics operations to run independently where the architecture permits.

## Project Goals

- Develop a custom GPU using Verilog.
- Provide framebuffer-based graphics output.
- Transfer graphics data efficiently between the GPU and DDR memory.
- Reduce CPU involvement through DMA.
- Support basic 2D graphics operations.
- Implement a display scanout pipeline.
- Develop a triangle rasterizer for basic 3D graphics.
- Support vertex processing, fragment processing, and shader calculations.
- Implement depth buffering for visibility testing.
- Improve texture access through caching.
- Integrate the GPU with the RV64GC SoC.
- Verify AXI transactions and memory transfers in simulation.
- Prepare the GPU for physical FPGA verification on the KV260.

## GPU Architecture

### 1. Framebuffer

The framebuffer stores the pixel data used to produce the displayed image.

Each pixel represents part of the final image, with its colour determined by the selected pixel format.

The framebuffer provides the connection between graphics rendering and display output.

It's responsibilities include:
- Storing image data.
- Providing pixel data to the display scanout module.
- Supporting updates from the graphics pipeline.
- Using external DDR memory where configured.
- Coordinating access with other GPU components.

Framebuffer performance is important because the display subsystem must retrieve pixel data continuously while other GPU modules may also need memory access.

### 2. FIFO

The FIFO module provides temporary queues between GPU components.

Its responsibilities include:
- Buffering data between processing stages.
- Handling differences in processing speed.
- Preventing short-term variations in data flow from immediately stalling other modules.
- Indicating when queues are full or empty.
- Supporting reliable communication between connected stages.

FIFO buffering helps decouple GPU components, although it cannot compensate for sustained memory-bandwidth limitations.

### 3. AXI DMA

The AXI DMA module transfers graphics data between the GPU and external DDR memory.

Its purpose is to move larger amounts of data without requiring the CPU to handle every individual transfer.

Its responsibilities include:
- Initiating memory transfers.
- Reading graphics data from DDR.
- Writing graphics results to memory.
- Supporting burst-based transfers where implemented.
- Tracking transfer progress and completion.
- Handling AXI handshakes and errors.

DMA is important for framebuffer access, texture retrieval, and other graphics operations involving large amounts of data.

The actual throughput depends on the AXI configuration, burst lengths, memory arbitration, and DDR performance.

### 4. Read/Write Arbiter

The read/write arbiter coordinates memory access between GPU components.

Several modules may need to access DDR memory at the same time. The arbiter determines which request can proceed and manages access to the shared memory interface.

Its responsibilities include:
- Coordinating competing read requests.
- Coordinating competing write requests.
- Managing access to shared memory resources.
- Preventing conflicting transactions on the relevant interfaces.
- Supporting efficient use of the available memory bandwidth.

Arbitration is particularly important when framebuffer scanout, texture sampling, and graphics rendering operate concurrently.

### 5. 2D Engine / Blitter

The 2D engine performs basic graphics operations without requiring the full 3D pipeline.

Supported or intended operations depend on the current implementation, but the module is designed for tasks such as:
- Copying image regions.
- Drawing rectangles.
- Moving blocks of pixel data.
- Performing basic framebuffer operations.

A dedicated blitter can accelerate common graphics operations that would otherwise require repeated CPU instructions.

### 6. Scanout / Display

The scanout module reads pixel data from the framebuffer and produces the output required by the display interface.

Its responsibilities include:
- Reading framebuffer contents.
- Tracking the current pixel position.
- Generating the pixel stream.
- Maintaining the required display timing where implemented.
- Providing pixel and synchronization signals to the selected display output interface.

Scanout must retrieve pixel data at a predictable rate to avoid display corruption or interruptions.

Physical display output depends on the configured interface, the KV260 hardware connections, and successful FPGA integration.

### 7. Vertex Fetch

The vertex-fetch stage retrieves geometry data required for 3D rendering.

For example, a triangle is defined by three vertices. Each vertex can contain information such as its position and other attributes required by the rendering pipeline.

The module is intended to:
- Retrieve vertex data.
- Provide geometry information to subsequent processing stages.
- Coordinate memory requests.
- Deliver vertices in the required order.

The exact vertex format and supported attributes depend on the implementation.

### 8. Triangle Rasterizer

The triangle rasterizer converts triangle geometry into fragments corresponding to pixel locations.

Instead of processing a triangle as a single object, rasterization determines which parts of the image are covered by the triangle.

Its responsibilities include:
- Processing triangle geometry.
- Determining covered pixel positions.
- Generating fragments for subsequent processing.
- Supporting the flow of geometry through the 3D pipeline.

Rasterization forms the basis of triangle-based 3D graphics.

### 9. Shader

The shader stage performs graphics calculations used to determine the appearance of rendered geometry.

Depending on the implemented shader functionality, these calculations may include:
- Transforming or processing vertex attributes.
- Calculating fragment or pixel properties.
- Performing arithmetic operations.
- Preparing colour and other values for later stages.

A programmable shader provides greater flexibility than a fixed-function graphics pipeline.

However, implementing a shader module does not automatically provide compatibility with established graphics APIs or existing GPU software. That requires additional hardware and software support.

### 10. Fragment Memory Stage

The fragment memory stage coordinates memory operations associated with rendered fragments.

Its responsibilities may include:
- Reading existing pixel or fragment data.
- Writing updated graphics results.
- Coordinating memory access with the rendering pipeline.
- Handling relevant data dependencies.
- Connecting fragment processing to framebuffer and depth-buffer operations.

Correct ordering is important when multiple fragments affect the same pixel or when depth testing determines whether a fragment should be written.

### 11. Depth Buffer

The depth buffer stores depth values associated with rendered pixels or fragments.

When multiple objects overlap on the screen, depth information helps determine which object should appear in front of the others.

The depth-buffer stage is intended to:
- Store depth values.
- Retrieve existing depth values.
- Compare incoming depth values with stored values.
- Support visibility decisions.
- Update depth information when appropriate.

Depth buffering is a fundamental component of a basic 3D graphics pipeline.

### 12. Texture Cache

The texture cache stores recently accessed texture data so that repeated requests can be served more efficiently.

Textures provide image information used to determine the appearance of rendered surfaces.

The cache is intended to:
- Store recently accessed texture data.
- Reduce repeated external memory accesses.
- Improve access to frequently used texture regions.
- Coordinate texture requests with the memory subsystem.

Cache effectiveness depends on the access pattern, cache capacity, replacement policy, and memory latency.

### 13. 3D Engine

The 3D engine coordinates the GPU's 3D processing stages.

It connects the relevant components involved in geometry retrieval, rasterization, shading, fragment processing, depth testing, and texture access.

Its purpose is to provide an integrated pipeline for rendering basic 3D graphics.

The actual capabilities depend on which stages are implemented, connected, and verified.

## Integration with the RV64GC SoC

The GPU is designed to integrate with the existing RV64GC computer and use external DDR memory for graphics data.

The processor and GPU have different responsibilities.

RV64GC processor:
- Runs software and graphics related programs.
- Configures GPU operations through the relevant control interface.
- Prepares graphics commands and data.
- Handles higher level application logic.

GPU:
- Performs graphics operations in dedicated hardware.
- Processes geometry and fragments where supported.
- Transfers graphics data through DMA.
- Reads and updates framebuffer and other graphics memory.
- Generates display output through the scanout pipeline.

DDR memory:
- Stores framebuffer data.
- Provides memory for graphics operations.
- Stores geometry and texture data where required.
- Acts as shared storage for GPU-related transfers.

AXI interface:
- Connects the GPU's memory-transfer path to the system memory architecture.
- Supports the relevant read and write transactions.
- Provides a path for burst transfers where implemented.

The GPU is designed to reduce unnecessary CPU involvement, but its real performance depends on the completed integration and the available memory bandwidth.

## Main Challenges

### Memory Bandwidth

Framebuffer scanout, texture sampling, DMA, and fragment processing may compete for access to DDR memory.

The memory subsystem must provide sufficient bandwidth and reasonable latency for these operations.

### AXI Correctness

AXI transactions must follow the required handshake and response rules. Burst length, data ordering, transaction completion, and error handling must be correct.

### Arbitration and Backpressure

GPU components may request memory access simultaneously. Arbitration and FIFO buffering must prevent invalid transactions and handle situations where downstream components cannot accept more data.

### Rendering Dependencies

The 3D pipeline contains dependencies between vertex processing, rasterization, shading, fragment operations, and depth testing.

Incorrect ordering or incomplete synchronization can produce rendering errors.

### Display Timing

The scanout module must supply pixel data at the required rate. Memory delays and insufficient buffering can interrupt the output stream.

### FPGA Resource Constraints

A GPU implemented in programmable logic must fit within the available FPGA resources and meet timing requirements.

Framebuffer size, cache capacity, pipeline complexity, and memory interfaces all affect implementation feasibility.

## Current Limitations

- The latest reported verification covers specific AXI and memory-transfer tests, not every GPU feature.
- Complete Vivado integration remains a major next step.
- Physical FPGA operation has not been established by the reported simulation results.
- Actual display output must be verified on the KV260.
- Full compatibility with a graphical Linux environment requires additional system and software integration.
- Browser rendering and game performance depend on the available graphics features, drivers, software support, and overall system performance.
- Implementing a custom GPU does not automatically provide compatibility with APIs such as OpenGL or Vulkan.

## Future Improvements

Potential improvements include:
- Optimizing DDR access and memory arbitration.
- Improving DMA throughput.
- Expanding framebuffer functionality.
- Improving 2D graphics performance.
- Extending rasterization and shader capabilities.
- Improving texture-cache performance.
- Adding more advanced graphics features.
- Developing software interfaces and drivers for the RV64GC system.
- Integrating the GPU with a supported graphical software stack.
- Measuring rendering performance on the KV260.

## What's Next

The next step is Vivado Integration and FPGA Hardware Verification.

The focus will be on integrating the GPU's RTL modules into the Vivado project, connecting the AXI memory path, and verifying that the design can operate within the KV260's FPGA resources and timing constraints.

Initial hardware tests should establish reliable DDR access, DMA operation, framebuffer handling, and display output. More advanced graphics functions can then be tested incrementally.

Goal: Demonstrate that the custom GPU can operate on the KV260 FPGA and provide a foundation for graphical output and future graphics acceleration in the RV64GC computer.
