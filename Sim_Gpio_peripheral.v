`timescale 1ns/1ps // Sets the time to scale one nanosecond, with the precision of one picosecond

module Sim_Gpio_peripheral;

    reg clk = 0;
    always #5 clk = ~clk; // 10ns period

    reg rst = 1;

    reg [3:0] ADR_I;
    reg [7:0] DAT_I;
    wire [7:0] DAT_O;
    reg CYC_I;
    reg STB_I;
    reg WE_I;
    wire ACK_O;

    // External GPIO pins
    reg [7:0] gpio_in;
    wire [7:0] gpio_out;

    // Sampled signals for VCD
    reg [7:0] tb_gpio_out = 8'h00;
    reg [7:0] tb_read_sample = 8'h00;

    // Instantiate DUT
    GPIO_Peripheral dut (
        .CLK_I(clk),
        .RST_I(rst),
        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .ACK_O(ACK_O),
        .GPIO_I(gpio_in),
        .GPIO_O(gpio_out)
    );

    // Performs a single-cycle write on posedge
    task wb_write(input [3:0] addr, input [7:0] data);
    begin
        ADR_I = addr;
        DAT_I = data;
        WE_I  = 1'b1;
        CYC_I = 1'b1;
        STB_I = 1'b1;
        @(posedge clk);
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I  = 1'b0;
        @(posedge clk);
    end
    endtask

    // Issues a cycle and samples DAT_O after a clock
    task wb_read(input [3:0] addr);
    begin
        ADR_I = addr;
        WE_I  = 1'b0;
        CYC_I = 1'b1;
        STB_I = 1'b1;
        @(posedge clk);
        tb_read_sample <= DAT_O;
        CYC_I = 1'b0;
        STB_I = 1'b0;
        @(posedge clk);
    end
    endtask

    always @(posedge clk) begin
        tb_gpio_out <= gpio_out;
    end

    initial begin
        $dumpfile("Sim_Gpio_peripheral.vcd");
        $dumpvars(0, Sim_Gpio_peripheral);

        // initial values
        ADR_I = 4'h0;
        DAT_I = 8'h00;
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I  = 1'b0;
        gpio_in = 8'h00;

        // Reset pulse
        rst = 1'b1;
        #25;
        rst = 1'b0;
        #20;

        wb_write(4'h1, 8'h0F);
        wb_write(4'h0, 8'hAA);

        #20;

        gpio_in = 8'h55;
        #20;

        wb_read(4'h0);

        gpio_in = 8'hFF;
        #20;

        wb_read(4'h0);

        // Cleanup
        #100;
        $finish;
    end

endmodule
