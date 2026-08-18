`timescale 1ns/1ps // Sets the time to scale one nanosecond, with the precision of one picosecond

module Sim_memory_mapped_io;

    reg clk = 0;
    always #5 clk = ~clk; // 10 ns period

    reg rst = 1;

    reg [15:0] ADR_I;
    reg [7:0] DAT_I;
    wire [7:0] DAT_O;
    reg CYC_I;
    reg STB_I;
    reg WE_I;
    wire ACK_O;

    // RAM interface
    wire RAM_WE;
    wire [3:0] RAM_ADR;
    wire [7:0] RAM_DAT_I;
    wire [7:0] RAM_DAT_O;

    // GPIO interface
    wire GPIO_CYC;
    wire GPIO_STB;
    wire GPIO_WE;
    wire [3:0] GPIO_ADR;
    wire [7:0] GPIO_DAT_I;
    wire [7:0] GPIO_DAT_O;
    wire GPIO_ACK;

    // UART interface
    wire UART_START;
    wire [7:0] UART_TX_DATA;
    wire [7:0] UART_RX_DATA;
    wire UART_RX_VALID;
    wire UART_TX_BUSY;

    // Reserved select (not used)
    wire RESERVED_SELECT;

    // Instantiate memory_mapped_io
    Memory_Mapped_IO mmio (
        .CLK_I(clk),
        .RST_I(rst),
        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .ACK_O(ACK_O),
        .RAM_WE(RAM_WE),
        .RAM_ADR(RAM_ADR),
        .RAM_DAT_I(RAM_DAT_I),
        .RAM_DAT_O(RAM_DAT_O),
        .GPIO_CYC(GPIO_CYC),
        .GPIO_STB(GPIO_STB),
        .GPIO_WE(GPIO_WE),
        .GPIO_ADR(GPIO_ADR),
        .GPIO_DAT_I(GPIO_DAT_I),
        .GPIO_DAT_O(GPIO_DAT_O),
        .GPIO_ACK(GPIO_ACK),
        .UART_START(UART_START),
        .UART_TX_DATA(UART_TX_DATA),
        .UART_RX_DATA(UART_RX_DATA),
        .UART_RX_VALID(UART_RX_VALID),
        .UART_TX_BUSY(UART_TX_BUSY),
        .RESERVED_SELECT(RESERVED_SELECT)
    );

    // Instantiate RAM
    RAM ram (
        .clk(clk),
        .we(RAM_WE),
        .address(RAM_ADR),
        .data_in(RAM_DAT_I),
        .data(RAM_DAT_O)
    );

    // Instantiate GPIO peripheral
    reg [7:0] ext_gpio_in = 8'h00;
    wire [7:0] ext_gpio_out;

    GPIO_Peripheral gpio_periph (
        .CLK_I(clk),
        .RST_I(rst),
        .ADR_I(GPIO_ADR),
        .DAT_I(GPIO_DAT_I),
        .DAT_O(GPIO_DAT_O),
        .CYC_I(GPIO_CYC),
        .STB_I(GPIO_STB),
        .WE_I(GPIO_WE),
        .ACK_O(GPIO_ACK),
        .GPIO_I(ext_gpio_in),
        .GPIO_O(ext_gpio_out)
    );

    reg [7:0] uart_rx_reg = 8'h00;
    reg uart_rx_valid_reg = 1'b0;
    reg uart_tx_busy_reg = 1'b0;

    assign UART_RX_DATA = uart_rx_reg;
    assign UART_RX_VALID = uart_rx_valid_reg;
    assign UART_TX_BUSY = uart_tx_busy_reg;


    always @(posedge clk) begin
        uart_rx_valid_reg <= 1'b0;
        uart_tx_busy_reg <= 1'b0;
        if (UART_START) begin
            // show busy for one cycle and deliver RX next cycle
            uart_tx_busy_reg <= 1'b1;
            uart_rx_reg <= UART_TX_DATA + 8'h01; // echo with +1 for visibility
            uart_rx_valid_reg <= 1'b1;
        end
    end

    // Sample arrays for VCD visibility
    reg [7:0] tb_ram_read [0:15];
    reg [7:0] tb_gpio_read;
    reg [7:0] tb_uart_read;

    // "CPU" write task
    task mem_write(input [15:0] addr, input [7:0] data);
    begin
        ADR_I = addr;
        DAT_I = data;
        WE_I = 1'b1;
        CYC_I = 1'b1;
        STB_I = 1'b1;

        // Wait for ACK
        wait (ACK_O == 1'b1);
        @(posedge clk);

        // Deassert
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;

        // small gap
        @(posedge clk);
    end
    endtask

    // "CPU" read task
    task mem_read(input [15:0] addr, output [7:0] rdata);
    begin
        ADR_I = addr;
        WE_I = 1'b0;
        CYC_I = 1'b1;
        STB_I = 1'b1;

        wait (ACK_O == 1'b1);
        // sample combinational DAT_O after ack
        rdata = DAT_O;

        // complete cycle
        @(posedge clk);
        CYC_I = 1'b0;
        STB_I = 1'b0;
        @(posedge clk);
    end
    endtask

    integer i;

    initial begin
        $dumpfile("Sim_memory_mapped_io.vcd");
        $dumpvars(0, Sim_memory_mapped_io);

        // init
        ADR_I = 16'h0000;
        DAT_I = 8'h00;
        CYC_I = 0;
        STB_I = 0;
        WE_I = 0;
        ext_gpio_in = 8'h00;
        uart_rx_reg = 8'h00;
        uart_rx_valid_reg = 0;
        uart_tx_busy_reg = 0;

        // reset
        rst = 1;
        #25;
        rst = 0;
        #10;

        // RAM test; write 0 to 7, then read back
        for (i = 0; i < 8; i = i + 1) begin
            mem_write(16'h0000 + i, 8'hA0 + i);
        end

        // Read back
        for (i = 0; i < 8; i = i + 1) begin
            mem_read(16'h0000 + i, tb_ram_read[i]);
        end

        #50;


        // GPIO test; set direction, set data, toggle external inputs and read
        mem_write(16'h1000 + 16'h0001, 8'h0F);

        mem_write(16'h1000 + 16'h0000, 8'hAA);

        // allow outputs to settle
        #20;

        // change external inputs
        ext_gpio_in = 8'h55;
        #20;
        mem_read(16'h1000 + 16'h0000, tb_gpio_read);

        ext_gpio_in = 8'hFF;
        #20;
        mem_read(16'h1000 + 16'h0000, tb_gpio_read);

        #50;


        // UART test; write TX data and read RX
        
        // Write TX data at 0x2000
        mem_write(16'h2000, 8'h33);

        #20;
        
        // Read back UART RX at 0x2000
        mem_read(16'h2000, tb_uart_read);

        #100;

        $finish;
    end

endmodule
