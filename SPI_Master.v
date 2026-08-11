module SPI_Master #(
    parameter CLK_DIV = 4
)(
    input clk,
    input reset,

    input start,
    input [7:0] data_in,

    input miso, // Master In Slave Out

    output reg mosi, // Master Out Slave In
    output reg sclk, // Serial clock
    output reg cs, // Chip Select

    output reg [7:0] data_out,
    output reg busy,
    output reg done
);

    // SPI states
    localparam IDLE = 2'b00;
    localparam TRANSFER = 2'b01;
    localparam FINISH = 2'b10;

    reg [1:0] state;

    reg [15:0] clk_count;

    // Holds the data to be sent
    reg [7:0] tx_shift_reg;

    // Holds the data to be recieved
    reg [7:0] rx_shift_reg;

    // Calculates what bit we are on
    reg [2:0] bit_count;


    always @(posedge clk or posedge reset) begin

        if (reset) begin

            state        <= IDLE;
            clk_count    <= 0;
            tx_shift_reg <= 0;
            rx_shift_reg <= 0;
            bit_count    <= 0;

            mosi         <= 0;
            sclk         <= 0;
            cs           <= 1;

            data_out     <= 0;
            busy         <= 0;
            done         <= 0;

        end

        else begin

            // Done is normally low
            done <= 0;

            case (state)

                IDLE: begin

                    sclk <= 0;
                    cs   <= 1;
                    busy <= 0;

                    if (start) begin

                        // Copy the data to be sent
                        tx_shift_reg <= data_in;

                        // clear the reciever register
                        rx_shift_reg <= 0;

                        // Start at bit 7 to send MSB first
                        bit_count <= 0;

                        // Add the first bit on MOSI
                        mosi <= data_in[7];

                        // Activate the SPI slave
                        cs <= 0;

                        busy <= 1;

                        clk_count <= 0;

                        state <= TRANSFER;
                    end

                end


                TRANSFER: begin

                    busy <= 1;

                    if (clk_count == CLK_DIV - 1) begin

                        clk_count <= 0;

                        // Shift the SPI clock
                        sclk <= ~sclk;


                        // Rising edge
                        if (sclk == 1'b0) begin

                            // Read MISO
                            rx_shift_reg <= {
                                rx_shift_reg[6:0],
                                miso
                            };

                        end


                        // Falling edge
                        else begin

                            if (bit_count == 7) begin

                                // All 8 bits are sent
                                state <= FINISH;

                            end

                            else begin

                                bit_count <= bit_count + 1;

                                // Next bit on MOSI
                                mosi <= tx_shift_reg[6 - bit_count];
                            end

                        end

                    end

                    else begin

                        clk_count <= clk_count + 1;

                    end

                end

                FINISH: begin

                    sclk <= 0;
                    cs   <= 1;
                    busy <= 0;

                    data_out <= rx_shift_reg;

                    done <= 1;

                    state <= IDLE;

                end


                default: begin

                    state <= IDLE;
                    sclk <= 0;
                    cs <= 1;
                    busy <= 0;

                end

            endcase

        end

    end

endmodule