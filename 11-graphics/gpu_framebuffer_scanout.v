`timescale 1ns/1ps


// GPU Framebuffer Scanout

// Reads a linear 32-bit framebuffer from DDR in 64-bit AXI bursts.
// Read data crosses into the pixel clock domain through gpu_async_fifo.v.
// Framebuffer base and stride must be 8-byte aligned.
// An odd framebuffer width leaves the upper pixel of the final word unused.

module gpu_framebuffer_scanout #(
    parameter integer XLEN = 64,
    parameter integer FIFO_ADDR_WIDTH = 9,
    parameter integer MAX_BURST = 16,
    parameter integer PREFILL_WORDS = 32
)(
    input clk_i,
    input pixel_clk_i,
    input rst_i,

    input start_i,
    input [XLEN-1:0] framebuffer_base_i,
    input [31:0] framebuffer_stride_i,
    input [15:0] framebuffer_width_i,
    input [15:0] framebuffer_height_i,

    // Read client interface. Connect this to gpu_read_arbiter.v.
    output rd_req_o,
    output [XLEN-1:0] rd_addr_o,
    output [7:0] rd_beats_o,
    input rd_req_ready_i,
    input rd_busy_i,
    input rd_valid_i,
    input [63:0] rd_data_i,
    input rd_last_i,
    output rd_data_ready_o,
    input rd_done_i,
    input rd_error_i,

    // Pixel-clock domain interface.
    input pixel_active_i,
    input [11:0] pixel_x_i,
    output [31:0] pixel_data_o,
    output reg pixel_ready_o,
    output reg pixel_underflow_o,
    output reg scanout_error_o
);

    localparam integer FIFO_DEPTH = (1 << FIFO_ADDR_WIDTH);
    localparam integer PREFILL_LIMIT = (PREFILL_WORDS > FIFO_DEPTH) ? FIFO_DEPTH : PREFILL_WORDS;
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_WAIT = 2'd1;

    reg [1:0] state;
    reg enabled;
    reg [XLEN-1:0] framebuffer_base;
    reg [31:0] framebuffer_stride;
    reg [15:0] framebuffer_width;
    reg [15:0] framebuffer_height;
    reg [15:0] row_index;
    reg [31:0] word_offset;
    reg [7:0] issued_beats;
    reg [FIFO_ADDR_WIDTH:0] prefill_target;

    reg [FIFO_ADDR_WIDTH:0] prefill_sync1;
    reg [FIFO_ADDR_WIDTH:0] prefill_sync2;
    reg enabled_sync1;
    reg enabled_sync2;

    wire [31:0] total_frame_words =
        ((({16'd0, framebuffer_width_i} + 1'b1) >> 1) * framebuffer_height_i);

    wire [31:0] row_words = ({16'd0, framebuffer_width} + 1'b1) >> 1;
    wire [31:0] words_remaining = row_words - word_offset;
    wire [7:0] next_beats = (words_remaining > MAX_BURST) ? MAX_BURST : words_remaining[7:0];
    wire [XLEN-1:0] row_offset =
        {{(XLEN-16){1'b0}}, row_index} * {{(XLEN-32){1'b0}}, framebuffer_stride};
    wire [XLEN-1:0] current_word_offset = {{(XLEN-32){1'b0}}, word_offset} << 3;

    wire fifo_full;
    wire fifo_empty;
    wire [FIFO_ADDR_WIDTH:0] fifo_count;
    wire [63:0] fifo_data;
    wire fifo_write = rd_valid_i && rd_data_ready_o;
    wire fifo_read = pixel_active_i && !pixel_x_i[0] && !fifo_empty;

    reg [63:0] pixel_pair;
    reg pair_valid;

    assign rd_req_o = enabled && (state == S_IDLE) && !fifo_full && !rd_busy_i;
    assign rd_addr_o = framebuffer_base + row_offset + current_word_offset;
    assign rd_beats_o = next_beats;
    assign rd_data_ready_o = !fifo_full;

    assign pixel_data_o = !pixel_active_i ? 32'd0 :
                          (!pixel_x_i[0] ? (fifo_empty ? 32'd0 : fifo_data[31:0]) :
                           (pair_valid ? pixel_pair[63:32] : 32'd0));

    gpu_async_fifo #(
        .WIDTH(64),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) pixel_fifo (
        .wr_clk_i(clk_i),
        .wr_rst_i(rst_i),
        .wr_en_i(fifo_write),
        .wr_data_i(rd_data_i),
        .full_o(fifo_full),
        .rd_clk_i(pixel_clk_i),
        .rd_rst_i(rst_i),
        .rd_en_i(fifo_read),
        .rd_data_o(fifo_data),
        .empty_o(fifo_empty),
        .rd_count_o(fifo_count)
    );

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            enabled <= 1'b0;
            framebuffer_base <= {XLEN{1'b0}};
            framebuffer_stride <= 32'd0;
            framebuffer_width <= 16'd0;
            framebuffer_height <= 16'd0;
            row_index <= 16'd0;
            word_offset <= 32'd0;
            issued_beats <= 8'd0;
            prefill_target <= {(FIFO_ADDR_WIDTH+1){1'b0}};
            scanout_error_o <= 1'b0;
        end else begin
            if (start_i && !enabled && (state == S_IDLE)) begin
                if ((framebuffer_base_i[2:0] != 3'b000) ||
                    (framebuffer_stride_i[2:0] != 3'b000) ||
                    (framebuffer_width_i == 0) ||
                    (framebuffer_height_i == 0) ||
                    (framebuffer_stride_i < ({16'd0, framebuffer_width_i} << 2))) begin
                    scanout_error_o <= 1'b1;
                    enabled <= 1'b0;
                end else begin
                    framebuffer_base <= framebuffer_base_i;
                    framebuffer_stride <= framebuffer_stride_i;
                    framebuffer_width <= framebuffer_width_i;
                    framebuffer_height <= framebuffer_height_i;
                    if (total_frame_words < PREFILL_LIMIT)
                        prefill_target <= total_frame_words[FIFO_ADDR_WIDTH:0];
                    else
                        prefill_target <= PREFILL_LIMIT;
                    row_index <= 16'd0;
                    word_offset <= 32'd0;
                    enabled <= 1'b1;
                    scanout_error_o <= 1'b0;
                end
            end

            case (state)
                S_IDLE: begin
                    if (rd_req_o && rd_req_ready_i) begin
                        issued_beats <= next_beats;
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (rd_error_i)
                        scanout_error_o <= 1'b1;

                    if (rd_done_i) begin
                        if (rd_error_i) begin
                            state <= S_IDLE;
                            enabled <= 1'b0;
                        end else if ((word_offset + issued_beats) < row_words) begin
                            word_offset <= word_offset + issued_beats;
                            state <= S_IDLE;
                        end else if ((row_index + 1'b1) < framebuffer_height) begin
                            row_index <= row_index + 1'b1;
                            word_offset <= 32'd0;
                            state <= S_IDLE;
                        end else begin
                            row_index <= 16'd0;
                            word_offset <= 32'd0;
                            state <= S_IDLE;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    always @(posedge pixel_clk_i) begin
        if (rst_i) begin
            pixel_pair <= 64'd0;
            pair_valid <= 1'b0;
            pixel_underflow_o <= 1'b0;
            pixel_ready_o <= 1'b0;
            prefill_sync1 <= {(FIFO_ADDR_WIDTH+1){1'b0}};
            prefill_sync2 <= {(FIFO_ADDR_WIDTH+1){1'b0}};
            enabled_sync1 <= 1'b0;
            enabled_sync2 <= 1'b0;
        end else begin
            prefill_sync1 <= prefill_target;
            prefill_sync2 <= prefill_sync1;
            enabled_sync1 <= enabled;
            enabled_sync2 <= enabled_sync1;
            if (!enabled_sync2)
                pixel_ready_o <= 1'b0;
            else if ((prefill_sync2 != 0) && (fifo_count >= prefill_sync2))
                pixel_ready_o <= 1'b1;

            if (pixel_active_i && !pixel_x_i[0]) begin
                if (!fifo_empty) begin
                    pixel_pair <= fifo_data;
                    pair_valid <= 1'b1;
                end else begin
                    pair_valid <= 1'b0;
                    pixel_underflow_o <= 1'b1;
                end
            end
        end
    end

endmodule