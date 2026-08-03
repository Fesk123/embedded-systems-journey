module D_Flip_Flop(
    output reg Q,
    input D,
    input reset,
    input clk
    );
    // You can define the inputs and outputs in the module header. Q is the output, D is the input, reset and clk are self-explanatory.

    always @(posedge clk or posedge reset)
        begin
            if (reset)
                begin
                    Q <= 0; // If reset is high, set Q to 0
                end
            else
                begin
                    Q <= D; // Otherwise, set Q to the value of D on the rising edge of clk
                end
        end

endmodule