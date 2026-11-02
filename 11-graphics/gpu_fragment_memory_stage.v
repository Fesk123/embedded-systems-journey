`timescale 1ns/1ps


// GPU Fragment Memory Stage

// Applies optional depth testing and source-over blending before framebuffer
// writeback. It processes the lanes in order and uses 64-bit aligned one-beat
// transactions. This is the correctness-first backend; line caching and
// multi-pixel coalescing can replace it later without changing its interface.

module gpu_fragment_memory_stage #(
    parameter integer XLEN = 64,
    parameter integer LANES = 1
)(
    input clk_i,
    input rst_i,

    input fragment_valid_i,
    output fragment_ready_o,
    input [LANES-1:0] fragment_mask_i,
    input [LANES*16-1:0] fragment_x_i,
    input [LANES*16-1:0] fragment_y_i,
    input [LANES*32-1:0] fragment_color_i,
    input [LANES*32-1:0] fragment_depth_i,

    input [XLEN-1:0] framebuffer_base_i,
    input [31:0] framebuffer_stride_i,
    input [15:0] framebuffer_width_i,
    input [15:0] framebuffer_height_i,
    input [XLEN-1:0] depth_base_i,
    input [31:0] depth_stride_i,
    input depth_enable_i,
    input depth_write_enable_i,
    input [2:0] depth_compare_i,
    input blend_enable_i,

    output wire                 busy_o,
    output reg done_o,
    output reg error_o,

    // Read client interface. Use one read-arbiter client.
    output rd_req_o,
    output [XLEN-1:0] rd_addr_o,
    output [7:0] rd_beats_o,
    input rd_req_ready_i,
    input rd_valid_i,
    input [63:0] rd_data_i,
    output rd_data_ready_o,
    input rd_done_i,
    input rd_error_i,

    // Write client interface. Use one write-mux client.
    output wr_start_o,
    output [XLEN-1:0] wr_addr_o,
    output [7:0] wr_beats_o,
    input wr_start_ready_i,
    output wr_valid_o,
    output [63:0] wr_data_o,
    output [7:0] wr_strb_o,
    input wr_data_ready_i,
    input wr_done_i,
    input wr_error_i
);

    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_FIND = 4'd1;
    localparam [3:0] S_READ_REQ = 4'd2;
    localparam [3:0] S_READ_WAIT = 4'd3;
    localparam [3:0] S_DEPTH_TEST = 4'd4;
    localparam [3:0] S_COLOR_BLEND= 4'd5;
    localparam [3:0] S_WRITE_REQ = 4'd6;
    localparam [3:0] S_WRITE_DATA = 4'd7;
    localparam [3:0] S_WRITE_WAIT = 4'd8;

    reg [3:0] state;
    reg [LANES-1:0] mask_reg;
    reg [LANES*16-1:0] x_reg;
    reg [LANES*16-1:0] y_reg;
    reg [LANES*32-1:0] color_reg;
    reg [LANES*32-1:0] depth_reg;

    reg [XLEN-1:0] framebuffer_base;
    reg [31:0] framebuffer_stride;
    reg [15:0] framebuffer_width;
    reg [15:0] framebuffer_height;
    reg [XLEN-1:0] depth_base;
    reg [31:0] depth_stride;
    reg depth_enable;
    reg depth_write_enable;
    reg [2:0] depth_compare;
    reg blend_enable;

    integer lane_index;
    reg [31:0] current_x;
    reg [31:0] current_y;
    reg [31:0] current_color;
    reg [31:0] current_depth;
    reg [XLEN-1:0] current_color_addr;
    reg [XLEN-1:0] current_depth_addr;

    reg [XLEN-1:0] read_address;
    reg [XLEN-1:0] write_address;
    reg [63:0] read_buffer;
    reg [63:0] write_buffer;
    reg [7:0] write_strobe;
    reg write_is_depth;
    reg read_is_depth;
    reg [31:0] old_depth;
    reg [31:0] old_color;
    reg [31:0] blended_color;

    wire [31:0] selected_read_pixel = current_x[0] ? read_buffer[63:32] : read_buffer[31:0];
    wire depth_pass;
    wire depth_write_unused;
    wire [31:0] blend_result;

    wire [XLEN-1:0] current_color_row_offset =
        {{(XLEN-16){1'b0}}, current_y[15:0]} *
        {{(XLEN-32){1'b0}}, framebuffer_stride};
    wire [XLEN-1:0] current_depth_row_offset =
        {{(XLEN-16){1'b0}}, current_y[15:0]} *
        {{(XLEN-32){1'b0}}, depth_stride};
    wire [XLEN-1:0] current_pixel_word_offset =
        {{(XLEN-15){1'b0}}, current_x[15:1]} << 3;

    assign fragment_ready_o = (state == S_IDLE);
    assign busy_o = (state != S_IDLE);

    assign rd_req_o = (state == S_READ_REQ);
    assign rd_addr_o = read_address;
    assign rd_beats_o = 8'd1;
    assign rd_data_ready_o = (state == S_READ_WAIT);

    assign wr_start_o = (state == S_WRITE_REQ);
    assign wr_addr_o = write_address;
    assign wr_beats_o = 8'd1;
    assign wr_valid_o = (state == S_WRITE_DATA);
    assign wr_data_o = write_buffer;
    assign wr_strb_o = write_strobe;

    gpu_depth_unit depth_test (
        .new_depth_i(current_depth),
        .old_depth_i(selected_read_pixel),
        .compare_mode_i(depth_compare),
        .depth_enable_i(depth_enable),
        .depth_write_enable_i(depth_write_enable),
        .pass_o(depth_pass),
        .write_enable_o(depth_write_unused)
    );

    gpu_blend_unit blend (
        .src_pixel_i(current_color),
        .dst_pixel_i(selected_read_pixel),
        .enable_i(blend_enable),
        .result_o(blend_result)
    );

    always @* begin
        current_x = 32'd0;
        current_y = 32'd0;
        current_color = 32'd0;
        current_depth = 32'd0;

        if (lane_index < LANES) begin
            current_x = {16'd0, x_reg[lane_index*16 +: 16]};
            current_y = {16'd0, y_reg[lane_index*16 +: 16]};
            current_color = color_reg[lane_index*32 +: 32];
            current_depth = depth_reg[lane_index*32 +: 32];
        end

        current_color_addr = framebuffer_base + current_color_row_offset + current_pixel_word_offset;
        current_depth_addr = depth_base + current_depth_row_offset + current_pixel_word_offset;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            mask_reg <= {LANES{1'b0}};
            x_reg <= {(LANES*16){1'b0}};
            y_reg <= {(LANES*16){1'b0}};
            color_reg <= {(LANES*32){1'b0}};
            depth_reg <= {(LANES*32){1'b0}};
            framebuffer_base <= {XLEN{1'b0}};
            framebuffer_stride <= 32'd0;
            framebuffer_width <= 16'd0;
            framebuffer_height <= 16'd0;
            depth_base <= {XLEN{1'b0}};
            depth_stride <= 32'd0;
            depth_enable <= 1'b0;
            depth_write_enable <= 1'b0;
            depth_compare <= 3'd6;
            blend_enable <= 1'b0;
            lane_index <= 0;
            read_address <= {XLEN{1'b0}};
            write_address <= {XLEN{1'b0}};
            read_buffer <= 64'd0;
            write_buffer <= 64'd0;
            write_strobe <= 8'd0;
            write_is_depth <= 1'b0;
            read_is_depth <= 1'b0;
            old_depth <= 32'd0;
            old_color <= 32'd0;
            blended_color <= 32'd0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (fragment_valid_i && fragment_ready_o) begin
                        if ((framebuffer_base_i[2:0] != 3'b000) ||
                            (framebuffer_stride_i[2:0] != 3'b000) ||
                            (framebuffer_stride_i < ({16'd0, framebuffer_width_i} << 2)) ||
                            (framebuffer_width_i == 0) || (framebuffer_height_i == 0) ||
                            (depth_enable_i && ((depth_base_i[2:0] != 3'b000) ||
                             (depth_stride_i[2:0] != 3'b000) ||
                             (depth_stride_i < ({16'd0, framebuffer_width_i} << 2))))) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;
                        end else begin
                            mask_reg <= fragment_mask_i;
                            x_reg <= fragment_x_i;
                            y_reg <= fragment_y_i;
                            color_reg <= fragment_color_i;
                            depth_reg <= fragment_depth_i;
                            framebuffer_base <= framebuffer_base_i;
                            framebuffer_stride <= framebuffer_stride_i;
                            framebuffer_width <= framebuffer_width_i;
                            framebuffer_height <= framebuffer_height_i;
                            depth_base <= depth_base_i;
                            depth_stride <= depth_stride_i;
                            depth_enable <= depth_enable_i;
                            depth_write_enable <= depth_write_enable_i;
                            depth_compare <= depth_compare_i;
                            blend_enable <= blend_enable_i;
                            lane_index <= 0;
                            state <= S_FIND;
                        end
                    end
                end

                S_FIND: begin
                    if (lane_index >= LANES) begin
                        done_o <= 1'b1;
                        state <= S_IDLE;
                    end else if (!mask_reg[lane_index]) begin
                        lane_index <= lane_index + 1;
                    end else if ((current_x >= framebuffer_width) ||
                                 (current_y >= framebuffer_height)) begin
                        error_o <= 1'b1;
                        lane_index <= lane_index + 1;
                    end else begin
                        if (depth_enable) begin
                            read_address <= current_depth_addr;
                            read_is_depth <= 1'b1;
                            state <= S_READ_REQ;
                        end else if (blend_enable) begin
                            read_address <= current_color_addr;
                            read_is_depth <= 1'b0;
                            state <= S_READ_REQ;
                        end else begin
                            write_address <= current_color_addr;
                            write_buffer <= current_x[0] ? {current_color, 32'd0} : {32'd0, current_color};
                            write_strobe <= current_x[0] ? 8'hF0 : 8'h0F;
                            write_is_depth <= 1'b0;
                            state <= S_WRITE_REQ;
                        end
                    end
                end

                S_READ_REQ: begin
                    if (rd_req_o && rd_req_ready_i)
                        state <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    if (rd_valid_i && rd_data_ready_o)
                        read_buffer <= rd_data_i;

                    if (rd_done_i) begin
                        if (rd_error_i) begin
                            error_o <= 1'b1;
                            lane_index <= lane_index + 1;
                            state <= S_FIND;
                        end else if (read_is_depth) begin
                            state <= S_DEPTH_TEST;
                        end else begin
                            state <= S_COLOR_BLEND;
                        end
                    end
                end

                S_DEPTH_TEST: begin
                    if (!depth_pass) begin
                        lane_index <= lane_index + 1;
                        state <= S_FIND;
                    end else if (blend_enable) begin
                        read_address <= current_color_addr;
                        read_is_depth <= 1'b0;
                        state <= S_READ_REQ;
                    end else begin
                        write_address <= current_color_addr;
                        write_buffer <= current_x[0] ? {current_color, 32'd0} : {32'd0, current_color};
                        write_strobe <= current_x[0] ? 8'hF0 : 8'h0F;
                        write_is_depth <= 1'b0;
                        state <= S_WRITE_REQ;
                    end
                end

                S_COLOR_BLEND: begin
                    old_color <= selected_read_pixel;
                    blended_color <= blend_result;
                    write_address <= current_color_addr;
                    write_buffer <= current_x[0] ? {blend_result, 32'd0} : {32'd0, blend_result};
                    write_strobe <= current_x[0] ? 8'hF0 : 8'h0F;
                    write_is_depth <= 1'b0;
                    state <= S_WRITE_REQ;
                end

                S_WRITE_REQ: begin
                    if (wr_start_o && wr_start_ready_i)
                        state <= S_WRITE_DATA;
                end

                S_WRITE_DATA: begin
                    if (wr_valid_o && wr_data_ready_i)
                        state <= S_WRITE_WAIT;
                end

                S_WRITE_WAIT: begin
                    if (wr_done_i) begin
                        if (wr_error_i) begin
                            error_o <= 1'b1;
                            lane_index <= lane_index + 1;
                            state <= S_FIND;
                        end else if (!write_is_depth && depth_enable && depth_write_enable) begin
                            write_address <= current_depth_addr;
                            write_buffer <= current_x[0] ? {current_depth, 32'd0} : {32'd0, current_depth};
                            write_strobe <= current_x[0] ? 8'hF0 : 8'h0F;
                            write_is_depth <= 1'b1;
                            state <= S_WRITE_REQ;
                        end else begin
                            lane_index <= lane_index + 1;
                            state <= S_FIND;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule