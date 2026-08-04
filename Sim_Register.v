module dff(
    input wire d,
    input wire clk,
    output wire q
);
    reg q_reg; // q_reg is used to hold the value of q between clock cycles. It is necessary because q is an output wire, and wires cannot hold values between clock cycles.

    always @(posedge clk)
        q_reg <= d;

    assign q = q_reg;
endmodule

module Sim_Register;
    reg [3:0] ip; // [3:0] is used to defina a 4-bit input. ip0, ip1, ip2 and ip3 are four separate inputs that can be used to set the value of the register.
    reg clk;
    reg rw; // rw: read/write control signal. When rw is high, the register will write the value of ip to the register on the rising edge of clk. When rw is low, the register will hold its current value and not change on the rising edge of clk.
    wire [3:0] temp; // temp is used to hold the value of the register between clock cycles. If rw is low, temp will hold the value and wont change, and if rw is high, temp will be set to the value of ip on the rising edge of clk.
    wire [3:0] out; // out is used to hold the value of the register that is outputted. It will always be equal to temp, and will not change on the rising edge of clk.

    assign out = temp;

    dff g1(.d(rw ? ip[3] : temp[3]), .clk(clk), .q(temp[3])); // On the rising edge of the clock, set temp[3] to ip[3] if rw is high, otherwise keep temp[3] the same
    dff g2(.d(rw ? ip[2] : temp[2]), .clk(clk), .q(temp[2])); // .d is the input to the D flip-flop, .clk is the clock input, and .q is the output of the D flip-flop.
    dff g3(.d(rw ? ip[1] : temp[1]), .clk(clk), .q(temp[1])); // the ? operator is a ternary (three-argument) operator that is used to select between two values based on a condition. In this case, if rw is high, the value of ip[1] will be selected, otherwise the value of temp[1] will be selected.
    dff g4(.d(rw ? ip[0] : temp[0]), .clk(clk), .q(temp[0]));

    always #5 clk = ~clk; // This clock is used to control the inputs to the D flip-flops. It will change the inputs every 5 time units.

    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_Register);

        ip = 4'b0000; rw = 1'b0; clk = 1'b0; #10; // 4'b0000 is a 4-bit binary number with a value of 0.
        ip = 4'b1010; rw = 1'b1; #10; // 4'b1010 is a 4-bit binary number with a value of 10.
        rw = 1'b0; #10;
        ip = 4'b1111; #10; // 4'b1111 is a 4-bit binary number with a value of 15. (The highest value that can be represented with 4 bits)
        rw = 1'b1; #10;
        rw = 1'b0; #10;

        $finish;
    end
endmodule