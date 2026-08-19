module Hardware_Timer #(
    parameter CLK_FREQ = 50_000_000
)(
    input CLK_I,
    input RST_I,

    // Wishbone 8-bit interface
    input [15:0] ADR_I,
    input [7:0] DAT_I,
    output reg [7:0] DAT_O,

    input CYC_I,
    input STB_I,
    input WE_I,
    output reg ACK_O,

    // Interrupt
    output reg timer_irq
);

    // Register addresses
    localparam ADDR_CONTROL = 16'h0000;
    localparam ADDR_STATUS = 16'h0001;

    // 32-bit period split into 4 bytes
    localparam ADDR_PER_0 = 16'h0004; // LSB
    localparam ADDR_PER_1 = 16'h0005;
    localparam ADDR_PER_2 = 16'h0006;
    localparam ADDR_PER_3 = 16'h0007; // MSB
    // LSB = Least Significant Byte
    // MSB = Most Significant Byte

    // Timer internal registers
    reg [31:0] counter;
    reg [31:0] period;

    reg enable;
    reg irq_enable;
    reg status;

    // Wishbone Write & Timer
    always @(posedge CLK_I or posedge RST_I) begin
        if (RST_I) begin
            counter <= 32'd0;
            period <= 32'd0;
            enable <= 1'b0;
            irq_enable <= 1'b0;
            status <= 1'b0;
            timer_irq <= 1'b0;
            ACK_O <= 1'b0;
        end else begin
            if (CYC_I && STB_I && !ACK_O) begin
                ACK_O <= 1'b1;
            end else begin
                ACK_O <= 1'b0;
            end

            // Wishbone write
            if (CYC_I && STB_I && WE_I && !ACK_O) begin
                case (ADR_I)
                    ADDR_CONTROL: begin
                        enable <= DAT_I[0];
                        irq_enable <= DAT_I[1];
                    end
                    ADDR_PER_0: period[7:0] <= DAT_I;
                    ADDR_PER_1: period[15:8] <= DAT_I;
                    ADDR_PER_2: period[23:16] <= DAT_I;
                    ADDR_PER_3: period[31:24] <= DAT_I;
                    ADDR_STATUS: begin
                        if (DAT_I[0]) begin
                            status <= 1'b0;
                            timer_irq <= 1'b0;
                        end
                    end
                endcase
            end

            // Timer logic
            if (enable) begin
                // period - 1 prevents clock drift
                if (counter >= (period - 1'b1)) begin
                    counter <= 32'd0;
                    status <= 1'b1;
                    if (irq_enable) begin
                        timer_irq <= 1'b1;
                    end
                end else begin
                    counter <= counter + 1'b1;
                end
            end else begin
                counter <= 32'd0;
            end
        end
    end

    // Combinational Wishbone Read
    always @(*) begin
        DAT_O = 8'h00;
        if (CYC_I && STB_I && !WE_I) begin
            case (ADR_I)
                ADDR_CONTROL: DAT_O = {6'b0, irq_enable, enable};
                ADDR_STATUS: DAT_O = {7'b0, status};
                ADDR_PER_0: DAT_O = period[7:0];
                ADDR_PER_1: DAT_O = period[15:8];
                ADDR_PER_2: DAT_O = period[23:16];
                ADDR_PER_3: DAT_O = period[31:24];
                default: DAT_O = 8'h00;
            endcase
        end
    end

endmodule
