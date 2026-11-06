`timescale 1ns/1ps

// Synchronous FIFO used by the USB HID and audio paths.
// DEPTH must be a power of two.

module usb_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 256
)(
    input wire clk,
    input wire rst,

    input wire wr_en,
    input wire [DATA_WIDTH-1:0] wr_data,

    input wire rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,

    output wire full,
    output wire empty,
    output reg [$clog2(DEPTH):0] count
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    wire do_write;
    wire do_read;

    assign full = (count == DEPTH);
    assign empty = (count == 0);

    assign do_write = wr_en && !full;
    assign do_read = rd_en && !empty;

    // First-word-fall-through read.
    assign rd_data = memory[rd_ptr];

    always @(posedge clk) begin

        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            
        end else begin
            if (do_write) begin
                memory[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_read)
                rd_ptr <= rd_ptr + 1'b1;

            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule