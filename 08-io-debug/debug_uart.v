`timescale 1ns/1ps

// 16550-style UART with a 64-bit Wishbone slave interface.
// Registers are spaced eight bytes apart to match the 64-bit bus.

module debug_uart #(
    parameter FIFO_DEPTH = 16
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

    input wire uart_rx_i,
    output reg uart_tx_o,
    output wire irq_o
);

    reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
    reg [7:0] rx_fifo [0:FIFO_DEPTH-1];

    reg [$clog2(FIFO_DEPTH)-1:0] tx_wr_ptr;
    reg [$clog2(FIFO_DEPTH)-1:0] tx_rd_ptr;
    reg [$clog2(FIFO_DEPTH)-1:0] rx_wr_ptr;
    reg [$clog2(FIFO_DEPTH)-1:0] rx_rd_ptr;
    reg [$clog2(FIFO_DEPTH+1)-1:0] tx_count;
    reg [$clog2(FIFO_DEPTH+1)-1:0] rx_count;

    reg [7:0] ier;
    reg [7:0] lcr;
    reg [7:0] mcr;
    reg [7:0] scr;
    reg [7:0] dll;
    reg [7:0] dlm;
    reg overrun_error;
    reg framing_error;

    reg tx_active;
    reg [9:0] tx_shift;
    reg [3:0] tx_bits_left;
    reg [19:0] tx_timer;

    reg rx_sync1;
    reg rx_sync2;
    reg rx_sync2_d;
    reg rx_active;
    reg [1:0] rx_state;
    reg [2:0] rx_bit_index;
    reg [7:0] rx_shift;
    reg [19:0] rx_timer;
    reg rx_push;
    reg [7:0] rx_push_data;

    reg ack_seen;
    wire wb_fire = wb_cyc_i && wb_stb_i && !ack_seen;
    wire [4:0] reg_index = wb_adr_i[7:3];
    wire dlab = lcr[7];

    wire fcr_clear_rx = wb_fire && wb_we_i && wb_sel_i[0] && reg_index == 5'd2 && wb_dat_i[1];
    wire fcr_clear_tx = wb_fire && wb_we_i && wb_sel_i[0] && reg_index == 5'd2 && wb_dat_i[2];
    wire tx_push = wb_fire && wb_we_i && wb_sel_i[0] && reg_index == 5'd0 && !dlab && (tx_count < FIFO_DEPTH);
    wire tx_pop = !fcr_clear_tx && !tx_active && (tx_count != 0);

    wire rx_pop = wb_fire && !wb_we_i && wb_sel_i[0] && reg_index == 5'd0 && !dlab && (rx_count != 0);
    wire [19:0] divisor = ( {dlm, dll} == 16'd0 ) ? 20'd16 : {dlm, dll, 4'b0000};

    assign wb_err_o = 1'b0;
    assign irq_o = ((ier[0] && (rx_count != 0)) || (ier[1] && (tx_count == 0) && !tx_active));

    // Wishbone register interface.
    always @(posedge clk_i) begin

        if (rst_i) begin
            wb_ack_o <= 1'b0;
            ack_seen <= 1'b0;
            wb_dat_o <= 64'd0;
            ier <= 0;
            lcr <= 8'h03;
            mcr <= 0;
            scr <= 0;
            dll <= 8'd1;
            dlm <= 0;

        end else begin

            wb_ack_o <= 1'b0;

            if (!wb_cyc_i || !wb_stb_i) begin
                ack_seen <= 1'b0;

            end else if (wb_fire) begin
                ack_seen <= 1'b1;
                wb_ack_o <= 1'b1;
                wb_dat_o <= 64'd0;

                if (wb_we_i) begin
                    if (wb_sel_i[0]) begin

                        case (reg_index)

                            5'd0: begin
                                if (dlab)
                                    dll <= wb_dat_i[7:0];
                                else begin
                                    // THR writes are handled by the transmit FIFO.
                                end
                            end

                            5'd1: begin
                                if (dlab)
                                    dlm <= wb_dat_i[7:0];
                                else
                                    ier <= wb_dat_i[3:0];
                            end

                            5'd2: begin end
                            5'd3: lcr <= wb_dat_i[7:0];
                            5'd4: mcr <= wb_dat_i[7:0];
                            5'd7: scr <= wb_dat_i[7:0];
                            default: begin end

                        endcase
                    end

                end else begin

                    case (reg_index)
                        5'd0: wb_dat_o[7:0] <= dlab ? dll : ((rx_count != 0) ? rx_fifo[rx_rd_ptr] : 8'd0);
                        5'd1: wb_dat_o[7:0] <= dlab ? dlm : ier;
                        5'd2: begin

                            if (rx_count != 0 && ier[0])
                                wb_dat_o[7:0] <= 8'h04;
                            else if ((tx_count == 0) && !tx_active && ier[1])
                                wb_dat_o[7:0] <= 8'h02;
                            else
                                wb_dat_o[7:0] <= 8'h01;
                        end

                        5'd3: wb_dat_o[7:0] <= lcr;
                        5'd4: wb_dat_o[7:0] <= mcr;
                        5'd5: wb_dat_o[7:0] <= {1'b0, ((tx_count == 0) && !tx_active), (tx_count == 0), 1'b0, framing_error, 1'b0, overrun_error, (rx_count != 0)};
                        5'd6: wb_dat_o[7:0] <= 8'hB0;
                        5'd7: wb_dat_o[7:0] <= scr;
                        default: wb_dat_o[7:0] <= 8'd0;

                    endcase
                end
            
            end
        
        
        end
    end

    // TX FIFO storage and counters.
    always @(posedge clk_i) begin

        if (rst_i) begin
            tx_wr_ptr <= 0;
        end else begin

            if (fcr_clear_tx)
                tx_wr_ptr <= 0;
            else if (tx_push) begin
                tx_fifo[tx_wr_ptr] <= wb_dat_i[7:0];
                tx_wr_ptr <= tx_wr_ptr + 1'b1;
            end

        end
    end

    always @(posedge clk_i) begin

        if (rst_i) begin
            tx_count <= 0;
            tx_rd_ptr <= 0;

        end else if (fcr_clear_tx) begin
            tx_count <= 0;
            tx_rd_ptr <= 0;
        end else begin
            case ({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: tx_count <= tx_count;
            endcase

            if (tx_pop)
                tx_rd_ptr <= tx_rd_ptr + 1'b1;
        end
    end

    // UART transmitter, 8 data bits, no parity, one stop bit.
    always @(posedge clk_i) begin

        if (rst_i) begin
            tx_active <= 1'b0;
            tx_shift <= 10'h3FF;
            tx_bits_left <= 0;
            tx_timer <= 0;
            uart_tx_o <= 1'b1;
        end else begin

            if (!tx_active && tx_count != 0) begin
                tx_active <= 1'b1;
                tx_shift <= {1'b1, tx_fifo[tx_rd_ptr], 1'b0};
                tx_bits_left <= 4'd10;
                tx_timer <= divisor - 1'b1;
                uart_tx_o <= 1'b0;
            end else if (tx_active) begin

                if (tx_timer != 0) begin
                    tx_timer <= tx_timer - 1'b1;
                end else if (tx_bits_left > 1) begin
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    uart_tx_o <= tx_shift[1];
                    tx_bits_left <= tx_bits_left - 1'b1;
                    tx_timer <= divisor - 1'b1;
                end else begin
                    tx_active <= 1'b0;
                    tx_bits_left <= 0;
                    tx_timer <= 0;
                    uart_tx_o <= 1'b1;
                end
            end
        end
    end

    // Synchronize and receive UART data.
    always @(posedge clk_i) begin
        if (rst_i) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
            rx_sync2_d <= 1'b1;
        end else begin
            rx_sync1 <= uart_rx_i;
            rx_sync2 <= rx_sync1;
            rx_sync2_d <= rx_sync2;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            rx_active <= 1'b0;
            rx_state <= 0;
            rx_bit_index <= 0;
            rx_shift <= 0;
            rx_timer <= 0;
            rx_push <= 1'b0;
            rx_push_data <= 0;
            framing_error <= 1'b0;
        end else begin
            rx_push <= 1'b0;

            if (!rx_active && rx_sync2_d && !rx_sync2) begin
                rx_active <= 1'b1;
                rx_state <= 2'd0;
                rx_timer <= (divisor >> 1) - 1'b1;
                rx_bit_index <= 0;
            end else if (rx_active) begin

                if (rx_timer != 0) begin
                    rx_timer <= rx_timer - 1'b1;
                end else begin

                    case (rx_state)
                        2'd0: begin
                            if (!rx_sync2) begin
                                rx_state <= 2'd1;
                                rx_timer <= divisor - 1'b1;
                                rx_bit_index <= 0;
                            end else begin
                                rx_active <= 1'b0;
                            end
                        end
                        2'd1: begin
                            rx_shift[rx_bit_index] <= rx_sync2;
                            rx_timer <= divisor - 1'b1;
                            if (rx_bit_index == 3'd7)
                                rx_state <= 2'd2;
                            else
                                rx_bit_index <= rx_bit_index + 1'b1;
                        end
                        2'd2: begin
                            if (rx_sync2) begin
                                rx_push <= 1'b1;
                                rx_push_data <= rx_shift;
                            end else begin
                                framing_error <= 1'b1;
                            end
                            rx_active <= 1'b0;
                            rx_state <= 2'd0;
                        end
                        default: begin
                            rx_active <= 1'b0;
                            rx_state <= 2'd0;
                        end
                    endcase
                end
            end
        end
    
    end

    // RX FIFO storage and counters.
    always @(posedge clk_i) begin

        if (rst_i) begin
            rx_wr_ptr <= 0;
            rx_rd_ptr <= 0;
            rx_count <= 0;
            overrun_error <= 1'b0;
        end else if (fcr_clear_rx) begin

            rx_wr_ptr <= 0;
            rx_rd_ptr <= 0;
            rx_count <= 0;
        end else begin
            if (rx_push) begin
                if (rx_count < FIFO_DEPTH) begin
                    rx_fifo[rx_wr_ptr] <= rx_push_data;
                    rx_wr_ptr <= rx_wr_ptr + 1'b1;
                end else begin
                    overrun_error <= 1'b1;
                end
            end

            case ({(rx_push && (rx_count < FIFO_DEPTH)), rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase

            if (rx_pop)
                rx_rd_ptr <= rx_rd_ptr + 1'b1;
        end
    
    end

endmodule