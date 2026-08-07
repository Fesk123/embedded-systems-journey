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

module Sim_Elevator;
    reg clk = 0;
    reg reset = 0;
    reg call_button = 0;
    reg up_down_button = 0;
    wire door_open;
    wire [1:0] state;

    Elevator dut (
        .clk(clk),
        .reset(reset),
        .call_button(call_button),
        .up_down_button(up_down_button),
        .door_open(door_open),
        .state(state)
    ); // dut (device under test) is the instance of the Elevator module that we are testing. It is connected to the inputs and outputs of the Sim_Elevator module. In python, we would say that dut is an object of the Elevator class. In verilog, we say that dut is an instance of the Elevator module.

    always #5 clk = ~clk;

    initial begin
        $dumpfile("elevator.vcd");
        $dumpvars(0, Sim_Elevator);

        reset = 1; #40;
        call_button = 1; up_down_button = 0; reset = 0; #20;
        call_button = 0; up_down_button = 1; #20;
        call_button = 0; up_down_button = 0; #20;
        reset = 1; #20;
        call_button = 1; up_down_button = 1; reset = 0; #20;
        #10;



        $finish;
    end // Standard simulation procedure.
endmodule