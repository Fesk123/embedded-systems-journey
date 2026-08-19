module Interrupt_Controller (
    // Wishbone B4 Classic Synchronous interface
    input CLK_I,
    input RST_I,

    input [15:0] ADR_I,
    input [7:0] DAT_I,
    output reg [7:0] DAT_O,

    input CYC_I,
    input STB_I,
    input WE_I,
    output reg ACK_O,

    // Generic interrupt inputs
    // 0 = UART
    // 1 = GPIO
    // 2 = TIMER
    // 3 = RESERVED
    input [3:0] IRQ_I,

    // Interrupt output to CPU
    output IRQ_O
);


    // Register addresses

    localparam ADDR_IRQ_PENDING = 16'h0000;
    localparam ADDR_IRQ_MASK = 16'h0004;
    localparam ADDR_IRQ_STATUS = 16'h0008;
    localparam ADDR_IRQ_CLEAR = 16'h000C;


    // Registers

    // Pending interrupts
    reg [3:0] irq_pending;

    // Interrupt mask
    reg [3:0] irq_mask;


    // Wishbone transaction

    wire wb_access;

    assign wb_access = CYC_I && STB_I;


    // IRQ STATUS

    wire [3:0] irq_status;

    assign irq_status = IRQ_I;


    // Combined interrupt output
    // Only pending AND unmasked interrupts reach the CPU.

    assign IRQ_O = |(irq_pending & irq_mask);


    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            irq_pending <= 4'b0000;
            irq_mask <= 4'b0000;

            ACK_O <= 1'b0;

        end

        else begin

            ACK_O <= 1'b0;


            // Wishbone access

            if (wb_access) begin

                ACK_O <= 1'b1;


                // WRITE

                if (WE_I) begin

                    case (ADR_I)

                        // IRQ_MASK
                        // Write 1 = enable interrupt
                        // Write 0 = disable interrupt
                        ADDR_IRQ_MASK: begin
                            irq_mask <= DAT_I[3:0];
                        end


                        // IRQ_CLEAR
                        // Write 1 to a bit to clear that pending interrupt.
                        ADDR_IRQ_CLEAR: begin
                            irq_pending <= irq_pending & ~DAT_I[3:0];
                        end


                        default: begin
                            // No writable register
                        end

                    endcase

                end


            end


            // Level-triggered interrupt handling

            irq_pending <= irq_pending | IRQ_I;


            // Clear has priority over the automatic set only when the IRQ input is LOW.
            // If IRQ_I is still HIGH, it remains pending.

            if (wb_access && WE_I &&
                (ADR_I == ADDR_IRQ_CLEAR)) begin

                irq_pending <=
                    (irq_pending & ~DAT_I[3:0]) | IRQ_I;

            end

        end
    end


    // Read multiplexer

    always @(*) begin

        DAT_O = 8'h00;

        if (CYC_I && STB_I && !WE_I) begin

            case (ADR_I)

                // 0x00 - IRQ_PENDING
                ADDR_IRQ_PENDING: begin
                    DAT_O = {4'b0000, irq_pending};
                end


                // 0x04 - IRQ_MASK
                ADDR_IRQ_MASK: begin
                    DAT_O = {4'b0000, irq_mask};
                end


                // 0x08 - IRQ_STATUS
                ADDR_IRQ_STATUS: begin
                    DAT_O = {4'b0000, irq_status};
                end


                // 0x0C - IRQ_CLEAR
                // This register is write-only.
                ADDR_IRQ_CLEAR: begin
                    DAT_O = 8'h00;
                end


                default: begin
                    DAT_O = 8'h00;
                end

            endcase

        end

    end

endmodule