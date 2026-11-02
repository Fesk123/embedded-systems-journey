`timescale 1ns/1ps


// Complete RV64GC GPU Subsystem

// Integrated GPU subsystem for the RV64GC SoC and KV260 PL.
//
// Features:
// - Wishbone control at offsets 0x000-0x0FF and 0x100-0x1FF.
// - 2D rectangle fill, framebuffer blit and 3D triangle submission.
// - Four-client round-robin AXI read path: scanout, texture, blitter, fragments.
// - Shared write path: rectangle fill, blitter, fast fragment writer and
//   depth/blend fragment backend.
// - Framebuffer scanout through a dual-clock FIFO and programmable video timing.
// - XLEN controls CPU address/register width; LANES controls fragment parallelism.
//
// The texture sampler currently samples one configured UV coordinate for a submitted triangle. 
// Per-fragment perspective-correct UV interpolation and a full OpenGL ES 2.0 driver/compiler are separate software/RTL milestones.

module gpu_complete #(

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
    parameter integer V_BACK = 20,
    parameter integer PIXEL_FIFO_ADDR_WIDTH = 9
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

    // Pixel clock and digital video output. Connect to KV260 display IP.
    input pixel_clk_i,
    output [11:0] video_x_o,
    output [11:0] video_y_o,
    output video_hsync_o,
    output video_vsync_o,
    output video_de_o,
    output [23:0] video_rgb_o,

    output gpu_irq_o,
    output gpu_busy_o,
    output [FIFO_ADDR_WIDTH:0] command_count_o,
    output gpu_command_error_o,
    output display_underflow_o,
    output scanout_error_o,
    output render_error_o
);

    wire core_wb_cyc = wb_cyc_i && (wb_adr_i[11:8] == 4'h0);
    wire core_wb_stb = wb_stb_i && (wb_adr_i[11:8] == 4'h0);
    wire ext_wb_cyc = wb_cyc_i && (wb_adr_i[11:8] == 4'h1);
    wire ext_wb_stb = wb_stb_i && (wb_adr_i[11:8] == 4'h1);
    wire tex_cache_mem_done;

    wire [XLEN-1:0] core_wb_data;
    wire core_wb_ack;
    wire core_wb_err;
    wire [XLEN-1:0] ext_wb_data;
    wire ext_wb_ack;
    wire ext_wb_err;
    reg unmapped_seen;
    reg unmapped_ack;

    assign wb_dat_o = (core_wb_ack) ? core_wb_data :
                      (ext_wb_ack) ? ext_wb_data : {XLEN{1'b0}};
    assign wb_ack_o = core_wb_ack || ext_wb_ack || unmapped_ack;
    assign wb_err_o = core_wb_err || ext_wb_err || unmapped_ack;

    always @(posedge clk_i) begin
        if (rst_i) begin
            unmapped_seen <= 1'b0;
            unmapped_ack <= 1'b0;
        end else begin
            unmapped_ack <= 1'b0;
            if (!wb_cyc_i || !wb_stb_i)
                unmapped_seen <= 1'b0;
            else if ((wb_adr_i[11:8] != 4'h0) &&
                     (wb_adr_i[11:8] != 4'h1) && !unmapped_seen) begin
                unmapped_seen <= 1'b1;
                unmapped_ack <= 1'b1;
            end
        end
    end

    wire [XLEN-1:0] framebuffer_base;
    wire [31:0] framebuffer_stride;
    wire [31:0] framebuffer_width;
    wire [31:0] framebuffer_height;

    wire scanout_start;
    wire triangle_start;
    wire signed [15:0] triangle_x0;
    wire signed [15:0] triangle_y0;
    wire signed [15:0] triangle_x1;
    wire signed [15:0] triangle_y1;
    wire signed [15:0] triangle_x2;
    wire signed [15:0] triangle_y2;
    wire [31:0] triangle_color;
    wire [3:0] triangle_shader_opcode;
    wire [31:0] triangle_depth;
    wire [XLEN-1:0] depth_base;
    wire [31:0] depth_stride;
    wire depth_enable;
    wire depth_write_enable;
    wire [2:0] depth_compare;
    wire blend_enable;

    wire blit_start;
    wire [XLEN-1:0] blit_src_base;
    wire [XLEN-1:0] blit_dst_base;
    wire [31:0] blit_src_stride;
    wire [31:0] blit_dst_stride;
    wire [15:0] blit_src_x;
    wire [15:0] blit_src_y;
    wire [15:0] blit_dst_x;
    wire [15:0] blit_dst_y;
    wire [15:0] blit_width;
    wire [15:0] blit_height;
    wire ext_irq;

    reg core_triangle_start;
    reg sampler_start;
    reg vertex_fetch_start;
    reg triangle_use_fetched;
    reg [2:0] triangle_dispatch_state;
    reg triangle_complete_pulse;
    reg triangle_dispatch_error;
    reg triangle_error_seen;
    wire triangle_busy_core;
    wire triangle_done_core;
    wire triangle_error_core;
    wire triangle_dispatch_busy;

    localparam [2:0] T_IDLE = 3'd0;
    localparam [2:0] T_WAIT_VERTEX = 3'd1;
    localparam [2:0] T_WAIT_TEXTURE = 3'd2;
    localparam [2:0] T_WAIT_RENDER = 3'd3;
    localparam [2:0] T_WAIT_BACKEND = 3'd4;

    wire sampler_busy;
    wire sampler_done;
    wire sampler_error;
    wire [31:0] sampler_color;
    wire [XLEN-1:0] texture_base;
    wire [31:0] texture_stride;
    wire [15:0] texture_width;
    wire [15:0] texture_height;
    wire [31:0] texture_u;
    wire [31:0] texture_v;
    wire [XLEN-1:0] vertex_base;
    wire [31:0] vertex_stride;
    wire triangle_fetch_mode;

    wire [LANES*32-1:0] triangle_texture_color = {LANES{sampler_color}};
    wire [31:0] texture_u_effective;
    wire [31:0] texture_v_effective;
    wire [33:0] fetched_u_sum = {2'b00, primitive_u0} + {2'b00, primitive_u1} + {2'b00, primitive_u2};
    wire [33:0] fetched_v_sum = {2'b00, primitive_v0} + {2'b00, primitive_v1} + {2'b00, primitive_v2};
    wire signed [15:0] triangle_x0_effective;
    wire signed [15:0] triangle_y0_effective;
    wire signed [15:0] triangle_x1_effective;
    wire signed [15:0] triangle_y1_effective;
    wire signed [15:0] triangle_x2_effective;
    wire signed [15:0] triangle_y2_effective;
    wire [31:0] triangle_color_effective;
    wire [31:0] triangle_depth_effective;

    wire vertex_rd_req;
    wire [XLEN-1:0] vertex_rd_addr;
    wire [7:0] vertex_rd_beats;
    wire vertex_rd_req_ready;
    wire vertex_rd_valid;
    wire [63:0] vertex_rd_data;
    wire vertex_rd_data_ready;
    wire vertex_rd_done;
    wire vertex_rd_error;
    wire vertex_valid;
    wire vertex_ready;
    wire signed [15:0] vertex_x;
    wire signed [15:0] vertex_y;
    wire [31:0] vertex_u;
    wire [31:0] vertex_v;
    wire [31:0] vertex_depth;
    wire [31:0] vertex_color;
    wire vertex_fetch_busy;
    wire vertex_fetch_done;
    wire vertex_fetch_error;

    wire primitive_triangle_valid;
    wire primitive_triangle_ready;
    wire signed [15:0] primitive_x0;
    wire signed [15:0] primitive_y0;
    wire signed [15:0] primitive_x1;
    wire signed [15:0] primitive_y1;
    wire signed [15:0] primitive_x2;
    wire signed [15:0] primitive_y2;
    wire [31:0] primitive_u0;
    wire [31:0] primitive_v0;
    wire [31:0] primitive_u1;
    wire [31:0] primitive_v1;
    wire [31:0] primitive_u2;
    wire [31:0] primitive_v2;
    wire [31:0] primitive_depth0;
    wire [31:0] primitive_depth1;
    wire [31:0] primitive_depth2;
    wire [31:0] primitive_color0;
    wire [31:0] primitive_color1;
    wire [31:0] primitive_color2;

    wire read_mux_req;
    wire [XLEN-1:0] read_mux_addr;
    wire [7:0] read_mux_beats;
    wire read_mux_ready;
    wire read_mux_valid;
    wire [63:0] read_mux_data;
    wire read_mux_last;
    wire read_mux_data_ready;
    wire read_mux_done;
    wire read_mux_error;

    wire blitter_busy;
    wire blitter_done;
    wire blitter_error;
    wire blit_rd_req;
    wire [XLEN-1:0] blit_rd_addr;
    wire [7:0] blit_rd_beats;
    wire blit_rd_ready;
    wire blit_rd_valid;
    wire [63:0] blit_rd_data;
    wire blit_rd_last;
    wire blit_rd_data_ready;
    wire blit_rd_done;
    wire blit_rd_error;
    wire blit_wr_start;
    wire [XLEN-1:0] blit_wr_addr;
    wire [7:0] blit_wr_beats;
    wire blit_wr_start_ready;
    wire blit_wr_valid;
    wire [63:0] blit_wr_data;
    wire [7:0] blit_wr_strb;
    wire blit_wr_data_ready;
    wire blit_wr_done;
    wire blit_wr_error;

    wire [LANES-1:0] fragment_mask;
    wire [LANES*16-1:0] fragment_x;
    wire [LANES*16-1:0] fragment_y;
    wire [LANES*32-1:0] fragment_color;
    wire fragment_valid;
    wire fragment_ready;

    wire fragment_writer_busy;
    wire fragment_writer_done;
    wire fragment_writer_error;
    wire fragment_writer_ready;
    wire frag_fast_wr_start;
    wire [XLEN-1:0] frag_fast_wr_addr;
    wire [7:0] frag_fast_wr_beats;
    wire frag_fast_wr_start_ready;
    wire frag_fast_wr_valid;
    wire [63:0] frag_fast_wr_data;
    wire [7:0] frag_fast_wr_strb;
    wire frag_fast_wr_data_ready;
    wire frag_fast_wr_done;
    wire frag_fast_wr_error;

    wire fragment_stage_busy;
    wire fragment_stage_done;
    wire fragment_stage_error;
    wire fragment_stage_ready;
    wire frag_stage_rd_req;
    wire [XLEN-1:0] frag_stage_rd_addr;
    wire [7:0] frag_stage_rd_beats;
    wire frag_stage_rd_ready;
    wire frag_stage_rd_valid;
    wire [63:0] frag_stage_rd_data;
    wire frag_stage_rd_data_ready;
    wire frag_stage_rd_done;
    wire frag_stage_rd_error;
    wire frag_stage_wr_start;
    wire [XLEN-1:0] frag_stage_wr_addr;
    wire [7:0] frag_stage_wr_beats;
    wire frag_stage_wr_start_ready;
    wire frag_stage_wr_valid;
    wire [63:0] frag_stage_wr_data;
    wire [7:0] frag_stage_wr_strb;
    wire frag_stage_wr_data_ready;
    wire frag_stage_wr_done;
    wire frag_stage_wr_error;

    wire scan_rd_req;
    wire [XLEN-1:0] scan_rd_addr;
    wire [7:0] scan_rd_beats;
    wire scan_rd_ready;
    wire scan_rd_valid;
    wire [63:0] scan_rd_data;
    wire scan_rd_last;
    wire scan_rd_data_ready;
    wire scan_rd_done;
    wire scan_rd_error;
    wire [31:0] scan_pixel_data;
    wire scan_pixel_ready;
    wire scan_underflow;
    wire scan_error;

    wire tex_cache_req_valid;
    wire tex_cache_req_ready;
    wire [XLEN-1:0] tex_cache_req_addr;
    wire tex_cache_resp_valid;
    wire tex_cache_resp_ready;
    wire [63:0] tex_cache_resp_data;
    wire tex_cache_resp_error;
    wire tex_cache_mem_req_valid;
    wire tex_cache_mem_req_ready;
    wire [XLEN-1:0] tex_cache_mem_req_addr;
    wire tex_cache_mem_valid;
    wire tex_cache_mem_ready;
    wire [63:0] tex_cache_mem_data;
    wire tex_cache_mem_error;

    wire rd_dma_start;
    wire [XLEN-1:0] rd_dma_addr;
    wire [7:0] rd_dma_beats;
    wire rd_dma_busy;
    wire rd_dma_valid;
    wire [63:0] rd_dma_data;
    wire rd_dma_last;
    wire rd_dma_ready;
    wire rd_dma_done;
    wire rd_dma_error;

    wire wr_mux_start;
    wire [XLEN-1:0] wr_mux_addr;
    wire [7:0] wr_mux_beats;
    wire wr_mux_ready;
    wire wr_mux_valid;
    wire [63:0] wr_mux_data;
    wire [7:0] wr_mux_strb;
    wire wr_mux_data_ready;
    wire wr_mux_done;
    wire wr_mux_error;

    wire [23:0] core_video_rgb;
    wire core_video_de;
    wire core_video_hsync;
    wire core_video_vsync;
    wire [11:0] core_video_x;
    wire [11:0] core_video_y;
    wire core_irq;
    wire core_busy;
    wire core_command_error;
    wire [FIFO_ADDR_WIDTH:0] core_command_count;

    assign video_x_o = core_video_x;
    assign video_y_o = core_video_y;
    assign video_hsync_o = core_video_hsync;
    assign video_vsync_o = core_video_vsync;
    assign video_de_o = core_video_de;
    assign video_rgb_o = core_video_rgb;

    assign triangle_dispatch_busy = (triangle_dispatch_state != T_IDLE) || sampler_busy || vertex_fetch_busy || primitive_triangle_valid;
    assign gpu_irq_o = core_irq || ext_irq;
    assign gpu_busy_o = core_busy || blitter_busy || fragment_writer_busy || fragment_stage_busy || triangle_dispatch_busy;
    assign command_count_o = core_command_count;
    assign gpu_command_error_o = core_command_error;
    assign display_underflow_o = scan_underflow;
    assign scanout_error_o = scan_error;
    assign render_error_o = triangle_error_core || triangle_dispatch_error || sampler_error || blitter_error || fragment_writer_error || fragment_stage_error;

    gpu_extension_registers #(
        .XLEN(XLEN)
    ) extension_registers (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_cyc_i(ext_wb_cyc),
        .wb_stb_i(ext_wb_stb),
        .wb_we_i(wb_we_i),
        .wb_dat_o(ext_wb_data),
        .wb_ack_o(ext_wb_ack),
        .wb_err_o(ext_wb_err),
        .triangle_busy_i(triangle_busy_core || triangle_dispatch_busy || fragment_writer_busy || fragment_stage_busy),
        .triangle_done_i(triangle_complete_pulse),
        .triangle_error_i(triangle_error_core || triangle_dispatch_error),
        .blit_busy_i(blitter_busy),
        .blit_done_i(blitter_done),
        .blit_error_i(blitter_error),
        .scanout_start_o(scanout_start),
        .triangle_start_o(triangle_start),
        .triangle_x0_o(triangle_x0),
        .triangle_y0_o(triangle_y0),
        .triangle_x1_o(triangle_x1),
        .triangle_y1_o(triangle_y1),
        .triangle_x2_o(triangle_x2),
        .triangle_y2_o(triangle_y2),
        .triangle_color_o(triangle_color),
        .triangle_shader_opcode_o(triangle_shader_opcode),
        .triangle_depth_o(triangle_depth),
        .texture_base_o(texture_base),
        .texture_stride_o(texture_stride),
        .texture_width_o(texture_width),
        .texture_height_o(texture_height),
        .texture_u_o(texture_u),
        .texture_v_o(texture_v),
        .vertex_base_o(vertex_base),
        .vertex_stride_o(vertex_stride),
        .triangle_fetch_mode_o(triangle_fetch_mode),
        .depth_base_o(depth_base),
        .depth_stride_o(depth_stride),
        .depth_enable_o(depth_enable),
        .depth_write_enable_o(depth_write_enable),
        .depth_compare_o(depth_compare),
        .blend_enable_o(blend_enable),
        .blit_start_o(blit_start),
        .blit_src_base_o(blit_src_base),
        .blit_dst_base_o(blit_dst_base),
        .blit_src_stride_o(blit_src_stride),
        .blit_dst_stride_o(blit_dst_stride),
        .blit_src_x_o(blit_src_x),
        .blit_src_y_o(blit_src_y),
        .blit_dst_x_o(blit_dst_x),
        .blit_dst_y_o(blit_dst_y),
        .blit_width_o(blit_width),
        .blit_height_o(blit_height),
        .irq_o(ext_irq)
    );

    assign triangle_x0_effective = triangle_use_fetched ? primitive_x0 : triangle_x0;
    assign triangle_y0_effective = triangle_use_fetched ? primitive_y0 : triangle_y0;
    assign triangle_x1_effective = triangle_use_fetched ? primitive_x1 : triangle_x1;
    assign triangle_y1_effective = triangle_use_fetched ? primitive_y1 : triangle_y1;
    assign triangle_x2_effective = triangle_use_fetched ? primitive_x2 : triangle_x2;
    assign triangle_y2_effective = triangle_use_fetched ? primitive_y2 : triangle_y2;
    assign triangle_color_effective = triangle_use_fetched ? primitive_color0 : triangle_color;
    assign triangle_depth_effective = triangle_use_fetched ? primitive_depth0 : triangle_depth;
    assign texture_u_effective = triangle_use_fetched ? (fetched_u_sum / 3) : texture_u;
    assign texture_v_effective = triangle_use_fetched ? (fetched_v_sum / 3) : texture_v;

    gpu_vertex_fetch #(
        .XLEN(XLEN)
    ) vertex_fetch (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(vertex_fetch_start),
        .vertex_base_i(vertex_base),
        .vertex_stride_i(vertex_stride),
        .rd_req_o(vertex_rd_req),
        .rd_addr_o(vertex_rd_addr),
        .rd_beats_o(vertex_rd_beats),
        .rd_req_ready_i(vertex_rd_req_ready),
        .rd_valid_i(vertex_rd_valid),
        .rd_data_i(vertex_rd_data),
        .rd_data_ready_o(vertex_rd_data_ready),
        .rd_done_i(vertex_rd_done),
        .rd_error_i(vertex_rd_error),
        .vertex_valid_o(vertex_valid),
        .vertex_ready_i(vertex_ready),
        .vertex_x_o(vertex_x),
        .vertex_y_o(vertex_y),
        .vertex_u_o(vertex_u),
        .vertex_v_o(vertex_v),
        .vertex_depth_o(vertex_depth),
        .vertex_color_o(vertex_color),
        .busy_o(vertex_fetch_busy),
        .done_o(vertex_fetch_done),
        .error_o(vertex_fetch_error)
    );

    gpu_primitive_assembler primitive_assembler (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .vertex_valid_i(vertex_valid),
        .vertex_ready_o(vertex_ready),
        .vertex_x_i(vertex_x),
        .vertex_y_i(vertex_y),
        .vertex_u_i(vertex_u),
        .vertex_v_i(vertex_v),
        .vertex_depth_i(vertex_depth),
        .vertex_color_i(vertex_color),
        .triangle_valid_o(primitive_triangle_valid),
        .triangle_ready_i(primitive_triangle_ready),
        .triangle_x0_o(primitive_x0),
        .triangle_y0_o(primitive_y0),
        .triangle_x1_o(primitive_x1),
        .triangle_y1_o(primitive_y1),
        .triangle_x2_o(primitive_x2),
        .triangle_y2_o(primitive_y2),
        .triangle_u0_o(primitive_u0),
        .triangle_v0_o(primitive_v0),
        .triangle_u1_o(primitive_u1),
        .triangle_v1_o(primitive_v1),
        .triangle_u2_o(primitive_u2),
        .triangle_v2_o(primitive_v2),
        .triangle_depth0_o(primitive_depth0),
        .triangle_depth1_o(primitive_depth1),
        .triangle_depth2_o(primitive_depth2),
        .triangle_color0_o(primitive_color0),
        .triangle_color1_o(primitive_color1),
        .triangle_color2_o(primitive_color2)
    );

    assign primitive_triangle_ready = (triangle_dispatch_state == T_WAIT_VERTEX) && primitive_triangle_valid;

    gpu_texture_cache #(
        .XLEN(XLEN),
        .SETS(64),
        .INDEX_WIDTH(6)
    ) texture_cache (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_valid_i(tex_cache_req_valid),
        .req_ready_o(tex_cache_req_ready),
        .req_addr_i(tex_cache_req_addr),
        .resp_valid_o(tex_cache_resp_valid),
        .resp_ready_i(tex_cache_resp_ready),
        .resp_data_o(tex_cache_resp_data),
        .resp_error_o(tex_cache_resp_error),
        .mem_req_valid_o(tex_cache_mem_req_valid),
        .mem_req_ready_i(tex_cache_mem_req_ready),
        .mem_req_addr_o(tex_cache_mem_req_addr),
        .mem_valid_i(tex_cache_mem_valid),
        .mem_ready_o(tex_cache_mem_ready),
        .mem_data_i(tex_cache_mem_data),
        .mem_error_i(tex_cache_mem_error),
        .mem_done_i(tex_cache_mem_done)
    );

    gpu_texture_sampler #(
        .XLEN(XLEN)
    ) texture_sampler (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(sampler_start),
        .texture_base_i(texture_base),
        .texture_stride_i(texture_stride),
        .texture_width_i(texture_width),
        .texture_height_i(texture_height),
        .u_i(texture_u_effective),
        .v_i(texture_v_effective),
        .busy_o(sampler_busy),
        .done_o(sampler_done),
        .error_o(sampler_error),
        .sample_color_o(sampler_color),
        .cache_req_valid_o(tex_cache_req_valid),
        .cache_req_ready_i(tex_cache_req_ready),
        .cache_req_addr_o(tex_cache_req_addr),
        .cache_resp_valid_i(tex_cache_resp_valid),
        .cache_resp_ready_o(tex_cache_resp_ready),
        .cache_resp_data_i(tex_cache_resp_data),
        .cache_resp_error_i(tex_cache_resp_error)
    );

    gpu_framebuffer_scanout #(
        .XLEN(XLEN),
        .FIFO_ADDR_WIDTH(PIXEL_FIFO_ADDR_WIDTH),
        .MAX_BURST(MAX_BURST),
        .PREFILL_WORDS(32)
    ) framebuffer_scanout (
        .clk_i(clk_i),
        .pixel_clk_i(pixel_clk_i),
        .rst_i(rst_i),
        .start_i(scanout_start),
        .framebuffer_base_i(framebuffer_base),
        .framebuffer_stride_i(framebuffer_stride),
        .framebuffer_width_i(framebuffer_width[15:0]),
        .framebuffer_height_i(framebuffer_height[15:0]),
        .rd_req_o(scan_rd_req),
        .rd_addr_o(scan_rd_addr),
        .rd_beats_o(scan_rd_beats),
        .rd_req_ready_i(scan_rd_ready),
        .rd_busy_i(rd_dma_busy),
        .rd_valid_i(scan_rd_valid),
        .rd_data_i(scan_rd_data),
        .rd_last_i(scan_rd_last),
        .rd_data_ready_o(scan_rd_data_ready),
        .rd_done_i(scan_rd_done),
        .rd_error_i(scan_rd_error),
        .pixel_active_i(core_video_de),
        .pixel_x_i(core_video_x),
        .pixel_data_o(scan_pixel_data),
        .pixel_ready_o(scan_pixel_ready),
        .pixel_underflow_o(scan_underflow),
        .scanout_error_o(scan_error)
    );

    gpu_2d_blitter #(
        .XLEN(XLEN),
        .MAX_BURST(MAX_BURST)
    ) blitter (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(blit_start),
        .src_base_i(blit_src_base),
        .dst_base_i(blit_dst_base),
        .src_stride_i(blit_src_stride),
        .dst_stride_i(blit_dst_stride),
        .src_fb_width_i(framebuffer_width[15:0]),
        .src_fb_height_i(framebuffer_height[15:0]),
        .dst_fb_width_i(framebuffer_width[15:0]),
        .dst_fb_height_i(framebuffer_height[15:0]),
        .src_x_i(blit_src_x),
        .src_y_i(blit_src_y),
        .dst_x_i(blit_dst_x),
        .dst_y_i(blit_dst_y),
        .width_i(blit_width),
        .height_i(blit_height),
        .busy_o(blitter_busy),
        .done_o(blitter_done),
        .error_o(blitter_error),
        .rd_start_o(blit_rd_req),
        .rd_addr_o(blit_rd_addr),
        .rd_beats_o(blit_rd_beats),
        .rd_start_ready_i(blit_rd_ready),
        .rd_valid_i(blit_rd_valid),
        .rd_data_i(blit_rd_data),
        .rd_ready_o(blit_rd_data_ready),
        .rd_done_i(blit_rd_done),
        .rd_error_i(blit_rd_error),
        .wr_start_o(blit_wr_start),
        .wr_addr_o(blit_wr_addr),
        .wr_beats_o(blit_wr_beats),
        .wr_start_ready_i(blit_wr_start_ready),
        .wr_valid_o(blit_wr_valid),
        .wr_data_o(blit_wr_data),
        .wr_strb_o(blit_wr_strb),
        .wr_ready_i(blit_wr_data_ready),
        .wr_done_i(blit_wr_done),
        .wr_error_i(blit_wr_error)
    );

    assign fragment_ready = (depth_enable || blend_enable) ? fragment_stage_ready : fragment_writer_ready;

    gpu_fragment_writer #(
        .XLEN(XLEN),
        .LANES(LANES),
        .MAX_BURST(MAX_BURST)
    ) fast_fragment_writer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .fragment_valid_i(fragment_valid && !(depth_enable || blend_enable)),
        .fragment_ready_o(fragment_writer_ready),
        .fragment_mask_i(fragment_mask),
        .fragment_x_i(fragment_x),
        .fragment_y_i(fragment_y),
        .fragment_color_i(fragment_color),
        .framebuffer_base_i(framebuffer_base),
        .framebuffer_stride_i(framebuffer_stride),
        .framebuffer_width_i(framebuffer_width[15:0]),
        .framebuffer_height_i(framebuffer_height[15:0]),
        .busy_o(fragment_writer_busy),
        .done_o(fragment_writer_done),
        .error_o(fragment_writer_error),
        .wr_start_o(frag_fast_wr_start),
        .wr_addr_o(frag_fast_wr_addr),
        .wr_beats_o(frag_fast_wr_beats),
        .wr_start_ready_i(frag_fast_wr_start_ready),
        .wr_valid_o(frag_fast_wr_valid),
        .wr_data_o(frag_fast_wr_data),
        .wr_strb_o(frag_fast_wr_strb),
        .wr_data_ready_i(frag_fast_wr_data_ready),
        .wr_done_i(frag_fast_wr_done),
        .wr_error_i(frag_fast_wr_error)
    );

    gpu_fragment_memory_stage #(
        .XLEN(XLEN),
        .LANES(LANES)
    ) fragment_memory_stage (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .fragment_valid_i(fragment_valid && (depth_enable || blend_enable)),
        .fragment_ready_o(fragment_stage_ready),
        .fragment_mask_i(fragment_mask),
        .fragment_x_i(fragment_x),
        .fragment_y_i(fragment_y),
        .fragment_color_i(fragment_color),
        .fragment_depth_i({LANES{triangle_depth_effective}}),
        .framebuffer_base_i(framebuffer_base),
        .framebuffer_stride_i(framebuffer_stride),
        .framebuffer_width_i(framebuffer_width[15:0]),
        .framebuffer_height_i(framebuffer_height[15:0]),
        .depth_base_i(depth_base),
        .depth_stride_i(depth_stride),
        .depth_enable_i(depth_enable),
        .depth_write_enable_i(depth_write_enable),
        .depth_compare_i(depth_compare),
        .blend_enable_i(blend_enable),
        .busy_o(fragment_stage_busy),
        .done_o(fragment_stage_done),
        .error_o(fragment_stage_error),
        .rd_req_o(frag_stage_rd_req),
        .rd_addr_o(frag_stage_rd_addr),
        .rd_beats_o(frag_stage_rd_beats),
        .rd_req_ready_i(frag_stage_rd_ready),
        .rd_valid_i(frag_stage_rd_valid),
        .rd_data_i(frag_stage_rd_data),
        .rd_data_ready_o(frag_stage_rd_data_ready),
        .rd_done_i(frag_stage_rd_done),
        .rd_error_i(frag_stage_rd_error),
        .wr_start_o(frag_stage_wr_start),
        .wr_addr_o(frag_stage_wr_addr),
        .wr_beats_o(frag_stage_wr_beats),
        .wr_start_ready_i(frag_stage_wr_start_ready),
        .wr_valid_o(frag_stage_wr_valid),
        .wr_data_o(frag_stage_wr_data),
        .wr_strb_o(frag_stage_wr_strb),
        .wr_data_ready_i(frag_stage_wr_data_ready),
        .wr_done_i(frag_stage_wr_done),
        .wr_error_i(frag_stage_wr_error)
    );

    gpu_write_client_mux3 #(
        .XLEN(XLEN)
    ) auxiliary_write_mux (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .c0_start_i(blit_wr_start),
        .c0_addr_i(blit_wr_addr),
        .c0_beats_i(blit_wr_beats),
        .c0_ready_o(blit_wr_start_ready),
        .c0_valid_i(blit_wr_valid),
        .c0_data_i(blit_wr_data),
        .c0_strb_i(blit_wr_strb),
        .c0_data_ready_o(blit_wr_data_ready),
        .c0_done_o(blit_wr_done),
        .c0_error_o(blit_wr_error),
        .c1_start_i(frag_fast_wr_start),
        .c1_addr_i(frag_fast_wr_addr),
        .c1_beats_i(frag_fast_wr_beats),
        .c1_ready_o(frag_fast_wr_start_ready),
        .c1_valid_i(frag_fast_wr_valid),
        .c1_data_i(frag_fast_wr_data),
        .c1_strb_i(frag_fast_wr_strb),
        .c1_data_ready_o(frag_fast_wr_data_ready),
        .c1_done_o(frag_fast_wr_done),
        .c1_error_o(frag_fast_wr_error),
        .c2_start_i(frag_stage_wr_start),
        .c2_addr_i(frag_stage_wr_addr),
        .c2_beats_i(frag_stage_wr_beats),
        .c2_ready_o(frag_stage_wr_start_ready),
        .c2_valid_i(frag_stage_wr_valid),
        .c2_data_i(frag_stage_wr_data),
        .c2_strb_i(frag_stage_wr_strb),
        .c2_data_ready_o(frag_stage_wr_data_ready),
        .c2_done_o(frag_stage_wr_done),
        .c2_error_o(frag_stage_wr_error),
        .aux_start_o(wr_mux_start),
        .aux_addr_o(wr_mux_addr),
        .aux_beats_o(wr_mux_beats),
        .aux_ready_i(wr_mux_ready),
        .aux_valid_o(wr_mux_valid),
        .aux_data_o(wr_mux_data),
        .aux_strb_o(wr_mux_strb),
        .aux_data_ready_i(wr_mux_data_ready),
        .aux_done_i(wr_mux_done),
        .aux_error_i(wr_mux_error)
    );

    gpu_read_client_mux2 #(
        .XLEN(XLEN)
    ) texture_vertex_read_mux (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .a_req_i(tex_cache_mem_req_valid),
        .a_addr_i(tex_cache_mem_req_addr),
        .a_beats_i(8'd1),
        .a_ready_o(tex_cache_mem_req_ready),
        .a_valid_o(tex_cache_mem_valid),
        .a_data_o(tex_cache_mem_data),
        .a_last_o(),
        .a_data_ready_i(tex_cache_mem_ready),
        .a_done_o(tex_cache_mem_done),
        .a_error_o(tex_cache_mem_error),
        .b_req_i(vertex_rd_req),
        .b_addr_i(vertex_rd_addr),
        .b_beats_i(vertex_rd_beats),
        .b_ready_o(vertex_rd_req_ready),
        .b_valid_o(vertex_rd_valid),
        .b_data_o(vertex_rd_data),
        .b_last_o(),
        .b_data_ready_i(vertex_rd_data_ready),
        .b_done_o(vertex_rd_done),
        .b_error_o(vertex_rd_error),
        .parent_req_o(read_mux_req),
        .parent_addr_o(read_mux_addr),
        .parent_beats_o(read_mux_beats),
        .parent_ready_i(read_mux_ready),
        .parent_valid_i(read_mux_valid),
        .parent_data_i(read_mux_data),
        .parent_last_i(read_mux_last),
        .parent_data_ready_o(read_mux_data_ready),
        .parent_done_i(read_mux_done),
        .parent_error_i(read_mux_error)
    );

    gpu_read_arbiter4 #(
        .XLEN(XLEN)
    ) read_arbiter (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .c0_req_i(scan_rd_req),
        .c0_addr_i(scan_rd_addr),
        .c0_beats_i(scan_rd_beats),
        .c0_ready_o(scan_rd_ready),
        .c0_valid_o(scan_rd_valid),
        .c0_data_o(scan_rd_data),
        .c0_last_o(scan_rd_last),
        .c0_data_ready_i(scan_rd_data_ready),
        .c0_done_o(scan_rd_done),
        .c0_error_o(scan_rd_error),
        .c1_req_i(read_mux_req),
        .c1_addr_i(read_mux_addr),
        .c1_beats_i(read_mux_beats),
        .c1_ready_o(read_mux_ready),
        .c1_valid_o(read_mux_valid),
        .c1_data_o(read_mux_data),
        .c1_last_o(read_mux_last),
        .c1_data_ready_i(read_mux_data_ready),
        .c1_done_o(read_mux_done),
        .c1_error_o(read_mux_error),
        .c2_req_i(blit_rd_req),
        .c2_addr_i(blit_rd_addr),
        .c2_beats_i(blit_rd_beats),
        .c2_ready_o(blit_rd_ready),
        .c2_valid_o(blit_rd_valid),
        .c2_data_o(blit_rd_data),
        .c2_last_o(blit_rd_last),
        .c2_data_ready_i(blit_rd_data_ready),
        .c2_done_o(blit_rd_done),
        .c2_error_o(blit_rd_error),
        .c3_req_i(frag_stage_rd_req),
        .c3_addr_i(frag_stage_rd_addr),
        .c3_beats_i(frag_stage_rd_beats),
        .c3_ready_o(frag_stage_rd_ready),
        .c3_valid_o(frag_stage_rd_valid),
        .c3_data_o(frag_stage_rd_data),
        .c3_last_o(),
        .c3_data_ready_i(frag_stage_rd_data_ready),
        .c3_done_o(frag_stage_rd_done),
        .c3_error_o(frag_stage_rd_error),
        .dma_start_o(rd_dma_start),
        .dma_addr_o(rd_dma_addr),
        .dma_beats_o(rd_dma_beats),
        .dma_busy_i(rd_dma_busy),
        .dma_valid_i(rd_dma_valid),
        .dma_data_i(rd_dma_data),
        .dma_last_i(rd_dma_last),
        .dma_ready_o(rd_dma_ready),
        .dma_done_i(rd_dma_done),
        .dma_error_i(rd_dma_error)
    );

    gpu #(
        .XLEN(XLEN),
        .LANES(LANES),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .MAX_BURST(MAX_BURST),
        .VIDEO_WIDTH(VIDEO_WIDTH),
        .VIDEO_HEIGHT(VIDEO_HEIGHT),
        .H_FRONT(H_FRONT),
        .H_SYNC(H_SYNC),
        .H_BACK(H_BACK),
        .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC),
        .V_BACK(V_BACK)
    ) gpu_core (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_cyc_i(core_wb_cyc),
        .wb_stb_i(core_wb_stb),
        .wb_we_i(wb_we_i),
        .wb_dat_o(core_wb_data),
        .wb_ack_o(core_wb_ack),
        .wb_err_o(core_wb_err),
        .rd_start_i(rd_dma_start),
        .rd_addr_i(rd_dma_addr),
        .rd_beats_i(rd_dma_beats),
        .rd_busy_o(rd_dma_busy),
        .rd_valid_o(rd_dma_valid),
        .rd_data_o(rd_dma_data),
        .rd_last_o(rd_dma_last),
        .rd_ready_i(rd_dma_ready),
        .rd_done_o(rd_dma_done),
        .rd_error_o(rd_dma_error),
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
        .m_axi_rready_o(m_axi_rready_o),
        .pixel_clk_i(pixel_clk_i),
        .video_enable_i(scan_pixel_ready),
        .pixel_data_i(scan_pixel_data),
        .video_x_o(core_video_x),
        .video_y_o(core_video_y),
        .video_hsync_o(core_video_hsync),
        .video_vsync_o(core_video_vsync),
        .video_de_o(core_video_de),
        .video_rgb_o(core_video_rgb),
        .triangle_start_i(core_triangle_start),
        .triangle_x0_i(triangle_x0_effective),
        .triangle_y0_i(triangle_y0_effective),
        .triangle_x1_i(triangle_x1_effective),
        .triangle_y1_i(triangle_y1_effective),
        .triangle_x2_i(triangle_x2_effective),
        .triangle_y2_i(triangle_y2_effective),
        .triangle_fb_width_i(framebuffer_width[15:0]),
        .triangle_fb_height_i(framebuffer_height[15:0]),
        .triangle_shader_opcode_i(triangle_shader_opcode),
        .triangle_uniform_color_i(triangle_color_effective),
        .triangle_texture_color_i(triangle_texture_color),
        .fragment_valid_o(fragment_valid),
        .fragment_ready_i(fragment_ready),
        .fragment_mask_o(fragment_mask),
        .fragment_x_o(fragment_x),
        .fragment_y_o(fragment_y),
        .fragment_color_o(fragment_color),
        .triangle_busy_o(triangle_busy_core),
        .triangle_done_o(triangle_done_core),
        .triangle_error_o(triangle_error_core),
        .aux_wr_start_i(wr_mux_start),
        .aux_wr_addr_i(wr_mux_addr),
        .aux_wr_beats_i(wr_mux_beats),
        .aux_wr_ready_o(wr_mux_ready),
        .aux_wr_valid_i(wr_mux_valid),
        .aux_wr_data_i(wr_mux_data),
        .aux_wr_strb_i(wr_mux_strb),
        .aux_wr_data_ready_o(wr_mux_data_ready),
        .aux_wr_done_o(wr_mux_done),
        .aux_wr_error_o(wr_mux_error),
        .gpu_irq_o(core_irq),
        .gpu_busy_o(core_busy),
        .command_count_o(core_command_count),
        .gpu_command_error_o(core_command_error),
        .framebuffer_base_o(framebuffer_base),
        .framebuffer_stride_o(framebuffer_stride),
        .framebuffer_width_o(framebuffer_width),
        .framebuffer_height_o(framebuffer_height)
    );

    always @(posedge clk_i) begin
        if (rst_i) begin
            core_triangle_start <= 1'b0;
            sampler_start <= 1'b0;
            vertex_fetch_start <= 1'b0;
            triangle_use_fetched <= 1'b0;
            triangle_dispatch_state <= T_IDLE;
            triangle_complete_pulse <= 1'b0;
            triangle_dispatch_error <= 1'b0;
            triangle_error_seen <= 1'b0;
        end else begin
            core_triangle_start <= 1'b0;
            sampler_start <= 1'b0;
            vertex_fetch_start <= 1'b0;
            triangle_complete_pulse <= 1'b0;
            triangle_dispatch_error <= 1'b0;

            case (triangle_dispatch_state)
                T_IDLE: begin
                    if (triangle_start) begin
                        triangle_error_seen <= 1'b0;
                        triangle_use_fetched <= triangle_fetch_mode;
                        if (triangle_fetch_mode) begin
                            vertex_fetch_start <= 1'b1;
                            triangle_dispatch_state <= T_WAIT_VERTEX;
                        end else if ((triangle_shader_opcode == 4'd1) ||
                                     (triangle_shader_opcode == 4'd2) ||
                                     (triangle_shader_opcode == 4'd3)) begin
                            sampler_start <= 1'b1;
                            triangle_dispatch_state <= T_WAIT_TEXTURE;
                        end else begin
                            core_triangle_start <= 1'b1;
                            triangle_dispatch_state <= T_WAIT_RENDER;
                        end
                    end
                end

                T_WAIT_VERTEX: begin
                    if (vertex_fetch_error) begin
                        triangle_dispatch_error <= 1'b1;
                        triangle_complete_pulse <= 1'b1;
                        triangle_use_fetched <= 1'b0;
                        triangle_dispatch_state <= T_IDLE;
                    end else if (vertex_fetch_done && primitive_triangle_valid) begin
                        if ((triangle_shader_opcode == 4'd1) ||
                            (triangle_shader_opcode == 4'd2) ||
                            (triangle_shader_opcode == 4'd3)) begin
                            sampler_start <= 1'b1;
                            triangle_dispatch_state <= T_WAIT_TEXTURE;
                        end else begin
                            core_triangle_start <= 1'b1;
                            triangle_dispatch_state <= T_WAIT_RENDER;
                        end
                    end
                end

                T_WAIT_TEXTURE: begin
                    if (sampler_done) begin
                        if (sampler_error) begin
                            triangle_dispatch_error <= 1'b1;
                            triangle_complete_pulse <= 1'b1;
                            triangle_use_fetched <= 1'b0;
                            triangle_dispatch_state <= T_IDLE;
                        end else begin
                            core_triangle_start <= 1'b1;
                            triangle_dispatch_state <= T_WAIT_RENDER;
                        end
                    end
                end

                T_WAIT_RENDER: begin
                    if (triangle_error_core || fragment_writer_error || fragment_stage_error)
                        triangle_error_seen <= 1'b1;
                    if (triangle_done_core || triangle_error_core)
                        triangle_dispatch_state <= T_WAIT_BACKEND;
                end

                T_WAIT_BACKEND: begin

                    if (triangle_error_core || fragment_writer_error || fragment_stage_error)
                        triangle_error_seen <= 1'b1;
                        
                    if (!triangle_busy_core && !fragment_writer_busy && !fragment_stage_busy) begin
                        triangle_complete_pulse <= 1'b1;
                        if (triangle_error_seen || triangle_error_core ||
                            fragment_writer_error || fragment_stage_error)
                            triangle_dispatch_error <= 1'b1;
                        triangle_use_fetched <= 1'b0;
                        triangle_dispatch_state <= T_IDLE;
                    end
                end

                default: triangle_dispatch_state <= T_IDLE;

            endcase


        end

    end

endmodule