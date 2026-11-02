`timescale 1ns/1ps


// GPU Four-Client Read Arbiter

// Round-robin arbiter for scanout, texture, blitter and fragment/depth reads.
// A burst remains owned by the selected client until DMA completion.

module gpu_read_arbiter4 #(
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

    input c2_req_i,
    input [XLEN-1:0] c2_addr_i,
    input [7:0] c2_beats_i,
    output c2_ready_o,
    output c2_valid_o,
    output [63:0] c2_data_o,
    output c2_last_o,
    input c2_data_ready_i,
    output c2_done_o,
    output c2_error_o,

    input c3_req_i,
    input [XLEN-1:0] c3_addr_i,
    input [7:0] c3_beats_i,
    output c3_ready_o,
    output c3_valid_o,
    output [63:0] c3_data_o,
    output c3_last_o,
    input c3_data_ready_i,
    output c3_done_o,
    output c3_error_o,

    output dma_start_o,
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

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_C0 = 3'd1;
    localparam [2:0] S_C1 = 3'd2;
    localparam [2:0] S_C2 = 3'd3;
    localparam [2:0] S_C3 = 3'd4;

    reg [2:0] state;
    reg [1:0] round_robin;
    reg error_seen;
    reg [1:0] select_client;
    reg select_valid;

    always @* begin
        select_client = round_robin;
        select_valid = 1'b0;

        case (round_robin)
            2'd0: begin
                if (c0_req_i) begin select_client = 2'd0; select_valid = 1'b1; end
                else if (c1_req_i) begin select_client = 2'd1; select_valid = 1'b1; end
                else if (c2_req_i) begin select_client = 2'd2; select_valid = 1'b1; end
                else if (c3_req_i) begin select_client = 2'd3; select_valid = 1'b1; end
            end
            2'd1: begin
                if (c1_req_i) begin select_client = 2'd1; select_valid = 1'b1; end
                else if (c2_req_i) begin select_client = 2'd2; select_valid = 1'b1; end
                else if (c3_req_i) begin select_client = 2'd3; select_valid = 1'b1; end
                else if (c0_req_i) begin select_client = 2'd0; select_valid = 1'b1; end
            end
            2'd2: begin
                if (c2_req_i) begin select_client = 2'd2; select_valid = 1'b1; end
                else if (c3_req_i) begin select_client = 2'd3; select_valid = 1'b1; end
                else if (c0_req_i) begin select_client = 2'd0; select_valid = 1'b1; end
                else if (c1_req_i) begin select_client = 2'd1; select_valid = 1'b1; end
            end
            default: begin
                if (c3_req_i) begin select_client = 2'd3; select_valid = 1'b1; end
                else if (c0_req_i) begin select_client = 2'd0; select_valid = 1'b1; end
                else if (c1_req_i) begin select_client = 2'd1; select_valid = 1'b1; end
                else if (c2_req_i) begin select_client = 2'd2; select_valid = 1'b1; end
            end
        endcase
    end

    assign dma_start_o = (state == S_IDLE) && !dma_busy_i && select_valid;

    assign c0_ready_o = dma_start_o && (select_client == 2'd0);
    assign c1_ready_o = dma_start_o && (select_client == 2'd1);
    assign c2_ready_o = dma_start_o && (select_client == 2'd2);
    assign c3_ready_o = dma_start_o && (select_client == 2'd3);

    assign c0_valid_o = (state == S_C0) && dma_valid_i;
    assign c1_valid_o = (state == S_C1) && dma_valid_i;
    assign c2_valid_o = (state == S_C2) && dma_valid_i;
    assign c3_valid_o = (state == S_C3) && dma_valid_i;

    assign c0_data_o = dma_data_i;
    assign c1_data_o = dma_data_i;
    assign c2_data_o = dma_data_i;
    assign c3_data_o = dma_data_i;
    assign c0_last_o = dma_last_i;
    assign c1_last_o = dma_last_i;
    assign c2_last_o = dma_last_i;
    assign c3_last_o = dma_last_i;

    assign dma_ready_o = (state == S_C0) ? c0_data_ready_i :
                         (state == S_C1) ? c1_data_ready_i :
                         (state == S_C2) ? c2_data_ready_i :
                         (state == S_C3) ? c3_data_ready_i : 1'b0;

    assign c0_done_o = (state == S_C0) && dma_done_i;
    assign c1_done_o = (state == S_C1) && dma_done_i;
    assign c2_done_o = (state == S_C2) && dma_done_i;
    assign c3_done_o = (state == S_C3) && dma_done_i;

    assign c0_error_o = (state == S_C0) && (dma_error_i || (dma_done_i && error_seen));
    assign c1_error_o = (state == S_C1) && (dma_error_i || (dma_done_i && error_seen));
    assign c2_error_o = (state == S_C2) && (dma_error_i || (dma_done_i && error_seen));
    assign c3_error_o = (state == S_C3) && (dma_error_i || (dma_done_i && error_seen));

    always @* begin
        dma_addr_o = {XLEN{1'b0}};
        dma_beats_o = 8'd0;
        case (select_client)
            2'd0: begin dma_addr_o = c0_addr_i; dma_beats_o = c0_beats_i; end
            2'd1: begin dma_addr_o = c1_addr_i; dma_beats_o = c1_beats_i; end
            2'd2: begin dma_addr_o = c2_addr_i; dma_beats_o = c2_beats_i; end
            default: begin dma_addr_o = c3_addr_i; dma_beats_o = c3_beats_i; end
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            round_robin <= 2'd0;
            error_seen <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    error_seen <= 1'b0;
                    if (dma_start_o) begin
                        case (select_client)
                            2'd0: state <= S_C0;
                            2'd1: state <= S_C1;
                            2'd2: state <= S_C2;
                            default: state <= S_C3;
                        endcase
                    end
                end
                S_C0, S_C1, S_C2, S_C3: begin
                    if (dma_error_i)
                        error_seen <= 1'b1;
                    if (dma_done_i) begin
                        round_robin <= round_robin + 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule