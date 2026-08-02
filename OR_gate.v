module OR_gate
    (
      input_1,
      input_2,
      output_1); // Defines the module name and its ports
    input input_1; 
    input input_2;
    output output_1;
    // Defines the inputs and outputs of the module

    wire or_temp; // A wire holds a value, either 0 or 1

    assign or_temp = input_1 | input_2; // | is the OR operator
    assign output_1 = or_temp; // Assigns the value of or_temp to the output

endmodule // Ends the module definition
// Most of the code is the same as the AND gate, except for the operator used in the assign statement.