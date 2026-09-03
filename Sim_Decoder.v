module Sim_Decoder;

    reg input_1, input_2;
    wire output_1, output_2, output_3, output_4;

    // Defines the inputs and outputs of the module as before

    wire not_input_1, not_input_2;

    // These wires are used to hold the inverted values of the inputs.

    not (
        not_input_1,
        input_1
    );
    not (
        not_input_2,
        input_2
    );

    // The not gates invert the values of the inputs. If input_1 is 0, not_input_1 will be 1, and vice versa.

    and (output_1, not_input_1, not_input_2);
    and (output_2, not_input_1, input_2);
    and (output_3, input_1, not_input_2);
    and (output_4, input_1, input_2);

    // The and gates combine the inverted and non-inveted inputs to produce the outputs. Each output corresponds to a unique combination of the inputs.


    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_Decoder);

        input_1 = 0; input_2 = 0; #20; // Both inputs are 0, targets output_1 to be 1
        input_1 = 0; input_2 = 1; #20; // input_2 becomes 1, targets output_2 to be 1
        input_1 = 1; input_2 = 0; #20; // input_1 becomes 1, targets output_3 to be 1
        input_1 = 1; input_2 = 1; #20; // Both inputs are 1, targets output_4 to be 1

        $finish; // Stops the simulation
    end

endmodule