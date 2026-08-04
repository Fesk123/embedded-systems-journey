module dflfl(output reg op, input ip, input clk);

    always @(posedge clk) begin
        op <= ip; // On the rising edge of the clock, set the output to the value of the input
    end

endmodule

module Register(output reg [3:0] out, input [3:0] ip, input clk, input rw);
    reg [3:0]intermed;  
    reg [3:0]temp; 


    //Below are the four D flip-flops that make up the 4-bit register. If it were a n-bit register, there would be n amount D flip-flops.
    dflfl g1(temp[3], rw ? ip[3]:temp[3], clk); // On the rising edge of the clock, set temp[3] to ip[3] if rw is high, otherwise keep temp[3] the same
    dflfl g2(temp[2], rw ? ip[2]:temp[2], clk); // On the rising edge of the clock, set temp[2] to ip[2] if rw is high, otherwise keep temp[2] the same
    dflfl g3(temp[1], rw ? ip[1]:temp[1], clk); // On the rising edge of the clock, set temp[1] to ip[1] if rw is high, otherwise keep temp[1] the same
    dflfl g4(temp[0], rw ? ip[0]:temp[0], clk); // On the rising edge of the clock, set temp[0] to ip[0] if rw is high, otherwise keep temp[0] the same

    always @(*) begin //The * means that this block will be executed whenever any of the signals in the sensitivity list change. In this case, it will be executed whenever temp changes.
        if(rw==1'b1) out <= intermed; // If rw is high, set intermed to temp. 1'b1 means that rw is a 1-bit binary number with a value of 1.
        else out <= temp; // If rw is low, keep intermed the same.
    end
endmodule