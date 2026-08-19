`timescale 1ns/1ps

module Sim_Hardware_Timer;

    // 50 MHz = 20 ns period

    reg clk = 0;

    always #10 clk = ~clk;

    reg rst = 1;

    // Wishbone signals

    reg [15:0] ADR_I;
    reg [7:0] DAT_I;
    wire [7:0] DAT_O;

    reg CYC_I;
    reg STB_I;
    reg WE_I;

    wire ACK_O;


    // Interrupt

    wire timer_irq;

    Hardware_Timer #(
        .CLK_FREQ(50_000_000)
    ) dut (
        .CLK_I(clk),
        .RST_I(rst),
        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .ACK_O(ACK_O),
        .timer_irq(timer_irq)
    );


    // Write task

    task mem_write;

        input [15:0] addr;
        input [7:0] data;

        begin

            ADR_I = addr;
            DAT_I = data;

            WE_I = 1'b1;
            CYC_I = 1'b1;
            STB_I = 1'b1;

            // Wait for Wishbone ACK
            @(posedge clk);
            wait (ACK_O);

            // End transaction
            @(posedge clk);

            CYC_I = 1'b0;
            STB_I = 1'b0;
            WE_I = 1'b0;

            @(posedge clk);

        end

    endtask


    // Read task

    task mem_read;

        input [15:0] addr;
        output [7:0] data;

        begin

            ADR_I = addr;
            DAT_I = 8'h00;

            WE_I = 1'b0;
            CYC_I = 1'b1;
            STB_I = 1'b1;

            @(posedge clk);
            wait (ACK_O);

            data = DAT_O;

            @(posedge clk);

            CYC_I = 1'b0;
            STB_I = 1'b0;

            @(posedge clk);

        end

    endtask

    reg [7:0] readval;

    initial begin
        $dumpfile("Sim_Hardware_Timer.vcd");
        $dumpvars(0, Sim_Hardware_Timer);
        $dumpvars(0, Sim_Hardware_Timer.dut);

        // Init
        ADR_I = 16'h0000;
        DAT_I = 8'h00;

        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;

        rst = 1'b1;

        repeat (3) @(posedge clk);

        rst = 1'b0;

        repeat (2) @(posedge clk);


        // Set timer period (32 bits divided into 4 bytes)
        // We want a period; 10 clock cycles (32'h0000000A)
        
        mem_write(16'h0004, 8'h0A); // Byte 0 (LSB)
        mem_write(16'h0005, 8'h00); // Byte 1
        mem_write(16'h0006, 8'h00); // Byte 2
        mem_write(16'h0007, 8'h00); // Byte 3 (MSB)


        // Enable timer + IRQ

        mem_write(16'h0000, 8'b00000011);


        // Let the timer run, wait 15 clock cycles.

        repeat (15) @(posedge clk);

        // Read status

        mem_read(16'h0001, readval);

        // Clear interrupt
        // Status: 16'h0001. Write 1 to bit 0 to clear.

        mem_write(16'h0001, 8'b00000001);

        // Give waveform some space and check if IRQ dropped
        repeat (5) @(posedge clk);


        // Disable timer

        mem_write(16'h0000, 8'b00000000);

        // End

        repeat (3) @(posedge clk);

        $finish;

    end

endmodule
