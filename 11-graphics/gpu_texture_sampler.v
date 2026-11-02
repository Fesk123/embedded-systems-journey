`timescale 1ns/1ps



// GPU Texture Sampler

// Fetches the four neighboring RGBA8888 texels through gpu_texture_cache and performs bilinear filtering. 
// U and V use unsigned 16.16 fixed point.
// Coordinates are clamped to the edge of the texture.

module gpu_texture_sampler #(
    parameter integer XLEN = 64
)(
    input clk_i,
    input rst_i,
    input start_i,
    input [XLEN-1:0] texture_base_i,
    input [31:0] texture_stride_i,
    input [15:0] texture_width_i,
    input [15:0] texture_height_i,
    input [31:0] u_i,
    input [31:0] v_i,

    output reg busy_o,
    output reg done_o,
    output reg error_o,
    output reg [31:0] sample_color_o,

    output reg cache_req_valid_o,
    input cache_req_ready_i,
    output reg [XLEN-1:0] cache_req_addr_o,
    input cache_resp_valid_i,
    output cache_resp_ready_o,
    input [63:0] cache_resp_data_i,
    input cache_resp_error_i
);

    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_REQ00 = 4'd1;
    localparam [3:0] S_WAIT00 = 4'd2;
    localparam [3:0] S_REQ10 = 4'd3;
    localparam [3:0] S_WAIT10 = 4'd4;
    localparam [3:0] S_REQ01 = 4'd5;
    localparam [3:0] S_WAIT01 = 4'd6;
    localparam [3:0] S_REQ11 = 4'd7;
    localparam [3:0] S_WAIT11 = 4'd8;
    localparam [3:0] S_output = 4'd9;

    reg [3:0] state;
    reg [XLEN-1:0] texture_base;
    reg [31:0] texture_stride;
    reg [15:0] texture_width;
    reg [15:0] texture_height;
    reg [15:0] x0;
    reg [15:0] x1;
    reg [15:0] y0;
    reg [15:0] y1;

    reg [7:0] fraction_x;
    reg [7:0] fraction_y;
    reg [31:0] texel00;
    reg [31:0] texel10;
    reg [31:0] texel01;
    reg [31:0] texel11;

    wire [XLEN-1:0] row0_offset = {{(XLEN-16){1'b0}}, y0} * {{(XLEN-32){1'b0}}, texture_stride};
    wire [XLEN-1:0] row1_offset = {{(XLEN-16){1'b0}}, y1} * {{(XLEN-32){1'b0}}, texture_stride};

    wire [XLEN-1:0] x0_offset = {{(XLEN-15){1'b0}}, x0[15:1]} << 3;
    wire [XLEN-1:0] x1_offset = {{(XLEN-15){1'b0}}, x1[15:1]} << 3;
    wire [XLEN-1:0] addr00 = texture_base + row0_offset + x0_offset;
    wire [XLEN-1:0] addr10 = texture_base + row0_offset + x1_offset;
    wire [XLEN-1:0] addr01 = texture_base + row1_offset + x0_offset;
    wire [XLEN-1:0] addr11 = texture_base + row1_offset + x1_offset;
    wire [31:0] selected_texel = x0[0] ? cache_resp_data_i[63:32] : cache_resp_data_i[31:0];
    wire [31:0] filtered_color;
    assign cache_resp_ready_o = (state == S_WAIT00) || (state == S_WAIT10) || (state == S_WAIT01) || (state == S_WAIT11);

    gpu_texture_filter filter (
        .texel00_i(texel00),
        .texel10_i(texel10),
        .texel01_i(texel01),
        .texel11_i(texel11),
        .fraction_x_i(fraction_x),
        .fraction_y_i(fraction_y),
        .filtered_o(filtered_color)
    );

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            sample_color_o <= 32'd0;
            texture_base <= {XLEN{1'b0}};
            texture_stride <= 32'd0;
            texture_width <= 16'd0;
            texture_height <= 16'd0;
            x0 <= 16'd0;
            x1 <= 16'd0;
            y0 <= 16'd0;
            y1 <= 16'd0;
            fraction_x <= 8'd0;
            fraction_y <= 8'd0;
            texel00 <= 32'd0;
            texel10 <= 32'd0;
            texel01 <= 32'd0;
            texel11 <= 32'd0;
            cache_req_valid_o <= 1'b0;
            cache_req_addr_o <= {XLEN{1'b0}};

        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_o <= 1'b0;
                    cache_req_valid_o <= 1'b0;

                    if (start_i) begin
                        if ((texture_base_i[2:0] != 3'b000) ||
                            (texture_stride_i[2:0] != 3'b000) ||
                            (texture_width_i == 0) || (texture_height_i == 0) ||
                            (texture_stride_i < ({16'd0, texture_width_i} << 2)) ||
                            (u_i[31:16] >= texture_width_i) ||
                            (v_i[31:16] >= texture_height_i)) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;

                        end else begin

                            texture_base <= texture_base_i;
                            texture_stride <= texture_stride_i;
                            texture_width <= texture_width_i;
                            texture_height <= texture_height_i;
                            x0 <= u_i[31:16];
                            x1 <= ((u_i[31:16] + 1'b1) >= texture_width_i) ? texture_width_i - 1'b1 : u_i[31:16] + 1'b1;
                            y0 <= v_i[31:16];
                            y1 <= ((v_i[31:16] + 1'b1) >= texture_height_i) ? texture_height_i - 1'b1 : v_i[31:16] + 1'b1;
                            fraction_x <= u_i[15:8];
                            fraction_y <= v_i[15:8];
                            busy_o <= 1'b1;
                            state <= S_REQ00;
                        end
                    end
                end

                S_REQ00: begin
                    cache_req_valid_o <= 1'b1;
                    cache_req_addr_o <= addr00;
                    if (cache_req_valid_o && cache_req_ready_i) begin
                        cache_req_valid_o <= 1'b0;
                        state <= S_WAIT00;
                    end
                end

                S_WAIT00: begin
                    if (cache_resp_valid_i && cache_resp_ready_o) begin
                        if (cache_resp_error_i) begin 
                            error_o <= 1'b1; done_o <= 1'b1; busy_o <= 1'b0; state <= S_IDLE; end
                        else begin 
                            texel00 <= x0[0] ? cache_resp_data_i[63:32] : cache_resp_data_i[31:0]; state <= S_REQ10; end
                    end
                end

                S_REQ10: begin
                    cache_req_valid_o <= 1'b1;
                    cache_req_addr_o <= addr10;

                    if (cache_req_valid_o && cache_req_ready_i) begin
                        cache_req_valid_o <= 1'b0;
                        state <= S_WAIT10;
                    end
                end

                S_WAIT10: begin
                    if (cache_resp_valid_i && cache_resp_ready_o) begin
                        if (cache_resp_error_i) begin error_o <= 1'b1; done_o <= 1'b1; busy_o <= 1'b0; state <= S_IDLE; end
                        else begin texel10 <= x1[0] ? cache_resp_data_i[63:32] : cache_resp_data_i[31:0]; state <= S_REQ01; end
                    end
                end

                S_REQ01: begin
                    cache_req_valid_o <= 1'b1;
                    cache_req_addr_o <= addr01;
                    if (cache_req_valid_o && cache_req_ready_i) begin
                        cache_req_valid_o <= 1'b0;
                        state <= S_WAIT01;
                    end
                end

                S_WAIT01: begin
                    if (cache_resp_valid_i && cache_resp_ready_o) begin
                        if (cache_resp_error_i) begin error_o <= 1'b1; done_o <= 1'b1; busy_o <= 1'b0; state <= S_IDLE; end
                        else begin texel01 <= x0[0] ? cache_resp_data_i[63:32] : cache_resp_data_i[31:0]; state <= S_REQ11; end
                    end
                end

                S_REQ11: begin
                    cache_req_valid_o <= 1'b1;
                    cache_req_addr_o <= addr11;
                    if (cache_req_valid_o && cache_req_ready_i) begin
                        cache_req_valid_o <= 1'b0;
                        state <= S_WAIT11;
                    end
                end

                S_WAIT11: begin
                    if (cache_resp_valid_i && cache_resp_ready_o) begin
                        if (cache_resp_error_i) begin error_o <= 1'b1; done_o <= 1'b1; busy_o <= 1'b0; state <= S_IDLE; end
                        else begin texel11 <= x1[0] ? cache_resp_data_i[63:32] : cache_resp_data_i[31:0]; state <= S_OUTPUT; end
                    end
                end

                S_OUTPUT: begin
                    sample_color_o <= filtered_color;
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy_o <= 1'b0;
                    cache_req_valid_o <= 1'b0;
                end

            endcase

        end


    end

endmodule