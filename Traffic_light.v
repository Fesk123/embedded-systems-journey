module Traffic_light(
    input clk,
    input reset,
    output reg red,
    output reg yellow,
    output reg green,
    output reg [1:0] state
);
    // The state is a 2-bit register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 2'b00;
            red <= 1'b1;
            yellow <= 1'b0;
            green <= 1'b0;
        end else begin // On the rising edge of the clock, if reset is not high, it will check the value of state and set the outputs accordingly.
            case (state) // A case statement is a control flow statement that allows you to execute different blocks of code based on the value of a variable. In this case, it is checking the value of state and executing the corresponding block of code.
                2'b00: begin
                    state <= 2'b01;
                    red <= 1'b0;
                    yellow <= 1'b0;
                    green <= 1'b1;
                end // 2'b00 is a 2-bit binary number with a value of 0, so is the rest.
                2'b01: begin
                    state <= 2'b10;
                    red <= 1'b0;
                    yellow <= 1'b1;
                    green <= 1'b0;
                end
                2'b10: begin
                    state <= 2'b00;
                    red <= 1'b1;
                    yellow <= 1'b0;
                    green <= 1'b0;
                end
                default: begin // A default case is used to catch any values of state that are not explicitly handled by the other cases. For example, b'101 is not handled by any of the other cases, so it will be handled through the default case.
                    state <= 2'b00;
                    red <= 1'b1;
                    yellow <= 1'b0;
                    green <= 1'b0;
                end
            endcase
        end
    end
endmodule