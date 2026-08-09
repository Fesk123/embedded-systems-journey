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

module Sim_UART_Baud;
    // testbench for the baud rate generator
    // this sim checks that baud_tick pulses once per bit interval.
    localparam CLK_FREQ = 50_000_000;
    localparam BAUD_RATE = 115_200;

    reg clk;
    reg reset;
    wire baud_tick;

    Baud_Generator #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    always #1 clk = ~clk;

    initial begin
        $dumpfile("UART_Baud.vcd");
        $dumpvars(0, Sim_UART_Baud);

        clk = 0;
        reset = 1;
        #20;
        reset = 0;   

        #(434 * 10 * 2); 

        $finish;
    end
endmodule