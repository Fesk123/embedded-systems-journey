`timescale 1ns/1ps


// GPU Video Timing Controller

// Generates raster timing for a 720p or 1080p display mode.
// pixel_data_i must be supplied by the framebuffer scanout path.
// pixel clock may be independent from the GPU/AXI clock.

module gpu_video_timing #(
    parameter integer ACTIVE_WIDTH = 1280,
    parameter integer ACTIVE_HEIGHT = 720,
    parameter integer H_FRONT = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BACK = 220,
    parameter integer V_FRONT = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BACK = 20,
    parameter integer HSYNC_POSITIVE = 0,
    parameter integer VSYNC_POSITIVE = 0
)(
    input pixel_clk_i,
    input rst_i,
    input enable_i,
    input [31:0] pixel_data_i,

    output [11:0] x_o,
    output [11:0] y_o,
    output hsync_o,
    output vsync_o,
    output de_o,
    output [23:0] rgb_o
);

    localparam integer H_TOTAL = ACTIVE_WIDTH + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL = ACTIVE_HEIGHT + V_FRONT + V_SYNC + V_BACK;

    reg [11:0] h_count;
    reg [11:0] v_count;

    wire active = enable_i && (h_count < ACTIVE_WIDTH) && (v_count < ACTIVE_HEIGHT);
    wire hsync_active = (h_count >= (ACTIVE_WIDTH + H_FRONT)) && (h_count < (ACTIVE_WIDTH + H_FRONT + H_SYNC));
    wire vsync_active = (v_count >= (ACTIVE_HEIGHT + V_FRONT)) && (v_count < (ACTIVE_HEIGHT + V_FRONT + V_SYNC));

    assign x_o = h_count;
    assign y_o = v_count;
    assign de_o = active;
    assign hsync_o = !enable_i ? (HSYNC_POSITIVE ? 1'b0 : 1'b1) : (HSYNC_POSITIVE ? hsync_active : !hsync_active);
    assign vsync_o = !enable_i ? (VSYNC_POSITIVE ? 1'b0 : 1'b1) : (VSYNC_POSITIVE ? vsync_active : !vsync_active);
    assign rgb_o = active ? pixel_data_i[23:0] : 24'h000000;

    always @(posedge pixel_clk_i) begin
        if (rst_i || !enable_i) begin
            h_count <= 12'd0;
            v_count <= 12'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 12'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 12'd0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end

        end

        
    end

endmodule