module GPIO_Peripheral (

    input CLK_I,
    input RST_I,

    // Wishbome interface

    input [3:0] ADR_I,
    input [7:0] DAT_I,
    output reg [7:0] DAT_O,

    input CYC_I,
    input STB_I,
    input WE_I,

    output ACK_O,

    input [7:0] GPIO_I,
    output [7:0] GPIO_O

);

    // Data register
    reg [7:0] gpio_data;

    // Direction register
    // 0 = input
    // 1 = output
    reg [7:0] gpio_dir;


    // Only output the stored data when the GPIO pin is configured as an output.

    assign GPIO_O = gpio_data & gpio_dir;

    assign ACK_O = CYC_I && STB_I;

    // Write
    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            gpio_data <= 8'b00000000;
            gpio_dir <= 8'b00000000;

        end

        else begin

            if (CYC_I && STB_I && WE_I) begin

                case (ADR_I)

                    // Gpio data
                    4'h0:
                        gpio_data <= DAT_I;


                    // Gpio direction
                    4'h1:
                        gpio_dir <= DAT_I;


                    default:
                        begin
                        end

                endcase

            end

        end

    end

    // Read
    always @(*) begin

        case (ADR_I)

            // Data register
            4'h0:
                DAT_O = GPIO_I;


            // Direction register
            4'h1:
                DAT_O = gpio_dir;


            default:
                DAT_O = 8'b00000000;

        endcase

    end

endmodule