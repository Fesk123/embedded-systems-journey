`timescale 1ns/1ps

// Wishbone interconnect for UART, GPIO, and trace peripherals.
// The decode lives outside each peripheral, so each slave can stay small and independent.

module debug_io_interconnect #(

    parameter [63:0] UART_BASE  = 64'h0000000010000000,
    parameter [63:0] GPIO_BASE  = 64'h0000000010010000,
    parameter [63:0] TRACE_BASE = 64'h0000000010020000,
    parameter [63:0] TIMER_BASE = 64'h0000000010030000,

    parameter GPIO_WIDTH = 32,
    parameter TRACE_DEPTH = 64
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
    output reg wb_err_o,

    input wire uart_rx_i,
    output wire uart_tx_o,
    output wire uart_irq_o,

    input wire [GPIO_WIDTH-1:0] gpio_i,
    output wire [GPIO_WIDTH-1:0] gpio_o,
    output wire [GPIO_WIDTH-1:0] gpio_oe_o,
    output wire gpio_irq_o,

    input wire trace_valid_i,
    input wire [63:0] trace_pc_i,
    input wire [31:0] trace_instruction_i,
    input wire [1:0] trace_privilege_i,
    input wire trace_exception_i,

    output wire trace_irq_o,
    output wire timer_msip_o,
    output wire timer_mtip_o,
    output wire [2:0] io_irq_o
);

    wire uart_select = (wb_adr_i[63:16] == UART_BASE[63:16]);
    wire gpio_select = (wb_adr_i[63:16] == GPIO_BASE[63:16]);
    wire trace_select = (wb_adr_i[63:16] == TRACE_BASE[63:16]);
    wire timer_select = (wb_adr_i[63:16] == TIMER_BASE[63:16]);
    wire selected_any = uart_select || gpio_select || trace_select || timer_select;

    wire [63:0] uart_dat_o;
    wire uart_ack_o;
    wire uart_err_o;
    wire [63:0] gpio_dat_o;
    wire gpio_ack_o;
    wire gpio_err_o;
    wire [63:0] trace_dat_o;
    wire trace_ack_o;
    wire trace_err_o;
    wire [63:0] timer_dat_o;
    wire timer_ack_o;
    wire timer_err_o;

    reg unmapped_seen;
    reg unmapped_ack;

    debug_uart uart(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_cyc_i(wb_cyc_i && uart_select),
        .wb_stb_i(wb_stb_i && uart_select),
        .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_dat_o(uart_dat_o),
        .wb_ack_o(uart_ack_o),
        .wb_err_o(uart_err_o),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .irq_o(uart_irq_o)
    );

    debug_gpio #(

        .GPIO_WIDTH(GPIO_WIDTH)

    ) gpio(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_cyc_i(wb_cyc_i && gpio_select),
        .wb_stb_i(wb_stb_i && gpio_select),
        .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_dat_o(gpio_dat_o),
        .wb_ack_o(gpio_ack_o),
        .wb_err_o(gpio_err_o),
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe_o),
        .irq_o(gpio_irq_o)
    );

    debug_trace #(
        .TRACE_DEPTH(TRACE_DEPTH)
    ) trace(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_cyc_i(wb_cyc_i && trace_select),
        .wb_stb_i(wb_stb_i && trace_select),
        .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_dat_o(trace_dat_o),
        .wb_ack_o(trace_ack_o),
        .wb_err_o(trace_err_o),
        .trace_valid_i(trace_valid_i),
        .trace_pc_i(trace_pc_i),
        .trace_instruction_i(trace_instruction_i),
        .trace_privilege_i(trace_privilege_i),
        .trace_exception_i(trace_exception_i),
        .trace_irq_o(trace_irq_o)
    );

    debug_timer timer(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_cyc_i(wb_cyc_i && timer_select),
        .wb_stb_i(wb_stb_i && timer_select),
        .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_dat_o(timer_dat_o),
        .wb_ack_o(timer_ack_o),
        .wb_err_o(timer_err_o),
        .msip_o(timer_msip_o),
        .mtip_o(timer_mtip_o)
    );

    assign io_irq_o = {trace_irq_o, gpio_irq_o, uart_irq_o};

    always @* begin
        wb_dat_o = 64'd0;
        wb_ack_o = 1'b0;
        wb_err_o = 1'b0;

        if (uart_select) begin
            wb_dat_o = uart_dat_o;
            wb_ack_o = uart_ack_o;
            wb_err_o = uart_err_o;

        end else if (gpio_select) begin
            wb_dat_o = gpio_dat_o;
            wb_ack_o = gpio_ack_o;
            wb_err_o = gpio_err_o;

        end else if (trace_select) begin
            wb_dat_o = trace_dat_o;
            wb_ack_o = trace_ack_o;
            wb_err_o = trace_err_o;

        end else if (timer_select) begin
            wb_dat_o = timer_dat_o;
            wb_ack_o = timer_ack_o;
            wb_err_o = timer_err_o;

        end else begin
            wb_ack_o = unmapped_ack;
            wb_err_o = unmapped_ack;

        end


    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            unmapped_seen <= 1'b0;
            unmapped_ack <= 1'b0;
        end else begin
            unmapped_ack <= 1'b0;

            if (!wb_cyc_i || !wb_stb_i) begin
                unmapped_seen <= 1'b0;
            end else if (!selected_any && !unmapped_seen) begin
                unmapped_seen <= 1'b1;
                unmapped_ack <= 1'b1;
            end
       
        end
    end

endmodule