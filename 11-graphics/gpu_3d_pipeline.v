`timescale 1ns/1ps


// GPU 3D Pipeline

// Connects the triangle rasterizer to the lane-parallel shader ALU.
// Fragment output is ready/valid and can be connected to a framebuffer writer.
// Texture colors are supplied by the texture sampling path for each lane.

module gpu_3d_pipeline #(
    parameter integer XLEN = 64,
    parameter integer LANES = 1,
    parameter integer COORD_WIDTH = 16
)(
    input clk_i,
    input rst_i,

    input triangle_start_i,
    input signed [15:0] x0_i,
    input signed [15:0] y0_i,
    input signed [15:0] x1_i,
    input signed [15:0] y1_i,
    input signed [15:0] x2_i,
    input signed [15:0] y2_i,
    input [15:0] framebuffer_width_i,
    input [15:0] framebuffer_height_i,

    input [3:0] shader_opcode_i,
    input [31:0] uniform_color_i,
    input [LANES*32-1:0] texture_color_i,

    output fragment_valid_o,
    input fragment_ready_i,
    output [LANES-1:0] fragment_mask_o,
    output [LANES*COORD_WIDTH-1:0] fragment_x_o,
    output [LANES*COORD_WIDTH-1:0] fragment_y_o,
    output [LANES*32-1:0] fragment_color_o,

    output busy_o,
    output reg done_o,
    output error_o
);

    wire raster_valid;
    wire raster_busy;
    wire raster_done;
    wire raster_error;
    reg done_pending;
    wire raster_ready;
    wire [LANES-1:0] raster_mask;
    wire [LANES*COORD_WIDTH-1:0] raster_x;
    wire [LANES*COORD_WIDTH-1:0] raster_y;
    wire shader_ready;
    wire shader_valid;
    wire [LANES-1:0] shader_mask;
    wire [LANES*32-1:0] shader_color;

    reg [LANES*COORD_WIDTH-1:0] fragment_x_reg;
    reg [LANES*COORD_WIDTH-1:0] fragment_y_reg;

    reg [LANES*32-1:0] vertex_color_bus;
    integer lane;

    assign raster_ready = shader_ready;
    assign busy_o = raster_busy || shader_valid || done_pending;
    assign error_o = raster_error;
    assign fragment_valid_o = shader_valid;
    assign fragment_mask_o = shader_mask;
    assign fragment_x_o = fragment_x_reg;
    assign fragment_y_o = fragment_y_reg;
    assign fragment_color_o = shader_color;

    always @* begin
        vertex_color_bus = {(LANES*32){1'b0}};
        for (lane = 0; lane < LANES; lane = lane + 1)
            vertex_color_bus[lane*32 +: 32] = uniform_color_i;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            fragment_x_reg <= {(LANES*COORD_WIDTH){1'b0}};
            fragment_y_reg <= {(LANES*COORD_WIDTH){1'b0}};
            done_pending <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;

            if (raster_valid && raster_ready) begin
                fragment_x_reg <= raster_x;
                fragment_y_reg <= raster_y;
            end

            if (raster_done)
                done_pending <= 1'b1;

            if (done_pending && !shader_valid) begin
                done_o <= 1'b1;
                done_pending <= 1'b0;
            end
        end
    end

    gpu_triangle_rasterizer #(
        .XLEN(XLEN),
        .LANES(LANES),
        .COORD_WIDTH(COORD_WIDTH)
    ) rasterizer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(triangle_start_i),
        .start_ready_o(),
        .x0_i(x0_i),
        .y0_i(y0_i),
        .x1_i(x1_i),
        .y1_i(y1_i),
        .x2_i(x2_i),
        .y2_i(y2_i),
        .framebuffer_width_i(framebuffer_width_i),
        .framebuffer_height_i(framebuffer_height_i),
        .out_valid_o(raster_valid),
        .out_ready_i(raster_ready),
        .lane_mask_o(raster_mask),
        .lane_x_o(raster_x),
        .lane_y_o(raster_y),
        .busy_o(raster_busy),
        .done_o(raster_done),
        .error_o(raster_error)
    );

    gpu_shader_unit #(
        .XLEN(XLEN),
        .LANES(LANES)
    ) shader (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .in_valid_i(raster_valid),
        .in_ready_o(shader_ready),
        .lane_mask_i(raster_mask),
        .opcode_i(shader_opcode_i),
        .uniform_color_i(uniform_color_i),
        .vertex_color_i(vertex_color_bus),
        .texture_color_i(texture_color_i),
        .out_valid_o(shader_valid),
        .out_ready_i(fragment_ready_i),
        .out_mask_o(shader_mask),
        .out_color_o(shader_color)
    );


endmodule