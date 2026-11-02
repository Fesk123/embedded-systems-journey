`timescale 1ns/1ps


// GPU Bilinear Texture Filter

// Interpolates four neighbouring RGBA texels using 8-bit fractional weights.
// Texels are expected in {A, R, G, B} order.

module gpu_texture_filter (
    input [31:0] texel00_i,
    input [31:0] texel10_i,
    input [31:0] texel01_i,
    input [31:0] texel11_i,
    input [7:0] fraction_x_i,
    input [7:0] fraction_y_i,
    output reg [31:0] filtered_o
);

    integer channel;
    reg [15:0] top_product0;
    reg [15:0] top_product1;
    reg [15:0] bottom_product0;
    reg [15:0] bottom_product1;
    reg [15:0] final_product0;
    reg [15:0] final_product1;

    function [7:0] divide_255_round;
        input [16:0] value;
        reg [17:0] temp;

        begin
            temp = {1'b0, value} + 18'd127;
            temp = temp + (temp >> 8);
            divide_255_round = temp[15:8];
        end
        
    endfunction

    reg [7:0] p00;
    reg [7:0] p10;
    reg [7:0] p01;
    reg [7:0] p11;
    reg [16:0] top_sum;
    reg [16:0] bottom_sum;
    reg [8:0] top_value;
    reg [8:0] bottom_value;
    reg [16:0] final_sum;

    always @* begin
        filtered_o = 32'd0;
        p00 = 8'd0;
        p10 = 8'd0;
        p01 = 8'd0;
        p11 = 8'd0;
        top_sum = 17'd0;
        bottom_sum = 17'd0;
        top_value = 9'd0;
        bottom_value = 9'd0;
        final_sum = 17'd0;
        top_product0 = 16'd0;
        top_product1 = 16'd0;
        bottom_product0 = 16'd0;
        bottom_product1 = 16'd0;
        final_product0 = 16'd0;
        final_product1 = 16'd0;

        for (channel = 0; channel < 4; channel = channel + 1) begin
            p00 = texel00_i[channel*8 +: 8];
            p10 = texel10_i[channel*8 +: 8];
            p01 = texel01_i[channel*8 +: 8];
            p11 = texel11_i[channel*8 +: 8];

            top_product0 = {8'd0, p00} * {8'd0, (8'd255 - fraction_x_i)};
            top_product1 = {8'd0, p10} * {8'd0, fraction_x_i};
            bottom_product0 = {8'd0, p01} * {8'd0, (8'd255 - fraction_x_i)};
            bottom_product1 = {8'd0, p11} * {8'd0, fraction_x_i};
            top_sum = {1'b0, top_product0} + {1'b0, top_product1};
            bottom_sum = {1'b0, bottom_product0} + {1'b0, bottom_product1};
            top_value = {1'b0, divide_255_round(top_sum)};
            bottom_value = {1'b0, divide_255_round(bottom_sum)};

            final_product0 = {7'd0, top_value} * {8'd0, (8'd255 - fraction_y_i)};
            final_product1 = {7'd0, bottom_value} * {8'd0, fraction_y_i};
            final_sum = {1'b0, final_product0} + {1'b0, final_product1};
            filtered_o[channel*8 +: 8] = divide_255_round(final_sum);
        end
    end

endmodule