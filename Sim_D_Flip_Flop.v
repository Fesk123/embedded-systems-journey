module Sim_D_Flip_Flop;

    reg D, reset, clk;
    wire Q;
    
    D_Flip_Flop d_flip_flop(Q, D, reset, clk);

    always #5 clk = ~clk; // This clock is used to control the inputs to the D flip-flop. It will change the inputs every 5 time units.

    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_D_Flip_Flop);
        
        D = 0; reset = 0; clk = 0; #20; // D is 0, reset is 0, clk is 0

        reset = 1; #10;
        D = 1; reset = 0; #10; // D becomes 1, reset is 0
        D = 0; #10; // D becomes 0
        D = 1; #30; // D becomes 1

        $finish; // Stops the simulation
    end


endmodule
