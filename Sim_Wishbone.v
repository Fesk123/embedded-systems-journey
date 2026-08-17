`timescale 1ns/1ps // Sets the time to scale one nanosecond, with the precision of one picosecond

module Sim_Wishbone;

    reg CLK_I;

    always #5 CLK_I = ~CLK_I;

    reg RST_I;

    reg cpu_start;
    reg cpu_write;
    reg [3:0] cpu_address;
    reg [7:0] cpu_write_data;

    wire [7:0] cpu_read_data;
    wire cpu_done;

    wire [3:0] ADR_W;
    wire [7:0] DAT_W_O;
    wire [7:0] DAT_W_I;

    wire CYC_W;
    wire STB_W;
    wire WE_W;
    wire ACK_W;



    wishbone_master master (

        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .cpu_start(cpu_start),
        .cpu_write(cpu_write),
        .cpu_address(cpu_address),
        .cpu_write_data(cpu_write_data),

        .cpu_read_data(cpu_read_data),
        .cpu_done(cpu_done),

        .ADR_O(ADR_W),
        .DAT_O(DAT_W_O),
        .DAT_I(DAT_W_I),

        .CYC_O(CYC_W),
        .STB_O(STB_W),
        .WE_O(WE_W),

        .ACK_I(ACK_W)

    );


    wishbone_ram slave (

        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .ADR_I(ADR_W),
        .DAT_I(DAT_W_O),
        .DAT_O(DAT_W_I),

        .CYC_I(CYC_W),
        .STB_I(STB_W),
        .WE_I(WE_W),

        .ACK_O(ACK_W)

    );

    task write_byte;

        input [3:0] address;
        input [7:0] value;

        begin

            // Set inputs away from rising edge
            @(negedge CLK_I);

            cpu_address = address;
            cpu_write_data = value;
            cpu_write = 1'b1;
            cpu_start = 1'b1;

            // Give master one rising edge to detect start
            @(posedge CLK_I);
            @(negedge CLK_I);

            cpu_start = 1'b0;

            // Wait for transaction to finish
            wait(cpu_done == 1'b1);

            // Allow done to return low
            @(posedge CLK_I);

        end

    endtask

    task read_byte;

        input [3:0] address;

        begin

            @(negedge CLK_I);

            cpu_address = address;
            cpu_write = 1'b0;
            cpu_start = 1'b1;

            @(posedge CLK_I);

            @(negedge CLK_I);

            cpu_start = 1'b0;

            // Wait for master to finish
            wait(cpu_done == 1'b1);

            #1;

            @(posedge CLK_I);

        end

    endtask

    initial begin

        $dumpfile("Sim_Wishbone.vcd");
        $dumpvars(0, Sim_Wishbone);

        CLK_I = 1'b0;
        RST_I = 1'b1;
        cpu_start = 1'b0;
        cpu_write = 1'b0;
        cpu_address = 4'b0000;
        cpu_write_data = 8'b00000000;

        #20;

        RST_I = 1'b0;

        #20;

        write_byte(4'd0, 8'hA0);
        write_byte(4'd1, 8'hA1);
        write_byte(4'd2, 8'hA2);
        write_byte(4'd3, 8'hA3);

        read_byte(4'd0);
        read_byte(4'd1);
        read_byte(4'd2);
        read_byte(4'd3);


        #20;

        $finish;

    end

endmodule