module Demultiplexer
    (
      input_1,
      select,
      output_1,
      output_2); // Defines the module name and its ports

    // Defines the inputs and outputs of the module
    input input_1, select;
    output output_1, output_2;
    // You can also define the inputs and outputs in a single line

    assign output_1 = input_1 & ~select; // If select is 0, output_1 is input_1, else output_1 is 0
    assign output_2 = input_1 & select; // If select is 1, output_2 is input_1, else output_2 is 0
    

endmodule // Ends the module definition

// Less of the code is the same as before, additional logic is added and a new variable is defined in the module.