`timescale 1ns/1ps // timescale of 1 nanosecond, with the precision of 1 picosecond

module Sim_interrupt_system;

    reg clk = 0;
    always #5 clk = ~clk; // 10 ns period

    reg rst = 1;

    // "CPU" signals
    reg [15:0] ADR_I;
    reg [7:0] DAT_I;
    wire [7:0] DAT_O;
    reg CYC_I;
    reg STB_I;
    reg WE_I;
    wire ACK_O;

    // Generic interrupt inputs
    // 0 = UART
    // 1 = GPIO
    // 2 = TIMER
    // 3 = RESERVED
    reg [3:0] IRQ_I_reg = 4'b0000;
    wire [3:0] IRQ_I = IRQ_I_reg;

    // Interrupt output to CPU
    wire IRQ_O;

    // Instantiate DUT
    Interrupt_Controller dut (
        .CLK_I(clk),
        .RST_I(rst),
        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .ACK_O(ACK_O),
        .IRQ_I(IRQ_I),
        .IRQ_O(IRQ_O)
    );

    reg [3:0] tb_irq_inputs = 4'h0;
    reg [3:0] tb_irq_pending = 4'h0;
    reg [3:0] tb_irq_mask = 4'h0;
    reg tb_irq_out = 1'b0;

    // Tasks for memory access
    task mem_write(input [15:0] addr, input [7:0] data);
    begin
        ADR_I = addr;
        DAT_I = data;
        WE_I = 1'b1;
        CYC_I = 1'b1;
        STB_I = 1'b1;
        wait (ACK_O == 1'b1);
        // allow synchronous logic to update on posedge
        @(posedge clk);
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;
        @(posedge clk);
    end
    endtask

    task mem_read(input [15:0] addr, output [7:0] rdata);
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

    always @(posedge clk) begin
        tb_irq_inputs <= IRQ_I;
        tb_irq_pending <= dut.irq_pending;
        tb_irq_mask <= dut.irq_mask;
        tb_irq_out <= IRQ_O;
    end

    integer i;
    reg [7:0] readval;

    initial begin
        $dumpfile("Sim_interrupt_system.vcd");
        $dumpvars(0, Sim_interrupt_system);
        $dumpvars(0, Sim_interrupt_system.dut);

        // init
        ADR_I = 16'h0000;
        DAT_I = 8'h00;
        CYC_I = 0;
        STB_I = 0;
        WE_I = 0;
        IRQ_I_reg = 4'b0000;

        // reset
        rst = 1;
        #25;
        rst = 0;
        #10;

        // Initially enable all interrupts
        mem_write(16'h0004, 8'h0F);

        // Ensure mask set
        mem_read(16'h0004, readval);
        tb_irq_mask <= readval[3:0];

        // Now pulse each IRQ one at a time and observe pending/IRQ_O
        // UART (bit 0)
        IRQ_I_reg = 4'b0001;
        #20;
        mem_read(16'h0000, readval);
        tb_irq_pending <= readval[3:0];
        #10;
        // Clear UART pending
        mem_write(16'h000C, 8'h01);
        #10;

        // GPIO (bit1)
        IRQ_I_reg = 4'b0010;
        #20;
        mem_read(16'h0000, readval);
        tb_irq_pending <= readval[3:0];
        // Clear GPIO pending
        mem_write(16'h000C, 8'h02);
        #10;

        // TIMER (bit2)
        IRQ_I_reg = 4'b0100;
        #20;
        mem_read(16'h0000, readval);
        tb_irq_pending <= readval[3:0];
        // Clear TIMER pending
        mem_write(16'h000C, 8'h04);
        #10;

        // Multiple IRQs simultaneously: UART+GPIO
        IRQ_I_reg = 4'b0011;
        #20;
        mem_read(16'h0000, readval);
        tb_irq_pending <= readval[3:0];
        // clear both
        mem_write(16'h000C, 8'h03);
        #10;

        // Test read status shows current IRQ_I
        IRQ_I_reg = 4'b0101; // UART + TIMER
        #10;
        mem_read(16'h0008, readval);
        tb_irq_inputs <= readval[3:0];

        // Final wait
        #100;
        $finish;
    end

endmodule
