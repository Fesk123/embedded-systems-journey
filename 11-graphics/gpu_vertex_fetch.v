`timescale 1ns/1ps


// GPU Vertex Fetch

// Fetches three 24-byte vertices from DDR. Each vertex contains:
// beat 0: signed integer screen-space X and Y (16 bits each)
// beat 1: unsigned 16.16 texture U and V
// beat 2: depth[31:0] and RGBA8888 color[31:0]
// Vertex stride must be 8-byte aligned and at least 24 bytes.

module gpu_vertex_fetch #(
    parameter integer XLEN = 64
)(
    input clk_i,
    input rst_i,
    input start_i,
    input [XLEN-1:0] vertex_base_i,
    input [31:0] vertex_stride_i,
    output rd_req_o,
    output [XLEN-1:0] rd_addr_o,
    output [7:0] rd_beats_o,
    input rd_req_ready_i,
    input rd_valid_i,
    input [63:0] rd_data_i,
    output rd_data_ready_o,
    input rd_done_i,
    input rd_error_i,

    output reg vertex_valid_o,
    input vertex_ready_i,
    output reg signed [15:0] vertex_x_o,
    output reg signed [15:0] vertex_y_o,
    output reg [31:0] vertex_u_o,
    output reg [31:0] vertex_v_o,
    output reg [31:0] vertex_depth_o,
    output reg [31:0] vertex_color_o,

    output reg busy_o,
    output reg done_o,
    output reg error_o
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_REQ = 3'd1;
    localparam [2:0] S_WAIT = 3'd2;
    localparam [2:0] S_OUT = 3'd3;

    reg [2:0] state;
    reg [XLEN-1:0] vertex_base;
    reg [31:0] vertex_stride;
    reg [1:0] vertex_index;
    reg [1:0] beat_index;
    reg [63:0] position_word;
    reg [63:0] texcoord_word;
    reg [63:0] attribute_word;
    reg [2:0] received_beats;

    wire [XLEN-1:0] vertex_offset = vertex_index * vertex_stride;

    assign rd_req_o = (state == S_REQ);
    assign rd_addr_o = vertex_base + vertex_offset;
    assign rd_beats_o = 8'd3;
    assign rd_data_ready_o = (state == S_WAIT);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            vertex_base <= {XLEN{1'b0}};
            vertex_stride <= 32'd0;
            vertex_index <= 2'd0;
            beat_index <= 2'd0;
            received_beats <= 3'd0;
            position_word <= 64'd0;
            texcoord_word <= 64'd0;
            attribute_word <= 64'd0;
            vertex_valid_o <= 1'b0;
            vertex_x_o <= 16'sd0;
            vertex_y_o <= 16'sd0;
            vertex_u_o <= 32'd0;
            vertex_v_o <= 32'd0;
            vertex_depth_o <= 32'd0;
            vertex_color_o <= 32'd0;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_o <= 1'b0;
                    vertex_valid_o <= 1'b0;

                    if (start_i) begin
                        if ((vertex_base_i[2:0] != 3'b000) ||
                            (vertex_stride_i[2:0] != 3'b000) ||
                            (vertex_stride_i < 32'd24)) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;
                        end else begin
                            vertex_base <= vertex_base_i;
                            vertex_stride <= vertex_stride_i;
                            vertex_index <= 2'd0;
                            busy_o <= 1'b1;
                            state <= S_REQ;
                        end
                    end



                end

                S_REQ: begin
                    if (rd_req_o && rd_req_ready_i) begin
                        received_beats <= 3'd0;
                        position_word <= 64'd0;
                        texcoord_word <= 64'd0;
                        attribute_word <= 64'd0;
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (rd_valid_i && rd_data_ready_o) begin
                        case (received_beats)
                            3'd0: position_word <= rd_data_i;
                            3'd1: texcoord_word <= rd_data_i;
                            3'd2: attribute_word <= rd_data_i;
                            default: begin end
                        endcase
                        received_beats <= received_beats + 1'b1;
                    end

                    if (rd_done_i) begin
                        if (rd_error_i || (received_beats != 3'd3)) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;
                            busy_o <= 1'b0;
                            state <= S_IDLE;
                        end else begin
                            vertex_x_o <= $signed(position_word[15:0]);
                            vertex_y_o <= $signed(position_word[31:16]);
                            vertex_u_o <= texcoord_word[31:0];
                            vertex_v_o <= texcoord_word[63:32];
                            vertex_depth_o <= attribute_word[63:32];
                            vertex_color_o <= attribute_word[31:0];
                            vertex_valid_o <= 1'b1;
                            state <= S_OUT;
                        end
                    end
                end

                S_OUT: begin

                    if (vertex_valid_o && vertex_ready_i) begin
                        vertex_valid_o <= 1'b0;
                        if (vertex_index == 2'd2) begin
                            done_o <= 1'b1;
                            busy_o <= 1'b0;
                            state <= S_IDLE;

                        end else begin
                            vertex_index <= vertex_index + 1'b1;
                            state <= S_REQ;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                    busy_o <= 1'b0;
                    vertex_valid_o <= 1'b0;
                end
            endcase

        end

        
    end


endmodule
