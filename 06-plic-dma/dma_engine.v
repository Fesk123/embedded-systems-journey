`timescale 1ns/1ps

module dma_engine (

    input CLK_I,
    input RST_I,

    // DMA CONTROL INTERFACE

    input START_I,
    input [63:0] SRC_I,
    input [63:0] DST_I,
    input [63:0] LENGTH_I,
    output BUSY_O,
    output reg DONE_O,
    output reg ERROR_O,
    output reg [2:0] ERROR_CODE_O,


    // WISHBONE MASTER INTERFACE


    output [63:0] WB_ADR_O,
    output [63:0] WB_DAT_O,
    input [63:0] WB_DAT_I,
    output [7:0] WB_SEL_O,
    output WB_CYC_O,
    output WB_STB_O,
    output WB_WE_O,
    input WB_ACK_I,
    input WB_ERR_I

);
    // DMA STATES

    localparam STATE_IDLE  = 3'd0;
    localparam STATE_READ  = 3'd1;
    localparam STATE_WRITE = 3'd2;

    reg [2:0] state;

    // DMA REGISTERS

    reg [63:0] current_src;
    reg [63:0] current_dst;
    reg [63:0] remaining;

    reg [63:0] data_buffer;
    reg [7:0] write_sel;
    reg [15:0] timeout_counter;

    function [7:0] byte_mask;

        input [63:0] count;

        begin

            case (count)
                64'd1: byte_mask = 8'b0000_0001;
                64'd2: byte_mask = 8'b0000_0011;
                64'd3: byte_mask = 8'b0000_0111;
                64'd4: byte_mask = 8'b0000_1111;

                64'd5: byte_mask = 8'b0001_1111;
                64'd6: byte_mask = 8'b0011_1111;
                64'd7: byte_mask = 8'b0111_1111;
                default: byte_mask = 8'b1111_1111;
            endcase

        end

    endfunction

    assign BUSY_O = (state != STATE_IDLE);

    assign WB_ADR_O = (state == STATE_READ) ? current_src : current_dst;
    assign WB_DAT_O = data_buffer;
    assign WB_SEL_O = (state == STATE_WRITE) ? write_sel : 8'hFF;

    assign WB_CYC_O = (state == STATE_READ) || (state == STATE_WRITE);
    assign WB_STB_O = (state == STATE_READ) || (state == STATE_WRITE);
    assign WB_WE_O  = (state == STATE_WRITE);


    // DMA TRANSFER CONTROL


    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            state <= STATE_IDLE;
            current_src <= 64'd0;
            current_dst <= 64'd0;
            remaining <= 64'd0;
            data_buffer <= 64'd0;

            write_sel <= 8'hFF;
            timeout_counter <= 16'd0;
            DONE_O <= 1'b0;
            ERROR_O <= 1'b0;
            ERROR_CODE_O <= 3'd0;

        end
        else begin

            DONE_O <= 1'b0;
            ERROR_O <= 1'b0;

            case (state)

                STATE_IDLE: begin

                    timeout_counter <= 16'd0;

                    if (START_I) begin

                        if ((LENGTH_I == 64'd0) || (SRC_I[2:0] != 3'b000) || (DST_I[2:0] != 3'b000)) begin
                            ERROR_O <= 1'b1;
                            ERROR_CODE_O <= 3'd1;
                        end

                        else begin
                            current_src <= SRC_I;
                            current_dst <= DST_I;
                            remaining <= LENGTH_I;
                            state <= STATE_READ;
                            ERROR_CODE_O <= 3'd0;
                        end
                    end


                end

                STATE_READ: begin

                    if (WB_ERR_I) begin
                        state <= STATE_IDLE;
                        ERROR_O <= 1'b1;
                        ERROR_CODE_O <= 3'd2;
                        timeout_counter <= 16'd0;
                    end

                    else if (WB_ACK_I) begin
                        data_buffer <= WB_DAT_I;
                        write_sel <= byte_mask(remaining);
                        state <= STATE_WRITE;
                        timeout_counter <= 16'd0;
                    end
                    
                    else if (timeout_counter == 16'hFFFE) begin
                        state <= STATE_IDLE;
                        ERROR_O <= 1'b1;
                        ERROR_CODE_O <= 3'd3;
                        timeout_counter <= 16'd0;
                    end

                    else begin
                        timeout_counter <= timeout_counter + 16'd1;
                    end

                end

                STATE_WRITE: begin

                    if (WB_ERR_I) begin
                        state <= STATE_IDLE;
                        ERROR_O <= 1'b1;
                        ERROR_CODE_O <= 3'd2;
                        timeout_counter <= 16'd0;
                    end

                    else if (WB_ACK_I) begin

                        timeout_counter <= 16'd0;

                        if (remaining <= 64'd8) begin
                            remaining <= 64'd0;
                            state <= STATE_IDLE;
                            DONE_O <= 1'b1;
                        end

                        else begin
                            current_src <= current_src + 64'd8;
                            current_dst <= current_dst + 64'd8;
                            remaining <= remaining - 64'd8;
                            state <= STATE_READ;
                        end

                    end

                    else if (timeout_counter == 16'hFFFE) begin
                        state <= STATE_IDLE;
                        ERROR_O <= 1'b1;
                        ERROR_CODE_O <= 3'd3;
                        timeout_counter <= 16'd0;
                    end

                    else begin
                        timeout_counter <= timeout_counter + 16'd1;
                    end

                end

                default: begin
                    state <= STATE_IDLE;
                end

          endcase

        end

    end


endmodule