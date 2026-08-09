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

module UART_RX #(
    parameter CLK_PER_BIT = 434
)(
    input clk,
    input reset,
    input rx,

    output reg [7:0] data_out,
    output reg valid
);

    // UART states
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;


    reg [15:0] clk_count;

    reg [2:0] bit_count;

    reg [7:0] shift_reg;


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

            valid <= 0;

            case (state)

                IDLE: begin

                    clk_count <= 0;
                    bit_count <= 0;

                    if (!rx) begin
                        state <= START;
                        clk_count <= 0;
                    end
                end


                START: begin

                    if (clk_count == (CLK_PER_BIT / 2) - 1) begin

                        clk_count <= 0;


                        if (!rx) begin
                            state <= DATA;
                            bit_count <= 0;
                        end
                        else begin
                            state <= IDLE;
                        end

                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end

                end


                DATA: begin

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

                    if (clk_count == CLK_PER_BIT - 1) begin

                        clk_count <= 0;

                        if (rx) begin
                            data_out <= shift_reg;
                            valid <= 1;
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

module Sim_UART_RX;
    // receiver testbench sends framed UART bytes directly into rx
    localparam CLK_PER_BIT = 10;  // bit width in clock cycles for the receiver testbench

    reg clk;
    reg reset;
    reg rx;
    wire [7:0] data_out;
    wire valid;

    UART_RX #(.CLK_PER_BIT(CLK_PER_BIT)) dut (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .data_out(data_out),
        .valid(valid)
    );

    always #1 clk = ~clk; // clock period 2 time units

    task send_byte;
        input [7:0] byte;
        integer i;
        begin
            // drive the start bit low first
            rx = 1'b0;
            #(CLK_PER_BIT * 2);

            for (i = 0; i < 8; i = i + 1) begin
                rx = byte[i];       // send LSB first
                #(CLK_PER_BIT * 2);
            end

            // stop bit must be high
            rx = 1'b1;
            #(CLK_PER_BIT * 4);
        end
    endtask

    initial begin
        $dumpfile("UART_RX.vcd");
        $dumpvars(0, Sim_UART_RX);

        clk = 0;
        reset = 1;
        rx = 1'b1;               // idle line is high
        #20;

        reset = 0;               // release reset and start receiver
        #20;

        send_byte(8'hA5);        // first test byte
        #(CLK_PER_BIT * 8);      // give receiver time to process
        send_byte(8'h3C);        // second test byte
        #(CLK_PER_BIT * 12);     // keep idle line after second byte

        $finish;
    end
endmodule
