module Sim_Memory_bus;

    reg clk = 0;
    always #5 clk = ~clk; // 10 time unit period

    reg cpu_mem_enable;
    reg cpu_write_enable;
    reg [3:0] cpu_address;
    reg [7:0] cpu_write_data;
    wire [7:0] cpu_read_data;
    reg [7:0] tb_cpu_read_data;

    // Signals between Memory Bus and RAM (wires from bus)
    wire ram_write_enable;
    wire [3:0] ram_address;
    wire [7:0] ram_data_in;
    wire [7:0] ram_data_out;

    // Instantiate Memory_Bus and RAM
    Memory_Bus bus (
        .clk(clk),
        .cpu_mem_enable(cpu_mem_enable),
        .cpu_write_enable(cpu_write_enable),
        .cpu_address(cpu_address),
        .cpu_write_data(cpu_write_data),
        .cpu_read_data(cpu_read_data),
        .ram_write_enable(ram_write_enable),
        .ram_address(ram_address),
        .ram_data_in(ram_data_in),
        .ram_data_out(ram_data_out)
    );

    RAM memory (
        .clk(clk),
        .we(ram_write_enable),
        .address(ram_address),
        .data_in(ram_data_in),
        .data(ram_data_out)
    );

    integer i;

    initial begin
        $dumpfile("Sim_Memory_bus.vcd");
        $dumpvars(0, Sim_Memory_bus);

        // initialize CPU signals
        cpu_mem_enable  = 1'b0;
        cpu_write_enable = 1'b0;
        cpu_address = 4'd0;
        cpu_write_data = 8'd0;
        tb_cpu_read_data = 8'd0;

        #20; // let it settle

        // Write data to RAM addresses 0..7
        for (i = 0; i < 8; i = i + 1) begin

            @(posedge clk);
            cpu_address = i[3:0];
            cpu_write_data = 8'hA0 + i;
            cpu_mem_enable = 1'b1;
            cpu_write_enable = 1'b1;

            @(posedge clk);
            cpu_write_enable = 1'b0;
            cpu_mem_enable = 1'b0;
            #1; // to settle

        end

        #20;

        for (i = 0; i < 8; i = i + 1) begin

            @(posedge clk);
            cpu_address = i[3:0];
            cpu_mem_enable = 1'b1;
            cpu_write_enable = 1'b0;
            #1; // to settle
            tb_cpu_read_data = cpu_read_data;

            @(posedge clk);
            cpu_mem_enable = 1'b0;
            #1;
            
        end

        #50;
        $finish;
    end

endmodule