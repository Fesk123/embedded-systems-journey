`timescale 1ns/1ps

// HID event FIFO.
// The PS-side producer uses valid/ready. The CPU consumes one 32-bit event.

module usb_hid_fifo #(
    parameter DEPTH = 256
)(
    input wire clk,
    input wire rst,

    input wire ps_valid_i,
    input wire [31:0] ps_data_i,
    output wire ps_ready_o,

    input wire cpu_read_i,
    output wire [31:0] cpu_data_o,
    output wire cpu_valid_o,

    output wire [$clog2(DEPTH):0] count_o
);

    wire full;
    wire empty;

    assign ps_ready_o = !full;
    assign cpu_valid_o = !empty;

    usb_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(DEPTH)
    ) hid_fifo (
        .clk(clk),
        .rst(rst),

        .wr_en(ps_valid_i && ps_ready_o),
        .wr_data(ps_data_i),

        .rd_en(cpu_read_i && cpu_valid_o),
        .rd_data(cpu_data_o),

        .full(full),
        .empty(empty),
        .count(count_o)
    );

endmodule