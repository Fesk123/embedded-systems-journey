`timescale 1ns/1ps


// GPU Display and Read-Memory Subsystem

// Combines framebuffer scanout and a second read client behind a fair arbiter.
// Client 0 is reserved for display scanout. Client 1 is intended for the texture cache or another GPU read client.
//
// Connect the DMA-side ports to the read client interface on gpu.v.
// The pixel timing signals come from gpu_video_timing inside gpu.v.

module gpu_display_subsystem #(
    parameter integer XLEN = 64,
    parameter integer FIFO_ADDR_WIDTH = 9,
    parameter integer MAX_BURST = 16,
    parameter integer PREFILL_WORDS = 32
)(
    input clk_i,
    input pixel_clk_i,
    input rst_i,

    // Framebuffer configuration.
    input scanout_start_i,
    input [XLEN-1:0] framebuffer_base_i,
    input [31:0] framebuffer_stride_i,
    input [15:0] framebuffer_width_i,
    input [15:0] framebuffer_height_i,

    // Pixel timing feedback from gpu.v.
    input pixel_active_i,
    input [11:0] pixel_x_i,
    output [31:0] pixel_data_o,
    output pixel_ready_o,
    output pixel_underflow_o,
    output scanout_error_o,

    // Second read client. Connect gpu_texture_cache.v here.
    input texture_req_i,
    input [XLEN-1:0] texture_addr_i,
    input [7:0] texture_beats_i,
    output texture_req_ready_o,
    output texture_valid_o,
    output [63:0] texture_data_o,
    output texture_last_o,
    input texture_data_ready_i,
    output texture_done_o,
    output texture_error_o,

    // Read DMA side. Connect to gpu.v rd_* ports.
    output dma_start_o,
    output [XLEN-1:0] dma_addr_o,
    output [7:0] dma_beats_o,
    input dma_busy_i,
    input dma_valid_i,
    input [63:0] dma_data_i,
    input dma_last_i,
    output dma_ready_o,
    input dma_done_i,
    input dma_error_i
);

    wire scanout_req;
    wire [XLEN-1:0] scanout_addr;
    wire [7:0] scanout_beats;
    wire scanout_req_ready;
    wire scanout_valid;
    wire [63:0] scanout_data;
    wire scanout_last;
    wire scanout_data_ready;
    wire scanout_done;
    wire scanout_error;

    gpu_framebuffer_scanout #(
        .XLEN(XLEN),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .MAX_BURST(MAX_BURST),
        .PREFILL_WORDS(PREFILL_WORDS)
    ) scanout (
        .clk_i(clk_i),
        .pixel_clk_i(pixel_clk_i),
        .rst_i(rst_i),
        .start_i(scanout_start_i),
        .framebuffer_base_i(framebuffer_base_i),
        .framebuffer_stride_i(framebuffer_stride_i),
        .framebuffer_width_i(framebuffer_width_i),
        .framebuffer_height_i(framebuffer_height_i),
        .rd_req_o(scanout_req),
        .rd_addr_o(scanout_addr),
        .rd_beats_o(scanout_beats),
        .rd_req_ready_i(scanout_req_ready),
        .rd_busy_i(1'b0),
        .rd_valid_i(scanout_valid),
        .rd_data_i(scanout_data),
        .rd_last_i(scanout_last),
        .rd_data_ready_o(scanout_data_ready),
        .rd_done_i(scanout_done),
        .rd_error_i(scanout_error),
        .pixel_active_i(pixel_active_i),
        .pixel_x_i(pixel_x_i),
        .pixel_data_o(pixel_data_o),
        .pixel_ready_o(pixel_ready_o),
        .pixel_underflow_o(pixel_underflow_o),
        .scanout_error_o(scanout_error_o)
    );

    gpu_read_arbiter #(
        .XLEN(XLEN)
    ) read_arbiter (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .c0_req_i(scanout_req),
        .c0_addr_i(scanout_addr),
        .c0_beats_i(scanout_beats),
        .c0_ready_o(scanout_req_ready),
        .c0_valid_o(scanout_valid),
        .c0_data_o(scanout_data),
        .c0_last_o(scanout_last),
        .c0_data_ready_i(scanout_data_ready),
        .c0_done_o(scanout_done),
        .c0_error_o(scanout_error),
        .c1_req_i(texture_req_i),
        .c1_addr_i(texture_addr_i),
        .c1_beats_i(texture_beats_i),
        .c1_ready_o(texture_req_ready_o),
        .c1_valid_o(texture_valid_o),
        .c1_data_o(texture_data_o),
        .c1_last_o(texture_last_o),
        .c1_data_ready_i(texture_data_ready_i),
        .c1_done_o(texture_done_o),
        .c1_error_o(texture_error_o),
        .dma_start_o(dma_start_o),
        .dma_addr_o(dma_addr_o),
        .dma_beats_o(dma_beats_o),
        .dma_busy_i(dma_busy_i),
        .dma_valid_i(dma_valid_i),
        .dma_data_i(dma_data_i),
        .dma_last_i(dma_last_i),
        .dma_ready_o(dma_ready_o),
        .dma_done_i(dma_done_i),
        .dma_error_i(dma_error_i)
    );

endmodule