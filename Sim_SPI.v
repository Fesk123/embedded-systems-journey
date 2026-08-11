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

module Sim_SPI;
    // SPI loopback simulation: master and slave exchange bytes simultaneously
    // MOSI, MISO, SCLK and CS are wired directly between master and slave.

    localparam CLK_DIV = 4;

    reg clk;
    reg reset;
    reg start;
    reg [7:0] master_data_in;
    reg [7:0] slave_data_in;

    wire mosi;
    wire miso;
    wire sclk;
    wire cs;

    wire [7:0] master_data_out;
    wire [7:0] slave_data_out;
    wire master_busy;
    wire master_done;
    wire slave_valid;

    SPI_Master #(.CLK_DIV(CLK_DIV)) master (
        .clk(clk),
        .reset(reset),
        .start(start),
        .data_in(master_data_in),
        .miso(miso),
        .mosi(mosi),
        .sclk(sclk),
        .cs(cs),
        .data_out(master_data_out),
        .busy(master_busy),
        .done(master_done)
    );

    SPI_Slave slave (
        .clk(clk),
        .reset(reset),
        .sclk(sclk),
        .cs(cs),
        .mosi(mosi),
        .miso(miso),
        .data_in(slave_data_in),
        .data_out(slave_data_out),
        .valid(slave_valid)
    );

    always #1 clk = ~clk; // clock period is 2 time units

    task send_transfer;
        input [7:0] m_byte;
        input [7:0] s_byte;
        begin
            wait (!master_busy);      // wait until master is idle
            master_data_in = m_byte;  // set master's transmit byte
            slave_data_in = s_byte;   // set slave's transmit byte
            start = 1'b1;             // start SPI transfer
            #2;                       // pulse start for one clock period
            start = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("Sim_SPI.vcd");
        $dumpvars(0, Sim_SPI);

        clk = 0;
        reset = 1;
        start = 1'b0;
        master_data_in = 8'h00;
        slave_data_in = 8'h00;
        #20;

        reset = 0;                // release reset and begin SPI transfers
        #20;

        send_transfer(8'hA5, 8'h3C);  // master sends A5 while slave sends 3C
        wait (master_done);
        wait (slave_valid);
        #10;

        send_transfer(8'h5A, 8'hC3);  // next full-duplex transfer
        wait (master_done);
        wait (slave_valid);
        #10;


        #50;
        $finish;
    end
endmodule