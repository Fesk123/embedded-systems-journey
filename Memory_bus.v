module Memory_Bus (

    // CPU
    input clk,
    input cpu_mem_enable,
    input cpu_write_enable,
    input [3:0] cpu_address, // 4 bit
    input [7:0] cpu_write_data, // 8 bit
    output [7:0] cpu_read_data,
    

    // RAM
    output ram_write_enable,
    output [3:0] ram_address, // 4 bit
    output [7:0] ram_data_in, // 8 bit
    input [7:0] ram_data_out

);

    assign ram_address = cpu_address;

    assign ram_data_in = cpu_write_data;
    
    assign ram_write_enable = cpu_mem_enable && cpu_write_enable;

    assign cpu_read_data = ram_data_out;


endmodule