module SPI_Slave(
    input clk,
    input reset,

    input sclk,             // SPI-clock from master
    input cs,               // Chip Select from master
    input mosi,             // Data from master
    output reg miso,        // Data to master

    input [7:0] data_in,    // Data to be sent by the slave
    output reg [7:0] data_out, // Data recieved by the slave
    output reg valid        // HIGH when a byte has been recieved
);

    reg [7:0] rx_shift_reg;
    reg [7:0] tx_shift_reg;

    reg [2:0] bit_count;


    always @(negedge cs or posedge reset) begin

        if (reset) begin
            tx_shift_reg <= 8'b0;
            miso <= 1'b0;
        end

        else begin
            tx_shift_reg <= data_in;

            // Because we send MSB first, we set bit 7 on MISO first.
            miso <= data_in[7];
        end

    end




    always @(posedge sclk or posedge reset) begin

        if (reset) begin
            rx_shift_reg <= 8'b0;
            bit_count <= 0;
            data_out <= 8'b0;
            valid <= 1'b0;
        end

        else if (!cs) begin

            // Read a bit from MOSI
            rx_shift_reg <= {
                rx_shift_reg[6:0],
                mosi
            };

            // After 8 bits, the byte is done
            if (bit_count == 7) begin

                data_out <= {
                    rx_shift_reg[6:0],
                    mosi
                };

                valid <= 1'b1;
                bit_count <= 0;

            end

            else begin
                bit_count <= bit_count + 1;
                valid <= 1'b0;
            end

        end

    end


    always @(negedge sclk or posedge reset) begin

        if (reset) begin
            tx_shift_reg <= 8'b0;
            miso <= 1'b0;
        end

        else if (!cs) begin

            // Send forward the next bit
            tx_shift_reg <= {
                tx_shift_reg[6:0],
                1'b0
            };

            // Next bit is sent to MISO
            miso <= tx_shift_reg[6];

        end

    end

endmodule