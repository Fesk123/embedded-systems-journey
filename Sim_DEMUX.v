module Sim_DEMUX;

    // Changed the inputs to reg inside the test block so that we can controll them
    reg input_1;
    reg select;
    wire output_1;
    wire output_2;

    assign output_1 = input_1 & ~select; // If select is 0, output_1 is input_1, else output_1 is 0
    assign output_2 = input_1 & select; // If select is 1, output_2 is input_1, else output_2 is 0

    // GTK-Wave needs to know which signals to watch, so we tell it to watch all signals in this module
    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_DEMUX);
        
        // This clock is used to control the inputs to the OR gate. It will change the inputs every 20 time units.
        input_1 = 0; select = 0; #20; // input_1 is 0
        input_1 = 1; select = 1; #20; // input_1 becomes 1
        input_1 = 0; select = 0; #20; // input_1 becomes 0
        input_1 = 1; select = 0; #20; // input_1 becomes 1

        $finish; // Stops the simulation
    end

endmodule // Ends the module definition
// Close to the multiplexer simulation, except for the operator used in the assign statement. The inputs and outputs are swapped.