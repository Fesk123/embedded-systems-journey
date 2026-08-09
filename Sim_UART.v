module Baud_Generator #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input clk,
    input reset,
    output reg baud_tick
);

    // generate a one-cycle baud_tick pulse every UART bit interval
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 50 000 000 / 115 200 ≈ 434 CLKS_PER_BIT

    reg [15:0] counter; // count system clocks until the next baud tick

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // stay in reset until released
            counter  <= 0;
            baud_tick <= 0;
        end
        else begin
            if (counter == CLKS_PER_BIT - 1) begin
                // one UART bit period has elapsed
                counter  <= 0;
                baud_tick <= 1; // pulse for one clock cycle
            end
            else begin
                counter  <= counter + 1;
                baud_tick <= 0;
            end
        end
    end

endmodule

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

            // done is only asserted for one cycle at end of stop bit
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

module UART_RX #(
    parameter CLK_PER_BIT = 434
)(
    input clk,
    input reset,
    input rx,

    output reg [7:0] data_out,
    output reg valid
);

    // UART receiver state machine for 8-N-1 framing
    // waits for the start bit, samples each data bit in the middle,
    // then checks the stop bit before asserting valid.
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;       // current receiver state
    reg [15:0] clk_count;  // count clocks within one bit interval
    reg [2:0] bit_count;   // count received data bits 0..7
    reg [7:0] shift_reg;   // assemble received bits LSB first


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

            valid <= 0; // valid pulses for one cycle when a byte is captured

            case (state)

                IDLE: begin

                    clk_count <= 0;
                    bit_count <= 0;

                    if (!rx) begin
                        // detected start bit low transition
                        state <= START;
                        clk_count <= 0;
                    end
                end


                START: begin

                    // sample start bit in the middle of its bit interval
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

                    // sample each data bit at the end of its bit interval
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
                            valid <= 1; // only valid if stop bit is high
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

module Sim_UART;
    // loopback simulation of UART_TX into UART_RX
    // uses a slow baud rate so the waveform is easy to inspect in GTKWave.
    localparam CLK_FREQ = 1000;   // low simulated clock frequency for waveform visibility
    localparam BAUD_RATE = 100;   // low simulated baud rate for easier inspection
    localparam CLK_PER_BIT = CLK_FREQ / BAUD_RATE; // should equal 10 here

    reg clk;
    reg reset;
    reg [7:0] data_in;
    reg start;
    wire tx;
    wire busy;
    wire done;
    wire baud_tick;
    wire [7:0] data_out;
    wire valid;
    wire rx_line;

    Baud_Generator #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) baud (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    UART_TX tx_dut (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick),
        .data_in(data_in),
        .start(start),
        .tx(tx),
        .busy(busy),
        .done(done)
    );

    assign rx_line = tx; // direct serial line connection for this loopback simulation

    UART_RX #(.CLK_PER_BIT(CLK_PER_BIT)) rx_dut (
        .clk(clk),
        .reset(reset),
        .rx(rx_line),
        .data_out(data_out),
        .valid(valid)
    );

    always #1 clk = ~clk; // clock period 2 time units

    task send_byte;
        input [7:0] byte;
        begin
            wait (!busy);          // wait until transmitter is idle before sending
            data_in = byte;
            start = 1'b1;
            #2;                    // pulse start for one clock period
            start = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("UART.vcd");
        $dumpvars(0, Sim_UART);

        clk = 0;
        reset = 1;
        data_in = 8'h00;
        start = 1'b0;
        #20;

        reset = 0;            // release reset and begin the loopback simulation
        #20;

        send_byte(8'hA5);     // send first byte through TX
        wait (done);
        #(CLK_PER_BIT * 10);   // wait a full idle gap before next byte

        send_byte(8'h3C);     // send second byte through TX
        wait (done);
        #(CLK_PER_BIT * 10);

        $finish;
    end
endmodule
