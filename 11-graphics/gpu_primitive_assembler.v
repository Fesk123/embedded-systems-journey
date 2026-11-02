`timescale 1ns/1ps


// GPU Primitive Assembler

// Collects three fetched vertices and presents one triangle to the rasterizer.
// The module uses a one-triangle output buffer and ready/valid handshaking.

module gpu_primitive_assembler (
    input clk_i,
    input rst_i,

    input vertex_valid_i,
    output vertex_ready_o,
    input signed [15:0] vertex_x_i,
    input signed [15:0] vertex_y_i,
    input [31:0] vertex_u_i,
    input [31:0] vertex_v_i,
    input [31:0] vertex_depth_i,
    input [31:0] vertex_color_i,

    output reg triangle_valid_o,
    input triangle_ready_i,
    output reg signed [15:0] triangle_x0_o,
    output reg signed [15:0] triangle_y0_o,
    output reg signed [15:0] triangle_x1_o,
    output reg signed [15:0] triangle_y1_o,
    output reg signed [15:0] triangle_x2_o,
    output reg signed [15:0] triangle_y2_o,
    output reg [31:0] triangle_u0_o,
    output reg [31:0] triangle_v0_o,
    output reg [31:0] triangle_u1_o,
    output reg [31:0] triangle_v1_o,
    output reg [31:0] triangle_u2_o,
    output reg [31:0] triangle_v2_o,
    output reg [31:0] triangle_depth0_o,
    output reg [31:0] triangle_depth1_o,
    output reg [31:0] triangle_depth2_o,
    output reg [31:0] triangle_color0_o,
    output reg [31:0] triangle_color1_o,
    output reg [31:0] triangle_color2_o
);

    reg [1:0] vertex_count;

    assign vertex_ready_o = !triangle_valid_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            vertex_count <= 2'd0;
            triangle_valid_o <= 1'b0;
            triangle_x0_o <= 16'sd0;
            triangle_y0_o <= 16'sd0;
            triangle_x1_o <= 16'sd0;
            triangle_y1_o <= 16'sd0;
            triangle_x2_o <= 16'sd0;
            triangle_y2_o <= 16'sd0;
            triangle_u0_o <= 32'd0;
            triangle_v0_o <= 32'd0;
            triangle_u1_o <= 32'd0;
            triangle_v1_o <= 32'd0;
            triangle_u2_o <= 32'd0;
            triangle_v2_o <= 32'd0;
            triangle_depth0_o <= 32'd0;
            triangle_depth1_o <= 32'd0;
            triangle_depth2_o <= 32'd0;
            triangle_color0_o <= 32'd0;
            triangle_color1_o <= 32'd0;
            triangle_color2_o <= 32'd0;
        end else begin
            if (triangle_valid_o && triangle_ready_i) begin
                triangle_valid_o <= 1'b0;
                vertex_count <= 2'd0;
            end else if (vertex_valid_i && vertex_ready_o) begin
                case (vertex_count)
                    2'd0: begin
                        triangle_x0_o <= vertex_x_i;
                        triangle_y0_o <= vertex_y_i;
                        triangle_u0_o <= vertex_u_i;
                        triangle_v0_o <= vertex_v_i;
                        triangle_depth0_o <= vertex_depth_i;
                        triangle_color0_o <= vertex_color_i;
                        vertex_count <= 2'd1;
                    end
                    2'd1: begin
                        triangle_x1_o <= vertex_x_i;
                        triangle_y1_o <= vertex_y_i;
                        triangle_u1_o <= vertex_u_i;
                        triangle_v1_o <= vertex_v_i;
                        triangle_depth1_o <= vertex_depth_i;
                        triangle_color1_o <= vertex_color_i;
                        vertex_count <= 2'd2;
                    end
                    default: begin
                        triangle_x2_o <= vertex_x_i;
                        triangle_y2_o <= vertex_y_i;
                        triangle_u2_o <= vertex_u_i;
                        triangle_v2_o <= vertex_v_i;
                        triangle_depth2_o <= vertex_depth_i;
                        triangle_color2_o <= vertex_color_i;
                        triangle_valid_o <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule