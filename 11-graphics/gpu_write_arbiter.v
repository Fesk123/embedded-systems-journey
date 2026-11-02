`timescale 1ns/1ps


// GPU Write DMA Arbiter

// Two-client round-robin arbiter for the shared AXI burst write engine.
// A client owns the write channel until its complete burst response returns.

module gpu_write_arbiter #(
    parameter integer XLEN = 64
)(
    input clk_i,
    input rst_i,

    input c0_start_i,
    input [XLEN-1:0] c0_addr_i,
    input [7:0] c0_beats_i,
    output c0_ready_o,
    input c0_valid_i,
    input [63:0] c0_data_i,
    input [7:0] c0_strb_i,
    output c0_data_ready_o,
    output c0_done_o,
    output c0_error_o,

    input c1_start_i,
    input [XLEN-1:0] c1_addr_i,
    input [7:0] c1_beats_i,
    output c1_ready_o,
    input c1_valid_i,
    input [63:0] c1_data_i,
    input [7:0] c1_strb_i,
    output c1_data_ready_o,
    output c1_done_o,
    output c1_error_o,

    output reg dma_start_o,
    output reg [XLEN-1:0] dma_addr_o,
    output reg [7:0] dma_beats_o,
    input dma_busy_i,
    output dma_valid_o,
    output [63:0] dma_data_o,
    output [7:0] dma_strb_o,
    input dma_data_ready_i,
    input dma_done_i,
    input dma_error_i
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_C0 = 2'd1;
    localparam [1:0] S_C1 = 2'd2;

    reg [1:0] state;
    reg round_robin;
    reg error_seen;

    wire choose_c0 = c0_start_i && (!c1_start_i || !round_robin);
    wire choose_c1 = c1_start_i && (!c0_start_i || round_robin);

    assign c0_ready_o = (state == S_IDLE) && !dma_busy_i && choose_c0;
    assign c1_ready_o = (state == S_IDLE) && !dma_busy_i && choose_c1;

    assign dma_valid_o = (state == S_C0) ? c0_valid_i :
                         (state == S_C1) ? c1_valid_i : 1'b0;
    assign dma_data_o = (state == S_C0) ? c0_data_i : c1_data_i;
    assign dma_strb_o = (state == S_C0) ? c0_strb_i : c1_strb_i;

    assign c0_data_ready_o = (state == S_C0) && dma_data_ready_i;
    assign c1_data_ready_o = (state == S_C1) && dma_data_ready_i;

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