`timescale 1ns/1ps

module Sim_SoC_Integration;

    localparam GPIO_BASE = 16'h1000;
    localparam UART_BASE = 16'h2000;
    localparam TIMER_BASE = 16'h3000;
    localparam IRQ_BASE = 16'h4000;

    reg clk = 0;
    always #10 clk = ~clk;

    reg rst = 1;

    reg [15:0] ADR_I = 16'h0000;
    reg [7:0] DAT_I = 8'h00;
    wire [7:0] DAT_O;
    reg CYC_I = 1'b0;
    reg STB_I = 1'b0;
    reg WE_I = 1'b0;
    wire ACK_O;

    reg [7:0] GPIO_I = 8'h00;
    wire [7:0] GPIO_O;

    reg UART_RX = 1'b1;
    wire UART_TX;
    wire IRQ_O;

    SoC_Integration dut (
        .CLK_I(clk),
        .RST_I(rst),
        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .ACK_O(ACK_O),
        .GPIO_I(GPIO_I),
        .GPIO_O(GPIO_O),
        .UART_RX(UART_RX),
        .UART_TX(UART_TX),
        .IRQ_O(IRQ_O)
    );

    reg [7:0] readval;
    reg [7:0] tx_byte;

    task mem_write;
        input [15:0] addr;
        input [7:0] data;
    begin
        ADR_I = addr;
        DAT_I = data;
        WE_I = 1'b1;
        CYC_I = 1'b1;
        STB_I = 1'b1;
        wait (ACK_O == 1'b1);
        @(posedge clk);
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;
        @(posedge clk);
    end
    endtask

    task mem_read;
        input [15:0] addr;
        output [7:0] rdata;
    begin
        ADR_I = addr;
        WE_I = 1'b0;
        CYC_I = 1'b1;
        STB_I = 1'b1;
        wait (ACK_O == 1'b1);
        rdata = DAT_O;
        @(posedge clk);
        CYC_I = 1'b0;
        STB_I = 1'b0;
        @(posedge clk);
    end
    endtask

    initial begin
        $dumpfile("Sim_SoC_integration.vcd");
        $dumpvars(0, Sim_SoC_Integration);
        $dumpvars(0, Sim_SoC_Integration.dut);

        ADR_I = 16'h0000;
        DAT_I = 8'h00;
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;
        GPIO_I = 8'h00;
        UART_RX = 1'b1;

        rst = 1'b1;
        #50;
        rst = 1'b0;
        #20;

        // RAM write/read
        mem_write(16'h0000, 8'hA5);
        mem_read(16'h0000, readval);

        // GPIO direction + data
        // DATA register reads GPIO_I, while GPIO_O reflects the configured output value.
        mem_write(GPIO_BASE + 16'h0001, 8'hFF);
        mem_write(GPIO_BASE + 16'h0000, 8'h5A);
        GPIO_I = 8'h5A;
        mem_read(GPIO_BASE + 16'h0000, readval);

        // UART RX stimulus: 8'h3C
        UART_RX = 1'b1;
        repeat (5) @(posedge clk);
        UART_RX = 1'b0;
        repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b0; repeat (434) @(posedge clk);
        UART_RX = 1'b1; repeat (434) @(posedge clk);

        mem_read(UART_BASE, readval);

        // TIMER + IRQ test
        mem_write(TIMER_BASE + 16'h0004, 8'd5);
        mem_write(TIMER_BASE + 16'h0000, 8'b00000011);
        mem_write(IRQ_BASE + 16'h0004, 8'h04);

        repeat (100) @(posedge clk);

        mem_read(TIMER_BASE + 16'h0008, readval);

        mem_read(IRQ_BASE + 16'h0000, readval);

        // UART TX capture: output should be 8'hA5 when writing UART base
        mem_write(UART_BASE, 8'hA5);
        wait (UART_TX == 1'b0);
        repeat (434 / 2) @(posedge clk);
        tx_byte = 8'h00;
        for (integer j = 0; j < 8; j = j + 1) begin
            tx_byte[j] = UART_TX;
            repeat (434) @(posedge clk);
        end

        $finish;
    end

endmodule
