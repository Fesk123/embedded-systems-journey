`timescale 1ns/1ps

module wb_arbiter (

    input CLK_I,
    input RST_I,

    // CPU WISHBONE MASTER

    input [63:0] CPU_ADR_I,
    input [63:0] CPU_DAT_I,
    output [63:0] CPU_DAT_O,
    
    input [7:0] CPU_SEL_I,
    input CPU_CYC_I,
    input CPU_STB_I,
    input CPU_WE_I,
    output CPU_ACK_O,
    output CPU_ERR_O,


    // DMA WISHBONE MASTER


    input [63:0] DMA_ADR_I,
    input [63:0] DMA_DAT_I,
    output [63:0] DMA_DAT_O,
    input [7:0] DMA_SEL_I,
    
    input DMA_CYC_I,
    input DMA_STB_I,
    input DMA_WE_I,
    output DMA_ACK_O,
    output DMA_ERR_O,


    // SHARED WISHBONE SLAVE INTERFACE


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
    localparam STATE_CPU  = 2'd1;
    localparam STATE_DMA  = 2'd2;

    reg [1:0] state;
    reg prefer_dma;

    // WISHBONE REQUEST SELECTION

    always @(*) begin

        WB_ADR_O = 64'd0;
        WB_DAT_O = 64'd0;
        WB_SEL_O = 8'd0;
        WB_CYC_O = 1'b0;
        WB_STB_O = 1'b0;
        WB_WE_O = 1'b0;

        case (state)

            STATE_CPU: begin
        
                WB_ADR_O = CPU_ADR_I;
                WB_DAT_O = CPU_DAT_I;
                WB_SEL_O = CPU_SEL_I;
                WB_CYC_O = CPU_CYC_I;
                WB_STB_O = CPU_STB_I;
                WB_WE_O = CPU_WE_I;
        
            end
        
            STATE_DMA: begin
        
                WB_ADR_O = DMA_ADR_I;
                WB_DAT_O = DMA_DAT_I;
                WB_SEL_O = DMA_SEL_I;
                WB_CYC_O = DMA_CYC_I;
                WB_STB_O = DMA_STB_I;
        
                WB_WE_O = DMA_WE_I;
        
            end
            default: begin end
        endcase


    end

    assign CPU_DAT_O = WB_DAT_I;
    assign DMA_DAT_O = WB_DAT_I;

    assign CPU_ACK_O = (state == STATE_CPU) && WB_ACK_I;
    assign CPU_ERR_O = (state == STATE_CPU) && WB_ERR_I;
    assign DMA_ACK_O = (state == STATE_DMA) && WB_ACK_I;
    assign DMA_ERR_O = (state == STATE_DMA) && WB_ERR_I;

    // ROUND-ROBIN ARBITRATION

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin
            state <= STATE_IDLE;
            prefer_dma <= 1'b0;
        end

        else begin

            case (state)
                STATE_IDLE: begin

                    if (CPU_CYC_I && CPU_STB_I && DMA_CYC_I && DMA_STB_I) begin

                        if (prefer_dma) begin
                            state <= STATE_DMA;
                        end

                        else begin
                            state <= STATE_CPU;
                        end

                    end

                    else if (CPU_CYC_I && CPU_STB_I) begin

                        state <= STATE_CPU;
                    end

                    else if (DMA_CYC_I && DMA_STB_I) begin
                        state <= STATE_DMA;

                    end

                end

                STATE_CPU: begin
                    if (!CPU_CYC_I || !CPU_STB_I || WB_ACK_I || WB_ERR_I) begin

                        state <= STATE_IDLE;
                        prefer_dma <= 1'b1;
                    end

                end

                STATE_DMA: begin

                    if (!DMA_CYC_I || !DMA_STB_I || WB_ACK_I || WB_ERR_I) begin
                        state <= STATE_IDLE;
                        prefer_dma <= 1'b0;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end



    end

endmodule