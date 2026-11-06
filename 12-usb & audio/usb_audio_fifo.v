`timescale 1ns/1ps

// Stereo PCM FIFO.
// One 32-bit word contains {left_sample[15:0], right_sample[15:0]}.

module usb_audio_fifo #(
    parameter DEPTH = 1024
)(
    input wire clk,
    input wire rst,

    input wire cpu_write_i,
    input wire [31:0] cpu_data_i,
    output wire full_o,

    input wire ps_ready_i,
    output wire ps_valid_o,
    output wire [31:0] ps_data_o,

    output wire almost_full_o,
    output wire [$clog2(DEPTH):0] count_o
);

    wire empty;
    wire [31:0] fifo_data;
    wire fifo_read;

    assign ps_valid_o = !empty;
    assign ps_data_o = fifo_data;
    assign fifo_read = ps_valid_o && ps_ready_i;

    assign almost_full_o = (count_o >= DEPTH - 16);

    usb_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(DEPTH)
    ) audio_fifo (
        .clk(clk),
        .rst(rst),

        .wr_en(cpu_write_i),
        .wr_data(cpu_data_i),

        .rd_en(fifo_read),
        .rd_data(fifo_data),

        .full(full_o),
        .empty(empty),
        .count(count_o)
    );

endmodule