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