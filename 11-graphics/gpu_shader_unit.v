`timescale 1ns/1ps


// GPU Shader Unit

// Small lane-parallel fragment shader ALU.
// This is a compact shader instruction subset, not a complete GLSL processor.
// The CPU-side graphics driver/compiler must translate supported operations.

module gpu_shader_unit #(
    parameter integer XLEN = 64,
    parameter integer LANES = 1
)(
    input clk_i,
    input rst_i,

    input in_valid_i,
    output in_ready_o,
    input [LANES-1:0] lane_mask_i,
    input [3:0] opcode_i,
    input [31:0] uniform_color_i,
    input [LANES*32-1:0] vertex_color_i,
    input [LANES*32-1:0] texture_color_i,

    output reg out_valid_o,
    input out_ready_i,
    output reg [LANES-1:0] out_mask_o,
    output reg [LANES*32-1:0] out_color_o
);

    localparam [3:0] SHADER_VERTEX = 4'd0;
    localparam [3:0] SHADER_TEXTURE = 4'd1;
    localparam [3:0] SHADER_MODULATE = 4'd2;
    localparam [3:0] SHADER_ADD = 4'd3;
    localparam [3:0] SHADER_SOLID = 4'd4;
    localparam [3:0] SHADER_INVERT = 4'd5;
    localparam [3:0] SHADER_ALPHA = 4'd6;

    reg [LANES*32-1:0] next_color;
    integer lane;

    function [7:0] divide_255_round;
        input [16:0] value;
        reg [17:0] temp;
        begin
            temp = {1'b0, value} + 18'd127;
            temp = temp + (temp >> 8);
            divide_255_round = temp[15:8];
        end
    endfunction
    reg [31:0] vertex_color;
    reg [31:0] texture_color;
    reg [31:0] result_color;
    reg [15:0] channel_product;
    integer channel;
    reg [7:0] source_channel;
    reg [7:0] texture_channel;
    reg [7:0] result_channel;

    assign in_ready_o = !out_valid_o || out_ready_i;

    always @* begin
        next_color = {(LANES*32){1'b0}};
        vertex_color = 32'd0;
        texture_color = 32'd0;
        result_color = 32'd0;
        channel_product = 16'd0;
        source_channel = 8'd0;
        texture_channel = 8'd0;
        result_channel = 8'd0;

        for (lane = 0; lane < LANES; lane = lane + 1) begin
            vertex_color = vertex_color_i[lane*32 +: 32];
            texture_color = texture_color_i[lane*32 +: 32];

            case (opcode_i)
                SHADER_VERTEX: result_color = vertex_color;
                SHADER_TEXTURE: result_color = texture_color;
                SHADER_MODULATE: begin
                    result_color = 32'd0;
                    for (channel = 0; channel < 4; channel = channel + 1) begin
                        source_channel = vertex_color[channel*8 +: 8];
                        texture_channel = texture_color[channel*8 +: 8];
                        channel_product = {8'd0, source_channel} * {8'd0, texture_channel};
                        result_channel = divide_255_round({1'b0, channel_product});
                        result_color[channel*8 +: 8] = result_channel;
                    end
                end
                SHADER_ADD: begin
                    result_color[7:0] = ({1'b0, vertex_color[7:0]}   + {1'b0, texture_color[7:0]}   > 9'd255) ? 8'hFF : vertex_color[7:0] + texture_color[7:0];
                    result_color[15:8] = ({1'b0, vertex_color[15:8]}  + {1'b0, texture_color[15:8]}  > 9'd255) ? 8'hFF : vertex_color[15:8] + texture_color[15:8];
                    result_color[23:16] = ({1'b0, vertex_color[23:16]} + {1'b0, texture_color[23:16]} > 9'd255) ? 8'hFF : vertex_color[23:16] + texture_color[23:16];
                    result_color[31:24] = ({1'b0, vertex_color[31:24]} + {1'b0, texture_color[31:24]} > 9'd255) ? 8'hFF : vertex_color[31:24] + texture_color[31:24];
                end
                SHADER_SOLID: result_color = uniform_color_i;
                SHADER_INVERT: result_color = ~vertex_color;
                SHADER_ALPHA: begin
                    result_color = vertex_color;
                    for (channel = 0; channel < 3; channel = channel + 1) begin
                        channel_product = {8'd0, vertex_color[channel*8 +: 8]} * {8'd0, uniform_color_i[31:24]};
                        result_color[channel*8 +: 8] = divide_255_round({1'b0, channel_product});
                    end
                end
                default: result_color = vertex_color;
            endcase

            next_color[lane*32 +: 32] = lane_mask_i[lane] ? result_color : 32'd0;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            out_valid_o <= 1'b0;
            out_mask_o <= {LANES{1'b0}};
            out_color_o <= {(LANES*32){1'b0}};
        end else if (in_ready_o) begin
            out_valid_o <= in_valid_i;
            if (in_valid_i) begin
                out_mask_o <= lane_mask_i;
                out_color_o <= next_color;
            end
        end
    end

endmodule