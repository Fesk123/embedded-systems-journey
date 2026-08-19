`timescale 1ns/1ps

module SoC_Integration (

    input CLK_I,
    input RST_I,

    // CPU / Wishbone master interface

    input [15:0] ADR_I,
    input [7:0] DAT_I,
    output [7:0] DAT_O,

    input CYC_I,
    input STB_I,
    input WE_I,
    output ACK_O,

    // GPIO

    input  [7:0] GPIO_I,
    output [7:0] GPIO_O,

    // UART

    input UART_RX,
    output UART_TX,

    // CPU interrupt

    output IRQ_O

);


    // Address map

    localparam RAM_BASE = 16'h0000;
    localparam RAM_END = 16'h00FF;

    localparam GPIO_BASE = 16'h1000;
    localparam GPIO_END = 16'h10FF;

    localparam UART_BASE = 16'h2000;
    localparam UART_END = 16'h20FF;

    localparam TIMER_BASE = 16'h3000;
    localparam TIMER_END = 16'h30FF;

    localparam IRQ_BASE = 16'h4000;
    localparam IRQ_END = 16'h40FF;

    localparam RESERVED_BASE = 16'h5000;
    localparam RESERVED_END = 16'h50FF;

    // Address decoder

    wire ram_select;
    wire gpio_select;
    wire uart_select;
    wire timer_select;
    wire irq_select;
    wire reserved_select;


    assign ram_select = (ADR_I >= RAM_BASE) && (ADR_I <= RAM_END);

    assign gpio_select = (ADR_I >= GPIO_BASE) && (ADR_I <= GPIO_END);

    assign uart_select = (ADR_I >= UART_BASE) && (ADR_I <= UART_END);

    assign timer_select = (ADR_I >= TIMER_BASE) && (ADR_I <= TIMER_END);

    assign irq_select = (ADR_I >= IRQ_BASE) && (ADR_I <= IRQ_END);

    assign reserved_select = (ADR_I >= RESERVED_BASE) && (ADR_I <= RESERVED_END);


    // RAM signals

    wire [3:0] ram_address;
    wire [7:0] ram_data_in;
    wire [7:0] ram_data_out;
    wire ram_we;


    assign ram_address = ADR_I[3:0];

    assign ram_data_in = DAT_I;

    assign ram_we = ram_select && CYC_I && STB_I && WE_I;


    // GPIO signals

    wire [3:0] gpio_address;
    wire [7:0] gpio_data_in;
    wire [7:0] gpio_data_out;
    wire gpio_cyc;
    wire gpio_stb;
    wire gpio_we;
    wire gpio_ack;


    assign gpio_address = ADR_I[3:0];

    assign gpio_data_in = DAT_I;

    assign gpio_cyc = CYC_I && gpio_select;

    assign gpio_stb = STB_I && gpio_select;

    assign gpio_we = gpio_select && CYC_I && STB_I && WE_I;


    // Timer signals

    wire [15:0] timer_address;
    wire [7:0] timer_data_out;
    wire timer_ack;
    wire timer_irq;


    // Convert global address to local peripheral address
    assign timer_address = ADR_I - TIMER_BASE;

    // Interrupt controller signals

    wire [7:0] irq_data_out;
    wire irq_ack;

    wire [3:0] irq_inputs;


    // IRQ mapping:
    // IRQ[0] = UART
    // IRQ[1] = GPIO
    // IRQ[2] = Timer
    // IRQ[3] = Reserved

    wire uart_irq;
    wire gpio_irq;

    assign irq_inputs = {1'b0, timer_irq, gpio_irq, uart_irq};

    // UART signals

    wire [7:0] uart_data_out;
    wire uart_ack;

    wire uart_start;
    wire [7:0] uart_tx_data;

    wire [7:0] uart_rx_data;
    wire uart_rx_valid;
    wire uart_tx_busy;


    // Local UART address
    wire [15:0] uart_address;

    assign uart_address = ADR_I - UART_BASE;

    // Data multiplexer

    reg [7:0] data_out_mux;

    always @(*) begin

        data_out_mux = 8'h00;

        if (ram_select) begin
            data_out_mux = ram_data_out;
        end

        else if (gpio_select) begin
            data_out_mux = gpio_data_out;
        end

        else if (uart_select) begin
            data_out_mux = uart_data_out;
        end

        else if (timer_select) begin
            data_out_mux = timer_data_out;
        end

        else if (irq_select) begin
            data_out_mux = irq_data_out;
        end

        else if (reserved_select) begin
            data_out_mux = 8'h00;
        end

    end

    assign DAT_O = data_out_mux;


    // ACK multiplexer

    assign ACK_O =
        (ram_select && CYC_I && STB_I) || (gpio_select && gpio_ack) || (uart_select && uart_ack) || (timer_select && timer_ack) || (irq_select && irq_ack);


    // RAM instance

    RAM ram_dut (
        .clk(CLK_I),
        .we(ram_we),
        .address(ram_address),
        .data_in(ram_data_in),
        .data(ram_data_out)
    );


    // GPIO instance

    GPIO_Peripheral gpio_dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(gpio_address),
        .DAT_I(gpio_data_in),
        .DAT_O(gpio_data_out),
        .CYC_I(gpio_cyc),
        .STB_I(gpio_stb),
        .WE_I(gpio_we),
        .ACK_O(gpio_ack),
        .GPIO_I(GPIO_I),
        .GPIO_O(GPIO_O)
    );


    // Timer instance

    Hardware_Timer #(
        .CLK_FREQ(50_000_000)
    ) timer_dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(timer_address),
        .DAT_I(DAT_I),
        .DAT_O(timer_data_out),
        .CYC_I(CYC_I && timer_select),
        .STB_I(STB_I && timer_select),
        .WE_I(WE_I),
        .ACK_O(timer_ack),
        .timer_irq(timer_irq)
    );


    // Interrupt controller instance

    Interrupt_Controller interrupt_dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(ADR_I - IRQ_BASE),
        .DAT_I(DAT_I),
        .DAT_O(irq_data_out),
        .CYC_I(CYC_I && irq_select),
        .STB_I(STB_I && irq_select),
        .WE_I(WE_I),
        .ACK_O(irq_ack),
        .IRQ_I(irq_inputs),
        .IRQ_O(IRQ_O)
    );


    // UART  

    assign uart_start = CYC_I && STB_I && WE_I && uart_select;
    assign uart_tx_data = DAT_I;


    
    // UART instance

    UART uart_dut (
        .clk(CLK_I),
        .reset(RST_I),
        .rx(UART_RX),
        .tx(UART_TX),
        .data_in(uart_tx_data),
        .start(uart_start),
        .data_out(uart_rx_data),
        .valid(uart_rx_valid),
        .busy(uart_tx_busy)
    );


    // Temporary UART-readback until UART peripheral-wrapper is used

    assign uart_data_out = uart_rx_data;


    // UART ACK
    assign uart_ack = uart_select && CYC_I && STB_I;

    // UART interrupt
    
    assign uart_irq = uart_rx_valid;


    // GPIO interrupt

    assign gpio_irq = 1'b0;


endmodule