module Sim_ALU;
    reg [7:0] A;
    reg [7:0] B;
    reg [3:0] operation;

    wire [7:0] result;
    wire zero;

    // instantiate the ALU (defined in ALU.v)
    ALU dut (
        .A(A),
        .B(B),
        .operation(operation),
        .result(result),
        .zero(zero)
    );

    integer i;

    initial begin
        $dumpfile("Sim_ALU.vcd");
        $dumpvars(0, Sim_ALU, dut);

        // cycle through operations ADD..CMP (0..7)
        for (i = 0; i < 8; i = i + 1) begin
            operation = i;
            A = 8'h10 + i;
            B = 8'h03 + i;
            #1;
            #9;
        end

        // SUB with equal operands to produce zero flag
        operation = 4'b0001;
        A = 8'h55;
        B = 8'h55;
        #1;

        #10;
        $finish;
    end
endmodule
