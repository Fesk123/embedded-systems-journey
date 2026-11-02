`timescale 1ns/1ps


// GPU Wishbone Registers

// 32/64-bit Wishbone control register bank.
// Commands are pushed into the GPU command queue when GPU_CMD is written.

module gpu_registers #(
    parameter integer XLEN = 64,
    parameter integer CMD_WIDTH = XLEN + 196,
    parameter integer LANES = 1
)(
    input clk_i,
    input rst_i,

    input [XLEN-1:0] wb_adr_i,
    input [XLEN-1:0] wb_dat_i,
    input [XLEN/8-1:0] wb_sel_i,
    input wb_cyc_i,
    input wb_stb_i,
    input wb_we_i,
    output reg [XLEN-1:0] wb_dat_o,
    output reg wb_ack_o,
    output reg wb_err_o,

    input engine_busy_i,
    input engine_done_i,
    input engine_error_i,

    output reg cmd_push_o,
    output [CMD_WIDTH-1:0] cmd_payload_o,
    input cmd_ready_i,

    output irq_o,
    output reg [31:0] fb_width_o,
    output reg [31:0] fb_height_o,
    output reg [31:0] fb_stride_o,
    output [XLEN-1:0] fb_base_o,
    output reg [31:0] fill_color_o,
    output reg [15:0] rect_x_o,
    output reg [15:0] rect_y_o,
    output reg [15:0] rect_width_o,
    output reg [15:0] rect_height_o
);

    localparam [11:0] WB_STATUS = 12'h008;
    localparam [11:0] WB_FB_BASE = 12'h010;
    localparam [11:0] WB_FB_STRIDE = 12'h018;
    localparam [11:0] WB_FB_WIDTH = 12'h020;
    localparam [11:0] WB_FB_HEIGHT = 12'h028;
    localparam [11:0] WB_COLOR = 12'h030;
    localparam [11:0] WB_RECT_XY = 12'h038;
    localparam [11:0] WB_RECT_WH = 12'h040;
    localparam [11:0] WB_CMD = 12'h048;
    localparam [11:0] WB_IRQ_ENABLE = 12'h050;
    localparam [11:0] WB_IRQ_STATUS = 12'h058;
    localparam [11:0] WB_VERSION = 12'h060;
    localparam [11:0] WB_CAPS = 12'h068;

    reg [XLEN-1:0] fb_base;
    reg [1:0] irq_enable;
    reg [1:0] irq_status;
    reg wb_seen;

    reg [XLEN-1:0] read_data;
    reg [XLEN-1:0] caps_data;

    assign fb_base_o = fb_base;
    assign irq_o = |(irq_enable & irq_status);

    assign cmd_payload_o = {
        fb_base,
        fb_stride_o,
        fb_width_o,
        fb_height_o,
        fill_color_o,
        rect_x_o,
        rect_y_o,
        rect_width_o,
        rect_height_o,
        4'd1
    };

    function [XLEN-1:0] merge_bytes;
        input [XLEN-1:0] old_value;
        input [XLEN-1:0] new_value;
        input [XLEN/8-1:0] byte_select;
        integer i;
        begin
            merge_bytes = old_value;
            for (i = 0; i < XLEN/8; i = i + 1) begin
                if (byte_select[i])
                    merge_bytes[i*8 +: 8] = new_value[i*8 +: 8];
            end
        end
    endfunction

    always @* begin
        read_data = {XLEN{1'b0}};
        caps_data = {XLEN{1'b0}};
        caps_data[7:0] = 8'd1;
        caps_data[15:8] = 8'd16;
        caps_data[23:16] = LANES;
        caps_data[31:24] = 8'd2;

        case (wb_adr_i[11:0])
            WB_STATUS: begin
                read_data[0] = engine_busy_i;
                read_data[1] = !cmd_ready_i;
                read_data[2] = irq_status[0];
                read_data[3] = irq_status[1];
            end
            WB_FB_BASE: read_data = fb_base;
            WB_FB_STRIDE: read_data = {{(XLEN-32){1'b0}}, fb_stride_o};
            WB_FB_WIDTH: read_data = {{(XLEN-32){1'b0}}, fb_width_o};
            WB_FB_HEIGHT: read_data = {{(XLEN-32){1'b0}}, fb_height_o};
            WB_COLOR: read_data = {{(XLEN-32){1'b0}}, fill_color_o};
            WB_RECT_XY: read_data = {{(XLEN-32){1'b0}}, rect_y_o, rect_x_o};
            WB_RECT_WH: read_data = {{(XLEN-32){1'b0}}, rect_height_o, rect_width_o};
            WB_IRQ_ENABLE: read_data[1:0] = irq_enable;
            WB_IRQ_STATUS: read_data[1:0] = irq_status;
            WB_VERSION: read_data[31:0] = 32'h47505501;
            WB_CAPS: read_data = caps_data;
            default: read_data = {XLEN{1'b0}};
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_dat_o <= {XLEN{1'b0}};
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            wb_seen <= 1'b0;
            fb_base <= {XLEN{1'b0}};
            fb_stride_o <= 32'd0;
            fb_width_o <= 32'd0;
            fb_height_o <= 32'd0;
            fill_color_o <= 32'd0;
            rect_x_o <= 16'd0;
            rect_y_o <= 16'd0;
            rect_width_o <= 16'd0;
            rect_height_o <= 16'd0;
            irq_enable <= 2'b00;
            irq_status <= 2'b00;
            cmd_push_o <= 1'b0;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            cmd_push_o <= 1'b0;

            if (!wb_cyc_i || !wb_stb_i)
                wb_seen <= 1'b0;

            if (engine_done_i)
                irq_status[0] <= 1'b1;
            if (engine_error_i)
                irq_status[1] <= 1'b1;

            if (wb_cyc_i && wb_stb_i && !wb_seen) begin
                wb_seen <= 1'b1;
                wb_ack_o <= 1'b1;

                if (wb_we_i) begin
                    case (wb_adr_i[11:0])
                        WB_FB_BASE: fb_base <= merge_bytes(fb_base, wb_dat_i, wb_sel_i);
                        WB_FB_STRIDE: fb_stride_o <= merge_bytes({{(XLEN-32){1'b0}}, fb_stride_o}, wb_dat_i, wb_sel_i);
                        WB_FB_WIDTH: fb_width_o <= merge_bytes({{(XLEN-32){1'b0}}, fb_width_o}, wb_dat_i, wb_sel_i);
                        WB_FB_HEIGHT: fb_height_o <= merge_bytes({{(XLEN-32){1'b0}}, fb_height_o}, wb_dat_i, wb_sel_i);
                        WB_COLOR: fill_color_o <= merge_bytes({{(XLEN-32){1'b0}}, fill_color_o}, wb_dat_i, wb_sel_i);
                        WB_RECT_XY: begin
                            rect_x_o <= merge_bytes({{(XLEN-32){1'b0}}, rect_y_o, rect_x_o}, wb_dat_i, wb_sel_i);
                            rect_y_o <= merge_bytes({{(XLEN-32){1'b0}}, rect_y_o, rect_x_o}, wb_dat_i, wb_sel_i) >> 16;
                        end
                        WB_RECT_WH: begin
                            rect_width_o <= merge_bytes({{(XLEN-32){1'b0}}, rect_height_o, rect_width_o}, wb_dat_i, wb_sel_i);
                            rect_height_o <= merge_bytes({{(XLEN-32){1'b0}}, rect_height_o, rect_width_o}, wb_dat_i, wb_sel_i) >> 16;
                        end
                        WB_CMD: begin
                            if (wb_sel_i[0] && wb_dat_i[0]) begin
                                if (wb_dat_i[3:0] != 4'd1)
                                    wb_err_o <= 1'b1;
                                else if (cmd_ready_i)
                                    cmd_push_o <= 1'b1;
                                else
                                    wb_err_o <= 1'b1;
                            end
                        end
                        WB_IRQ_ENABLE: irq_enable <= merge_bytes({{(XLEN-2){1'b0}}, irq_enable}, wb_dat_i, wb_sel_i);
                        WB_IRQ_STATUS: irq_status <= irq_status & ~wb_dat_i[1:0];
                        default: wb_err_o <= 1'b1;
                    endcase
                end else begin
                    wb_dat_o <= read_data;
                    case (wb_adr_i[11:0])
                        WB_STATUS, WB_FB_BASE, WB_FB_STRIDE, WB_FB_WIDTH,
                        WB_FB_HEIGHT, WB_COLOR, WB_RECT_XY, WB_RECT_WH,
                        WB_IRQ_ENABLE, WB_IRQ_STATUS, WB_VERSION, WB_CAPS: begin end
                        default: wb_err_o <= 1'b1;
                    endcase
                end
            end
        end
    end

endmodule