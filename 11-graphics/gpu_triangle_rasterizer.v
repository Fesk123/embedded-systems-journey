`timescale 1ns/1ps


// GPU Triangle Rasterizer

// Bounding-box triangle rasterizer with parallel pixel lanes.
// Coordinates are signed integer screen coordinates.
// LANES can be increased to 2, 4, 8, and so on without changing the interface.
// Each accepted beat presents LANES adjacent candidate pixels and a coverage mask.

module gpu_triangle_rasterizer #(
    parameter integer XLEN = 64,
    parameter integer LANES = 1,
    parameter integer COORD_WIDTH = 16
)(
    input clk_i,
    input rst_i,

    input start_i,
    output start_ready_o,
    input signed [15:0] x0_i,
    input signed [15:0] y0_i,
    input signed [15:0] x1_i,
    input signed [15:0] y1_i,
    input signed [15:0] x2_i,
    input signed [15:0] y2_i,
    input [15:0] framebuffer_width_i,
    input [15:0] framebuffer_height_i,

    output out_valid_o,
    input out_ready_i,
    output [LANES-1:0] lane_mask_o,
    output [LANES*COORD_WIDTH-1:0] lane_x_o,
    output [LANES*COORD_WIDTH-1:0] lane_y_o,

    output reg busy_o,
    output reg done_o,
    output reg error_o
);

    reg signed [15:0] v0_x;
    reg signed [15:0] v0_y;
    reg signed [15:0] v1_x;
    reg signed [15:0] v1_y;
    reg signed [15:0] v2_x;
    reg signed [15:0] v2_y;

    reg [15:0] min_x;
    reg [15:0] max_x;
    reg [15:0] min_y;
    reg [15:0] max_y;
    reg [15:0] scan_x;
    reg [15:0] scan_y;
    reg area_positive;

    wire signed [31:0] x_min_01 = ($signed(x0_i) < $signed(x1_i)) ? $signed(x0_i) : $signed(x1_i);
    wire signed [31:0] x_min_all = (x_min_01 < $signed(x2_i)) ? x_min_01 : $signed(x2_i);
    wire signed [31:0] x_max_01 = ($signed(x0_i) > $signed(x1_i)) ? $signed(x0_i) : $signed(x1_i);
    wire signed [31:0] x_max_all = (x_max_01 > $signed(x2_i)) ? x_max_01 : $signed(x2_i);
    wire signed [31:0] y_min_01 = ($signed(y0_i) < $signed(y1_i)) ? $signed(y0_i) : $signed(y1_i);
    wire signed [31:0] y_min_all = (y_min_01 < $signed(y2_i)) ? y_min_01 : $signed(y2_i);
    wire signed [31:0] y_max_01 = ($signed(y0_i) > $signed(y1_i)) ? $signed(y0_i) : $signed(y1_i);
    wire signed [31:0] y_max_all = (y_max_01 > $signed(y2_i)) ? y_max_01 : $signed(y2_i);

    wire [15:0] clipped_min_x = (x_min_all < 0) ? 16'd0 : x_min_all[15:0];
    wire [15:0] clipped_min_y = (y_min_all < 0) ? 16'd0 : y_min_all[15:0];
    wire [15:0] clipped_max_x = (x_max_all >= $signed({16'd0, framebuffer_width_i})) ? framebuffer_width_i - 1'b1 : x_max_all[15:0];
    wire [15:0] clipped_max_y = (y_max_all >= $signed({16'd0, framebuffer_height_i})) ? framebuffer_height_i - 1'b1 : y_max_all[15:0];

    reg [LANES-1:0] lane_mask;
    reg [LANES*COORD_WIDTH-1:0] lane_x;
    reg [LANES*COORD_WIDTH-1:0] lane_y;

    integer lane;
    reg signed [31:0] candidate_x;
    reg signed [31:0] candidate_y;
    reg signed [63:0] edge0;
    reg signed [63:0] edge1;
    reg signed [63:0] edge2;

    function signed [63:0] edge_function;
        input signed [31:0] ax;
        input signed [31:0] ay;
        input signed [31:0] bx;
        input signed [31:0] by;
        input signed [31:0] px;
        input signed [31:0] py;
        reg signed [63:0] dx1;
        reg signed [63:0] dy1;
        reg signed [63:0] dx2;
        reg signed [63:0] dy2;
        begin
            dx1 = px - ax;
            dy1 = by - ay;
            dx2 = py - ay;
            dy2 = bx - ax;
            edge_function = (dx1 * dy1) - (dx2 * dy2);
        end
    endfunction

    function signed [63:0] triangle_area;
        input signed [15:0] ax;
        input signed [15:0] ay;
        input signed [15:0] bx;
        input signed [15:0] by;
        input signed [15:0] cx;
        input signed [15:0] cy;
        reg signed [31:0] ax32;
        reg signed [31:0] ay32;
        reg signed [31:0] bx32;
        reg signed [31:0] by32;
        reg signed [31:0] cx32;
        reg signed [31:0] cy32;
        begin
            ax32 = ax;
            ay32 = ay;
            bx32 = bx;
            by32 = by;
            cx32 = cx;
            cy32 = cy;
            triangle_area = edge_function(ax32, ay32, bx32, by32, cx32, cy32);
        end
    endfunction

    wire signed [63:0] start_area = triangle_area(x0_i, y0_i, x1_i, y1_i, x2_i, y2_i);

    assign start_ready_o = !busy_o;
    assign out_valid_o = busy_o;
    assign lane_mask_o = lane_mask;
    assign lane_x_o = lane_x;
    assign lane_y_o = lane_y;

    always @* begin
        lane_mask = {LANES{1'b0}};
        lane_x = {(LANES*COORD_WIDTH){1'b0}};
        lane_y = {(LANES*COORD_WIDTH){1'b0}};

        for (lane = 0; lane < LANES; lane = lane + 1) begin
            candidate_x = scan_x + lane;
            candidate_y = scan_y;

            lane_x[lane*COORD_WIDTH +: COORD_WIDTH] = candidate_x[COORD_WIDTH-1:0];
            lane_y[lane*COORD_WIDTH +: COORD_WIDTH] = candidate_y[COORD_WIDTH-1:0];

            edge0 = edge_function(v0_x, v0_y, v1_x, v1_y, candidate_x, candidate_y);
            edge1 = edge_function(v1_x, v1_y, v2_x, v2_y, candidate_x, candidate_y);
            edge2 = edge_function(v2_x, v2_y, v0_x, v0_y, candidate_x, candidate_y);

            if (busy_o && (candidate_x <= max_x) && ((area_positive && (edge0 >= 0) && (edge1 >= 0) && (edge2 >= 0)) ||(!area_positive && (edge0 <= 0) && (edge1 <= 0) && (edge2 <= 0))))
                lane_mask[lane] = 1'b1;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            v0_x <= 16'sd0;
            v0_y <= 16'sd0;
            v1_x <= 16'sd0;
            v1_y <= 16'sd0;
            v2_x <= 16'sd0;
            v2_y <= 16'sd0;
            min_x <= 16'd0;
            max_x <= 16'd0;
            min_y <= 16'd0;
            max_y <= 16'd0;
            scan_x <= 16'd0;
            scan_y <= 16'd0;
            area_positive <= 1'b1;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;

            if (start_i && start_ready_o) begin
                if ((framebuffer_width_i == 0) || (framebuffer_height_i == 0) || (start_area == 0)) begin
                    error_o <= (start_area == 0);
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                end else if ((x_max_all < 0) || (y_max_all < 0) || (x_min_all >= $signed({16'd0, framebuffer_width_i})) || (y_min_all >= $signed({16'd0, framebuffer_height_i})) || (clipped_max_x < clipped_min_x) || (clipped_max_y < clipped_min_y)) begin
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                end else begin
                    v0_x <= x0_i;
                    v0_y <= y0_i;
                    v1_x <= x1_i;
                    v1_y <= y1_i;
                    v2_x <= x2_i;
                    v2_y <= y2_i;
                    min_x <= clipped_min_x;
                    max_x <= clipped_max_x;
                    min_y <= clipped_min_y;
                    max_y <= clipped_max_y;
                    scan_x <= clipped_min_x;
                    scan_y <= clipped_min_y;
                    area_positive <= (start_area > 0);
                    busy_o <= 1'b1;
                end

            end else if (busy_o && out_ready_i) begin
                if ((scan_x + LANES) > max_x) begin
                    if (scan_y >= max_y) begin
                        busy_o <= 1'b0;
                        done_o <= 1'b1;
                    end else begin
                        scan_x <= min_x;
                        scan_y <= scan_y + 1'b1;
                    end
                end else begin
                    scan_x <= scan_x + LANES;
                end

            end

        end
    end

    

endmodule