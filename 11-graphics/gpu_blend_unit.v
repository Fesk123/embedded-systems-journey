`timescale 1ns/1ps


// GPU Alpha Blend Unit

// 32-bit RGBA source-over blending for straight-alpha source pixels.
// Pixel format is {A, R, G, B}; destination RGB is expected opaque or
// compatible with the selected SRC_ALPHA / ONE_MINUS_SRC_ALPHA blend mode.

module gpu_blend_unit (
    input [31:0] src_pixel_i,
    input [31:0] dst_pixel_i,
    input enable_i,
    output reg [31:0] result_o
);

    integer channel;

    function [7:0] divide_255_round;
        input [16:0] value;
        reg [17:0] temp;

        begin
            temp = {1'b0, value} + 18'd127;
            temp = temp + (temp >> 8);
            divide_255_round = temp[15:8];
        end

    endfunction

    reg [7:0] src_alpha;
    reg [7:0] src_value;
    reg [7:0] dst_value;
    reg [16:0] blend_sum;
    reg [16:0] alpha_sum;

    always @* begin
        result_o = src_pixel_i;
        src_alpha = src_pixel_i[31:24];
        src_value = 8'd0;
        dst_value = 8'd0;
        blend_sum = 17'd0;
        alpha_sum = 17'd0;

        if (enable_i) begin
            for (channel = 0; channel < 3; channel = channel + 1) begin
                src_value = src_pixel_i[channel*8 +: 8];
                dst_value = dst_pixel_i[channel*8 +: 8];
                blend_sum = ({9'd0, src_value} * {9'd0, src_alpha}) + ({9'd0, dst_value} * {9'd0, (8'd255 - src_alpha)});
                result_o[channel*8 +: 8] = divide_255_round(blend_sum);
            end

            alpha_sum = ({9'd0, src_alpha} * 17'd255) + ({9'd0, dst_pixel_i[31:24]} * {9'd0, (8'd255 - src_alpha)});
            result_o[31:24] = divide_255_round(alpha_sum);
        end
    end

endmodule