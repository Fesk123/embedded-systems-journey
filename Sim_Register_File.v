module Register_File (
    input clk,

    input  write_enable,
    input  [2:0] write_address,
    input  [7:0] write_data,

    // Read port 1
    input  [2:0] read_address_1,
    output [7:0] read_data_1,

    // Read port 2
    input  [2:0] read_address_2,
    output [7:0] read_data_2
);

    // 8 registers, each 8 bits wide
    reg [7:0] registers [0:7];


    // Synchronous, it depends on the clock.
    always @(posedge clk) begin
        if (write_enable) begin
            registers[write_address] <= write_data;
        end
    end


    // Asynchronous, it does not depend on the clock.
    assign read_data_1 = registers[read_address_1];
    assign read_data_2 = registers[read_address_2];

endmodule

module Sim_Register_File;
    reg clk;
    reg write_enable;
    reg [2:0] write_address;
    reg [7:0] write_data;

    reg [2:0] read_address_1;
    wire [7:0] read_data_1;

    reg [2:0] read_address_2;
    wire [7:0] read_data_2;


    // Instantiate Register File
    Register_File dut (
        .clk(clk),
        .write_enable(write_enable),
        .write_address(write_address),
        .write_data(write_data),
        .read_address_1(read_address_1),
        .read_data_1(read_data_1),
        .read_address_2(read_address_2),
        .read_data_2(read_data_2)
    );


    // Clock period = 10 time units
    always #5 clk = ~clk;


    integer i;


    initial begin

        $dumpfile("Sim_Register_File.vcd");
        $dumpvars(0, Sim_Register_File);

        clk = 0;
        write_enable = 0;
        write_address = 3'b000;
        write_data = 8'h00;

        read_address_1 = 3'b000;
        read_address_2 = 3'b000;

        #10;

        for (i = 0; i < 8; i = i + 1) begin

            write_address = i;
            write_data = 8'h10 + i;
            write_enable = 1'b1;

            @(posedge clk);

            #1;
            write_enable = 1'b0;

            #2;
        end

        #10;

        for (i = 0; i < 8; i = i + 1) begin

            read_address_1 = i;
            read_address_2 = 7 - i;

            #10;

        end

        write_address = 3'd3;
        write_data = 8'hFF;
        write_enable = 1'b0;

        @(posedge clk);
        #1;

        write_address = 3'd3;
        write_data = 8'h77;
        write_enable = 1'b1;

        @(posedge clk);

        #1;
        write_enable = 1'b0;

        #1;


        #20;

        $finish;

    end

endmodule