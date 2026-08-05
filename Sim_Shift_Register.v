module dff(
    input wire d,
    input wire clk,
    output reg q
);
    initial q = 1'b0;

    always @(posedge clk)
        q <= d;
endmodule

module Sim_Shift_Register;
    reg [3:0] ip; // [3:0] is used to defina a 4-bit input. ip0, ip1, ip2 and ip3 are four separate inputs that can be used to set the value of the register.
    reg clk;
    reg en; // rw: read/write control signal. When rw is high, the register will write the value of ip to the register on the rising edge of clk. When rw is low, the register will hold its current value and not change on the rising edge of clk.
    wire [3:0] temp; // temp is used to hold the value of the register between clock cycles. If rw is low, temp will hold the value and wont change, and if rw is high, temp will be set to the value of ip on the rising edge of clk.
    wire [3:0] out; // out is used to hold the value of the register that is outputted. It will always be equal to temp, and will not change on the rising edge of clk.

    assign out = temp;

    dff g1(.d(en ? ip[3] : out[3]), .clk(clk), .q(temp[3])); // The same as regular registers, but the input to the D flip-flop is now a ternary (three-argument) operator that is used to select between two values based on a condition. In this case, if en is high, the value of ip[3] will be selected, otherwise the value of out[3] will be selected.
    dff g2(.d(en ? out[3] : out[2]), .clk(clk), .q(temp[2]));
    dff g3(.d(en ? out[2] : out[1]), .clk(clk), .q(temp[1]));
    dff g4(.d(en ? out[1] : out[0]), .clk(clk), .q(temp[0]));

    always #5 clk = ~clk; // This clock is used to control the inputs to the D flip-flops. It will change the inputs every 5 time units.

    initial begin
        $dumpfile("gate.vcd");
        $dumpvars(0, Sim_Shift_Register);

        ip = 4'b0000;
        en = 1'b0;
        clk = 1'b0;
        #2;

        ip = 4'b1010;
        en = 1'b1;
        #10;

        en = 1'b0;
        #10;

        ip = 4'b1111;
        #10;

        en = 1'b1;
        #10;

        en = 1'b0;
        #10;

        $finish;
    end
endmodule