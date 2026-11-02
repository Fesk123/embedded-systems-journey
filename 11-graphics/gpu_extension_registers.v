`timescale 1ns/1ps


// GPU Extension Registers

// Wishbone register bank for triangle setup, depth/blend and framebuffer blit.
// The block is mapped at GPU base + 0x100. The original gpu_registers.v
// remains mapped at GPU base + 0x000 for compatibility.

module gpu_extension_registers #(
    parameter integer XLEN = 64
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

    input triangle_busy_i,
    input triangle_done_i,
    input triangle_error_i,
    input blit_busy_i,
    input blit_done_i,
    input blit_error_i,

    output reg scanout_start_o,
    output reg triangle_start_o,
    output reg signed [15:0] triangle_x0_o,
    output reg signed [15:0] triangle_y0_o,
    output reg signed [15:0] triangle_x1_o,
    output reg signed [15:0] triangle_y1_o,
    output reg signed [15:0] triangle_x2_o,
    output reg signed [15:0] triangle_y2_o,
    output reg [31:0] triangle_color_o,
    output reg [3:0] triangle_shader_opcode_o,
    output reg [31:0] triangle_depth_o,

    output reg [XLEN-1:0] texture_base_o,
    output reg [31:0] texture_stride_o,
    output reg [15:0] texture_width_o,
    output reg [15:0] texture_height_o,
    output reg [31:0] texture_u_o,
    output reg [31:0] texture_v_o,
    output reg [XLEN-1:0] vertex_base_o,
    output reg [31:0] vertex_stride_o,
    output reg triangle_fetch_mode_o,

    output reg [XLEN-1:0] depth_base_o,
    output reg [31:0] depth_stride_o,
    output reg depth_enable_o,
    output reg depth_write_enable_o,
    output reg [2:0] depth_compare_o,
    output reg blend_enable_o,

    output reg blit_start_o,
    output reg [XLEN-1:0] blit_src_base_o,
    output reg [XLEN-1:0] blit_dst_base_o,
    output reg [31:0] blit_src_stride_o,
    output reg [31:0] blit_dst_stride_o,
    output reg [15:0] blit_src_x_o,
    output reg [15:0] blit_src_y_o,
    output reg [15:0] blit_dst_x_o,
    output reg [15:0] blit_dst_y_o,
    output reg [15:0] blit_width_o,
    output reg [15:0] blit_height_o,

    output irq_o
);

    localparam [7:0] REG_STATUS = 8'h00;
    localparam [7:0] REG_DISPLAY_CMD = 8'h08;
    localparam [7:0] REG_TRI_X0Y0 = 8'h10;
    localparam [7:0] REG_TRI_X1Y1 = 8'h18;
    localparam [7:0] REG_TRI_X2Y2 = 8'h20;
    localparam [7:0] REG_TRI_COLOR = 8'h28;
    localparam [7:0] REG_TRI_SHADER = 8'h30;
    localparam [7:0] REG_TRI_DEPTH = 8'h38;
    localparam [7:0] REG_DEPTH_BASE = 8'h40;
    localparam [7:0] REG_DEPTH_STRIDE = 8'h48;
    localparam [7:0] REG_DEPTH_CTRL = 8'h50;
    localparam [7:0] REG_BLIT_SRC_BASE = 8'h58;
    localparam [7:0] REG_BLIT_DST_BASE = 8'h60;
    localparam [7:0] REG_BLIT_SRC_STRIDE = 8'h68;
    localparam [7:0] REG_BLIT_DST_STRIDE = 8'h70;
    localparam [7:0] REG_BLIT_SRC_XY = 8'h78;
    localparam [7:0] REG_BLIT_DST_XY = 8'h80;
    localparam [7:0] REG_BLIT_WH = 8'h88;
    localparam [7:0] REG_BLIT_CMD = 8'h90;
    localparam [7:0] REG_IRQ_ENABLE = 8'h98;
    localparam [7:0] REG_IRQ_STATUS = 8'hA0;
    localparam [7:0] REG_VERSION = 8'hA8;
    localparam [7:0] REG_TRI_CMD = 8'hB0;
    localparam [7:0] REG_TEX_BASE = 8'hB8;
    localparam [7:0] REG_TEX_STRIDE = 8'hC0;
    localparam [7:0] REG_TEX_SIZE = 8'hC8;
    localparam [7:0] REG_TEX_UV = 8'hD0;
    localparam [7:0] REG_TEX_U = 8'hD8;
    localparam [7:0] REG_VERTEX_BASE = 8'hE0;
    localparam [7:0] REG_VERTEX_STRIDE = 8'hE8;

    reg wb_seen;
    reg [1:0] irq_enable;
    reg [1:0] irq_status;
    reg [XLEN-1:0] blit_src_base_reg;
    reg [XLEN-1:0] blit_dst_base_reg;
    reg [XLEN-1:0] depth_base_reg;
    reg [XLEN-1:0] texture_base_reg;
    reg [XLEN-1:0] vertex_base_reg;
    reg [XLEN-1:0] read_data;

    function [XLEN-1:0] merge_bytes;
        input [XLEN-1:0] old_value;
        input [XLEN-1:0] new_value;
        input [XLEN/8-1:0] byte_select;
        integer byte_index;

        begin
            merge_bytes = old_value;
            for (byte_index = 0; byte_index < XLEN/8; byte_index = byte_index + 1) begin
                if (byte_select[byte_index])
                    merge_bytes[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
            end
        end

    endfunction

    assign irq_o = |(irq_enable & irq_status);

    always @* begin
        read_data = {XLEN{1'b0}};
        case (wb_adr_i[7:0])

            REG_STATUS: begin
                read_data[0] = triangle_busy_i;
                read_data[1] = blit_busy_i;
                read_data[2] = irq_status[0];
                read_data[3] = irq_status[1];
            end

            REG_TRI_X0Y0: read_data[31:0] = {triangle_y0_o, triangle_x0_o};
            REG_TRI_X1Y1: read_data[31:0] = {triangle_y1_o, triangle_x1_o};
            REG_TRI_X2Y2: read_data[31:0] = {triangle_y2_o, triangle_x2_o};
            REG_TRI_COLOR: read_data[31:0] = triangle_color_o;
            REG_TRI_SHADER: read_data[3:0] = triangle_shader_opcode_o;
            REG_TRI_DEPTH: read_data[31:0] = triangle_depth_o;
            REG_DEPTH_BASE: read_data = depth_base_reg;
            REG_DEPTH_STRIDE: read_data[31:0] = depth_stride_o;
           
            REG_DEPTH_CTRL: begin
                read_data[0] = depth_enable_o;
                read_data[1] = depth_write_enable_o;
                read_data[4:2] = depth_compare_o;
                read_data[5] = blend_enable_o;
            end
          
            REG_BLIT_SRC_BASE: read_data = blit_src_base_reg;
            REG_BLIT_DST_BASE: read_data = blit_dst_base_reg;
            REG_BLIT_SRC_STRIDE: read_data[31:0] = blit_src_stride_o;
            REG_BLIT_DST_STRIDE: read_data[31:0] = blit_dst_stride_o;
            REG_BLIT_SRC_XY: read_data[31:0] = {blit_src_y_o, blit_src_x_o};
            REG_BLIT_DST_XY: read_data[31:0] = {blit_dst_y_o, blit_dst_x_o};
            REG_BLIT_WH: read_data[31:0] = {blit_height_o, blit_width_o};
            REG_IRQ_ENABLE: read_data[1:0] = irq_enable;
            REG_IRQ_STATUS: read_data[1:0] = irq_status;
            REG_VERSION: read_data[31:0] = 32'h47505502;
           
            REG_TRI_CMD: begin
                read_data[0] = triangle_busy_i;
                read_data[1] = triangle_fetch_mode_o;
            end
          
            REG_TEX_BASE: read_data = texture_base_reg;
            REG_TEX_STRIDE: read_data[31:0] = texture_stride_o;
            REG_TEX_SIZE: read_data[31:0] = {texture_height_o, texture_width_o};
            REG_TEX_UV: read_data[31:0] = texture_v_o;
            REG_TEX_U: read_data[31:0] = texture_u_o;
            REG_VERTEX_BASE: read_data = vertex_base_reg;
            REG_VERTEX_STRIDE: read_data[31:0] = vertex_stride_o;
            default: read_data = {XLEN{1'b0}};
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_dat_o <= {XLEN{1'b0}};
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            wb_seen <= 1'b0;
            irq_enable <= 2'b00;
            irq_status <= 2'b00;
            scanout_start_o <= 1'b0;
          
            triangle_start_o <= 1'b0;
            triangle_x0_o <= 16'sd0;
            triangle_y0_o <= 16'sd0;
            triangle_x1_o <= 16'sd0;
            triangle_y1_o <= 16'sd0;
            triangle_x2_o <= 16'sd0;
            triangle_y2_o <= 16'sd0;
            triangle_color_o <= 32'hFFFFFFFF;
            triangle_shader_opcode_o <= 4'd4;
            triangle_depth_o <= 32'd0;
           
            texture_base_o <= {XLEN{1'b0}};
            texture_base_reg <= {XLEN{1'b0}};
            texture_stride_o <= 32'd0;
            texture_width_o <= 16'd0;
            texture_height_o <= 16'd0;
            texture_u_o <= 32'd0;
          
            texture_v_o <= 32'd0;
            vertex_base_o <= {XLEN{1'b0}};
            vertex_base_reg <= {XLEN{1'b0}};
            vertex_stride_o <= 32'd24;
            triangle_fetch_mode_o <= 1'b0;
           
            depth_base_reg <= {XLEN{1'b0}};
            depth_base_o <= {XLEN{1'b0}};
            depth_stride_o <= 32'd0;
            depth_enable_o <= 1'b0;
            depth_write_enable_o <= 1'b0;
            depth_compare_o <= 3'd1;
            blend_enable_o <= 1'b0;
           
            blit_start_o <= 1'b0;
            blit_src_base_reg <= {XLEN{1'b0}};
            blit_dst_base_reg <= {XLEN{1'b0}};
            blit_src_base_o <= {XLEN{1'b0}};
            blit_dst_base_o <= {XLEN{1'b0}};
            blit_src_stride_o <= 32'd0;
            blit_dst_stride_o <= 32'd0;
            blit_src_x_o <= 16'd0;
            blit_src_y_o <= 16'd0;
            blit_dst_x_o <= 16'd0;
            blit_dst_y_o <= 16'd0;
            blit_width_o <= 16'd0;
            blit_height_o <= 16'd0;
      
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            scanout_start_o <= 1'b0;
            triangle_start_o <= 1'b0;
            blit_start_o <= 1'b0;

            if (triangle_done_i || blit_done_i)
                irq_status[0] <= 1'b1;
            if (triangle_error_i || blit_error_i)
                irq_status[1] <= 1'b1;

            if (!wb_cyc_i || !wb_stb_i)
                wb_seen <= 1'b0;

            if (wb_cyc_i && wb_stb_i && !wb_seen) begin
                wb_seen <= 1'b1;
                wb_ack_o <= 1'b1;

                if (wb_we_i) begin

                    case (wb_adr_i[7:0])

                        REG_DISPLAY_CMD: begin

                            if (wb_sel_i[0] && wb_dat_i[0])
                                scanout_start_o <= 1'b1;
                        end
                        REG_TRI_X0Y0: begin
                            if (wb_sel_i[0]) triangle_x0_o <= wb_dat_i[15:0];
                            if (wb_sel_i[1]) triangle_y0_o <= wb_dat_i[31:16];
                        end
                        REG_TRI_X1Y1: begin
                            if (wb_sel_i[0]) triangle_x1_o <= wb_dat_i[15:0];
                            if (wb_sel_i[1]) triangle_y1_o <= wb_dat_i[31:16];
                        end
                        REG_TRI_X2Y2: begin
                            if (wb_sel_i[0]) triangle_x2_o <= wb_dat_i[15:0];
                            if (wb_sel_i[1]) triangle_y2_o <= wb_dat_i[31:16];
                        end

                        REG_TRI_COLOR: triangle_color_o <= merge_bytes({{(XLEN-32){1'b0}}, triangle_color_o}, wb_dat_i, wb_sel_i);
                        REG_TRI_SHADER: triangle_shader_opcode_o <= wb_dat_i[3:0];
                        REG_TRI_DEPTH: triangle_depth_o <= merge_bytes({{(XLEN-32){1'b0}}, triangle_depth_o}, wb_dat_i, wb_sel_i);
                       
                        REG_DEPTH_BASE: begin
                            depth_base_reg <= merge_bytes(depth_base_reg, wb_dat_i, wb_sel_i);
                            depth_base_o <= merge_bytes(depth_base_o, wb_dat_i, wb_sel_i);
                        end
                        
                        REG_DEPTH_STRIDE: depth_stride_o <= merge_bytes({{(XLEN-32){1'b0}}, depth_stride_o}, wb_dat_i, wb_sel_i);
                        REG_DEPTH_CTRL: begin
                            if (wb_sel_i[0]) begin
                                depth_enable_o <= wb_dat_i[0];
                                depth_write_enable_o <= wb_dat_i[1];
                                depth_compare_o <= wb_dat_i[4:2];
                                blend_enable_o <= wb_dat_i[5];
                            end
                        end
                        
                        REG_BLIT_SRC_BASE: begin
                            blit_src_base_reg <= merge_bytes(blit_src_base_reg, wb_dat_i, wb_sel_i);
                            blit_src_base_o <= merge_bytes(blit_src_base_o, wb_dat_i, wb_sel_i);
                        end
                        
                        REG_BLIT_DST_BASE: begin
                            blit_dst_base_reg <= merge_bytes(blit_dst_base_reg, wb_dat_i, wb_sel_i);
                            blit_dst_base_o <= merge_bytes(blit_dst_base_o, wb_dat_i, wb_sel_i);
                        end
                        
                        REG_BLIT_SRC_STRIDE: blit_src_stride_o <= merge_bytes({{(XLEN-32){1'b0}}, blit_src_stride_o}, wb_dat_i, wb_sel_i);
                        REG_BLIT_DST_STRIDE: blit_dst_stride_o <= merge_bytes({{(XLEN-32){1'b0}}, blit_dst_stride_o}, wb_dat_i, wb_sel_i);
                       
                        REG_BLIT_SRC_XY: begin
                            blit_src_x_o <= wb_dat_i[15:0];
                            blit_src_y_o <= wb_dat_i[31:16];
                        end
                       
                        REG_BLIT_DST_XY: begin
                            blit_dst_x_o <= wb_dat_i[15:0];
                            blit_dst_y_o <= wb_dat_i[31:16];
                        end
                        
                        REG_BLIT_WH: begin
                            blit_width_o <= wb_dat_i[15:0];
                            blit_height_o <= wb_dat_i[31:16];
                        end
                       
                        REG_TRI_CMD: begin
                            if (wb_sel_i[0]) begin
                                triangle_fetch_mode_o <= wb_dat_i[1];
                                if (wb_dat_i[0]) begin
                                    if (!triangle_busy_i)
                                        triangle_start_o <= 1'b1;
                                    else
                                        wb_err_o <= 1'b1;
                                end
                            end
                        end
                       
                        REG_TEX_BASE: begin
                            texture_base_reg <= merge_bytes(texture_base_reg, wb_dat_i, wb_sel_i);
                            texture_base_o <= merge_bytes(texture_base_o, wb_dat_i, wb_sel_i);
                        end
                        
                        REG_TEX_STRIDE: texture_stride_o <= merge_bytes({{(XLEN-32){1'b0}}, texture_stride_o}, wb_dat_i, wb_sel_i);
                        REG_TEX_SIZE: begin
                            texture_width_o <= wb_dat_i[15:0];
                            texture_height_o <= wb_dat_i[31:16];
                        end
                        REG_TEX_UV: texture_v_o <= wb_dat_i[31:0];
                        
                        REG_TEX_U: texture_u_o <= wb_dat_i[31:0];
                        REG_VERTEX_BASE: begin
                            vertex_base_reg <= merge_bytes(vertex_base_reg, wb_dat_i, wb_sel_i);
                            vertex_base_o <= merge_bytes(vertex_base_o, wb_dat_i, wb_sel_i);
                        end
                        REG_VERTEX_STRIDE: vertex_stride_o <= merge_bytes({{(XLEN-32){1'b0}}, vertex_stride_o}, wb_dat_i, wb_sel_i);
                        REG_BLIT_CMD: begin
                            if (wb_sel_i[0] && wb_dat_i[0]) begin
                                if (!blit_busy_i)
                                    blit_start_o <= 1'b1;
                                else
                                    wb_err_o <= 1'b1;
                            end
                        end
                        REG_IRQ_ENABLE: irq_enable <= merge_bytes({{(XLEN-2){1'b0}}, irq_enable}, wb_dat_i, wb_sel_i);
                        REG_IRQ_STATUS: irq_status <= irq_status & ~wb_dat_i[1:0];
                        default: wb_err_o <= 1'b1;
                    endcase

                end else begin
                    wb_dat_o <= read_data;
                    case (wb_adr_i[7:0])
                        REG_STATUS, REG_DISPLAY_CMD, REG_TRI_X0Y0, REG_TRI_X1Y1,
                        REG_TRI_X2Y2, REG_TRI_COLOR, REG_TRI_SHADER, REG_TRI_DEPTH,
                        REG_DEPTH_BASE, REG_DEPTH_STRIDE, REG_DEPTH_CTRL,
                        REG_BLIT_SRC_BASE, REG_BLIT_DST_BASE, REG_BLIT_SRC_STRIDE,
                       
                        REG_BLIT_DST_STRIDE, REG_BLIT_SRC_XY, REG_BLIT_DST_XY,
                        REG_BLIT_WH, REG_BLIT_CMD, REG_IRQ_ENABLE, REG_IRQ_STATUS,
                        REG_VERSION, REG_TRI_CMD, REG_TEX_BASE, REG_TEX_STRIDE,
                        REG_TEX_SIZE, REG_TEX_UV, REG_TEX_U, REG_VERTEX_BASE,
                        REG_VERTEX_STRIDE: begin end
                        default: wb_err_o <= 1'b1;
                    endcase
                end
            
            end
       
       
        end
   
    end

endmodule          