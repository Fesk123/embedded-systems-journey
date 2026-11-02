`timescale 1ns/1ps


// GPU Top Module

// RV64GC SoC graphics subsystem.
//
// The CPU controls this block through a 32/64-bit Wishbone slave port.
// Framebuffer writes use AXI4 bursts to shared DDR through a fair two-clientarbiter. 
// The read DMA is exposed as a client port for scanout and textures.
//
// LANES is used by the independent 3D pipeline modules. The 2D fill engine remains memory-bus limited and does not duplicate the external DDR port.

module gpu #(
    parameter integer XLEN = 64,
    parameter integer LANES = 1,
    parameter integer FIFO_DEPTH = 16,
    parameter integer FIFO_ADDR_WIDTH = 4,
    parameter integer MAX_BURST = 16,
    parameter integer VIDEO_WIDTH = 1280,
    parameter integer VIDEO_HEIGHT = 720,
    parameter integer H_FRONT = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BACK = 220,
    parameter integer V_FRONT = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BACK = 20
)(
    input clk_i,
    input rst_i,

    // Wishbone slave interface from the RV64GC SoC.
    input [XLEN-1:0] wb_adr_i,
    input [XLEN-1:0] wb_dat_i,
    input [XLEN/8-1:0] wb_sel_i,
    input wb_cyc_i,
    input wb_stb_i,
    input wb_we_i,
    output [XLEN-1:0] wb_dat_o,
    output wb_ack_o,
    output wb_err_o,

    // AXI4 read client interface. Connect scanout and texture clients through gpu_read_arbiter.v when both are used.
    input rd_start_i,
    input [XLEN-1:0] rd_addr_i,
    input [7:0] rd_beats_i,
    output rd_busy_o,
    output rd_valid_o,
    output [63:0] rd_data_o,
    output rd_last_o,
    input rd_ready_i,
    output rd_done_o,
    output rd_error_o,

    // AXI4 master interface to shared DDR.
    output [3:0] m_axi_awid_o,
    output [XLEN-1:0] m_axi_awaddr_o,
    output [7:0] m_axi_awlen_o,
    output [2:0] m_axi_awsize_o,
    output [1:0] m_axi_awburst_o,
    output m_axi_awlock_o,
    output [3:0] m_axi_awcache_o,
    output [2:0] m_axi_awprot_o,
    output [3:0] m_axi_awqos_o,
    output m_axi_awvalid_o,
    input m_axi_awready_i,

    output [63:0] m_axi_wdata_o,
    output [7:0] m_axi_wstrb_o,
    output m_axi_wlast_o,
    output m_axi_wvalid_o,
    input m_axi_wready_i,

    input [3:0] m_axi_bid_i,
    input [1:0] m_axi_bresp_i,
    input m_axi_bvalid_i,
    output m_axi_bready_o,

    output [3:0] m_axi_arid_o,
    output [XLEN-1:0] m_axi_araddr_o,
    output [7:0] m_axi_arlen_o,
    output [2:0] m_axi_arsize_o,
    output [1:0] m_axi_arburst_o,
    output m_axi_arlock_o,
    output [3:0] m_axi_arcache_o,
    output [2:0] m_axi_arprot_o,
    output [3:0] m_axi_arqos_o,
    output m_axi_arvalid_o,
    input m_axi_arready_i,

    input [3:0] m_axi_rid_i,
    input [63:0] m_axi_rdata_i,
    input [1:0] m_axi_rresp_i,
    input m_axi_rlast_i,
    input m_axi_rvalid_i,
    output m_axi_rready_o,

    // Video timing and pixel interface.
    input pixel_clk_i,
    input video_enable_i,
    input [31:0] pixel_data_i,
    output [11:0] video_x_o,
    output [11:0] video_y_o,
    output video_hsync_o,
    output video_vsync_o,
    output video_de_o,
    output [23:0] video_rgb_o,

    // 3D triangle command and fragment stream.
    // A SoC command-register wrapper can drive triangle_start_i.
    input triangle_start_i,
    input signed [15:0] triangle_x0_i,
    input signed [15:0] triangle_y0_i,
    input signed [15:0] triangle_x1_i,
    input signed [15:0] triangle_y1_i,
    input signed [15:0] triangle_x2_i,
    input signed [15:0] triangle_y2_i,
    input [15:0] triangle_fb_width_i,
    input [15:0] triangle_fb_height_i,
    input [3:0] triangle_shader_opcode_i,
    input [31:0] triangle_uniform_color_i,
    input [LANES*32-1:0] triangle_texture_color_i,
    output fragment_valid_o,
    input fragment_ready_i,
    output [LANES-1:0] fragment_mask_o,
    output [LANES*16-1:0] fragment_x_o,
    output [LANES*16-1:0] fragment_y_o,
    output [LANES*32-1:0] fragment_color_o,
    output triangle_busy_o,
    output triangle_done_o,
    output triangle_error_o,

    // Auxiliary write client. Connect gpu_2d_blitter or another writer here.
    input aux_wr_start_i,
    input [XLEN-1:0] aux_wr_addr_i,
    input [7:0] aux_wr_beats_i,
    output aux_wr_ready_o,
    input aux_wr_valid_i,
    input [63:0] aux_wr_data_i,
    input [7:0] aux_wr_strb_i,
    output aux_wr_data_ready_o,
    output aux_wr_done_o,
    output aux_wr_error_o,

    output gpu_irq_o,
    output gpu_busy_o,
    output [FIFO_ADDR_WIDTH:0] command_count_o,
    output gpu_command_error_o,

    // Framebuffer configuration is shared with scanout and the 3D backend.
    output [XLEN-1:0] framebuffer_base_o,
    output [31:0] framebuffer_stride_o,
    output [31:0] framebuffer_width_o,
    output [31:0] framebuffer_height_o
);

    localparam integer CMD_WIDTH = XLEN + 196;

    wire [XLEN-1:0] fb_base;
    wire [31:0] fb_stride;
    wire [31:0] fb_width;
    wire [31:0] fb_height;
    wire [31:0] fill_color;
    wire [15:0] rect_x;
    wire [15:0] rect_y;
    wire [15:0] rect_width;
    wire [15:0] rect_height;

    wire cmd_push;
    wire [CMD_WIDTH-1:0] cmd_payload;
    wire cmd_ready;

    wire engine_start;
    wire [XLEN-1:0] engine_fb_base;
    wire [31:0] engine_fb_stride;
    wire [31:0] engine_fb_width;
    wire [31:0] engine_fb_height;
    wire [31:0] engine_color;
    wire [15:0] engine_rect_x;
    wire [15:0] engine_rect_y;
    wire [15:0] engine_rect_width;
    wire [15:0] engine_rect_height;

    wire engine_busy;
    wire engine_done;
    wire engine_error;
    wire command_error;
    wire processor_busy;

    wire fill_wr_start;
    wire [XLEN-1:0] fill_wr_addr;
    wire [7:0] fill_wr_beats;
    wire fill_wr_start_ready;
    wire fill_wr_data_valid;
    wire [63:0] fill_wr_data;
    wire [7:0] fill_wr_strb;
    wire fill_wr_data_ready;
    wire fill_wr_done;
    wire fill_wr_error;

    wire dma_wr_start;
    wire [XLEN-1:0] dma_wr_addr;
    wire [7:0] dma_wr_beats;
    wire dma_wr_busy;
    wire dma_wr_data_valid;
    wire [63:0] dma_wr_data;
    wire [7:0] dma_wr_strb;
    wire dma_wr_data_ready;
    wire dma_wr_done;
    wire dma_wr_error;

    wire dma_rd_busy;
    wire dma_rd_valid;
    wire [63:0] dma_rd_data;
    wire dma_rd_last;
    wire dma_rd_done;
    wire dma_rd_error;

    assign gpu_busy_o = processor_busy || triangle_busy_o;
    assign gpu_command_error_o = command_error;
    assign framebuffer_base_o = fb_base;
    assign framebuffer_stride_o = fb_stride;
    assign framebuffer_width_o = fb_width;
    assign framebuffer_height_o = fb_height;

    gpu_registers #(
        .XLEN(XLEN),
        .CMD_WIDTH(CMD_WIDTH),
        .LANES(LANES)
    ) registers (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_stb_i(wb_stb_i),
        .wb_we_i(wb_we_i),
        .wb_dat_o(wb_dat_o),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),
        .engine_busy_i(processor_busy || triangle_busy_o),
        .engine_done_i(engine_done | triangle_done_o),
        .engine_error_i(engine_error | command_error | triangle_error_o),
        .cmd_push_o(cmd_push),
        .cmd_payload_o(cmd_payload),
        .cmd_ready_i(cmd_ready),
        .irq_o(gpu_irq_o),
        .fb_width_o(fb_width),
        .fb_height_o(fb_height),
        .fb_stride_o(fb_stride),
        .fb_base_o(fb_base),
        .fill_color_o(fill_color),
        .rect_x_o(rect_x),
        .rect_y_o(rect_y),
        .rect_width_o(rect_width),
        .rect_height_o(rect_height)
    );

    gpu_command_processor #(
        .XLEN(XLEN),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .CMD_WIDTH(CMD_WIDTH)
    ) command_processor (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_push_i(cmd_push),
        .cmd_payload_i(cmd_payload),
        .cmd_ready_o(cmd_ready),
        .engine_busy_i(engine_busy || triangle_busy_o),
        .engine_done_i(engine_done),
        .engine_error_i(engine_error),
        .engine_start_o(engine_start),
        .engine_fb_base_o(engine_fb_base),
        .engine_fb_stride_o(engine_fb_stride),
        .engine_fb_width_o(engine_fb_width),
        .engine_fb_height_o(engine_fb_height),
        .engine_color_o(engine_color),
        .engine_rect_x_o(engine_rect_x),
        .engine_rect_y_o(engine_rect_y),
        .engine_rect_width_o(engine_rect_width),
        .engine_rect_height_o(engine_rect_height),
        .busy_o(processor_busy),
        .command_error_o(command_error),
        .queue_count_o(command_count_o)
    );

    gpu_2d_engine #(
        .XLEN(XLEN),
        .MAX_BURST(MAX_BURST)
    ) fill_engine (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(engine_start),
        .fb_base_i(engine_fb_base),
        .fb_stride_i(engine_fb_stride),
        .fb_width_i(engine_fb_width),
        .fb_height_i(engine_fb_height),
        .color_i(engine_color),
        .rect_x_i(engine_rect_x),
        .rect_y_i(engine_rect_y),
        .rect_width_i(engine_rect_width),
        .rect_height_i(engine_rect_height),
        .busy_o(engine_busy),
        .done_o(engine_done),
        .error_o(engine_error),
        .dma_wr_start_o(fill_wr_start),
        .dma_wr_addr_o(fill_wr_addr),
        .dma_wr_beats_o(fill_wr_beats),
        .dma_wr_start_ready_i(fill_wr_start_ready),
        .dma_wr_data_valid_o(fill_wr_data_valid),
        .dma_wr_data_o(fill_wr_data),
        .dma_wr_strb_o(fill_wr_strb),
        .dma_wr_data_ready_i(fill_wr_data_ready),
        .dma_wr_done_i(fill_wr_done),
        .dma_wr_error_i(fill_wr_error)
    );

    gpu_write_arbiter #(
        .XLEN(XLEN)
    ) write_arbiter (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .c0_start_i(fill_wr_start),
        .c0_addr_i(fill_wr_addr),
        .c0_beats_i(fill_wr_beats),
        .c0_ready_o(fill_wr_start_ready),
        .c0_valid_i(fill_wr_data_valid),
        .c0_data_i(fill_wr_data),
        .c0_strb_i(fill_wr_strb),
        .c0_data_ready_o(fill_wr_data_ready),
        .c0_done_o(fill_wr_done),
        .c0_error_o(fill_wr_error),
        .c1_start_i(aux_wr_start_i),
        .c1_addr_i(aux_wr_addr_i),
        .c1_beats_i(aux_wr_beats_i),
        .c1_ready_o(aux_wr_ready_o),
        .c1_valid_i(aux_wr_valid_i),
        .c1_data_i(aux_wr_data_i),
        .c1_strb_i(aux_wr_strb_i),
        .c1_data_ready_o(aux_wr_data_ready_o),
        .c1_done_o(aux_wr_done_o),
        .c1_error_o(aux_wr_error_o),
        .dma_start_o(dma_wr_start),
        .dma_addr_o(dma_wr_addr),
        .dma_beats_o(dma_wr_beats),
        .dma_busy_i(dma_wr_busy),
        .dma_valid_o(dma_wr_data_valid),
        .dma_data_o(dma_wr_data),
        .dma_strb_o(dma_wr_strb),
        .dma_data_ready_i(dma_wr_data_ready),
        .dma_done_i(dma_wr_done),
        .dma_error_i(dma_wr_error)
    );

    gpu_axi_dma #(
        .XLEN(XLEN),
        .ID_WIDTH(4),
        .MAX_BURST(MAX_BURST)
    ) dma (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wr_start_i(dma_wr_start),
        .wr_addr_i(dma_wr_addr),
        .wr_beats_i(dma_wr_beats),
        .wr_busy_o(dma_wr_busy),
        .wr_data_valid_i(dma_wr_data_valid),
        .wr_data_i(dma_wr_data),
        .wr_strb_i(dma_wr_strb),
        .wr_data_ready_o(dma_wr_data_ready),
        .wr_done_o(dma_wr_done),
        .wr_error_o(dma_wr_error),
        .rd_start_i(rd_start_i),
        .rd_addr_i(rd_addr_i),
        .rd_beats_i(rd_beats_i),
        .rd_busy_o(dma_rd_busy),
        .rd_valid_o(dma_rd_valid),
        .rd_data_o(dma_rd_data),
        .rd_last_o(dma_rd_last),
        .rd_ready_i(rd_ready_i),
        .rd_done_o(dma_rd_done),
        .rd_error_o(dma_rd_error),
        .m_axi_awid_o(m_axi_awid_o),
        .m_axi_awaddr_o(m_axi_awaddr_o),
        .m_axi_awlen_o(m_axi_awlen_o),
        .m_axi_awsize_o(m_axi_awsize_o),
        .m_axi_awburst_o(m_axi_awburst_o),
        .m_axi_awlock_o(m_axi_awlock_o),
        .m_axi_awcache_o(m_axi_awcache_o),
        .m_axi_awprot_o(m_axi_awprot_o),
        .m_axi_awqos_o(m_axi_awqos_o),
        .m_axi_awvalid_o(m_axi_awvalid_o),
        .m_axi_awready_i(m_axi_awready_i),
        .m_axi_wdata_o(m_axi_wdata_o),
        .m_axi_wstrb_o(m_axi_wstrb_o),
        .m_axi_wlast_o(m_axi_wlast_o),
        .m_axi_wvalid_o(m_axi_wvalid_o),
        .m_axi_wready_i(m_axi_wready_i),
        .m_axi_bid_i(m_axi_bid_i),
        .m_axi_bresp_i(m_axi_bresp_i),
        .m_axi_bvalid_i(m_axi_bvalid_i),
        .m_axi_bready_o(m_axi_bready_o),
        .m_axi_arid_o(m_axi_arid_o),
        .m_axi_araddr_o(m_axi_araddr_o),
        .m_axi_arlen_o(m_axi_arlen_o),
        .m_axi_arsize_o(m_axi_arsize_o),
        .m_axi_arburst_o(m_axi_arburst_o),
        .m_axi_arlock_o(m_axi_arlock_o),
        .m_axi_arcache_o(m_axi_arcache_o),
        .m_axi_arprot_o(m_axi_arprot_o),
        .m_axi_arqos_o(m_axi_arqos_o),
        .m_axi_arvalid_o(m_axi_arvalid_o),
        .m_axi_arready_i(m_axi_arready_i),
        .m_axi_rid_i(m_axi_rid_i),
        .m_axi_rdata_i(m_axi_rdata_i),
        .m_axi_rresp_i(m_axi_rresp_i),
        .m_axi_rlast_i(m_axi_rlast_i),
        .m_axi_rvalid_i(m_axi_rvalid_i),
        .m_axi_rready_o(m_axi_rready_o)
    );

    assign rd_busy_o = dma_rd_busy;
    assign rd_valid_o = dma_rd_valid;
    assign rd_data_o = dma_rd_data;
    assign rd_last_o = dma_rd_last;
    assign rd_done_o = dma_rd_done;
    assign rd_error_o = dma_rd_error;

    gpu_3d_pipeline #(
        .XLEN(XLEN),
        .LANES(LANES),
        .COORD_WIDTH(16)
    ) pipeline_3d (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .triangle_start_i(triangle_start_i),
        .x0_i(triangle_x0_i),
        .y0_i(triangle_y0_i),
        .x1_i(triangle_x1_i),
        .y1_i(triangle_y1_i),
        .x2_i(triangle_x2_i),
        .y2_i(triangle_y2_i),
        .framebuffer_width_i(triangle_fb_width_i),
        .framebuffer_height_i(triangle_fb_height_i),
        .shader_opcode_i(triangle_shader_opcode_i),
        .uniform_color_i(triangle_uniform_color_i),
        .texture_color_i(triangle_texture_color_i),
        .fragment_valid_o(fragment_valid_o),
        .fragment_ready_i(fragment_ready_i),
        .fragment_mask_o(fragment_mask_o),
        .fragment_x_o(fragment_x_o),
        .fragment_y_o(fragment_y_o),
        .fragment_color_o(fragment_color_o),
        .busy_o(triangle_busy_o),
        .done_o(triangle_done_o),
        .error_o(triangle_error_o)
    );

    gpu_video_timing #(
        .ACTIVE_WIDTH(VIDEO_WIDTH),
        .ACTIVE_HEIGHT(VIDEO_HEIGHT),
        .H_FRONT(H_FRONT),
        .H_SYNC(H_SYNC),
        .H_BACK(H_BACK),
        .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC),
        .V_BACK(V_BACK)
    ) video_timing (
        .pixel_clk_i(pixel_clk_i),
        .rst_i(rst_i),
        .enable_i(video_enable_i),
        .pixel_data_i(pixel_data_i),
        .x_o(video_x_o),
        .y_o(video_y_o),
        .hsync_o(video_hsync_o),
        .vsync_o(video_vsync_o),
        .de_o(video_de_o),
        .rgb_o(video_rgb_o)
    );

endmodule