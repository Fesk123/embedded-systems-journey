`timescale 1ns/1ps

// 32-bit GPIO controller with direction and edge-triggered interrupts.
// Registers are spaced eight bytes apart for a 64-bit Wishbone bus.

module debug_gpio #(
    parameter GPIO_WIDTH = 32
)(
    input wire clk_i,
    input wire rst_i,

    input wire wb_cyc_i,
    input wire wb_stb_i,
    input wire wb_we_i,
    input wire [63:0] wb_adr_i,
    input wire [63:0] wb_dat_i,
    input wire [7:0] wb_sel_i,
    output reg [63:0] wb_dat_o,
    output reg wb_ack_o,
    output wire wb_err_o,

    input wire [GPIO_WIDTH-1:0] gpio_i,
    output wire [GPIO_WIDTH-1:0] gpio_o,
    output wire [GPIO_WIDTH-1:0] gpio_oe_o,
    output wire irq_o
);

    reg [GPIO_WIDTH-1:0] output_reg;
    reg [GPIO_WIDTH-1:0] direction_reg;
    reg [GPIO_WIDTH-1:0] rise_enable_reg;
    reg [GPIO_WIDTH-1:0] fall_enable_reg;
    reg [GPIO_WIDTH-1:0] irq_status_reg;

    reg [GPIO_WIDTH-1:0] gpio_sync1;
    reg [GPIO_WIDTH-1:0] gpio_sync2;
    reg [GPIO_WIDTH-1:0] gpio_previous;

    reg ack_seen;
    wire wb_fire = wb_cyc_i && wb_stb_i && !ack_seen;
    wire [4:0] reg_index = wb_adr_i[7:3];

    wire [GPIO_WIDTH-1:0] rise_event = gpio_sync2 & ~gpio_previous;
    wire [GPIO_WIDTH-1:0] fall_event = ~gpio_sync2 & gpio_previous;
    wire [GPIO_WIDTH-1:0] edge_event = (rise_event & rise_enable_reg) | (fall_event & fall_enable_reg);
    wire [GPIO_WIDTH-1:0] irq_clear_mask = (wb_fire && wb_we_i && wb_sel_i[0] && reg_index == 5'd6) ? wb_dat_i[GPIO_WIDTH-1:0] : {GPIO_WIDTH{1'b0}};

    assign wb_err_o = 1'b0;
    assign gpio_o = output_reg;
    assign gpio_oe_o = direction_reg;
    assign irq_o = |(irq_status_reg & (rise_enable_reg | fall_enable_reg));

    always @(posedge clk_i) begin

        if (rst_i) begin
            wb_ack_o <= 1'b0;
            ack_seen <= 1'b0;
            wb_dat_o <= 64'd0;
            output_reg <= 0;
            direction_reg <= 0;
            rise_enable_reg <= 0;
            fall_enable_reg <= 0;
            irq_status_reg <= 0;
        end else begin
            wb_ack_o <= 1'b0;

            if (!wb_cyc_i || !wb_stb_i) begin
                ack_seen <= 1'b0;
            end else if (wb_fire) begin
                ack_seen <= 1'b1;
                wb_ack_o <= 1'b1;
                wb_dat_o <= 64'd0;

                if (wb_we_i && wb_sel_i[0]) begin
                    case (reg_index)
                        5'd0: output_reg <= wb_dat_i[GPIO_WIDTH-1:0];
                        5'd2: direction_reg <= wb_dat_i[GPIO_WIDTH-1:0];
                        5'd3: rise_enable_reg <= wb_dat_i[GPIO_WIDTH-1:0];
                        5'd4: fall_enable_reg <= wb_dat_i[GPIO_WIDTH-1:0];
                        default: begin end
                    endcase

                end else if (!wb_we_i) begin
                    case (reg_index)
                        5'd0: wb_dat_o[GPIO_WIDTH-1:0] <= output_reg;
                        5'd1: wb_dat_o[GPIO_WIDTH-1:0] <= gpio_sync2;
                        5'd2: wb_dat_o[GPIO_WIDTH-1:0] <= direction_reg;

                        5'd3: wb_dat_o[GPIO_WIDTH-1:0] <= rise_enable_reg;
                        5'd4: wb_dat_o[GPIO_WIDTH-1:0] <= fall_enable_reg;
                        5'd5: wb_dat_o[GPIO_WIDTH-1:0] <= irq_status_reg;
                        5'd7: wb_dat_o[GPIO_WIDTH-1:0] <= GPIO_WIDTH;
                        default: wb_dat_o <= 64'd0;
                    endcase
                end
            end

            irq_status_reg <= (irq_status_reg & ~irq_clear_mask) | edge_event;
        end
    end

    // External pins are synchronized before they are sampled by the register block.
    always @(posedge clk_i) begin
        if (rst_i) begin
            gpio_sync1 <= 0;
            gpio_sync2 <= 0;
            gpio_previous <= 0;
        end else begin
            gpio_sync1 <= gpio_i;
            gpio_sync2 <= gpio_sync1;
            gpio_previous <= gpio_sync2;
        end
        
    end

endmodule