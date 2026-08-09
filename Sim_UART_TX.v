module Baud_Generator #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input clk,
    input reset,
    output reg baud_tick
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 50 000 000 / 115 200 ≈ 434 CLKS_PER_BIT

    reg [15:0] counter;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter  <= 0;
            baud_tick <= 0;
        end
        else begin
            if (counter == CLKS_PER_BIT - 1) begin
                counter  <= 0;
                baud_tick <= 1;
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

    // UART states
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_count;


    always @(posedge clk or posedge reset) begin

        if (reset) begin
            state     <= IDLE;
            shift_reg <= 8'b0;
            bit_count <= 0;
            tx        <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
        end

        else begin

            done <= 1'b0;

            case (state)

                IDLE: begin

                    tx   <= 1'b1;
                    busy <= 1'b0;

                    if (start) begin
                        shift_reg <= data_in;
                        bit_count <= 0;
                        busy      <= 1'b1;
                        state     <= START;
                    end
                end


                START: begin

                    tx <= 1'b0;

                    if (baud_tick) begin
                        state <= DATA;
                    end
                end


                DATA: begin


                    tx <= shift_reg[bit_count];

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

                    tx <= 1'b1;

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

module Sim_UART_TX;
    // transmitter testbench uses a slower baud rate so waveform transitions are visible
    localparam CLK_FREQ = 1000;   // smaller simulation frequency for visible waves
    localparam BAUD_RATE = 100;   // low baud rate to simplify debugging

    reg clk;
    reg reset;
    reg [7:0] data_in;
    reg start;
    wire tx;
    wire busy;
    wire done;
    wire baud_tick;

    Baud_Generator #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) baud (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    UART_TX dut (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick),
        .data_in(data_in),
        .start(start),
        .tx(tx),
        .busy(busy),
        .done(done)
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
        $dumpfile("UART_TX.vcd");
        $dumpvars(0, Sim_UART_TX);

        clk = 0;
        reset = 1;
        data_in = 8'h00;
        start = 1'b0;
        #20;

        reset = 0;            // release reset and begin normal operation
        #20;

        send_byte(8'hA5);     // send first test byte
        wait (done);
        #50;

        send_byte(8'h3C);     // send second test byte
        wait (done);
        #100;

        $finish;
    end
endmodule

