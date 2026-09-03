module Sim_XOR_gate;

    // Changed the inputs to reg inside the test block so that we can controll them
    reg input_1;
    reg input_2;
    wire output_1;

    wire xor_temp;

    assign xor_temp = input_1 ^ input_2;
    assign output_1 = xor_temp;

    // GTK-Wave needs to know which signals to watch, so we tell it to watch all signals in this module
    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_XOR_gate);
        
        // This clock is used to control the inputs to the OR gate. It will change the inputs every 20 time units.
        input_1 = 0; input_2 = 0; #20; // input_1 and input_2 are both 0
        input_1 = 1; input_2 = 0; #20; // input_1 becomes 1
        input_1 = 0; input_2 = 1; #20; // input_2 becomes 1
        input_1 = 1; input_2 = 1; #20; // Both are 1 (now output_1 jumps to 1)
        
        $finish; // Stops the simulation
    end

endmodule // Ends the module definition
// Same as before, except for the operator used in the assign statement.