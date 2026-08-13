module RAM (
    input clk,
    input we,
    input [3:0] address,
    input [7:0] data_in,
    output reg [7:0] data
);

    // Memory array
    // 16 addresses, each containing 8 bits
    reg [7:0] memory [0:15];


    // Initialize the memory
    initial begin
        memory[0]  = 8'd0;
        memory[1]  = 8'd1;
        memory[2]  = 8'd2;
        memory[3]  = 8'd3;
        memory[4]  = 8'd4;
        memory[5]  = 8'd5;
        memory[6]  = 8'd6;
        memory[7]  = 8'd7;
        memory[8]  = 8'd8;
        memory[9]  = 8'd9;
        memory[10] = 8'd10;
        memory[11] = 8'd11;
        memory[12] = 8'd12;
        memory[13] = 8'd13;
        memory[14] = 8'd14;
        memory[15] = 8'd15;
    end


    // Write to the RAM
    // Data is written on the rising edge of the clock
    // when write enable (we) is high.
    always @(posedge clk) begin
        if (we) begin
            memory[address] <= data_in;
        end
    end


    // Read from the RAM
    // The data at the selected address is sent to the output.
    always @(*) begin

        case (address)

            4'b0000: data = memory[0];  // Address 0
            4'b0001: data = memory[1];  // Address 1
            4'b0010: data = memory[2];  // Address 2
            4'b0011: data = memory[3];  // Address 3
                                        // Address etc.
            4'b0100: data = memory[4];
            4'b0101: data = memory[5];
            4'b0110: data = memory[6];
            4'b0111: data = memory[7];

            4'b1000: data = memory[8];
            4'b1001: data = memory[9];
            4'b1010: data = memory[10];
            4'b1011: data = memory[11];

            4'b1100: data = memory[12];
            4'b1101: data = memory[13];
            4'b1110: data = memory[14];
            4'b1111: data = memory[15];

            default: data = 8'b00000000; // If data is outside of the addresses, for example 6'b111111 would go to default.

        endcase

    end

endmodule