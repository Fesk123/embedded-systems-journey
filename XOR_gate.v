module XOR_gate
    (
      input_1,
      input_2,
      output_1); 
    input input_1; 
    input input_2;
    output output_1;
    // Defines the inputs and outputs of the module

    wire xor_temp; // A wire holds a value, either 0 or 1

    assign xor_temp = input_1 ^ input_2; // ^ is the XOR operator
    assign output_1 = xor_temp; // Assigns the value of xor_temp to the output

endmodule // Ends the module definition
// Again, most of the code is the same as the past, except for the operator used in the assign statement.