`timescale 1ns/1ps


// GPU Command Processor

// Buffers CPU commands and dispatches them when the 2D engine is available.
// Command format is shared with gpu_registers.v.

module gpu_command_processor #(
    parameter integer XLEN = 64,
    parameter integer FIFO_DEPTH = 16,
    parameter integer FIFO_ADDR_WIDTH = 4,
    parameter integer CMD_WIDTH = XLEN + 196
)(
    input clk_i,
    input rst_i,

    input cmd_push_i,
    input [CMD_WIDTH-1:0] cmd_payload_i,
    output cmd_ready_o,

    input engine_busy_i,
    input engine_done_i,
    input engine_error_i,

    output engine_start_o,
    output [XLEN-1:0] engine_fb_base_o,
    output [31:0] engine_fb_stride_o,
    output [31:0] engine_fb_width_o,
    output [31:0] engine_fb_height_o,
    output [31:0] engine_color_o,
    output [15:0] engine_rect_x_o,
    output [15:0] engine_rect_y_o,
    output [15:0] engine_rect_width_o,
    output [15:0] engine_rect_height_o,

    output busy_o,
    output reg command_error_o,
    output [FIFO_ADDR_WIDTH:0] queue_count_o
);

    localparam integer FIFO_WIDTH = CMD_WIDTH;
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_ISSUE = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;

    reg [1:0] state;
    reg [CMD_WIDTH-1:0] active_command;

    wire [CMD_WIDTH-1:0] fifo_data;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_pop;

    gpu_fifo #(
        .WIDTH(FIFO_WIDTH),
        .DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) command_fifo (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .push_i(cmd_push_i),
        .data_i(cmd_payload_i),
        .pop_i(fifo_pop),
        .data_o(fifo_data),
        .full_o(fifo_full),
        .empty_o(fifo_empty),
        .count_o(queue_count_o)
    );

    assign cmd_ready_o = !fifo_full;
    assign fifo_pop = (state == S_IDLE) && !fifo_empty && !engine_busy_i;
    assign engine_start_o = (state == S_ISSUE);
    assign busy_o = (state != S_IDLE) || !fifo_empty;

    assign engine_fb_base_o = active_command[CMD_WIDTH-1 -: XLEN];
    assign engine_fb_stride_o = active_command[195:164];
    assign engine_fb_width_o = active_command[163:132];
    assign engine_fb_height_o = active_command[131:100];
    assign engine_color_o = active_command[99:68];
    assign engine_rect_x_o = active_command[67:52];
    assign engine_rect_y_o = active_command[51:36];
    assign engine_rect_width_o = active_command[35:20];
    assign engine_rect_height_o = active_command[19:4];

    always @(posedge clk_i) begin

        if (rst_i) begin
            state <= S_IDLE;
            active_command <= {CMD_WIDTH{1'b0}};
            command_error_o <= 1'b0;

        end else begin
            command_error_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (fifo_pop) begin
                        active_command <= fifo_data;
                        if (fifo_data[3:0] == 4'd1)
                            state <= S_ISSUE;
                        else begin
                            command_error_o <= 1'b1;
                            state <= S_IDLE;
                        end
                    end
                end

                S_ISSUE: state <= S_WAIT;

                S_WAIT: begin
                    if (engine_done_i || engine_error_i)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

        end


    end

endmodule