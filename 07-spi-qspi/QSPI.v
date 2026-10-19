`timescale 1ns/1ps

// QSPI FLASH MASTER CONTROLLER
// 64-bit Wishbone interface and 64-byte quad transfers
//
// Features:
// - 64-bit Wishbone slave interface
// - Single-line command phase
// - Configurable 0 to 4 byte address phase
// - Single-line or quad address phase
// - Configurable dummy clock cycles
// - Single-line or quad data phase
// - Up to 64 data bytes per transaction
// - Eight 64-bit TX and RX buffer words
// - Automatic TX word-index increment
// - RX word-index register for reading burst results
// - Configurable serial clock divider
// - Completion, buffer-valid and error status
// - Interrupt on completion or error
//
// Register map:
// 0x00 CTRL            bit 0 = START, bit 1 = WRITE,
//                      bit 2 = QUAD_ADDRESS, bit 3 = QUAD_DATA,
//                      bit 4 = CLEAR_BUFFERS
// 0x08 STATUS          bit 0 = BUSY, bit 1 = DONE, bit 2 = ERROR,
//                      bit 3 = TX_BUFFER_COMPLETE. DONE and ERROR are W1C.
// 0x10 CLK_DIV         System clock cycles per half SCK period minus 1
// 0x18 COMMAND         8-bit flash command, sent MSB first on IO0
// 0x20 ADDRESS         32-bit flash address
// 0x28 TX_DATA         Write/read selected 64-bit TX buffer word
// 0x30 RX_DATA         Read selected 64-bit RX buffer word
// 0x38 DATA_LENGTH     Number of data bytes, from 1 to 64
// 0x40 ADDR_LENGTH     Number of address bytes, from 0 to 4
// 0x48 DUMMY           Number of dummy clock cycles
// 0x50 IRQ_ENABLE      bit 0 = enable completion/error interrupt
// 0x58 TX_INDEX        TX buffer word index, 0 to 7; writes auto-increment
// 0x60 RX_INDEX        RX buffer word index, 0 to 7
// 0x68 BUF_STATUS      [7:0] TX written mask, [15:8] RX valid mask,
//                      [18:16] TX index, [21:19] RX index
//
// TX_DATA words are supplied in transfer order. Full words are sent MSB first. If the final word contains fewer than 8 bytes, those bytes are right-aligned in TX_DATA. The controller places them at the end of theserial payload. 
// RX data words are returned in transfer order; a partial final word is right-aligned. QSPI uses mode 0 and the command phase is always single-line.
// Flash-specific WREN, status polling and erase/program sequencing are handled by software or a higher-level flash driver.

module QSPI (

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

    // QSPI PHYSICAL INTERFACE    

    output reg QSPI_SCK_O,
    output reg QSPI_CS_N_O,
    input [3:0] QSPI_IO_I,
    output reg [3:0] QSPI_IO_O,
    output reg [3:0] QSPI_IO_OE,

    // INTERRUPT AND DEBUG INTERFACE

    output wire IRQ_O,
    output wire debug_busy,
    output wire debug_done,
    output wire debug_error,
    output wire [2:0] debug_state,
    output wire [7:0] debug_phase_count,
    output wire [63:0] debug_rx_data

);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_CMD = 3'd1;
    localparam [2:0] ST_ADDR = 3'd2;
    localparam [2:0] ST_DUMMY = 3'd3;
    localparam [2:0] ST_DATA = 3'd4;
    localparam [2:0] ST_FINISH = 3'd5;

    reg [2:0] state_reg;
    reg wb_seen;

    reg write_mode_reg;
    reg quad_address_reg;
    reg quad_data_reg;
    reg [15:0] clk_div_reg;
    reg [7:0] command_reg;

    reg [31:0] address_reg;
    reg [6:0] data_length_reg;
    reg [2:0] address_length_reg;
    reg [7:0] dummy_cycles_reg;
    reg irq_enable_reg;

    reg [63:0] tx_buffer [0:7];
    reg [63:0] rx_buffer [0:7];
    reg [2:0] tx_index_reg;
    reg [2:0] rx_index_reg;
    reg [7:0] tx_written_mask_reg;
    reg [7:0] rx_valid_mask_reg;

    reg busy_reg;
    reg done_reg;
    reg error_reg;

    reg [7:0] command_shift_reg;
    reg [31:0] address_shift_reg;
    reg [511:0] tx_shift_reg;
    reg [511:0] rx_shift_reg;

    reg [15:0] divider_count_reg;
    reg [9:0] phase_count_reg;
    reg [7:0] dummy_count_reg;
    reg [9:0] address_beats_reg;
    reg [9:0] data_beats_reg;
    reg [511:0] tx_start_data_temp;

    integer byte_index;
    integer word_index;
    integer byte_offset;
    integer valid_bytes_in_word;
    integer shift_amount;

    function tx_data_ready;
        input [6:0] length;
        input [7:0] written_mask;
        integer k;
        integer words_needed;

        begin
            words_needed = (length + 7) / 8;
            tx_data_ready = 1'b1;
            for (k = 0; k < 8; k = k + 1) begin
                if ((k < words_needed) && !written_mask[k])
                    tx_data_ready = 1'b0;
            end
        end
    endfunction

    assign IRQ_O = irq_enable_reg && (done_reg || error_reg);

    assign debug_busy = busy_reg;
    assign debug_done = done_reg;
    assign debug_error = error_reg;

    assign debug_state = state_reg;
    assign debug_phase_count = phase_count_reg[7:0];
    assign debug_rx_data = rx_buffer[rx_index_reg];

    // WISHBONE REGISTER INTERFACE

    always @(posedge CLK_I) begin

        if (RST_I) begin

            DAT_O <= 64'd0;
            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            wb_seen <= 1'b0;

            write_mode_reg <= 1'b0;
            quad_address_reg <= 1'b0;
            quad_data_reg <= 1'b0;
            clk_div_reg <= 16'd1;
            command_reg <= 8'h03;
            address_reg <= 32'd0;
            data_length_reg <= 7'd8;
            address_length_reg <= 3'd3;
            dummy_cycles_reg <= 8'd0;
            irq_enable_reg <= 1'b0;

            tx_index_reg <= 3'd0;
            rx_index_reg <= 3'd0;
            tx_written_mask_reg <= 8'd0;
            rx_valid_mask_reg <= 8'd0;

            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            error_reg <= 1'b0;
            state_reg <= ST_IDLE;

            command_shift_reg <= 8'd0;
            address_shift_reg <= 32'd0;
            tx_shift_reg <= 512'd0;
            rx_shift_reg <= 512'd0;
            divider_count_reg <= 16'd0;
            phase_count_reg <= 10'd0;
            dummy_count_reg <= 8'd0;
            address_beats_reg <= 10'd0;
            data_beats_reg <= 10'd0;

            QSPI_SCK_O <= 1'b0;
            QSPI_CS_N_O <= 1'b1;
            QSPI_IO_O <= 4'd0;
            QSPI_IO_OE <= 4'b0000;

            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                tx_buffer[byte_index] <= 64'd0;
                rx_buffer[byte_index] <= 64'd0;
            end

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
                        8'h38,
                        8'h40,
                        8'h48,
                        8'h50,
                        8'h58,
                        8'h60,
                        8'h68: begin
            
                            if (WE_I && busy_reg && (ADR_I[7:0] != 8'h08)) begin
                                ERR_O <= 1'b1;
            
                            end else if (WE_I && (SEL_I == 8'd0)) begin
                                ERR_O <= 1'b1;
                            end else begin
                            
                                case (ADR_I[7:0])
                                    8'h00: begin
                            
                                        if (WE_I) begin
                                            if (!SEL_I[0]) begin
                                                ERR_O <= 1'b1;
                                            end else if (DAT_I[4] && DAT_I[0]) begin
                                                ERR_O <= 1'b1;
                                            end else begin
                                                ACK_O <= 1'b1;

                                                if (DAT_I[4]) begin
                                                    tx_index_reg <= 3'd0;
                                                    rx_index_reg <= 3'd0;
                                                    tx_written_mask_reg <= 8'd0;
                                                    rx_valid_mask_reg <= 8'd0;
                                                end else begin
                                                    write_mode_reg <= DAT_I[1];
                                                    quad_address_reg <= DAT_I[2];
                                                    quad_data_reg <= DAT_I[3];

                                                    if (DAT_I[0]) begin
                                                        if ((data_length_reg == 7'd0) ||
                                                            (data_length_reg > 7'd64) ||
                                                            (address_length_reg > 3'd4)) begin
                                                            error_reg <= 1'b1;
                                                            done_reg <= 1'b0;
                                                        end else if (DAT_I[1] && !tx_data_ready(data_length_reg, tx_written_mask_reg)) begin
                                                            error_reg <= 1'b1;
                                                            done_reg <= 1'b0;
                                                        end else begin
                                                            busy_reg <= 1'b1;
                                                            done_reg <= 1'b0;
                                                            error_reg <= 1'b0;
                                                            state_reg <= ST_CMD;
                                                            QSPI_SCK_O <= 1'b0;
                                                            QSPI_CS_N_O <= 1'b0;
                                                            QSPI_IO_O <= {3'b000, command_reg[7]};
                                                            QSPI_IO_OE <= 4'b0001;
                            
                                                            command_shift_reg <= {command_reg[6:0], 1'b0};
                                                            address_shift_reg <= address_reg << ((4 - address_length_reg) * 8);
                                                            rx_shift_reg <= 512'd0;
                                                            divider_count_reg <= 16'd0;
                                                            phase_count_reg <= 10'd0;
                                                            dummy_count_reg <= 8'd0;
                                                            address_beats_reg <= DAT_I[2] ? (address_length_reg * 2) : (address_length_reg * 8);
                                                            data_beats_reg <= DAT_I[3] ? (data_length_reg * 2) : (data_length_reg * 8);
                                                            rx_valid_mask_reg <= 8'd0;

                                                            tx_start_data_temp = 512'd0;
                            
                                                            for (byte_index = 0; byte_index < 64; byte_index = byte_index + 1) begin
                            
                                                                if (byte_index < data_length_reg) begin
                                                                    word_index = byte_index / 8;
                                                                    byte_offset = byte_index % 8;
                                                                    valid_bytes_in_word = data_length_reg - (word_index * 8);
                                                                    if (valid_bytes_in_word > 8)
                                                                        valid_bytes_in_word = 8;

                                                                    if (valid_bytes_in_word < 8) begin
                                                                        shift_amount = (valid_bytes_in_word - 1 - byte_offset) * 8;
                                                                    end else begin
                                                                        shift_amount = (7 - byte_offset) * 8;
                                                                    end

                                                                    tx_start_data_temp[511 - (byte_index * 8) -: 8] =
                                                                        (tx_buffer[word_index] >> shift_amount) & 8'hFF;
                                                                end
                                                            end
                                                            tx_shift_reg <= tx_start_data_temp;
                                                        end
                            
                                                    end
                                                end
                            
                                            end
                            
                            
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {60'd0, quad_data_reg, quad_address_reg, write_mode_reg, 1'b0};
                                        end
                                    end

                                    8'h08: begin
                            
                                        if (WE_I) begin
                            
                                            if (!SEL_I[0]) begin
                                                ERR_O <= 1'b1;
                            
                                            end else begin
                                                ACK_O <= 1'b1;
                                                if (DAT_I[1]) done_reg <= 1'b0;
                                                if (DAT_I[2]) error_reg <= 1'b0;
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {60'd0, tx_data_ready(data_length_reg, tx_written_mask_reg), error_reg, done_reg, busy_reg};
                                        end
                                    end

                                    8'h10: begin
                            
                                        if (WE_I) begin
                                            ACK_O <= 1'b1;
                                            if (SEL_I[0]) clk_div_reg[7:0] <= DAT_I[7:0];
                                            if (SEL_I[1]) clk_div_reg[15:8] <= DAT_I[15:8];
                            
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {48'd0, clk_div_reg};
                                        end
                            
                                    end

                                    8'h18: begin
                            
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                                            else begin
                                                ACK_O <= 1'b1;
                                                command_reg <= DAT_I[7:0];
                                            end
                            
                                        end else begin
                            
                                            ACK_O <= 1'b1;
                                            DAT_O <= {56'd0, command_reg};
                                        end
                                    end

                                    8'h20: begin
                            
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                                            else begin
                                                ACK_O <= 1'b1;
                                                address_reg <= DAT_I[31:0];
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {32'd0, address_reg};
                                        end
                            
                                    end

                                    8'h28: begin
                            
                                        if (WE_I) begin
                                            if (SEL_I != 8'hFF) begin
                                                ERR_O <= 1'b1;
                                            end else begin
                                                ACK_O <= 1'b1;
                                                tx_buffer[tx_index_reg] <= DAT_I;
                                                tx_written_mask_reg[tx_index_reg] <= 1'b1;
                                                tx_index_reg <= tx_index_reg + 1'b1;
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= tx_buffer[tx_index_reg];
                            
                                        end
                                    end

                                    8'h30: begin
                                        if (WE_I) begin
                                            ERR_O <= 1'b1;
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= rx_buffer[rx_index_reg];
                                        end
                                    end

                                    8'h38: begin
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                                            else if (DAT_I[6:0] > 7'd64) ERR_O <= 1'b1;
                            
                                            else begin
                                                ACK_O <= 1'b1;
                                                data_length_reg <= DAT_I[6:0];
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {57'd0, data_length_reg};
                                        end
                                    end

                                    8'h40: begin
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                            
                                            else if (DAT_I[2:0] > 3'd4) ERR_O <= 1'b1;
                            
                                            else begin
                                                ACK_O <= 1'b1;
                                                address_length_reg <= DAT_I[2:0];
                                            end
                            
                            
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {61'd0, address_length_reg};
                                        end
                                    end

                                    8'h48: begin
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                                            else begin
                                                ACK_O <= 1'b1;
                                                dummy_cycles_reg <= DAT_I[7:0];
                            
                                            end
                            
                                        end else begin
                                            ACK_O <= 1'b1;
                            
                                            DAT_O <= {56'd0, dummy_cycles_reg};
                                        end
                                    end

                                    8'h50: begin
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                                            else begin
                                                ACK_O <= 1'b1;
                                                irq_enable_reg <= DAT_I[0];
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {63'd0, irq_enable_reg};
                                        end
                                    end

                                    8'h58: begin
                            
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                            
                                            else if (DAT_I[63:3] != 61'd0) ERR_O <= 1'b1;
                                            else begin
                                                ACK_O <= 1'b1;
                                                tx_index_reg <= DAT_I[2:0];
                            
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {61'd0, tx_index_reg};
                                        end
                                    end

                                    8'h60: begin
                            
                                        if (WE_I) begin
                                            if (!SEL_I[0]) ERR_O <= 1'b1;
                                            else if (DAT_I[63:3] != 61'd0) ERR_O <= 1'b1;
                                            else begin
                                                ACK_O <= 1'b1;
                                                rx_index_reg <= DAT_I[2:0];
                                            end
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {61'd0, rx_index_reg};
                                        end
                                    end

                                    8'h68: begin
                            
                                        if (WE_I) begin
                                            ERR_O <= 1'b1;
                                        end else begin
                                            ACK_O <= 1'b1;
                                            DAT_O <= {42'd0, rx_index_reg, tx_index_reg, rx_valid_mask_reg, tx_written_mask_reg};
                                        end
                                    end

                                    default: ERR_O <= 1'b1;
                                endcase
                            
                            end
                        end



                        default: ERR_O <= 1'b1;
                    endcase
                end
            end

            // QSPI TRANSFER ENGINE
            // QSPI uses mode 0: data changes on falling edges and is sampled on rising edges.

            if (state_reg != ST_IDLE) begin
               
                if (state_reg == ST_FINISH) begin
               
                    if (divider_count_reg >= clk_div_reg) begin
               
                        QSPI_SCK_O <= 1'b0;
                        QSPI_CS_N_O <= 1'b1;
                        QSPI_IO_OE <= 4'b0000;
                        QSPI_IO_O <= 4'd0;
                        busy_reg <= 1'b0;
                        done_reg <= 1'b1;
                        state_reg <= ST_IDLE;
                        divider_count_reg <= 16'd0;

                        if (!write_mode_reg) begin
               
                            for (word_index = 0; word_index < 8; word_index = word_index + 1) begin
               
                                if (word_index < ((data_length_reg + 7) / 8)) begin
               
                                    if (data_length_reg >= ((word_index + 1) * 8)) begin
               
                                        shift_amount = (data_length_reg - ((word_index + 1) * 8)) * 8;
                                        rx_buffer[word_index] <= rx_shift_reg >> shift_amount;
                                    end else begin
               
                                        rx_buffer[word_index] <= rx_shift_reg[63:0] & (64'hFFFFFFFFFFFFFFFF >> ((8 - (data_length_reg - (word_index * 8))) * 8));
                                    end
                                    rx_valid_mask_reg[word_index] <= 1'b1;
               
                                end
               
                            end
               
                        end
               
               
                    end else begin
                        divider_count_reg <= divider_count_reg + 1'b1;
                    end
                end else if (divider_count_reg >= clk_div_reg) begin
                    divider_count_reg <= 16'd0;

                    if (!QSPI_SCK_O) begin
                        // Rising edge: sample input and advance phase counts.
                        QSPI_SCK_O <= 1'b1;

                        case (state_reg)
                            ST_CMD: begin
               
                                if (phase_count_reg == 10'd7) begin
                                    phase_count_reg <= 10'd0;
                                    if (address_length_reg != 3'd0) begin
                                        state_reg <= ST_ADDR;
               
                                    end else if (dummy_cycles_reg != 8'd0) begin
                                        state_reg <= ST_DUMMY;
               
                                        dummy_count_reg <= 8'd0;
                                    end else begin
                                        state_reg <= ST_DATA;
                                    end
                                end else begin
               
                                    phase_count_reg <= phase_count_reg + 1'b1;
                                end
                            end

                            ST_ADDR: begin
               
                                if (phase_count_reg >= (address_beats_reg - 1'b1)) begin
                                    phase_count_reg <= 10'd0;
               
                                    if (dummy_cycles_reg != 8'd0) begin
                                        state_reg <= ST_DUMMY;
                                        dummy_count_reg <= 8'd0;
                                    end else begin
                                        state_reg <= ST_DATA;
                                    end
               
                                end else begin
                                    phase_count_reg <= phase_count_reg + 1'b1;
                                end
                            end

                            ST_DUMMY: begin
               
                                if (dummy_count_reg >= (dummy_cycles_reg - 1'b1)) begin
                                    state_reg <= ST_DATA;
                                    phase_count_reg <= 10'd0;
                                end else begin
                                    dummy_count_reg <= dummy_count_reg + 1'b1;
                                end
               
                            end

                            ST_DATA: begin
                                if (!write_mode_reg) begin
                                    if (quad_data_reg) begin
                                        rx_shift_reg <= {rx_shift_reg[507:0], QSPI_IO_I};
                                    end else begin
                                        rx_shift_reg <= {rx_shift_reg[510:0], QSPI_IO_I[1]};
                                    end
                                end

                                if (phase_count_reg >= (data_beats_reg - 1'b1)) begin
                                    state_reg <= ST_FINISH;
                                end else begin
                                    phase_count_reg <= phase_count_reg + 1'b1;
                                end
                            end

                            default: begin
                                state_reg <= ST_FINISH;
                            end
                        endcase
                    end else begin
                        // Falling edge: drive the next command, address or data.
                        QSPI_SCK_O <= 1'b0;

                        case (state_reg)
                            ST_CMD: begin
                                QSPI_IO_O <= {3'b000, command_shift_reg[7]};
                                QSPI_IO_OE <= 4'b0001;
                                command_shift_reg <= {command_shift_reg[6:0], 1'b0};
                            end

                            ST_ADDR: begin
                                if (quad_address_reg) begin
                                    QSPI_IO_O <= address_shift_reg[31:28];
                                    QSPI_IO_OE <= 4'b1111;
                                    address_shift_reg <= {address_shift_reg[27:0], 4'b0000};
               
                                end else begin
                                    QSPI_IO_O <= {3'b000, address_shift_reg[31]};
                                    QSPI_IO_OE <= 4'b0001;
                                    address_shift_reg <= {address_shift_reg[30:0], 1'b0};
                                end
                            end

                            ST_DUMMY: begin
                                QSPI_IO_O <= 4'd0;
                                QSPI_IO_OE <= 4'b0000;
                            end

                            ST_DATA: begin
               
                                if (write_mode_reg) begin
                                    if (quad_data_reg) begin
                                        QSPI_IO_O <= tx_shift_reg[511:508];
                                        QSPI_IO_OE <= 4'b1111;
                                        tx_shift_reg <= {tx_shift_reg[507:0], 4'b0000};
               
                                    end else begin
                                        QSPI_IO_O <= {3'b000, tx_shift_reg[511]};
                                        QSPI_IO_OE <= 4'b0001;
                                        tx_shift_reg <= {tx_shift_reg[510:0], 1'b0};
                                    end
                                end else begin
                                    QSPI_IO_O <= 4'd0;
                                    QSPI_IO_OE <= 4'b0000;
                                end
                            end

                            default: begin
                                QSPI_IO_OE <= 4'b0000;
                            end
                        endcase
                    end
                end else begin
                    divider_count_reg <= divider_count_reg + 1'b1;
                end
            end
        
        
        end

    end

endmodule