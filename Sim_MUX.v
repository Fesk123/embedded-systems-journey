module Sim_MUX;

    // Changed the inputs to reg inside the test block so that we can controll them
    reg input_1;
    reg input_2;
    reg select;
    wire output_1;

    assign output_1 = (select) ? input_2 : input_1; // If select is 1, output_1 is input_2, else output_1 is input_1

    // GTK-Wave needs to know which signals to watch, so we tell it to watch all signals in this module
    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_MUX);
        
        // This clock is used to control the inputs to the OR gate. It will change the inputs every 20 time units.
        input_1 = 0; input_2 = 0; select = 0; #20; // input_1 and input_2 are both 0
        input_1 = 1; input_2 = 0; select = 1; #20; // input_1 becomes 1
        input_1 = 0; input_2 = 1; select = 0; #20; // input_2 becomes 1
        input_1 = 1; input_2 = 1; select = 1; #20; // Both are 1 (now output_1 jumps to 1)

        $finish; // Stops the simulation
    end

endmodule // Ends the module definition
// Same as before, except for the operator used in the assign statement.