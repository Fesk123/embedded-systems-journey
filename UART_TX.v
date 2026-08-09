module UART_TX(
    input clk,
    input reset,
    input baud_tick,

    input [7:0] data_in,
    input start,

    output reg tx,
    output reg busy,
    output reg done
);

    // UART states: idle, start bit, 8 data bits, stop bit
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;        // current transmitter state
    reg [7:0] shift_reg;    // data bits to shift out LSB first
    reg [2:0] bit_count;    // counts 0-7 for data bit positions


    always @(posedge clk or posedge reset) begin

        if (reset) begin
            // asynchronous reset: return to idle, clear outputs
            state     <= IDLE;
            shift_reg <= 8'b0;
            bit_count <= 0;
            tx        <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
        end

        else begin

            // valid is only asserted for one cycle at end of stop bit
            done <= 1'b0;

            case (state)

                IDLE: begin

                    tx   <= 1'b1;   // line idle is high
                    busy <= 1'b0;  // transmitter is free

                    if (start) begin
                        shift_reg <= data_in; // load byte to send
                        bit_count <= 0;
                        busy      <= 1'b1;
                        state     <= START;
                    end
                end


                START: begin

                    tx <= 1'b0; // start bit is low

                    if (baud_tick) begin
                        state <= DATA;
                    end
                end


                DATA: begin

                    tx <= shift_reg[bit_count]; // output current data bit

                    if (baud_tick) begin
                        if (bit_count == 7) begin
                            bit_count <= 0;
                            state <= STOP;
                        end
                        else begin
                            bit_count <= bit_count + 1;
                        end
                    end
                end

                STOP: begin

                    tx <= 1'b1; // stop bit is high

                    if (baud_tick) begin
                        state <= IDLE;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end
                end

            endcase
        end
    end

endmodule