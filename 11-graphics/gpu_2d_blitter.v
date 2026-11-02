`timescale 1ns/1ps
// GPU 2D Blitter

// Copies a rectangular pixel region between two 32-bit framebuffers.
// Uses a 16-beat local buffer so reads and writes are burst based.
// Source and destination X coordinates, base addresses and strides must be
// 8-byte aligned (X coordinates must be even). Odd widths are supported.

module gpu_2d_blitter #(
    parameter integer XLEN = 64,
    parameter integer MAX_BURST = 16
)(
    input clk_i,
    input rst_i,

    input start_i,
    input [XLEN-1:0] src_base_i,
    input [XLEN-1:0] dst_base_i,
    input [31:0] src_stride_i,
    input [31:0] dst_stride_i,
    input [15:0] src_fb_width_i,
    input [15:0] src_fb_height_i,
    input [15:0] dst_fb_width_i,
    input [15:0] dst_fb_height_i,
    input [15:0] src_x_i,
    input [15:0] src_y_i,
    input [15:0] dst_x_i,
    input [15:0] dst_y_i,
    input [15:0] width_i,
    input [15:0] height_i,

    output reg busy_o,
    output reg done_o,
    output reg error_o,

    // Read client interface.
    output rd_start_o,
    output [XLEN-1:0] rd_addr_o,
    output [7:0] rd_beats_o,
    input rd_start_ready_i,
    input rd_valid_i,
    input [63:0] rd_data_i,
    output rd_ready_o,
    input rd_done_i,
    input rd_error_i,

    // Write client interface.
    output wr_start_o,
    output [XLEN-1:0] wr_addr_o,
    output [7:0] wr_beats_o,
    input wr_start_ready_i,
    output wr_valid_o,
    output [63:0] wr_data_o,
    output [7:0] wr_strb_o,
    input wr_ready_i,
    input wr_done_i,
    input wr_error_i
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_RD_ISSUE = 3'd1;
    localparam [2:0] S_RD_DATA = 3'd2;
    localparam [2:0] S_WR_ISSUE = 3'd3;
    localparam [2:0] S_WR_DATA = 3'd4;
    localparam [2:0] S_WR_WAIT = 3'd5;

    reg [2:0] state;
    reg [63:0] burst_buffer [0:MAX_BURST-1];

    reg [XLEN-1:0] src_base;
    reg [XLEN-1:0] dst_base;
    reg [31:0] src_stride;
    reg [31:0] dst_stride;
    reg [15:0] src_x;
    reg [15:0] src_y;
    reg [15:0] dst_x;
    reg [15:0] dst_y;
    reg [15:0] copy_width;
    reg [15:0] copy_height;
    reg [15:0] row_index;
    reg [31:0] word_offset;
    reg [7:0] chunk_beats;
    reg [7:0] read_count;
    reg [7:0] write_count;

    wire [31:0] row_words = ({16'd0, copy_width} + 1'b1) >> 1;
    wire [31:0] words_remaining = row_words - word_offset;
    wire [7:0] next_beats = (words_remaining > MAX_BURST) ? MAX_BURST : words_remaining[7:0];

    wire [XLEN-1:0] src_row_offset = {{(XLEN-16){1'b0}}, (src_y + row_index)} * {{(XLEN-32){1'b0}}, src_stride};
    wire [XLEN-1:0] dst_row_offset = {{(XLEN-16){1'b0}}, (dst_y + row_index)} * {{(XLEN-32){1'b0}}, dst_stride};
    wire [XLEN-1:0] x_word_offset = ({{(XLEN-32){1'b0}}, ((src_x >> 1) + word_offset)} << 3);
    wire [XLEN-1:0] dst_word_offset = ({{(XLEN-32){1'b0}}, ((dst_x >> 1) + word_offset)} << 3);

    assign rd_start_o = (state == S_RD_ISSUE);
    assign rd_addr_o = src_base + src_row_offset + x_word_offset;
    assign rd_beats_o = next_beats;
    assign rd_ready_o = (state == S_RD_DATA);

    assign wr_start_o = (state == S_WR_ISSUE);
    assign wr_addr_o = dst_base + dst_row_offset + dst_word_offset;
    assign wr_beats_o = chunk_beats;
    assign wr_valid_o = (state == S_WR_DATA);
    assign wr_data_o = burst_buffer[write_count];
    assign wr_strb_o = ((copy_width[0]) && ((word_offset + write_count) == (row_words - 1'b1))) ? 8'h0F : 8'hFF;

    always @(posedge clk_i) begin

        if (rst_i) begin
            state <= S_IDLE;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            src_base <= {XLEN{1'b0}};
            dst_base <= {XLEN{1'b0}};
            src_stride <= 32'd0;
            dst_stride <= 32'd0;
            src_x <= 16'd0;
            src_y <= 16'd0;
            dst_x <= 16'd0;
            dst_y <= 16'd0;
            copy_width <= 16'd0;
            copy_height <= 16'd0;
            row_index <= 16'd0;
            word_offset <= 32'd0;
            chunk_beats <= 8'd0;
            read_count <= 8'd0;
            write_count <= 8'd0;

        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_o <= 1'b0;

                    if (start_i) begin
                        if ((width_i == 0) || (height_i == 0) ||
                            (src_base_i[2:0] != 3'b000) ||
                            (dst_base_i[2:0] != 3'b000) ||
                            (src_stride_i[2:0] != 3'b000) ||
                            (dst_stride_i[2:0] != 3'b000) ||
                            (src_x_i[0] || dst_x_i[0]) ||
                            (src_stride_i < ({16'd0, src_fb_width_i} << 2)) ||
                            (dst_stride_i < ({16'd0, dst_fb_width_i} << 2)) ||
                            (({16'd0, src_x_i} + {16'd0, width_i}) > src_fb_width_i) ||
                            (({16'd0, dst_x_i} + {16'd0, width_i}) > dst_fb_width_i) ||
                            (({16'd0, src_y_i} + {16'd0, height_i}) > src_fb_height_i) ||
                            (({16'd0, dst_y_i} + {16'd0, height_i}) > dst_fb_height_i)) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;

                        end else begin
                            src_base <= src_base_i;
                            dst_base <= dst_base_i;
                            src_stride <= src_stride_i;
                            dst_stride <= dst_stride_i;
                            src_x <= src_x_i;
                            src_y <= src_y_i;
                            dst_x <= dst_x_i;
                            dst_y <= dst_y_i;
                            copy_width <= width_i;
                            copy_height <= height_i;
                            row_index <= 16'd0;
                            word_offset <= 32'd0;
                            busy_o <= 1'b1;
                            state <= S_RD_ISSUE;
                        end

                    end


                end

                S_RD_ISSUE: begin
                    if (rd_start_o && rd_start_ready_i) begin
                        chunk_beats <= next_beats;
                        read_count <= 8'd0;
                        state <= S_RD_DATA;
                    end
                end

                S_RD_DATA: begin
                    if (rd_valid_i && rd_ready_o) begin
                        burst_buffer[read_count] <= rd_data_i;
                        read_count <= read_count + 1'b1;
                    end

                    if (rd_error_i) begin
                        error_o <= 1'b1;
                        done_o <= 1'b1;
                        busy_o <= 1'b0;
                        state <= S_IDLE;
                    end else if (rd_done_i) begin
                        write_count <= 8'd0;
                        state <= S_WR_ISSUE;
                    end
                end

                S_WR_ISSUE: begin
                    if (wr_start_o && wr_start_ready_i) begin
                        write_count <= 8'd0;
                        state <= S_WR_DATA;
                    end
                end

                S_WR_DATA: begin
                    if (wr_valid_o && wr_ready_i) begin
                        write_count <= write_count + 1'b1;
                        if (write_count == chunk_beats - 1'b1)
                            state <= S_WR_WAIT;
                    end
                end

                S_WR_WAIT: begin

                    if (wr_error_i) begin
                        error_o <= 1'b1;
                        done_o <= 1'b1;
                        busy_o <= 1'b0;
                        state <= S_IDLE;

                    end else if (wr_done_i) begin

                        if ((word_offset + chunk_beats) < row_words) begin
                            word_offset <= word_offset + chunk_beats;
                            state <= S_RD_ISSUE;
                        end else if ((row_index + 1'b1) < copy_height) begin
                            row_index <= row_index + 1'b1;
                            word_offset <= 32'd0;
                            state <= S_RD_ISSUE;
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