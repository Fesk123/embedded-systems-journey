`timescale 1ns/1ps


// GPU Read Client Mux

// Multiplexes two independent read engines (texture cache and vertex fetch)
// onto one read-arbiter client. The selected client owns the full burst.

module gpu_read_client_mux2 #(
    parameter integer XLEN = 64
)(
    input clk_i,
    input rst_i,

    input a_req_i,
    input [XLEN-1:0] a_addr_i,
    input [7:0] a_beats_i,
    output a_ready_o,
    output a_valid_o,
    output [63:0] a_data_o,
    output a_last_o,
    input a_data_ready_i,
    output a_done_o,
    output a_error_o,

    input b_req_i,
    input [XLEN-1:0] b_addr_i,
    input [7:0] b_beats_i,
    output b_ready_o,
    output b_valid_o,
    output [63:0] b_data_o,
    output b_last_o,
    input b_data_ready_i,
    output b_done_o,
    output b_error_o,

    output parent_req_o,
    output [XLEN-1:0] parent_addr_o,
    output [7:0] parent_beats_o,
    input parent_ready_i,
    input parent_valid_i,
    input [63:0] parent_data_i,
    input parent_last_i,
    output parent_data_ready_o,
    input parent_done_i,
    input parent_error_i
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_A = 2'd1;
    localparam [1:0] S_B = 2'd2;

    reg [1:0] state;
    reg round_robin;
    reg choose_b;
    reg request_valid;
    reg error_seen;

    always @* begin
        choose_b = round_robin;
        request_valid = 1'b0;
        if (!round_robin) begin
            if (a_req_i) begin choose_b=1'b0; request_valid=1'b1; end
            else if (b_req_i) begin choose_b=1'b1; request_valid=1'b1; end
        end else begin
            if (b_req_i) begin choose_b=1'b1; request_valid=1'b1; end
            else if (a_req_i) begin choose_b=1'b0; request_valid=1'b1; end
        end
    end

    assign parent_req_o = (state == S_IDLE) && request_valid;
    assign parent_addr_o = choose_b ? b_addr_i : a_addr_i;
    assign parent_beats_o = choose_b ? b_beats_i : a_beats_i;
    assign a_ready_o = parent_req_o && parent_ready_i && !choose_b;
    assign b_ready_o = parent_req_o && parent_ready_i && choose_b;

    assign a_valid_o = (state == S_A) && parent_valid_i;
    assign b_valid_o = (state == S_B) && parent_valid_i;
    assign a_data_o = parent_data_i;
    assign b_data_o = parent_data_i;
    assign a_last_o = parent_last_i;
    assign b_last_o = parent_last_i;
    assign parent_data_ready_o = (state == S_A) ? a_data_ready_i :
                                 (state == S_B) ? b_data_ready_i : 1'b0;
    assign a_done_o = (state == S_A) && parent_done_i;
    assign b_done_o = (state == S_B) && parent_done_i;
    assign a_error_o = (state == S_A) && (parent_error_i || (parent_done_i && error_seen));
    assign b_error_o = (state == S_B) && (parent_error_i || (parent_done_i && error_seen));

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            round_robin <= 1'b0;
            error_seen <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    error_seen <= 1'b0;
                    if (parent_req_o && parent_ready_i) begin
                        if (choose_b)
                            state <= S_B;
                        else
                            state <= S_A;
                    end
                end
                S_A: begin
                    if (parent_error_i)
                        error_seen <= 1'b1;
                    if (parent_done_i) begin
                        state <= S_IDLE;
                        round_robin <= 1'b1;
                    end
                end
                S_B: begin
                    if (parent_error_i)
                        error_seen <= 1'b1;
                    if (parent_done_i) begin
                        state <= S_IDLE;
                        round_robin <= 1'b0;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule