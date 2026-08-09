module UART_RX #(
    parameter CLK_PER_BIT = 434
)(
    input clk,
    input reset,
    input rx,

    output reg [7:0] data_out,
    output reg valid
);

    // UART states for receiver state machine
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;       // current receiver state
    reg [15:0] clk_count;  // counts clock cycles inside a bit interval
    reg [2:0] bit_count;   // counts received data bits 0..7
    reg [7:0] shift_reg;   // assembles received bits LSB first


    always @(posedge clk or posedge reset) begin

        if (reset) begin
            state     <= IDLE;
            clk_count <= 0;
            bit_count <= 0;
            shift_reg <= 0;
            data_out  <= 0;
            valid     <= 0;
        end

        else begin

            valid <= 0; // valid pulses for one clock cycle when a byte is captured

            case (state)

                IDLE: begin

                    clk_count <= 0;
                    bit_count <= 0;

                    if (!rx) begin
                        // start bit detected (line went low)
                        state <= START;
                        clk_count <= 0;
                    end
                end


                START: begin

                    // wait half a bit time, then sample the start bit in the middle
                    if (clk_count == (CLK_PER_BIT / 2) - 1) begin

                        clk_count <= 0;

                        if (!rx) begin
                            // valid start bit confirmed
                            state <= DATA;
                            bit_count <= 0;
                        end
                        else begin
                            // false start, return to idle
                            state <= IDLE;
                        end

                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end

                end


                DATA: begin

                    // sample each data bit in the middle of its bit window
                    if (clk_count == CLK_PER_BIT - 1) begin

                        clk_count <= 0;
                        shift_reg[bit_count] <= rx;

                        if (bit_count == 7) begin
                            bit_count <= 0;
                            state <= STOP;
                        end
                        else begin
                            bit_count <= bit_count + 1;
                        end

                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end

                end


                STOP: begin

                    // sample stop bit at the end of the bit period
                    if (clk_count == CLK_PER_BIT - 1) begin

                        clk_count <= 0;

                        if (rx) begin
                            data_out <= shift_reg;
                            valid <= 1; // valid only if stop bit is high
                        end

                        state <= IDLE;

                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end

                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule