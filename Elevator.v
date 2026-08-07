module Elevator(
    input clk,
    input reset,
    input call_button,
    input up_down_button,
    output reg door_open,
    output reg [1:0] state // 2'b00: idle, 2'b01: Moving up, 2'b10: Moving down
);
    // The state is a 2-bit register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 2'b00;
            door_open <= 1'b0; // The door is closed when the elevator is reset.
        end else begin // On the rising edge of the clock, if reset is not high, it will check the value of state and set the outputs accordingly.
            case (state) // A case statement is a control flow statement that allows you to execute different blocks of code based on the value of a variable. In this case, it is checking the value of state and executing the corresponding block of code.
                2'b00: begin
                    if (call_button) begin
                        state <= 2'b01;
                        door_open <= 1'b0; // The door is closed when the elevator is moving.
                    end else if (!call_button) begin
                        state <= 2'b00;
                        door_open <= 1'b1; // The door is open when the elevator is idle.
                        if (up_down_button) begin
                            state <= 2'b10;
                        end else if (!up_down_button) begin
                            state <= 2'b00;
                        end
                    end 
                    
                end
                2'b01: begin
                    state <= 2'b00;
                    door_open <= 1'b0;
                end
                2'b10: begin
                    state <= 2'b00;
                    door_open <= 1'b0;
                end
            endcase
        end
    end
endmodule