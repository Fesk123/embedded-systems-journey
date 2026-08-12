module ROM (
    input  [3:0] address,
    output reg [7:0] data  
    );

    always @(*) begin
        case (address)

            4'b0000: data = 8'b10101010; // Address 0
            4'b0001: data = 8'b11110000; // Address 1
            4'b0010: data = 8'b01010101; // Address 2
            4'b0011: data = 8'b00001111; // Address 3
                                         // Address etc.
            4'b0100: data = 8'b11001100;
            4'b0101: data = 8'b00110011;
            4'b0110: data = 8'b11111111;
            4'b0111: data = 8'b00000000;

            4'b1000: data = 8'b00000000;
            4'b1001: data = 8'b00000000;
            4'b1010: data = 8'b00000000;
            4'b1011: data = 8'b00000000;

            4'b1100: data = 8'b00000000;
            4'b1101: data = 8'b00000000;
            4'b1110: data = 8'b00000000;
            4'b1111: data = 8'b00000000;

            default: data = 8'b00000000; // If data is outside of the addresses, for example 6'b111111 would go to default.

        endcase
    end

endmodule


module Sim_ROM;
    reg [3:0] address;
    wire [7:0] data;

    ROM dut (
        .address(address),
        .data(data)
    );

    initial begin
        $dumpfile("Sim_ROM.vcd");
        $dumpvars(0, Sim_ROM);

        // cycle through all addresses with a visible delay
        address = 4'b0000;
        #5;

        repeat (15) begin
            #10;
            address = address + 1;
            #1; // small settle time before reading
        end

        #20;
        $finish;
    end
endmodule