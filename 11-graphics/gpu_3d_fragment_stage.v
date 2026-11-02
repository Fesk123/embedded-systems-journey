`timescale 1ns/1ps


// GPU 3D Fragment Stage

// Lane-parallel depth testing and alpha blending after shader execution.
// Old color and depth values are supplied by the framebuffer/depth cache path.

module gpu_3d_fragment_stage #(

    parameter integer XLEN = 64,
    parameter integer LANES = 1
)(
    input [LANES-1:0] lane_valid_i,
    input [LANES*32-1:0] source_color_i,
    input [LANES*32-1:0] destination_color_i,
    input [LANES*32-1:0] new_depth_i,
    input [LANES*32-1:0] old_depth_i,
    input [2:0] depth_compare_i,
    input depth_enable_i,
    input depth_write_enable_i,
    input blend_enable_i,

    output reg [LANES-1:0] lane_pass_o,
    output reg [LANES-1:0] depth_write_o,
    output reg [LANES*32-1:0] result_color_o
);

    integer lane;
    wire [LANES-1:0] depth_pass;
    wire [LANES-1:0] depth_write;
    wire [LANES*32-1:0] blended_color;

    genvar g;
    generate

        for (g = 0; g < LANES; g = g + 1) begin : fragment_lanes
            gpu_depth_unit depth_test (
                .new_depth_i(new_depth_i[g*32 +: 32]),
                .old_depth_i(old_depth_i[g*32 +: 32]),
                .compare_mode_i(depth_compare_i),
                .depth_enable_i(depth_enable_i),
                .depth_write_enable_i(depth_write_enable_i),
                .pass_o(depth_pass[g]),
                .write_enable_o(depth_write[g])
            );

            gpu_blend_unit blend (
                .src_pixel_i(source_color_i[g*32 +: 32]),
                .dst_pixel_i(destination_color_i[g*32 +: 32]),
                .enable_i(blend_enable_i),
                .result_o(blended_color[g*32 +: 32])
            );
        end
    endgenerate

    always @* begin
        lane_pass_o = {LANES{1'b0}};
        depth_write_o = {LANES{1'b0}};
        result_color_o = {(LANES*32){1'b0}};

        for (lane = 0; lane < LANES; lane = lane + 1) begin
            lane_pass_o[lane] = lane_valid_i[lane] && depth_pass[lane];
            depth_write_o[lane] = lane_valid_i[lane] && depth_write[lane];
            result_color_o[lane*32 +: 32] = (lane_valid_i[lane] && depth_pass[lane]) ? blended_color[lane*32 +: 32] : 32'd0;
        end

    end


endmodule