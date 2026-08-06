module Sim_Counter;
    reg clk = 0;
    reg reset;
    wire [3:0] count;
    // Instantiate the counter module with a parameter of 4 (for a 4-bit counter)

    counter #(.N(4)) c1(
        .clk(clk),
        .reset(reset),
        .count(count)
    );
    // #(.N(4)) is used to set the parameter N to 4 (for a 4-bit counter).
    // .clk(clk) is used to connect the clk input of the counter module to the clk signal in this testbench. Vice versa for .reset(reset) and .count(count).

    always #5 clk = ~clk;
    // Sets the clock signal to toggle every 5 time units.

    initial begin // Simulation
        $dumpfile("counter.vcd");
        $dumpvars(0, Sim_Counter);

        reset = 1;
        #20;
        reset = 0;
        #200;
        $finish;
    end
endmodule