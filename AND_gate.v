module AND_gate
    (
      input_1,
      input_2,
      output_1); // Defines the module name and its ports
    input input_1; 
    input input_2;
    output output_1;
    // Defines the inputs and outputs of the module

    wire and_temp; // A wire holds a value, eitheir 0 or 1

    assign and_temp = input_1 & input_2; // & is the AND operator
    assign output_1 = and_temp; // Assigns the value of and_temp to the output

endmodule // Ends the module definition
