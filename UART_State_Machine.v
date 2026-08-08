// UART State Machine receiver
// This module samples an incoming serial RX line and converts one byte
// into a parallel 8-bit output when a full valid stop-bit framed packet has been received.
module UART_State_Machine #(parameter CLK_PER_BIT = 868) (
    input clk,
    input reset,
    input rx,
    output reg [7:0] data_out,
    output reg valid
);

    // UART receiver states
    localparam IDLE  = 2'b00, // waiting for start bit
               START = 2'b01, // sampling the middle of the start bit
               DATA  = 2'b10, // receiving 8 data bits
               STOP  = 2'b11; // sampling stop bit and updating output
    
    reg [1:0] state;       // current state of the state machine
    reg [9:0] clk_count;   // counts clock cycles for bit timing
    reg [2:0] bit_count;   // counts received data bits 0-7
    reg [7:0] shift_reg;   // shift register for incoming serial bits

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            // asynchronous reset: go to IDLE and clear all registers
            state <= IDLE;
            clk_count <= 0;
            bit_count <= 0;
            shift_reg <= 0;
            data_out <= 0;
            valid <= 0;
        end else begin
            // valid is only asserted for one clock cycle when a byte is ready
            valid <= 0;

            case (state)
                IDLE: begin
                    // wait for start bit: rx goes low
                    if (!rx) begin
                        state <= START;
                        clk_count <= 0;
                    end
                end

                START: begin
                    // sample in the middle of the start bit
                    if (clk_count == CLK_PER_BIT/2-1) begin
                        clk_count <= 0;
                        bit_count <= 0;
                        state <= DATA;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA: begin
                    // sample each data bit in the middle of its bit window
                    if (clk_count == CLK_PER_BIT-1) begin
                        shift_reg <= {rx, shift_reg[7:1]};
                        clk_count <= 0;
                        if (bit_count == 7) begin
                            state <= STOP;
                        end else begin
                            bit_count <= bit_count + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP: begin
                    // sample stop bit and update output parallel byte
                    if (clk_count == CLK_PER_BIT-1) begin
                        data_out <= shift_reg;
                        valid <= rx; // valid only if stop bit is high
                        state <= IDLE;
                        clk_count <= 0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

            endcase
        end
    end

endmodule