`timescale 1ns/1ps

module plic (

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

    // INTERRUPT INTERFACE

    input [31:0] IRQ_I,
    output IRQ_O

);

    // PLIC REGISTERS
    reg [2:0] source_priority [0:31];
    reg [31:0] irq_pending;
    reg [31:0] irq_enable;
    reg [2:0] threshold;

    reg [31:0] irq_sync_1;
    reg [31:0] irq_sync_2;

    reg wb_seen;

    reg [5:0] claim_id;
    reg [2:0] best_source_priority;
    integer i;
    integer reset_index;

    // REGISTER MAP

    // Each register occupies 8 bytes on the 64-bit Wishbone bus.
    // Priority: 0x000 + source * 8
    // Pending: 0x1000
    // Enable: 0x2000
    // Threshold: 0x200000
    // Claim: 0x200008

    always @(*) begin

        claim_id = 6'd0;
        best_source_priority = threshold;

        for (i = 1; i < 32; i = i + 1) begin

            if (irq_pending[i] && irq_enable[i] && (source_priority[i] > best_source_priority)) begin
                best_source_priority = source_priority[i];
                claim_id = i[5:0];
            end

        end

    end

    assign IRQ_O = (claim_id != 6'd0);


    // WISHBONE READ DATA

    reg [63:0] dat_o_reg;
    assign DAT_O = dat_o_reg;

    always @(*) begin

        dat_o_reg = 64'd0;

        if (ADR_I[63:24] == 40'd0) begin

            if ((ADR_I[23:3] <= 21'd31) && (ADR_I[2:0] == 3'b000)) begin
                dat_o_reg[2:0] = source_priority[ADR_I[7:3]];
            end

            else if (ADR_I[23:0] == 24'h001000) begin
                dat_o_reg[31:0] = irq_pending;

            end

            else if (ADR_I[23:0] == 24'h002000) begin
                dat_o_reg[31:0] = irq_enable;
            end

            else if (ADR_I[23:0] == 24'h200000) begin
                dat_o_reg[2:0] = threshold;

            end

            else if (ADR_I[23:0] == 24'h200008) begin

                dat_o_reg[5:0] = claim_id;
            end

        end


    end


    // PLIC CONTROL


    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            wb_seen <= 1'b0;

            irq_sync_1 <= 32'd0;
            irq_sync_2 <= 32'd0;
            irq_pending <= 32'd0;
            irq_enable <= 32'd0;
            threshold <= 3'd0;

            for (reset_index = 0; reset_index < 32; reset_index = reset_index + 1) begin

                source_priority[reset_index] <= 3'd0;
            end

        end
        else begin

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;

            irq_sync_1 <= IRQ_I;
            irq_sync_2 <= irq_sync_1;
            irq_pending <= irq_pending | irq_sync_2;

            if (!CYC_I || !STB_I) begin
                wb_seen <= 1'b0;
            end

            else if (!wb_seen) begin

                wb_seen <= 1'b1;

                if ((ADR_I[2:0] != 3'b000) || (ADR_I[63:24] != 40'd0)) begin
                    ERR_O <= 1'b1;
                end

                else if ((ADR_I[23:3] <= 21'd31) || (ADR_I[23:0] == 24'h001000) || (ADR_I[23:0] == 24'h002000) || (ADR_I[23:0] == 24'h200000) || (ADR_I[23:0] == 24'h200008)) begin

                    ACK_O <= 1'b1;

                    if (WE_I) begin
                        if (SEL_I[0]) begin

                            if ((ADR_I[23:3] <= 21'd31) && (ADR_I[7:3] != 5'd0)) begin
                                source_priority[ADR_I[7:3]] <= DAT_I[2:0];
                            end

                            else if (ADR_I[23:0] == 24'h002000) begin
                                irq_enable <= DAT_I[31:0] & 32'hFFFF_FFFE;
                            end

                            else if (ADR_I[23:0] == 24'h200000) begin
                                threshold <= DAT_I[2:0];
                            end

                            else if (ADR_I[23:0] == 24'h200008) begin
                                // A write to the claim register completes the interrupt.
                                // Pending is cleared when the interrupt is claimed.
                            end

                        end
                    end
                    else if (ADR_I[23:0] == 24'h200008) begin

                        if (claim_id != 6'd0) begin
                            irq_pending <= (irq_pending | irq_sync_2) & ~(32'h0000_0001 << claim_id);
                        end

                    end


                end

                else begin
                    ERR_O <= 1'b1;
                end


            end


        end



    end

endmodule