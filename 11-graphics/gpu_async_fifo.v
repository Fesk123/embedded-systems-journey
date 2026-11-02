`timescale 1ns/1ps


// GPU Asynchronous FIFO

// Gray-coded dual-clock FIFO for crossing the AXI clock domain into the video pixel-clock domain. DEPTH is 2**ADDR_WIDTH.

module gpu_async_fifo #(
    parameter integer WIDTH = 64,
    parameter integer ADDR_WIDTH = 9
)(
    input wr_clk_i,
    input wr_rst_i,
    input wr_en_i,
    input [WIDTH-1:0] wr_data_i,
    output full_o,

    input rd_clk_i,
    input rd_rst_i,
    input rd_en_i,
    output [WIDTH-1:0] rd_data_o,
    output empty_o,
    output [ADDR_WIDTH:0] rd_count_o
);

    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;

    reg [WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];

    reg [PTR_WIDTH-1:0] wr_bin;
    reg [PTR_WIDTH-1:0] wr_gray;
    reg [PTR_WIDTH-1:0] rd_bin;
    reg [PTR_WIDTH-1:0] rd_gray;

    reg [PTR_WIDTH-1:0] rd_gray_sync1;
    reg [PTR_WIDTH-1:0] rd_gray_sync2;
    reg [PTR_WIDTH-1:0] wr_gray_sync1;
    reg [PTR_WIDTH-1:0] wr_gray_sync2;

    reg full_reg;
    reg empty_reg;

    wire wr_take = wr_en_i && !full_reg;
    wire rd_take = rd_en_i && !empty_reg;

    wire [PTR_WIDTH-1:0] wr_bin_next = wr_bin + wr_take;
    wire [PTR_WIDTH-1:0] rd_bin_next = rd_bin + rd_take;
    wire [PTR_WIDTH-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [PTR_WIDTH-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    function [PTR_WIDTH-1:0] gray_to_bin;
        input [PTR_WIDTH-1:0] gray_value;
        integer i;
        begin
            gray_to_bin[PTR_WIDTH-1] = gray_value[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                gray_to_bin[i] = gray_to_bin[i+1] ^ gray_value[i];
        end
    endfunction

    wire [PTR_WIDTH-1:0] wr_bin_sync = gray_to_bin(wr_gray_sync2);
    wire [PTR_WIDTH-1:0] rd_count = wr_bin_sync - rd_bin;

    wire full_next = (wr_gray_next == {~rd_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2], rd_gray_sync2[PTR_WIDTH-3:0]});
    wire empty_next = (rd_gray_next == wr_gray_sync2);

    assign full_o = full_reg;
    assign empty_o = empty_reg;
    assign rd_data_o = memory[rd_bin[ADDR_WIDTH-1:0]];
    assign rd_count_o = rd_count[ADDR_WIDTH:0];

    always @(posedge wr_clk_i) begin

        if (wr_rst_i) begin

            rd_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_gray_sync2 <= {PTR_WIDTH{1'b0}};

        end else begin

            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;

        end

    end

    always @(posedge rd_clk_i) begin
        if (rd_rst_i) begin
            wr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    always @(posedge wr_clk_i) begin
        if (wr_rst_i) begin
            wr_bin <= {PTR_WIDTH{1'b0}};
            wr_gray <= {PTR_WIDTH{1'b0}};
            full_reg <= 1'b0;
        end else begin
            if (wr_take)
                memory[wr_bin[ADDR_WIDTH-1:0]] <= wr_data_i;
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full_reg <= full_next;
        end
    end

    always @(posedge rd_clk_i) begin
        if (rd_rst_i) begin
            rd_bin <= {PTR_WIDTH{1'b0}};

            rd_gray <= {PTR_WIDTH{1'b0}};
            empty_reg <= 1'b1;
        end else begin
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty_reg <= empty_next;
        end
    
    
    end

endmodule