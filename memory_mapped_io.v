module Memory_Mapped_IO (

    // Wishbone input

    input CLK_I,
    input RST_I,

    input [15:0] ADR_I,
    input [7:0]  DAT_I,
    output reg [7:0] DAT_O,

    input CYC_I,
    input STB_I,
    input WE_I,
    output ACK_O,


    // RAM

    output RAM_WE,
    output [3:0] RAM_ADR,
    output [7:0] RAM_DAT_I,
    input [7:0] RAM_DAT_O,


    // GPIO

    output GPIO_CYC,
    output GPIO_STB,
    output GPIO_WE,
    output [3:0] GPIO_ADR,
    output [7:0] GPIO_DAT_I,
    input [7:0] GPIO_DAT_O,
    input GPIO_ACK,


    // UART

    output UART_START,
    output [7:0] UART_TX_DATA,
    input [7:0] UART_RX_DATA,
    input UART_RX_VALID,
    input UART_TX_BUSY,


    // Reserved

    output RESERVED_SELECT

);


    // Address decoder

    wire ram_select;
    wire gpio_select;
    wire uart_select;
    wire reserved_select;


    // RAM
    assign ram_select = (ADR_I >= 16'h0000) && (ADR_I <= 16'h00FF);


    // GPIO
    assign gpio_select = (ADR_I >= 16'h1000) && (ADR_I <= 16'h10FF);


    // UART
    assign uart_select = (ADR_I >= 16'h2000) && (ADR_I <= 16'h20FF);


    // RESERVED
    assign reserved_select = (ADR_I >= 16'h3000) && (ADR_I <= 16'h30FF);


    assign RESERVED_SELECT = reserved_select;


    // RAM

    assign RAM_ADR = ADR_I[3:0];

    assign RAM_DAT_I = DAT_I;

    assign RAM_WE = ram_select && CYC_I && STB_I && WE_I;


    // GPIO

    assign GPIO_CYC = CYC_I && gpio_select;

    assign GPIO_STB = STB_I && gpio_select;

    assign GPIO_WE = WE_I;

    assign GPIO_ADR = ADR_I[3:0];

    assign GPIO_DAT_I = DAT_I;


    // UART

    assign UART_START = CYC_I && STB_I && WE_I && uart_select;

    assign UART_TX_DATA = DAT_I;


    // Read data multiplexer

    always @(*) begin

        // Default value for invalid addresses
        DAT_O = 8'h00;

        if (ram_select) begin
            DAT_O = RAM_DAT_O;
        end

        else if (gpio_select) begin
            DAT_O = GPIO_DAT_O;
        end

        else if (uart_select) begin
            DAT_O = UART_RX_DATA;
        end

        else if (reserved_select) begin
            DAT_O = 8'h00;
        end

    end


    // Acknowledge

    assign ACK_O = (ram_select  && CYC_I && STB_I) || (gpio_select && GPIO_ACK) || (uart_select && CYC_I && STB_I);


endmodule