`timescale 1ns/1ps

// ASYNCHRONOUS FIFO
// Dual-clock FIFO using Gray-coded read/write pointers.


module Async_FIFO #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 4
)(
    input wire WR_CLK_I,
    input wire WR_RST_I,
    input wire WR_EN_I,
    input wire [DATA_WIDTH-1:0] WR_DATA_I,
    output wire WR_FULL_O,

    input wire RD_CLK_I,
    input wire RD_RST_I,
    input wire RD_EN_I,
    output reg [DATA_WIDTH-1:0] RD_DATA_O,
    output reg RD_VALID_O,
    output wire RD_EMPTY_O
);

    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;

    reg [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];

    reg [PTR_WIDTH-1:0] wr_binary;
    reg [PTR_WIDTH-1:0] wr_gray;
    reg [PTR_WIDTH-1:0] rd_binary;
    reg [PTR_WIDTH-1:0] rd_gray;

    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_wr_sync1;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_wr_sync2;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_rd_sync1;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_rd_sync2;

    reg wr_full;
    reg rd_empty;

    wire [PTR_WIDTH-1:0] wr_binary_next;
    wire [PTR_WIDTH-1:0] wr_gray_next;
    wire [PTR_WIDTH-1:0] rd_binary_next;
    wire [PTR_WIDTH-1:0] rd_gray_next;
    wire wr_full_next;
    wire rd_empty_next;
    reg [PTR_WIDTH-1:0] inverted_rd_gray;

    assign wr_binary_next = wr_binary + ((WR_EN_I && !wr_full) ? 1'b1 : 1'b0);
    assign wr_gray_next = (wr_binary_next >> 1) ^ wr_binary_next;

    assign rd_binary_next = rd_binary + ((RD_EN_I && !rd_empty) ? 1'b1 : 1'b0);
    assign rd_gray_next = (rd_binary_next >> 1) ^ rd_binary_next;

    // Inverting the two most significant synchronized Gray bits is the standard asynchronous FIFO full comparison.
    always @(*) begin
        inverted_rd_gray = rd_gray_wr_sync2;
        inverted_rd_gray[PTR_WIDTH-1] = ~rd_gray_wr_sync2[PTR_WIDTH-1];
        inverted_rd_gray[PTR_WIDTH-2] = ~rd_gray_wr_sync2[PTR_WIDTH-2];
    end

    assign wr_full_next = (wr_gray_next == inverted_rd_gray);
    assign rd_empty_next = (rd_gray_next == wr_gray_rd_sync2);

    assign WR_FULL_O = wr_full;
    assign RD_EMPTY_O = rd_empty;

    // Synchronize the read pointer into the write-clock domain.
    always @(posedge WR_CLK_I or posedge WR_RST_I) begin
        if (WR_RST_I) begin
            rd_gray_wr_sync1 <= {PTR_WIDTH{1'b0}};
            rd_gray_wr_sync2 <= {PTR_WIDTH{1'b0}};
        end

        else begin
            rd_gray_wr_sync1 <= rd_gray;
            rd_gray_wr_sync2 <= rd_gray_wr_sync1;
        end
    end

    // Synchronize the write pointer into the read-clock domain.
    always @(posedge RD_CLK_I or posedge RD_RST_I) begin
        if (RD_RST_I) begin
            wr_gray_rd_sync1 <= {PTR_WIDTH{1'b0}};
            wr_gray_rd_sync2 <= {PTR_WIDTH{1'b0}};
        end
        
        else begin
            wr_gray_rd_sync1 <= wr_gray;
            wr_gray_rd_sync2 <= wr_gray_rd_sync1;
        end
    end

    // Write-side pointer and storage.
    always @(posedge WR_CLK_I or posedge WR_RST_I) begin
        if (WR_RST_I) begin
            wr_binary <= {PTR_WIDTH{1'b0}};
            wr_gray <= {PTR_WIDTH{1'b0}};
            wr_full <= 1'b0;
        end
        
        else begin
            wr_full <= wr_full_next;
            if (WR_EN_I && !wr_full) begin
                memory[wr_binary[ADDR_WIDTH-1:0]] <= WR_DATA_I;
                wr_binary <= wr_binary_next;
                wr_gray <= wr_gray_next;
            end
        
        end
    
    
    end

    // Read-side pointer and synchronous data output. RD_VALID_O is asserted for one cycle after each accepted read.
    // Throughput is one word per read clock when RD_EN_I remains asserted.
    always @(posedge RD_CLK_I or posedge RD_RST_I) begin
        if (RD_RST_I) begin
            rd_binary <= {PTR_WIDTH{1'b0}};
            rd_gray <= {PTR_WIDTH{1'b0}};
            rd_empty <= 1'b1;
            RD_DATA_O <= {DATA_WIDTH{1'b0}};
            RD_VALID_O <= 1'b0;
        end
        
        else begin
            rd_empty <= rd_empty_next;
            RD_VALID_O <= 1'b0;
        
            if (RD_EN_I && !rd_empty) begin
                RD_DATA_O <= memory[rd_binary[ADDR_WIDTH-1:0]];
                RD_VALID_O <= 1'b1;
                rd_binary <= rd_binary_next;
                rd_gray <= rd_gray_next;
            end
        end
    end
    

endmodule