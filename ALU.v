module ALU #(
    parameter DATA_WIDTH = 8 // Set to a byte.
)(
    input  [DATA_WIDTH-1:0] A,
    input  [DATA_WIDTH-1:0] B,
    input  [3:0] operation,

    output reg [DATA_WIDTH-1:0] result,
    output reg zero
);
    // The system does not use a clock, therefore its asynchronous.


    // Operation codes
    localparam ADD = 4'b0000;
    localparam SUB = 4'b0001;
    localparam AND = 4'b0010;
    localparam OR  = 4'b0011;
    localparam XOR = 4'b0100;
    localparam SHL = 4'b0101;
    localparam SHR = 4'b0110;
    localparam CMP = 4'b0111;


    always @(*) begin

        case (operation)

            // Addition
            ADD: begin
                result = A + B;
            end

            // Subtraction
            SUB: begin
                result = A - B;
            end

            // Bitwise AND
            AND: begin
                result = A & B;
            end

            // Bitwise OR
            OR: begin
                result = A | B;
            end

            // Bitwise XOR
            XOR: begin
                result = A ^ B;
            end

            // Shift A left
            SHL: begin
                result = A << 1;
            end

            // Shift A right
            SHR: begin
                result = A >> 1;
            end

            // Compare A and B
            // The largest value is selected.
            CMP: begin
                if (A >= B)
                    result = A;
                else
                    result = B;
            end

            // Default
            default: begin
                result = 0;
            end

        endcase


        // Zero flag
        if (result == 0)
            zero = 1'b1;
        else
            zero = 1'b0;

    end

endmodule