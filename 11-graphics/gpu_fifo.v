`timescale 1ns/1ps


// GPU FIFO

// Synchronous FIFO used for GPU command buffering.
// DEPTH must be a power of two.

module gpu_fifo #(
    parameter integer WIDTH = 64,
    parameter integer DEPTH = 16,
    parameter integer ADDR_WIDTH = 4
)(
    input clk_i,
    input rst_i,

    input push_i,
    input [WIDTH-1:0] data_i,
    input pop_i,
    output [WIDTH-1:0] data_o,

    output full_o,
    output empty_o,
    output reg [ADDR_WIDTH:0] count_o
);

    reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;

    wire push_accept = push_i && !full_o;
    wire pop_accept = pop_i && !empty_o;

    assign full_o = (count_o == DEPTH);
    assign empty_o = (count_o == 0);
    assign data_o = memory[read_ptr];

    always @(posedge clk_i) begin
        if (rst_i) begin
            write_ptr <= {ADDR_WIDTH{1'b0}};
            read_ptr <= {ADDR_WIDTH{1'b0}};
            count_o <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (push_accept) begin
                memory[write_ptr] <= data_i;
                write_ptr <= write_ptr + 1'b1;
            end

            if (pop_accept)
                read_ptr <= read_ptr + 1'b1;

            case ({push_accept, pop_accept})
                2'b10: count_o <= count_o + 1'b1;
                2'b01: count_o <= count_o - 1'b1;
                default: count_o <= count_o;
            endcase
        end
    end

endmodule