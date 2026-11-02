`timescale 1ns/1ps


// GPU Read DMA Arbiter

// Fair two-client arbiter for the single AXI read DMA stream.
// Typical clients are framebuffer scanout and the texture cache.
// A granted burst remains owned by that client until the final beat.

module gpu_read_arbiter #(
    parameter integer XLEN = 64
)(
    input clk_i,
    input rst_i,

    input c0_req_i,
    input [XLEN-1:0] c0_addr_i,
    input [7:0] c0_beats_i,
    output c0_ready_o,
    output c0_valid_o,
    output [63:0] c0_data_o,
    output c0_last_o,
    input c0_data_ready_i,
    output c0_done_o,
    output c0_error_o,

    input c1_req_i,
    input [XLEN-1:0] c1_addr_i,
    input [7:0] c1_beats_i,
    output c1_ready_o,
    output c1_valid_o,
    output [63:0] c1_data_o,
    output c1_last_o,
    input c1_data_ready_i,
    output c1_done_o,
    output c1_error_o,

    output reg dma_start_o,
    output reg [XLEN-1:0] dma_addr_o,
    output reg [7:0] dma_beats_o,
    input dma_busy_i,
    input dma_valid_i,
    input [63:0] dma_data_i,
    input dma_last_i,
    output dma_ready_o,
    input dma_done_i,
    input dma_error_i
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_C0 = 2'd1;
    localparam [1:0] S_C1 = 2'd2;

    reg [1:0] state;
    reg round_robin;
    reg error_seen;

    wire choose_c0 = c0_req_i && (!c1_req_i || !round_robin);
    wire choose_c1 = c1_req_i && (!c0_req_i || round_robin);

    assign c0_ready_o = (state == S_IDLE) && !dma_busy_i && choose_c0;
    assign c1_ready_o = (state == S_IDLE) && !dma_busy_i && choose_c1;

    assign c0_valid_o = (state == S_C0) && dma_valid_i;
    assign c1_valid_o = (state == S_C1) && dma_valid_i;
    assign c0_data_o = dma_data_i;
    assign c1_data_o = dma_data_i;
    assign c0_last_o = dma_last_i;
    assign c1_last_o = dma_last_i;

    assign dma_ready_o = (state == S_C0) ? c0_data_ready_i :
                         (state == S_C1) ? c1_data_ready_i : 1'b0;

    assign c0_done_o = (state == S_C0) && dma_done_i;
    assign c1_done_o = (state == S_C1) && dma_done_i;
    assign c0_error_o = (state == S_C0) && (dma_error_i || (dma_done_i && error_seen));
    assign c1_error_o = (state == S_C1) && (dma_error_i || (dma_done_i && error_seen));

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            round_robin <= 1'b0;
            dma_start_o <= 1'b0;
            dma_addr_o <= {XLEN{1'b0}};
            dma_beats_o <= 8'd0;
            error_seen <= 1'b0;
        end else begin
            dma_start_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    error_seen <= 1'b0;
                    if (!dma_busy_i && choose_c0) begin
                        dma_start_o <= 1'b1;
                        dma_addr_o <= c0_addr_i;
                        dma_beats_o <= c0_beats_i;
                        state <= S_C0;
                    end else if (!dma_busy_i && choose_c1) begin
                        dma_start_o <= 1'b1;
                        dma_addr_o <= c1_addr_i;
                        dma_beats_o <= c1_beats_i;
                        state <= S_C1;
                    end
                end

                S_C0: begin
                    if (dma_error_i)
                        error_seen <= 1'b1;
                    if (dma_done_i) begin
                        round_robin <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_C1: begin
                    if (dma_error_i)
                        error_seen <= 1'b1;
                    if (dma_done_i) begin
                        round_robin <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule