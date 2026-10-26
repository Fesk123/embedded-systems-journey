`timescale 1ns/1ps

// Simple synchronous FIFO used for storage requests and completions.
// The FIFO clock must be shared by both interfaces connected to sd_emmc.v.

module sd_emmc_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH = 16,
    parameter integer COUNT_WIDTH = $clog2(DEPTH + 1),
    parameter integer PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
)(
    input wire clk_i,
    input wire rst_i,

    input wire push_i,
    input wire [DATA_WIDTH-1:0] data_i,
    input wire pop_i,

    output wire [DATA_WIDTH-1:0] data_o,
    output wire [COUNT_WIDTH-1:0] count_o,
    output wire full_o,
    output wire empty_o
);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [COUNT_WIDTH-1:0] count;

    wire push_accept;
    wire pop_accept;

    integer i;

    assign full_o = (count == DEPTH);
    assign empty_o = (count == 0);
    assign count_o = count;
    assign data_o = memory[read_ptr];

    assign push_accept = push_i && !full_o;
    assign pop_accept = pop_i && !empty_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            write_ptr <= {PTR_WIDTH{1'b0}};
            read_ptr <= {PTR_WIDTH{1'b0}};
            count <= {COUNT_WIDTH{1'b0}};

            for (i = 0; i < DEPTH; i = i + 1) begin
                memory[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (push_accept) begin
                memory[write_ptr] <= data_i;
                write_ptr <= write_ptr + 1'b1;
            end

            if (pop_accept) begin
                read_ptr <= read_ptr + 1'b1;
            end

            case ({push_accept, pop_accept})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule