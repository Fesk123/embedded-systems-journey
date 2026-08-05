module dflfl(output reg op, input ip, input clk);

    always @(posedge clk) begin
        op <= ip; // On the rising edge of the clock, set the output to the value of the input
    end
endmodule

module siso(output reg [3:0] out,
    input ip,
    input clk,
    input en);

    reg [3:0] temp;

    dflfl g1(temp[3], en ? ip:out[3], clk); // On the rising edge of the clock, set temp[3] to ip if en is high, otherwise keep temp[3] the same
    dflfl g2(temp[2], en ? out[3]:out[2], clk); // On the rising edge of the clock, set temp[2] to out[3] if en is high, otherwise keep temp[2] the same
    dflfl g3(temp[1], en ? out[2]:out[1], clk); // On the rising edge of the clock, set temp[1] to out[2] if en is high, otherwise keep temp[1] the same
    dflfl g4(temp[0], en ? out[1]:out[0], clk); // On the rising edge of the clock, set temp[0] to out[1] if en is high, otherwise keep temp[0] the same

endmodule