`timescale 1ns/1ps

module dma_arbiter (

    input CLK_I,
    input RST_I,

    // DMA ENGINE MASTER

    input [63:0] M0_ADR_I,
    input [63:0] M0_DAT_I,
    output [63:0] M0_DAT_O,
    input [7:0] M0_SEL_I,
    input M0_CYC_I,
    input M0_STB_I,
    input M0_WE_I,
    output M0_ACK_O,
    output M0_ERR_O,

    // DESCRIPTOR MASTER

    input [63:0] M1_ADR_I,
    input [63:0] M1_DAT_I,
    output [63:0] M1_DAT_O,
    input [7:0] M1_SEL_I,

    input M1_CYC_I,
    input M1_STB_I,
    input M1_WE_I,
    output M1_ACK_O,
    output M1_ERR_O,

    // SHARED WISHBONE MASTER INTERFACE

    output reg [63:0] WB_ADR_O,
    output reg [63:0] WB_DAT_O,
    input [63:0] WB_DAT_I,
    output reg [7:0] WB_SEL_O,

    output reg WB_CYC_O,
    output reg WB_STB_O,
    output reg WB_WE_O,
    input WB_ACK_I,
    input WB_ERR_I

);

    // ARBITER STATES

    localparam STATE_IDLE = 2'd0;
    localparam STATE_M0 = 2'd1;
    localparam STATE_M1 = 2'd2;

    reg [1:0] state;
    reg prefer_m1;

    // WISHBONE REQUEST SELECTION

    always @(*) begin

        WB_ADR_O = 64'd0;
        WB_DAT_O = 64'd0;
        WB_SEL_O = 8'd0;

        WB_CYC_O = 1'b0;
        WB_STB_O = 1'b0;
        WB_WE_O = 1'b0;

        case (state)

            STATE_M0: begin
                WB_ADR_O = M0_ADR_I;
                WB_DAT_O = M0_DAT_I;
                WB_SEL_O = M0_SEL_I;
                WB_CYC_O = M0_CYC_I;
                WB_STB_O = M0_STB_I;
                WB_WE_O = M0_WE_I;
            end

            STATE_M1: begin
                WB_ADR_O = M1_ADR_I;
                WB_DAT_O = M1_DAT_I;
                WB_SEL_O = M1_SEL_I;
                WB_CYC_O = M1_CYC_I;
                WB_STB_O = M1_STB_I;
                WB_WE_O = M1_WE_I;
            end

            default: begin end

        endcase

    end

    assign M0_DAT_O = WB_DAT_I;
    assign M1_DAT_O = WB_DAT_I;

    assign M0_ACK_O = (state == STATE_M0) && WB_ACK_I;
    assign M0_ERR_O = (state == STATE_M0) && WB_ERR_I;
    assign M1_ACK_O = (state == STATE_M1) && WB_ACK_I;
    assign M1_ERR_O = (state == STATE_M1) && WB_ERR_I;


    // ROUND-ROBIN ARBITRATION


    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            state <= STATE_IDLE;
            prefer_m1 <= 1'b0;

        end

        else begin

            case (state)

                STATE_IDLE: begin

                    if (M0_CYC_I && M0_STB_I && M1_CYC_I && M1_STB_I) begin

                        if (prefer_m1) begin
                            state <= STATE_M1;
                        end

                        else begin
                            state <= STATE_M0;
                        end

                    end

                    else if (M0_CYC_I && M0_STB_I) begin
                        state <= STATE_M0;
                    end

                    else if (M1_CYC_I && M1_STB_I) begin
                        state <= STATE_M1;
                    end
                end

                STATE_M0: begin
                    
                    if (!M0_CYC_I || !M0_STB_I || WB_ACK_I || WB_ERR_I) begin
                        state <= STATE_IDLE;
                        prefer_m1 <= 1'b1;
                    
                    end
                end

                STATE_M1: begin
                    
                    if (!M1_CYC_I || !M1_STB_I || WB_ACK_I || WB_ERR_I) begin
                        state <= STATE_IDLE;
                        prefer_m1 <= 1'b0;
                    
                    end
                end

                default: begin
                    
                    state <= STATE_IDLE;
                end

            endcase
        end
    end


endmodule