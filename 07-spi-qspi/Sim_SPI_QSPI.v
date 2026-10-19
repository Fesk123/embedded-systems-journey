`timescale 1ns/1ps

// SPI + QSPI CONTROLLERS
//
// It uses three clearly separated scenarios:
//
// Scenario 1: SPI 8-bit MSB-first transfer with loopback.
// Scenario 2: QSPI 16-byte quad write across two TX words.
// Scenario 3: QSPI 8-byte quad read with a simulated flash response.

module Sim_SPI_QSPI;

    reg CLK_I;
    reg RST_I;

    reg [3:0] scenario;
    reg [7:0] checkpoint;
    
    // SPI WISHBONE SIGNALS    

    reg [63:0] spi_ADR_I;
    reg [63:0] spi_DAT_I;
    wire [63:0] spi_DAT_O;
    reg [7:0] spi_SEL_I;
    reg spi_CYC_I;
    reg spi_STB_I;
    reg spi_WE_I;
    wire spi_ACK_O;
    wire spi_ERR_O;

    wire SPI_SCK_O;
    wire SPI_MOSI_O;
    wire SPI_MISO_I;
    wire [3:0] SPI_CS_N_O;

    wire spi_IRQ_O;
    wire spi_debug_busy;
    wire spi_debug_done;
    wire spi_debug_error;
    wire [2:0] spi_debug_state;
    wire [6:0] spi_debug_bit_count;
    wire [15:0] spi_debug_clk_count;
    wire [63:0] spi_debug_rx_data;

    // QSPI WISHBONE SIGNALS

    reg [63:0] qspi_ADR_I;
    reg [63:0] qspi_DAT_I;
    wire [63:0] qspi_DAT_O;
    reg [7:0] qspi_SEL_I;
    reg qspi_CYC_I;
    reg qspi_STB_I;
    reg qspi_WE_I;
    wire qspi_ACK_O;
    wire qspi_ERR_O;

    wire QSPI_SCK_O;
    wire QSPI_CS_N_O;
    wire [3:0] QSPI_IO_I;
    wire [3:0] QSPI_IO_O;
    wire [3:0] QSPI_IO_OE;

    wire qspi_IRQ_O;
    wire qspi_debug_busy;
    wire qspi_debug_done;
    wire qspi_debug_error;
    wire [2:0] qspi_debug_state;
    wire [7:0] qspi_debug_phase_count;
    wire [63:0] qspi_debug_rx_data;

    // SIMULATION CONTROL AND FLASH MODEL    

    reg [63:0] qspi_model_data;
    reg qspi_read_model_enable;
    reg [63:0] tx_word_0;
    reg [63:0] tx_word_1;
    reg [63:0] temp_data;

    assign SPI_MISO_I = SPI_MOSI_O;

    assign QSPI_IO_I = (qspi_read_model_enable && (qspi_debug_state == 3'd4)) ? ((qspi_model_data >> (60 - (qspi_debug_phase_count * 4))) & 4'hF) : 4'h0;

    // DUT INSTANCES    

    SPI spi_dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(spi_ADR_I),
        .DAT_I(spi_DAT_I),
        .DAT_O(spi_DAT_O),
        .SEL_I(spi_SEL_I),
        .CYC_I(spi_CYC_I),
        .STB_I(spi_STB_I),
        .WE_I(spi_WE_I),
        
        .ACK_O(spi_ACK_O),
        .ERR_O(spi_ERR_O),
        .SPI_SCK_O(SPI_SCK_O),
        .SPI_MOSI_O(SPI_MOSI_O),
        .SPI_MISO_I(SPI_MISO_I),
        .SPI_CS_N_O(SPI_CS_N_O),
        .IRQ_O(spi_IRQ_O),
        
        .debug_busy(spi_debug_busy),
        .debug_done(spi_debug_done),
        .debug_error(spi_debug_error),
        .debug_state(spi_debug_state),
        .debug_bit_count(spi_debug_bit_count),
        .debug_clk_count(spi_debug_clk_count),
        .debug_rx_data(spi_debug_rx_data)
    );

    QSPI qspi_dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(qspi_ADR_I),
        .DAT_I(qspi_DAT_I),
        .DAT_O(qspi_DAT_O),
        .SEL_I(qspi_SEL_I),
        .CYC_I(qspi_CYC_I),
        .STB_I(qspi_STB_I),
        .WE_I(qspi_WE_I),
        .ACK_O(qspi_ACK_O),
        .ERR_O(qspi_ERR_O),
        
        .QSPI_SCK_O(QSPI_SCK_O),
        .QSPI_CS_N_O(QSPI_CS_N_O),
        .QSPI_IO_I(QSPI_IO_I),
        .QSPI_IO_O(QSPI_IO_O),
        .QSPI_IO_OE(QSPI_IO_OE),
        
        .IRQ_O(qspi_IRQ_O),
        .debug_busy(qspi_debug_busy),
        .debug_done(qspi_debug_done),
        .debug_error(qspi_debug_error),
        .debug_state(qspi_debug_state),
        .debug_phase_count(qspi_debug_phase_count),
        .debug_rx_data(qspi_debug_rx_data)
    );

    // CLOCK AND WAVEFORM DUMP

    initial begin
        CLK_I = 1'b0;
        forever #5 CLK_I = ~CLK_I;
    end

    initial begin
        $dumpfile("Sim_SPI_QSPI.vcd");
        $dumpvars(0, Sim_SPI_QSPI);
    end
    
    // SPI WISHBONE TASKS    

    task spi_wb_xfer;
        input write_enable;
        input [63:0] address;
        input [63:0] write_data;
        input [7:0] byte_select;
        output [63:0] read_data;
        output got_ack;
        output got_error;
        
        reg [63:0] read_data;
        reg got_ack;
        reg got_error;
        integer wait_count;
        reg response_seen;
        
        begin
            read_data = 64'd0;
            got_ack = 1'b0;
            got_error = 1'b0;
            response_seen = 1'b0;

            @(negedge CLK_I);
            spi_ADR_I = address;
            spi_DAT_I = write_data;
            spi_SEL_I = byte_select;
            spi_WE_I = write_enable;
            spi_CYC_I = 1'b1;
            spi_STB_I = 1'b1;

            for (wait_count = 0; wait_count < 100; wait_count = wait_count + 1) begin
                @(posedge CLK_I);
                #1;
                if ((spi_ACK_O === 1'b1) || (spi_ERR_O === 1'b1)) begin
                    read_data = spi_DAT_O;
                    got_ack = spi_ACK_O;
                    got_error = spi_ERR_O;
                    response_seen = 1'b1;
                    wait_count = 100;
                end
            end

            if (!response_seen) begin
                got_ack = 1'b0;
                got_error = 1'b0;
            end

            @(negedge CLK_I);
            spi_CYC_I = 1'b0;
            spi_STB_I = 1'b0;
            spi_WE_I = 1'b0;
            @(posedge CLK_I);
            #1;
        end
    endtask

    task spi_wb_write;
        input [63:0] address;
        input [63:0] write_data;
        reg [63:0] unused_data;
        reg got_ack;
        reg got_error;
        
        begin
            spi_wb_xfer(1'b1, address, write_data, 8'hFF, unused_data, got_ack, got_error);
        end
    
    endtask

    task spi_wb_read;
        input [63:0] address;
        output [63:0] read_data;
        reg [63:0] value;
        reg got_ack;
        reg got_error;
    
        begin
            spi_wb_xfer(1'b0, address, 64'd0, 8'hFF, value, got_ack, got_error);
            read_data = value;
        end
    
    endtask

    task wait_spi_done;
        integer wait_count;
        begin
            for (wait_count = 0; wait_count < 2000; wait_count = wait_count + 1) begin
                @(posedge CLK_I);
                #1;

                if (spi_debug_done === 1'b1)
                    wait_count = 2000;
            end
        end
    endtask

    
    // QSPI WISHBONE TASKS
    

    task qspi_wb_xfer;
        input write_enable;
        input [63:0] address;
        input [63:0] write_data;
        input [7:0] byte_select;
        
        output [63:0] read_data;
        output got_ack;
        output got_error;
        
        reg [63:0] read_data;
        reg got_ack;
        reg got_error;
        integer wait_count;
        reg response_seen;
        
        begin
            read_data = 64'd0;
            got_ack = 1'b0;
            got_error = 1'b0;
            response_seen = 1'b0;

            @(negedge CLK_I);
            qspi_ADR_I = address;
            qspi_DAT_I = write_data;
            qspi_SEL_I = byte_select;
            qspi_WE_I = write_enable;
            qspi_CYC_I = 1'b1;
            qspi_STB_I = 1'b1;

            for (wait_count = 0; wait_count < 100; wait_count = wait_count + 1) begin
                @(posedge CLK_I);
                #1;
        
                if ((qspi_ACK_O === 1'b1) || (qspi_ERR_O === 1'b1)) begin
                    read_data = qspi_DAT_O;
                    got_ack = qspi_ACK_O;
                    got_error = qspi_ERR_O;
                    response_seen = 1'b1;
                    wait_count = 100;
                end
        
            end

            if (!response_seen) begin
                got_ack = 1'b0;
                got_error = 1'b0;
            end

            @(negedge CLK_I);
            qspi_CYC_I = 1'b0;
            qspi_STB_I = 1'b0;
            qspi_WE_I = 1'b0;
            @(posedge CLK_I);
            #1;
        end
    endtask

    task qspi_wb_write;
        input [63:0] address;
        input [63:0] write_data;
        reg [63:0] unused_data;
        reg got_ack;
        reg got_error;
        
        begin
            qspi_wb_xfer(1'b1, address, write_data, 8'hFF, unused_data, got_ack, got_error);
        
        end
    
    endtask

    task qspi_wb_read;
        input [63:0] address;
        output [63:0] read_data;
        reg [63:0] value;
        reg got_ack;
        reg got_error;
       
        begin
            qspi_wb_xfer(1'b0, address, 64'd0, 8'hFF, value, got_ack, got_error);
            read_data = value;
    
        end
    endtask

    task wait_qspi_done;
        integer wait_count;
        begin
            for (wait_count = 0; wait_count < 10000; wait_count = wait_count + 1) begin
                @(posedge CLK_I);
                #1;
                if (qspi_debug_done === 1'b1)
                    wait_count = 10000;
            end
        end
    endtask

    // MAIN WAVEFORM SCENARIOS

    initial begin
        RST_I = 1'b1;
        scenario = 4'd0;
        checkpoint = 8'd0;

        spi_ADR_I = 64'd0;
        spi_DAT_I = 64'd0;
        spi_SEL_I = 8'hFF;
        spi_CYC_I = 1'b0;
        spi_STB_I = 1'b0;
        spi_WE_I = 1'b0;

        qspi_ADR_I = 64'd0;
        qspi_DAT_I = 64'd0;
        qspi_SEL_I = 8'hFF;
        qspi_CYC_I = 1'b0;
        qspi_STB_I = 1'b0;
        qspi_WE_I = 1'b0;

        qspi_model_data = 64'h1122_3344_5566_7788;
        qspi_read_model_enable = 1'b0;
        tx_word_0 = 64'h0123_4567_89AB_CDEF;
        tx_word_1 = 64'h1021_3243_5465_7687;
        temp_data = 64'd0;

        repeat (5) @(posedge CLK_I);
        @(negedge CLK_I);
        RST_I = 1'b0;
        scenario = 4'd1;
        checkpoint = 8'd1;

        // SCENARIO 1
        // SPI LOOPBACK TRANSFER
        // Expected capture window: 0 ns to 950 ns.

        spi_wb_write(64'h38, 64'd1);
        spi_wb_write(64'h10, 64'd0);
        spi_wb_write(64'h28, 64'd8);
        spi_wb_write(64'h30, 64'd1);
        spi_wb_write(64'h18, 64'hA5);
        checkpoint = 8'd2;
        spi_wb_write(64'h00, 64'h01);

        checkpoint = 8'd3;
        wait_spi_done;
        checkpoint = 8'd4;
        spi_wb_read(64'h20, temp_data);

        if ($time < 1000)
            #(1000 - $time);

        // SCENARIO 2
        // QSPI 16-BYTE QUAD WRITE
        // Expected capture window: 1000 ns to 2250 ns.

        scenario = 4'd2;
        checkpoint = 8'd10;
        qspi_wb_write(64'h00, 64'h10);
        qspi_wb_write(64'h10, 64'd0);
        qspi_wb_write(64'h50, 64'd1);
        qspi_wb_write(64'h18, 64'h32);
        qspi_wb_write(64'h20, 64'h0012_3456);
        qspi_wb_write(64'h38, 64'd16);
        qspi_wb_write(64'h40, 64'd3);
        qspi_wb_write(64'h48, 64'd0);
        qspi_wb_write(64'h58, 64'd0);
        qspi_wb_write(64'h28, tx_word_0);
        qspi_wb_write(64'h28, tx_word_1);

        checkpoint = 8'd11;
        qspi_wb_write(64'h00, 64'h0F);
        checkpoint = 8'd12;

        while (qspi_debug_state != 3'd4)
            @(posedge CLK_I);
        checkpoint = 8'd13;

        wait_qspi_done;
        checkpoint = 8'd14;
        qspi_wb_read(64'h68, temp_data);

        if ($time < 2300)
            #(2300 - $time);

        // SCENARIO 3
        // QSPI 8-BYTE QUAD READ
        // Expected capture window: 2300 ns to 3350 ns.        

        scenario = 4'd3;
        checkpoint = 8'd20;
        qspi_read_model_enable = 1'b1;
        qspi_wb_write(64'h18, 64'hEB);
        qspi_wb_write(64'h20, 64'h0000_2345);
        qspi_wb_write(64'h38, 64'd8);
        qspi_wb_write(64'h40, 64'd3);
        qspi_wb_write(64'h48, 64'd2);
        qspi_wb_write(64'h60, 64'd0);

        checkpoint = 8'd21;
        qspi_wb_write(64'h00, 64'h0D);

        while (qspi_debug_state != 3'd4)
            @(posedge CLK_I);
        checkpoint = 8'd22;

        wait_qspi_done;
        checkpoint = 8'd23;
        qspi_wb_read(64'h30, temp_data);
        checkpoint = 8'd24;

        if ($time < 3400)
            #(3400 - $time);

        scenario = 4'd0;
        checkpoint = 8'd0;
        #50;
        $finish;
    end

endmodule