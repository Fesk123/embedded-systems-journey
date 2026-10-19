`timescale 1ns/1ps

// SPI MASTER CONTROLLER
// 64-bit Wishbone interface and configurable SPI mode
//
// Features:
// - 64-bit Wishbone slave interface
// - Four chip-select outputs
// - SPI CPOL and CPHA configuration
// - MSB-first and LSB-first transfers
// - Transfer length from 1 to 64 bits
// - Configurable serial clock divider
// - Byte-select support for Wishbone register writes
// - Sticky completion and error status
// - Interrupt on completion or error
//
// Register map:
// 0x00 CTRL            bit 0 = START, bit 1 = CPOL,
//                      bit 2 = CPHA, bit 3 = LSB_FIRST
// 0x08 STATUS          bit 0 = BUSY, bit 1 = DONE, bit 2 = ERROR
//                      Write 1 to bit 1 or 2 to clear DONE or ERROR.
// 0x10 CLK_DIV         System clock cycles per half SCK period minus 1
// 0x18 TX_DATA         Transmit data
// 0x20 RX_DATA         Received data (read only)
// 0x28 BIT_LENGTH      Number of transfer bits, from 1 to 64
// 0x30 CS_SELECT       Chip select number, from 0 to 3
// 0x38 IRQ_ENABLE      bit 0 = enable completion/error interrupt
//
// TX_DATA is right-aligned for MSB-first transfers. For example, an 8-bit transfer of 8'hA5 uses TX_DATA = 64'h00000000000000A5.
// LSB-first transfers use the least-significant bit first.
//
// The controller performs one transfer at a time. Software must write the configuration registers before writing CTRL with START set.

module SPI (

    input CLK_I,
    input RST_I,

    // WISHBONE SLAVE INTERFACE    

    input [63:0] ADR_I,
    input [63:0] DAT_I,
    output reg [63:0] DAT_O,
    input [7:0] SEL_I,
    input CYC_I,
    input STB_I,
    input WE_I,
    output reg ACK_O,
    output reg ERR_O,

    
    // SPI PHYSICAL INTERFACE
    

    output reg SPI_SCK_O,
    output reg SPI_MOSI_O,
    input SPI_MISO_I,
    output reg [3:0] SPI_CS_N_O,
    
    // INTERRUPT AND DEBUG INTERFACE

    output wire IRQ_O,
    output wire debug_busy,
    output wire debug_done,
    output wire debug_error,
    output wire [2:0] debug_state,
    output wire [6:0] debug_bit_count,
    output wire [15:0] debug_clk_count,
    output wire [63:0] debug_rx_data

);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_TRANSFER = 2'd1;
    localparam [1:0] ST_FINISH = 2'd2;

    reg [1:0] state_reg;
    reg wb_seen;

    reg cpol_reg;
    reg cpha_reg;
    reg lsb_first_reg;
    reg [15:0] clk_div_reg;
    reg [63:0] tx_data_reg;
    reg [63:0] rx_data_reg;
    reg [6:0] bit_length_reg;
    reg [1:0] cs_select_reg;
    reg irq_enable_reg;

    reg busy_reg;
    reg done_reg;
    reg error_reg;

    reg [63:0] tx_shift_reg;
    reg [63:0] rx_shift_reg;
    reg [6:0] bits_remaining_reg;
    reg [6:0] bits_transferred_reg;
    reg [15:0] divider_count_reg;
    reg [63:0] tx_start_data_temp;

    integer byte_index;

    assign IRQ_O = irq_enable_reg && (done_reg || error_reg);

    assign debug_busy = busy_reg;
    assign debug_done = done_reg;
    assign debug_error = error_reg;
    assign debug_state = {1'b0, state_reg};
    assign debug_bit_count = bits_transferred_reg;
    assign debug_clk_count = divider_count_reg;
    assign debug_rx_data = rx_data_reg;

    // WISHBONE REGISTER INTERFACE
    
    always @(posedge CLK_I) begin

        if (RST_I) begin
            DAT_O <= 64'd0;
            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            wb_seen <= 1'b0;

            cpol_reg <= 1'b0;
            cpha_reg <= 1'b0;
            lsb_first_reg <= 1'b0;
            clk_div_reg <= 16'd1;
            tx_data_reg <= 64'd0;
            rx_data_reg <= 64'd0;
            bit_length_reg <= 7'd8;
            cs_select_reg <= 2'd0;
            irq_enable_reg <= 1'b0;

            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            error_reg <= 1'b0;
            state_reg <= ST_IDLE;

            tx_shift_reg <= 64'd0;
            rx_shift_reg <= 64'd0;
            bits_remaining_reg <= 7'd0;
            bits_transferred_reg <= 7'd0;
            divider_count_reg <= 16'd0;

            SPI_SCK_O <= 1'b0;
            SPI_MOSI_O <= 1'b0;
            SPI_CS_N_O <= 4'b1111;
        
        end else begin
        
            ACK_O <= 1'b0;
            ERR_O <= 1'b0;

            if (!(CYC_I && STB_I)) begin
                wb_seen <= 1'b0;
        
            end else if (!wb_seen) begin
                wb_seen <= 1'b1;

                if ((ADR_I[63:8] != 56'd0) || (ADR_I[2:0] != 3'd0)) begin
                    ERR_O <= 1'b1;
        
                end else begin
        
                    case (ADR_I[7:0])
        
                        8'h00,
                        8'h08,
                        8'h10,
                        8'h18,
                        8'h20,
                        8'h28,
                        8'h30,
                        8'h38: begin
                        
                            if (WE_I && (busy_reg && (ADR_I[7:0] != 8'h08))) begin
                                ERR_O <= 1'b1;
                        
                            end else if (WE_I && (SEL_I == 8'd0)) begin
                                ERR_O <= 1'b1;
                            
                            end else if (WE_I && (ADR_I[7:0] == 8'h20)) begin
                                ERR_O <= 1'b1;
                            
                            end else begin
                                ACK_O <= 1'b1;

                                if (WE_I) begin
                            
                                    case (ADR_I[7:0])
                                        8'h00: begin
                                            if (SEL_I[0]) begin
                            
                                                cpol_reg <= DAT_I[1];
                                                cpha_reg <= DAT_I[2];
                                                SPI_SCK_O <= DAT_I[1];
                                                lsb_first_reg <= DAT_I[3];

                                                if (DAT_I[0]) begin
                            
                                                    if ((bit_length_reg == 7'd0) ||
                                                        (bit_length_reg > 7'd64)) begin
                                                        error_reg <= 1'b1;
                                                        done_reg <= 1'b0;
                            
                                                    end else begin
                            
                                                        busy_reg <= 1'b1;
                                                        done_reg <= 1'b0;
                                                        error_reg <= 1'b0;
                                                        state_reg <= ST_TRANSFER;
                                                        SPI_SCK_O <= DAT_I[1];
                                                        SPI_CS_N_O <= ~(4'b0001 << cs_select_reg);

                                                        tx_start_data_temp = tx_data_reg << (64 - bit_length_reg);

                                                        if (DAT_I[3]) begin
                            
                                                            SPI_MOSI_O <= tx_data_reg[0];
                                                            tx_shift_reg <= tx_data_reg;
                                                        end else begin
                            
                                                            SPI_MOSI_O <= tx_start_data_temp[63];
                                                            tx_shift_reg <= tx_start_data_temp;
                                                        end

                                                        rx_shift_reg <= 64'd0;
                                                        bits_remaining_reg <= bit_length_reg;
                                                        bits_transferred_reg <= 7'd0;
                                                        divider_count_reg <= 16'd0;
                                                    end
                                                end
                                            end
                                        end

                            
                                        8'h08: begin
                                            if (SEL_I[0]) begin
                                                if (DAT_I[1])
                                                    done_reg <= 1'b0;
                                                if (DAT_I[2])
                                                    error_reg <= 1'b0;
                                            end
                                        end

                            
                                        8'h10: begin
                                            if (SEL_I[0]) clk_div_reg[7:0] <= DAT_I[7:0];
                                            if (SEL_I[1]) clk_div_reg[15:8] <= DAT_I[15:8];
                                        end

                                        8'h18: begin
                            
                                            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                                                if (SEL_I[byte_index])
                                                    tx_data_reg[(byte_index * 8) +: 8] <= DAT_I[(byte_index * 8) +: 8];
                                            end
                            
                                        end

                                        8'h20: begin end

                                        8'h28: begin
                                            if (SEL_I[0])
                                                bit_length_reg <= DAT_I[6:0];
                                        end

                                        8'h30: begin
                                            if (SEL_I[0])
                                                cs_select_reg <= DAT_I[1:0];
                                        end

                                        8'h38: begin
                                            if (SEL_I[0])
                                                irq_enable_reg <= DAT_I[0];
                                        end

                                        default: ERR_O <= 1'b1;
                                    endcase
                                end else begin
                            
                                    case (ADR_I[7:0])
                                        8'h00: DAT_O <= {60'd0, lsb_first_reg, cpha_reg, cpol_reg, 1'b0};
                                        8'h08: DAT_O <= {61'd0, error_reg, done_reg, busy_reg};
                                        8'h10: DAT_O <= {48'd0, clk_div_reg};
                                        8'h18: DAT_O <= tx_data_reg;
                                        8'h20: DAT_O <= rx_data_reg;
                                        8'h28: DAT_O <= {57'd0, bit_length_reg};
                                        8'h30: DAT_O <= {62'd0, cs_select_reg};
                                        8'h38: DAT_O <= {63'd0, irq_enable_reg};
                                        default: DAT_O <= 64'd0;
                                    endcase
                            
                                end
                            end
                        end

                        default: ERR_O <= 1'b1;
                    endcase
                end
            end

            // SPI TRANSFER ENGINE            

            if (state_reg == ST_FINISH) begin
                
                SPI_SCK_O <= cpol_reg;
                SPI_CS_N_O <= 4'b1111;
                busy_reg <= 1'b0;
                done_reg <= 1'b1;
            
                state_reg <= ST_IDLE;
                rx_data_reg <= rx_shift_reg;
                divider_count_reg <= 16'd0;
            
            end else if (state_reg == ST_TRANSFER) begin
            
                if (divider_count_reg >= clk_div_reg) begin
                    divider_count_reg <= 16'd0;

                    if (SPI_SCK_O == cpol_reg) begin
                        // Leading edge
                        SPI_SCK_O <= ~SPI_SCK_O;

                        if (cpha_reg) begin
            
                            // Change data on the leading edge for CPHA = 1.
                            if (lsb_first_reg) begin
                                SPI_MOSI_O <= tx_shift_reg[0];
                                tx_shift_reg <= {1'b0, tx_shift_reg[63:1]};
            
                            end else begin
                                SPI_MOSI_O <= tx_shift_reg[63];
                                tx_shift_reg <= {tx_shift_reg[62:0], 1'b0};
                            end
            
                        end else begin
                            // Sample data on the leading edge for CPHA = 0.
            
                            if (lsb_first_reg) begin
                                rx_shift_reg[bits_transferred_reg] <= SPI_MISO_I;
            
                            end else begin
                                rx_shift_reg <= {rx_shift_reg[62:0], SPI_MISO_I};
                            end
            
                            bits_transferred_reg <= bits_transferred_reg + 1'b1;
                        end
                    end else begin
                        // Trailing edge returns SCK to its idle polarity.
                        SPI_SCK_O <= ~SPI_SCK_O;

                        if (cpha_reg) begin
                            // Sample data on the trailing edge for CPHA = 1.
            
                            if (lsb_first_reg) begin
                                rx_shift_reg[bits_transferred_reg] <= SPI_MISO_I;
            
                            end else begin
                                rx_shift_reg <= {rx_shift_reg[62:0], SPI_MISO_I};
            
                            end
                            bits_transferred_reg <= bits_transferred_reg + 1'b1;
            
                        end else begin
                            // Change data on the trailing edge for CPHA = 0.
            
                            if (lsb_first_reg) begin
                                SPI_MOSI_O <= tx_shift_reg[1];
                                tx_shift_reg <= {1'b0, tx_shift_reg[63:1]};
                            end else begin
            
                                SPI_MOSI_O <= tx_shift_reg[62];
                                tx_shift_reg <= {tx_shift_reg[62:0], 1'b0};
                            end
                        end

                        if (bits_remaining_reg <= 7'd1) begin
                            state_reg <= ST_FINISH;
                        end else begin
                            bits_remaining_reg <= bits_remaining_reg - 1'b1;
                        end
                    end
                end else begin
                    divider_count_reg <= divider_count_reg + 1'b1;
            
                end
        
            end
        end

    end

endmodule