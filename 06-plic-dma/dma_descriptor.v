`timescale 1ns/1ps

module dma_descriptor (

    input CLK_I,
    input RST_I,

    // DESCRIPTOR CONTROL INTERFACE

    input START_I,
    input [63:0] DESCRIPTOR_ADDRESS_I,
    output reg BUSY_O,
    output reg VALID_O,
    output reg ERROR_O,

    output reg [63:0] SRC_O,
    output reg [63:0] DST_O,
    output reg [63:0] LENGTH_O,
    output reg [63:0] CONTROL_O,
    output reg [63:0] NEXT_O,

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

    // DESCRIPTOR STATES

    localparam STATE_IDLE = 2'd0;
    localparam STATE_READ = 2'd1;

    reg [1:0] state;
    reg [63:0] descriptor_address;
    reg [2:0] word_index;
    reg [15:0] timeout_counter;

    assign WB_ADR_O = descriptor_address + {58'd0, word_index, 3'b000};
    assign WB_DAT_O = 64'd0;
    assign WB_SEL_O = 8'hFF;
    assign WB_CYC_O = (state == STATE_READ);
    assign WB_STB_O = (state == STATE_READ);
    assign WB_WE_O  = 1'b0;

    // DESCRIPTOR FORMAT

    // Word 0: source address
    // Word 1: destination address
    // Word 2: transfer length in bytes
    // Word 3: control flags
    // Word 4: address of the next descriptor, or zero

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            state <= STATE_IDLE;
            descriptor_address <= 64'd0;
            word_index <= 3'd0;
            timeout_counter <= 16'd0;

            BUSY_O <= 1'b0;
            VALID_O <= 1'b0;
            ERROR_O <= 1'b0;
            SRC_O <= 64'd0;
            DST_O <= 64'd0;

            LENGTH_O <= 64'd0;
            CONTROL_O <= 64'd0;
            NEXT_O <= 64'd0;

        end
        else begin

            VALID_O <= 1'b0;
            ERROR_O <= 1'b0;

            case (state)

                STATE_IDLE: begin

                    BUSY_O <= 1'b0;
                    timeout_counter <= 16'd0;

                    if (START_I) begin

                        if (DESCRIPTOR_ADDRESS_I[2:0] != 3'b000) begin
                            ERROR_O <= 1'b1;
                        end

                        else begin
                            descriptor_address <= DESCRIPTOR_ADDRESS_I;
                            word_index <= 3'd0;
                            BUSY_O <= 1'b1;
                            state <= STATE_READ;
                        end
                    end


                end

                STATE_READ: begin

                    if (WB_ERR_I) begin
                        state <= STATE_IDLE;
                        BUSY_O <= 1'b0;
                        ERROR_O <= 1'b1;
                        timeout_counter <= 16'd0;
                    end

                    else if (WB_ACK_I) begin

                        timeout_counter <= 16'd0;

                        case (word_index)
                            3'd0: SRC_O <= WB_DAT_I;
                            3'd1: DST_O <= WB_DAT_I;
                            3'd2: LENGTH_O <= WB_DAT_I;
                            3'd3: CONTROL_O <= WB_DAT_I;
                            3'd4: NEXT_O <= WB_DAT_I;
                            default: begin end
                        endcase

                        if (word_index == 3'd4) begin

                            state <= STATE_IDLE;
                            BUSY_O <= 1'b0;
                            VALID_O <= 1'b1;
                        end

                        else begin
                            word_index <= word_index + 3'd1;
                        end

                    end
                    else if (timeout_counter == 16'hFFFE) begin
                        state <= STATE_IDLE;
                        BUSY_O <= 1'b0;
                        ERROR_O <= 1'b1;
                        timeout_counter <= 16'd0;
                    end

                    else begin
                        timeout_counter <= timeout_counter + 16'd1;
                    end

                end

                default: begin
                    state <= STATE_IDLE;
                    BUSY_O <= 1'b0;
                end
            endcase
        end
    end
endmodule