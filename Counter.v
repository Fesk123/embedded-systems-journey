module counter #(parameter N = 4)(input clk, input reset, output reg [N-1:0] count);
    // parameter N = 4 is used to set the width of the counter. In this case, it is set to 4 bits.
    // We see that the parameter is used later in "output reg [N-1:0] count" to set the width of the count output to N bits.
    always @(posedge clk or posedge reset) begin
        if (reset) count <= 0; // If reset is high, set count to 0
        else count <= count + 1; // Otherwise, increment count by 1 on the rising edge of clk
    end
endmodule