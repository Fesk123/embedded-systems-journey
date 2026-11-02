`timescale 1ns/1ps


// GPU Three-Client Auxiliary Write Mux

// Shares gpu.v auxiliary write client between the blitter, fast fragment
// writer and depth/blend fragment backend. A burst remains owned until B.

module gpu_write_client_mux3 #(
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

    input c2_start_i,
    input [XLEN-1:0] c2_addr_i,
    input [7:0] c2_beats_i,
    output c2_ready_o,
    input c2_valid_i,
    input [63:0] c2_data_i,
    input [7:0] c2_strb_i,
    output c2_data_ready_o,
    output c2_done_o,
    output c2_error_o,

    output aux_start_o,
    output reg [XLEN-1:0] aux_addr_o,
    output reg [7:0] aux_beats_o,
    input aux_ready_i,
    output aux_valid_o,
    output reg [63:0] aux_data_o,
    output reg [7:0] aux_strb_o,
    input aux_data_ready_i,
    input aux_done_i,
    input aux_error_i
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_C0 = 2'd1;
    localparam [1:0] S_C1 = 2'd2;
    localparam [1:0] S_C2 = 2'd3;

    reg [1:0] state;
    reg [1:0] round_robin;
    reg [1:0] selected;
    reg selected_valid;

    always @* begin
        selected = round_robin;
        selected_valid = 1'b0;

        case (round_robin)
            2'd0: begin
                if (c0_start_i) begin selected=2'd0; selected_valid=1'b1; end
                else if (c1_start_i) begin selected=2'd1; selected_valid=1'b1; end
                else if (c2_start_i) begin selected=2'd2; selected_valid=1'b1; end
            end
            2'd1: begin
                if (c1_start_i) begin selected=2'd1; selected_valid=1'b1; end
                else if (c2_start_i) begin selected=2'd2; selected_valid=1'b1; end
                else if (c0_start_i) begin selected=2'd0; selected_valid=1'b1; end
            end
            default: begin
                if (c2_start_i) begin selected=2'd2; selected_valid=1'b1; end
                else if (c0_start_i) begin selected=2'd0; selected_valid=1'b1; end
                else if (c1_start_i) begin selected=2'd1; selected_valid=1'b1; end
            end
        endcase
    end

    assign aux_start_o = (state == S_IDLE) && selected_valid;
    assign c0_ready_o = aux_start_o && aux_ready_i && (selected == 2'd0);
    assign c1_ready_o = aux_start_o && aux_ready_i && (selected == 2'd1);
    assign c2_ready_o = aux_start_o && aux_ready_i && (selected == 2'd2);

    assign aux_valid_o = (state == S_C0) ? c0_valid_i : (state == S_C1) ? c1_valid_i : (state == S_C2) ? c2_valid_i : 1'b0;
    assign c0_data_ready_o = (state == S_C0) && aux_data_ready_i;
    assign c1_data_ready_o = (state == S_C1) && aux_data_ready_i;
    assign c2_data_ready_o = (state == S_C2) && aux_data_ready_i;

    assign c0_done_o = (state == S_C0) && aux_done_i;
    assign c1_done_o = (state == S_C1) && aux_done_i;
    assign c2_done_o = (state == S_C2) && aux_done_i;
    assign c0_error_o = (state == S_C0) && aux_error_i;
    assign c1_error_o = (state == S_C1) && aux_error_i;
    assign c2_error_o = (state == S_C2) && aux_error_i;

    always @* begin

        aux_addr_o = {XLEN{1'b0}};
        aux_beats_o = 8'd0;
        aux_data_o = 64'd0;
        aux_strb_o = 8'd0;

        case (state)
            S_IDLE: begin
                case (selected)
                    2'd0: begin aux_addr_o=c0_addr_i; aux_beats_o=c0_beats_i; end
                    2'd1: begin aux_addr_o=c1_addr_i; aux_beats_o=c1_beats_i; end
                    default: begin aux_addr_o=c2_addr_i; aux_beats_o=c2_beats_i; end
                endcase

            end

            S_C0: begin aux_addr_o=c0_addr_i; aux_beats_o=c0_beats_i; aux_data_o=c0_data_i; aux_strb_o=c0_strb_i; end
            S_C1: begin aux_addr_o=c1_addr_i; aux_beats_o=c1_beats_i; aux_data_o=c1_data_i; aux_strb_o=c1_strb_i; end
            S_C2: begin aux_addr_o=c2_addr_i; aux_beats_o=c2_beats_i; aux_data_o=c2_data_i; aux_strb_o=c2_strb_i; end
            default: begin end

        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            round_robin <= 2'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (aux_start_o && aux_ready_i) begin
                        case (selected)
                            2'd0: state <= S_C0;
                            2'd1: state <= S_C1;
                            default: state <= S_C2;
                        endcase
                    end
                end
                S_C0: if (aux_done_i) begin state <= S_IDLE; round_robin <= 2'd1; end
                S_C1: if (aux_done_i) begin state <= S_IDLE; round_robin <= 2'd2; end
                S_C2: if (aux_done_i) begin state <= S_IDLE; round_robin <= 2'd0; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule