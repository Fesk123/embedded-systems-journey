`timescale 1ns/1ps

module dma_controller (

    input CLK_I,
    input RST_I,


    // WISHBONE SLAVE INTERFACE


    input [63:0] ADR_I,
    input [63:0] DAT_I,
    output [63:0] DAT_O,
    input [7:0] SEL_I,
    input CYC_I,
    input STB_I,
    input WE_I,
    output reg ACK_O,
    output reg ERR_O,


    // DMA ENGINE INTERFACE


    output reg ENGINE_START_O,
    output reg [63:0] ENGINE_SRC_O,
    output reg [63:0] ENGINE_DST_O,
    output reg [63:0] ENGINE_LENGTH_O,
    input ENGINE_BUSY_I,
    input ENGINE_DONE_I,
    input ENGINE_ERROR_I,

    // DESCRIPTOR INTERFACE

    output reg DESCRIPTOR_START_O,
    output reg [63:0] DESCRIPTOR_ADDRESS_O,
    input DESCRIPTOR_BUSY_I,
    input DESCRIPTOR_VALID_I,
    input DESCRIPTOR_ERROR_I,
    input [63:0] DESCRIPTOR_SRC_I,
    input [63:0] DESCRIPTOR_DST_I,
    input [63:0] DESCRIPTOR_LENGTH_I,
    input [63:0] DESCRIPTOR_CONTROL_I,
    input [63:0] DESCRIPTOR_NEXT_I,

    // CHANNEL INTERRUPTS

    output [3:0] IRQ_O

);


    // DMA REGISTER MAP

    // Each channel occupies 0x40 bytes.
    // 0x00: Source address
    // 0x08: Destination address
    // 0x10: Length in bytes
    // 0x18: Control (bit 0 = start, bit 1 = descriptor mode)
    // 0x20: Status (bit 0 = busy, bit 1 = done, bit 2 = error)
    // 0x28: Descriptor address
    // 0x30: Interrupt status (write 1 to clear)

    localparam CTRL_IDLE = 2'd0;
    localparam CTRL_DESC_WAIT = 2'd1;
    localparam CTRL_ENGINE_WAIT = 2'd2;

    reg [1:0] controller_state;

    reg [63:0] channel_src [0:3];
    reg [63:0] channel_dst [0:3];
    reg [63:0] channel_length [0:3];
    reg [63:0] channel_control [0:3];
    reg [63:0] channel_descriptor [0:3];
    reg [2:0] channel_status [0:3];
    reg [1:0] channel_irq_status [0:3];

    reg [3:0] pending_start;
    reg [1:0] active_channel;
    reg [1:0] next_channel;
    reg active_descriptor_mode;
    reg [63:0] active_descriptor_next;

    reg wb_seen;

    integer reset_index;

    wire [1:0] wb_channel = ADR_I[7:6];
    wire [5:0] wb_offset = ADR_I[5:0];

    function [2:0] find_next_channel;

        input [3:0] pending;
        input [1:0] start_from;
        integer k;

        reg [1:0] index;
        reg found;

        begin

            find_next_channel = 3'b100;
            found = 1'b0;

            for (k = 0; k < 4; k = k + 1) begin

                index = start_from + k;

                if (pending[index] && !found) begin

                    find_next_channel = {1'b0, index};
                    found = 1'b1;

                end

            end


        end

    endfunction

    wire [2:0] selected_channel = find_next_channel(pending_start, next_channel);


    // WISHBONE READ DATA


    reg [63:0] dat_o_reg;
    assign DAT_O = dat_o_reg;

    always @(*) begin

        dat_o_reg = 64'd0;

        if (ADR_I[63:8] == 56'd0) begin

            case (wb_offset)
                6'h00: dat_o_reg = channel_src[wb_channel];
                6'h08: dat_o_reg = channel_dst[wb_channel];
                6'h10: dat_o_reg = channel_length[wb_channel];
                6'h18: dat_o_reg = channel_control[wb_channel];

                6'h20: dat_o_reg[2:0] = channel_status[wb_channel];
                6'h28: dat_o_reg = channel_descriptor[wb_channel];
                6'h30: dat_o_reg[1:0] = channel_irq_status[wb_channel];
                default: dat_o_reg = 64'd0;
            endcase

        end

    end

    assign IRQ_O[0] = |channel_irq_status[0];
    assign IRQ_O[1] = |channel_irq_status[1];
    assign IRQ_O[2] = |channel_irq_status[2];
    assign IRQ_O[3] = |channel_irq_status[3];


    // DMA REGISTER AND TRANSFER CONTROL


    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            wb_seen <= 1'b0;

            ENGINE_START_O <= 1'b0;
            ENGINE_SRC_O <= 64'd0;
            ENGINE_DST_O <= 64'd0;
            ENGINE_LENGTH_O <= 64'd0;

            DESCRIPTOR_START_O <= 1'b0;
            DESCRIPTOR_ADDRESS_O <= 64'd0;

            controller_state <= CTRL_IDLE;
            pending_start <= 4'd0;
            active_channel <= 2'd0;
            next_channel <= 2'd0;
            active_descriptor_mode <= 1'b0;
            active_descriptor_next <= 64'd0;

            for (reset_index = 0; reset_index < 4; reset_index = reset_index + 1) begin

                channel_src[reset_index] <= 64'd0;
                channel_dst[reset_index] <= 64'd0;
                channel_length[reset_index] <= 64'd0;
                channel_control[reset_index] <= 64'd0;

                channel_descriptor[reset_index] <= 64'd0;
                channel_status[reset_index] <= 3'b000;
                channel_irq_status[reset_index] <= 2'b00;

            end

        end
        else begin

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            ENGINE_START_O <= 1'b0;
            DESCRIPTOR_START_O <= 1'b0;

            // Wishbone register access

            if (!CYC_I || !STB_I) begin

                wb_seen <= 1'b0;

            end

            else if (!wb_seen) begin

                wb_seen <= 1'b1;

                if ((ADR_I[63:8] != 56'd0) || (ADR_I[2:0] != 3'b000)) begin

                    ERR_O <= 1'b1;

                end

                else if ((wb_offset == 6'h00) || (wb_offset == 6'h08) || (wb_offset == 6'h10) || (wb_offset == 6'h18) || (wb_offset == 6'h20) || (wb_offset == 6'h28) || (wb_offset == 6'h30)) begin

                    ACK_O <= 1'b1;

                    if (WE_I && SEL_I[0]) begin

                        case (wb_offset)

                            6'h00: channel_src[wb_channel] <= DAT_I;
                            6'h08: channel_dst[wb_channel] <= DAT_I;
                            6'h10: channel_length[wb_channel] <= DAT_I;

                            6'h18: begin

                                channel_control[wb_channel] <= DAT_I & 64'hFFFF_FFFF_FFFF_FFFE;

                                if (DAT_I[0]) begin
                                    pending_start[wb_channel] <= 1'b1;
                                    channel_status[wb_channel] <= 3'b000;
                                end
                            end

                            6'h28: channel_descriptor[wb_channel] <= DAT_I;
                            6'h30: channel_irq_status[wb_channel] <= channel_irq_status[wb_channel] & ~DAT_I[1:0];
                            default: begin end

                        endcase
                    end

                end
                else begin
                    ERR_O <= 1'b1;
                end

            end


            // Channel scheduler


            case (controller_state)

                CTRL_IDLE: begin

                    if (selected_channel[2] == 1'b0) begin

                        active_channel <= selected_channel[1:0];
                        next_channel <= selected_channel[1:0] + 2'd1;
                        active_descriptor_mode <= channel_control[selected_channel[1:0]][1];

                        active_descriptor_next <= 64'd0;
                        pending_start[selected_channel[1:0]] <= 1'b0;
                        channel_status[selected_channel[1:0]] <= 3'b001;

                        if (channel_control[selected_channel[1:0]][1]) begin

                            DESCRIPTOR_ADDRESS_O <= channel_descriptor[selected_channel[1:0]];
                            DESCRIPTOR_START_O <= 1'b1;
                            controller_state <= CTRL_DESC_WAIT;

                        end

                        else begin

                            ENGINE_SRC_O <= channel_src[selected_channel[1:0]];
                            ENGINE_DST_O <= channel_dst[selected_channel[1:0]];
                            ENGINE_LENGTH_O <= channel_length[selected_channel[1:0]];

                            ENGINE_START_O <= 1'b1;
                            controller_state <= CTRL_ENGINE_WAIT;

                        end

                    end

                end

                CTRL_DESC_WAIT: begin

                    if (DESCRIPTOR_ERROR_I) begin
                        channel_status[active_channel] <= 3'b100;
                        channel_irq_status[active_channel][1] <= 1'b1;
                        controller_state <= CTRL_IDLE;
                    end

                    else if (DESCRIPTOR_VALID_I) begin
                        ENGINE_SRC_O <= DESCRIPTOR_SRC_I;
                        ENGINE_DST_O <= DESCRIPTOR_DST_I;
                        ENGINE_LENGTH_O <= DESCRIPTOR_LENGTH_I;

                        active_descriptor_next <= DESCRIPTOR_NEXT_I;
                        ENGINE_START_O <= 1'b1;
                        controller_state <= CTRL_ENGINE_WAIT;
                    end

                end

                CTRL_ENGINE_WAIT: begin

                    if (ENGINE_ERROR_I) begin
                        channel_status[active_channel] <= 3'b100;
                        channel_irq_status[active_channel][1] <= 1'b1;
                        controller_state <= CTRL_IDLE;
                    end

                    else if (ENGINE_DONE_I) begin

                        if (active_descriptor_mode && (active_descriptor_next != 64'd0)) begin
                            channel_descriptor[active_channel] <= active_descriptor_next;
                            DESCRIPTOR_ADDRESS_O <= active_descriptor_next;

                            DESCRIPTOR_START_O <= 1'b1;
                            controller_state <= CTRL_DESC_WAIT;
                        end

                        else begin
                            channel_status[active_channel] <= 3'b010;
                            channel_irq_status[active_channel][0] <= 1'b1;
                            controller_state <= CTRL_IDLE;
                        end
                    end
                end

                default: begin
                    controller_state <= CTRL_IDLE;
                end

            endcase

        end


    end


endmodule