`timescale 1ns/1ps


// GPU 2D Fill Engine

// Writes solid-color rectangles to a 32-bit framebuffer in DDR.
// Two adjacent pixels are packed into each 64-bit AXI beat.
// Writes are grouped into bursts of at most 16 beats.

module gpu_2d_engine #(
    parameter integer XLEN = 64,
    parameter integer MAX_BURST = 16
)(
    input clk_i,
    input rst_i,

    input start_i,
    input [XLEN-1:0] fb_base_i,
    input [31:0] fb_stride_i,
    input [31:0] fb_width_i,
    input [31:0] fb_height_i,
    input [31:0] color_i,
    input [15:0] rect_x_i,
    input [15:0] rect_y_i,
    input [15:0] rect_width_i,
    input [15:0] rect_height_i,

    output reg busy_o,
    output reg done_o,
    output reg error_o,

    // AXI DMA write request and stream interface.
    output dma_wr_start_o,
    output [XLEN-1:0] dma_wr_addr_o,
    output [7:0] dma_wr_beats_o,
    input dma_wr_start_ready_i,
    output dma_wr_data_valid_o,
    output [63:0] dma_wr_data_o,
    output [7:0] dma_wr_strb_o,
    input dma_wr_data_ready_i,
    input dma_wr_done_i,
    input dma_wr_error_i
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_ISSUE = 2'd1;
    localparam [1:0] S_SEND = 2'd2;
    localparam [1:0] S_WAIT = 2'd3;

    reg [1:0] state;

    reg [XLEN-1:0] fb_base;
    reg [31:0] fb_stride;
    reg [31:0] fb_width;
    reg [31:0] fb_height;
    reg [31:0] fill_color;

    reg [15:0] x_start;
    reg [15:0] y_start;
    reg [15:0] fill_width;
    reg [15:0] fill_height;

    reg [15:0] row_index;
    reg [31:0] word_offset;
    reg [7:0] burst_beats;
    reg [7:0] beat_index;

    wire [31:0] x_first = {16'd0, x_start};
    wire [31:0] x_end_exclusive = {16'd0, x_start} + {16'd0, fill_width};
    wire [31:0] first_word = x_first >> 1;
    wire [31:0] last_word = (x_end_exclusive - 1'b1) >> 1;
    wire [31:0] row_words = last_word - first_word + 1'b1;
    wire [31:0] words_remaining = row_words - word_offset;
    wire [7:0] next_burst_beats = (words_remaining > MAX_BURST) ? MAX_BURST : words_remaining[7:0];

    wire [31:0] current_word = first_word + word_offset + beat_index;
    wire [31:0] current_pixel_x = current_word << 1;
    wire [31:0] x_end = x_end_exclusive;

    reg [7:0] current_strb;

    assign dma_wr_start_o = (state == S_ISSUE);
    assign dma_wr_addr_o = fb_base + ({{(XLEN-16){1'b0}}, (y_start + row_index)} * {{(XLEN-32){1'b0}}, fb_stride}) + ({{(XLEN-32){1'b0}}, (first_word + word_offset)} << 3);
    assign dma_wr_beats_o = next_burst_beats;
    assign dma_wr_data_valid_o = (state == S_SEND);
    assign dma_wr_data_o = {fill_color, fill_color};
    assign dma_wr_strb_o = current_strb;

    always @* begin
        current_strb = 8'h00;

        if ((current_pixel_x >= x_first) && (current_pixel_x < x_end))
            current_strb[3:0] = 4'hF;

        if (((current_pixel_x + 1'b1) >= x_first) && ((current_pixel_x + 1'b1) < x_end))
            current_strb[7:4] = 4'hF;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            fb_base <= {XLEN{1'b0}};
            fb_stride <= 32'd0;
            fb_width <= 32'd0;
            fb_height <= 32'd0;
            fill_color <= 32'd0;
            x_start <= 16'd0;
            y_start <= 16'd0;
            fill_width <= 16'd0;
            fill_height <= 16'd0;
            row_index <= 16'd0;
            word_offset <= 32'd0;
            burst_beats <= 8'd0;
            beat_index <= 8'd0;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_o <= 1'b0;

                    if (start_i) begin
                        if ((rect_width_i == 0) ||
                            (rect_height_i == 0) ||
                            (fb_base_i[2:0] != 3'b000) ||
                            (fb_stride_i[2:0] != 3'b000) ||
                            (fb_stride_i < (fb_width_i << 2)) ||
                            (({16'd0, rect_x_i} + {16'd0, rect_width_i}) > fb_width_i) ||
                            (({16'd0, rect_y_i} + {16'd0, rect_height_i}) > fb_height_i)) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;

                        end else begin
                            fb_base <= fb_base_i;
                            fb_stride <= fb_stride_i;
                            fb_width <= fb_width_i;
                            fb_height <= fb_height_i;
                            fill_color <= color_i;
                            x_start <= rect_x_i;
                            y_start <= rect_y_i;
                            fill_width <= rect_width_i;
                            fill_height <= rect_height_i;
                            row_index <= 16'd0;
                            word_offset <= 32'd0;
                            beat_index <= 8'd0;
                            busy_o <= 1'b1;
                            state <= S_ISSUE;
                        end
                    end
                end

                S_ISSUE: begin
                    if (dma_wr_start_o && dma_wr_start_ready_i) begin
                        burst_beats <= next_burst_beats;
                        beat_index <= 8'd0;
                        state <= S_SEND;
                    end
                end

                S_SEND: begin
                    if (dma_wr_data_valid_o && dma_wr_data_ready_i) begin
                        beat_index <= beat_index + 1'b1;
                        if (beat_index == burst_beats - 1'b1)
                            state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (dma_wr_done_i) begin
                        if (dma_wr_error_i) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;
                            busy_o <= 1'b0;
                            state <= S_IDLE;
                        end else if ((word_offset + burst_beats) < row_words) begin
                            word_offset <= word_offset + burst_beats;
                            state <= S_ISSUE;
                        end else if ((row_index + 1'b1) < fill_height) begin
                            row_index <= row_index + 1'b1;
                            word_offset <= 32'd0;
                            state <= S_ISSUE;
                        end else begin
                            done_o <= 1'b1;
                            busy_o <= 1'b0;
                            state <= S_IDLE;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                    busy_o <= 1'b0;
                end
            endcase

        end

        
    end



endmodule