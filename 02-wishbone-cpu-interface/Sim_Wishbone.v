`timescale 1ns/1ps

// WISHBONE GTKWave TESTBENCH
// Focused waveform verification
//
// The testbench is divided into three waveform sections:
//
// Section 1 - Classic transfer + SEL + wait states
// Section 2 - Incrementing burst transfer
// Section 3 - Two-master arbitration
//
// Use wave_section to find the three sections in GTKWave.


module Sim_Wishbone;

    reg CLK_I;
    reg RST_I;

    reg [3:0] wave_section;


    // SECTION 1 / 2
    // Direct master and RAM


    reg direct_cpu_start;
    reg direct_cpu_write;
    reg direct_cpu_burst;
    reg [4:0] direct_cpu_burst_length;
    reg [63:0] direct_cpu_address;
    reg [63:0] direct_cpu_write_data;
    reg [7:0] direct_cpu_select;
    reg [1023:0] direct_cpu_burst_write_data;

    wire [63:0] direct_cpu_read_data;
    wire [1023:0] direct_cpu_burst_read_data;
    wire [4:0] direct_cpu_beat_index;
    wire direct_cpu_beat_done;
    wire direct_cpu_done;
    wire direct_cpu_error;

    wire [63:0] direct_ADR_O;
    wire [63:0] direct_DAT_O;
    wire [63:0] direct_DAT_I;
    wire [7:0] direct_SEL_O;
    wire direct_CYC_O;
    wire direct_STB_O;
    wire direct_WE_O;
    wire [2:0] direct_CTI_O;
    wire [1:0] direct_BTE_O;
    wire direct_ACK_I;
    wire direct_ERR_I;

    Wishbone_Master #(
        .ADDR_WIDTH(64),
        .DATA_WIDTH(64),
        .MAX_BURST_LENGTH(16)
        
    ) direct_master (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .cpu_start(direct_cpu_start),
        .cpu_write(direct_cpu_write),
        .cpu_burst(direct_cpu_burst),
        .cpu_burst_length(direct_cpu_burst_length),
        .cpu_address(direct_cpu_address),
        .cpu_write_data(direct_cpu_write_data),
        .cpu_select(direct_cpu_select),
        .cpu_burst_write_data(direct_cpu_burst_write_data),
        .cpu_read_data(direct_cpu_read_data),
        .cpu_burst_read_data(direct_cpu_burst_read_data),
        .cpu_beat_index(direct_cpu_beat_index),
        .cpu_beat_done(direct_cpu_beat_done),
        .cpu_done(direct_cpu_done),
        .cpu_error(direct_cpu_error),
        .ADR_O(direct_ADR_O),
        .DAT_O(direct_DAT_O),
        .DAT_I(direct_DAT_I),
        .SEL_O(direct_SEL_O),
        .CYC_O(direct_CYC_O),
        .STB_O(direct_STB_O),
        .WE_O(direct_WE_O),
        .CTI_O(direct_CTI_O),
        .BTE_O(direct_BTE_O),
        .ACK_I(direct_ACK_I),
        .ERR_I(direct_ERR_I)
    );

    Wishbone_RAM #(
        .ADDR_WIDTH(64),
        .DATA_WIDTH(64),
        .MEMORY_WORDS(256),
        .WAIT_STATES(2)
    ) direct_ram (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(direct_ADR_O),
        .DAT_I(direct_DAT_O),
        .DAT_O(direct_DAT_I),
        .SEL_I(direct_SEL_O),
        .CYC_I(direct_CYC_O),
        .STB_I(direct_STB_O),
        .WE_I(direct_WE_O),
        .CTI_I(direct_CTI_O),
        .BTE_I(direct_BTE_O),
        .ACK_O(direct_ACK_I),
        .ERR_O(direct_ERR_I)
    );


    // SECTION 3
    // Two masters + interconnect + two visible slaves


    reg m0_cpu_start;
    reg m0_cpu_write;
    reg m0_cpu_burst;
    reg [4:0] m0_cpu_burst_length;
    reg [63:0] m0_cpu_address;
    reg [63:0] m0_cpu_write_data;
    reg [7:0] m0_cpu_select;
    reg [1023:0] m0_cpu_burst_write_data;

    reg m1_cpu_start;
    reg m1_cpu_write;
    reg m1_cpu_burst;
    reg [4:0] m1_cpu_burst_length;
    reg [63:0] m1_cpu_address;
    reg [63:0] m1_cpu_write_data;
    reg [7:0] m1_cpu_select;
    reg [1023:0] m1_cpu_burst_write_data;

    wire [63:0] m0_cpu_read_data;
    wire [1023:0] m0_cpu_burst_read_data;
    wire [4:0] m0_cpu_beat_index;
    wire m0_cpu_beat_done;
    wire m0_cpu_done;
    wire m0_cpu_error;

    wire [63:0] m1_cpu_read_data;
    wire [1023:0] m1_cpu_burst_read_data;
    wire [4:0] m1_cpu_beat_index;
    wire m1_cpu_beat_done;
    wire m1_cpu_done;
    wire m1_cpu_error;

    wire [63:0] m0_ADR_O;
    wire [63:0] m0_DAT_O;
    wire [63:0] m0_DAT_I;
    wire [7:0] m0_SEL_O;
    wire m0_CYC_O;
    wire m0_STB_O;
    wire m0_WE_O;
    wire [2:0] m0_CTI_O;
    wire [1:0] m0_BTE_O;
    wire m0_ACK_I;
    wire m0_ERR_I;

    wire [63:0] m1_ADR_O;
    wire [63:0] m1_DAT_O;
    wire [63:0] m1_DAT_I;
    wire [7:0] m1_SEL_O;
    wire m1_CYC_O;
    wire m1_STB_O;
    wire m1_WE_O;
    wire [2:0] m1_CTI_O;
    wire [1:0] m1_BTE_O;
    wire m1_ACK_I;
    wire m1_ERR_I;

    wire m0_grant;
    wire m1_grant;

    wire [63:0] s0_ADR;
    wire [63:0] s0_DAT_O;
    wire [63:0] s0_DAT_I;
    wire [7:0] s0_SEL;
    wire s0_CYC;
    wire s0_STB;
    wire s0_WE;
    wire [2:0] s0_CTI;
    wire [1:0] s0_BTE;
    wire s0_ACK;
    wire s0_ERR;

    wire [63:0] s1_ADR;
    wire [63:0] s1_DAT_O;
    wire [63:0] s1_DAT_I;
    wire [7:0] s1_SEL;
    wire s1_CYC;
    wire s1_STB;
    wire s1_WE;
    wire [2:0] s1_CTI;
    wire [1:0] s1_BTE;
    wire s1_ACK;
    wire s1_ERR;

    wire [63:0] s2_ADR;
    wire [63:0] s2_DAT_O;
    wire [63:0] s2_DAT_I;
    wire [7:0] s2_SEL;
    wire s2_CYC;
    wire s2_STB;
    wire s2_WE;
    wire [2:0] s2_CTI;
    wire [1:0] s2_BTE;
    wire s2_ACK;
    wire s2_ERR;

    wire [63:0] s3_ADR;
    wire [63:0] s3_DAT_O;
    wire [63:0] s3_DAT_I;
    wire [7:0] s3_SEL;
    wire s3_CYC;
    wire s3_STB;
    wire s3_WE;
    wire [2:0] s3_CTI;
    wire [1:0] s3_BTE;
    wire s3_ACK;
    wire s3_ERR;

    Wishbone_Master #(.MAX_BURST_LENGTH(16)) master0 (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .cpu_start(m0_cpu_start), .cpu_write(m0_cpu_write), .cpu_burst(m0_cpu_burst),
        .cpu_burst_length(m0_cpu_burst_length), .cpu_address(m0_cpu_address),
        .cpu_write_data(m0_cpu_write_data), .cpu_select(m0_cpu_select),
        .cpu_burst_write_data(m0_cpu_burst_write_data),
        .cpu_read_data(m0_cpu_read_data), .cpu_burst_read_data(m0_cpu_burst_read_data),
        .cpu_beat_index(m0_cpu_beat_index), .cpu_beat_done(m0_cpu_beat_done),
        .cpu_done(m0_cpu_done), .cpu_error(m0_cpu_error),
        .ADR_O(m0_ADR_O), .DAT_O(m0_DAT_O), .DAT_I(m0_DAT_I), .SEL_O(m0_SEL_O),
        .CYC_O(m0_CYC_O), .STB_O(m0_STB_O), .WE_O(m0_WE_O),
        .CTI_O(m0_CTI_O), .BTE_O(m0_BTE_O), .ACK_I(m0_ACK_I), .ERR_I(m0_ERR_I)
    );

    Wishbone_Master #(.MAX_BURST_LENGTH(16)) master1 (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .cpu_start(m1_cpu_start), .cpu_write(m1_cpu_write), .cpu_burst(m1_cpu_burst),
        .cpu_burst_length(m1_cpu_burst_length), .cpu_address(m1_cpu_address),
        .cpu_write_data(m1_cpu_write_data), .cpu_select(m1_cpu_select),
        .cpu_burst_write_data(m1_cpu_burst_write_data),
        .cpu_read_data(m1_cpu_read_data), .cpu_burst_read_data(m1_cpu_burst_read_data),
        .cpu_beat_index(m1_cpu_beat_index), .cpu_beat_done(m1_cpu_beat_done),
        .cpu_done(m1_cpu_done), .cpu_error(m1_cpu_error),
        .ADR_O(m1_ADR_O), .DAT_O(m1_DAT_O), .DAT_I(m1_DAT_I), .SEL_O(m1_SEL_O),
        .CYC_O(m1_CYC_O), .STB_O(m1_STB_O), .WE_O(m1_WE_O),
        .CTI_O(m1_CTI_O), .BTE_O(m1_BTE_O), .ACK_I(m1_ACK_I), .ERR_I(m1_ERR_I)
    );

    Wishbone_Interconnect wb_interconnect (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .M0_ADR_I(m0_ADR_O), .M0_DAT_O(m0_DAT_O), .M0_DAT_I(m0_DAT_I),
        .M0_SEL_I(m0_SEL_O), .M0_CYC_I(m0_CYC_O), .M0_STB_I(m0_STB_O),
        .M0_WE_I(m0_WE_O), .M0_CTI_I(m0_CTI_O), .M0_BTE_I(m0_BTE_O),
        .M0_ACK_O(m0_ACK_I), .M0_ERR_O(m0_ERR_I),
        .M1_ADR_I(m1_ADR_O), .M1_DAT_O(m1_DAT_O), .M1_DAT_I(m1_DAT_I),
        .M1_SEL_I(m1_SEL_O), .M1_CYC_I(m1_CYC_O), .M1_STB_I(m1_STB_O),
        .M1_WE_I(m1_WE_O), .M1_CTI_I(m1_CTI_O), .M1_BTE_I(m1_BTE_O),
        .M1_ACK_O(m1_ACK_I), .M1_ERR_O(m1_ERR_I),
        .M0_GRANT_O(m0_grant), .M1_GRANT_O(m1_grant),
        .S0_ADR_O(s0_ADR), .S0_DAT_O(s0_DAT_O), .S0_DAT_I(s0_DAT_I),
        .S0_SEL_O(s0_SEL), .S0_CYC_O(s0_CYC), .S0_STB_O(s0_STB),
        .S0_WE_O(s0_WE), .S0_CTI_O(s0_CTI), .S0_BTE_O(s0_BTE),
        .S0_ACK_I(s0_ACK), .S0_ERR_I(s0_ERR),
        .S1_ADR_O(s1_ADR), .S1_DAT_O(s1_DAT_O), .S1_DAT_I(s1_DAT_I),
        .S1_SEL_O(s1_SEL), .S1_CYC_O(s1_CYC), .S1_STB_O(s1_STB),
        .S1_WE_O(s1_WE), .S1_CTI_O(s1_CTI), .S1_BTE_O(s1_BTE),
        .S1_ACK_I(s1_ACK), .S1_ERR_I(s1_ERR),
        .S2_ADR_O(s2_ADR), .S2_DAT_O(s2_DAT_O), .S2_DAT_I(s2_DAT_I),
        .S2_SEL_O(s2_SEL), .S2_CYC_O(s2_CYC), .S2_STB_O(s2_STB),
        .S2_WE_O(s2_WE), .S2_CTI_O(s2_CTI), .S2_BTE_O(s2_BTE),
        .S2_ACK_I(s2_ACK), .S2_ERR_I(s2_ERR),
        .S3_ADR_O(s3_ADR), .S3_DAT_O(s3_DAT_O), .S3_DAT_I(s3_DAT_I),
        .S3_SEL_O(s3_SEL), .S3_CYC_O(s3_CYC), .S3_STB_O(s3_STB),
        .S3_WE_O(s3_WE), .S3_CTI_O(s3_CTI), .S3_BTE_O(s3_BTE),
        .S3_ACK_I(s3_ACK), .S3_ERR_I(s3_ERR)
    );

    Wishbone_RAM #(.MEMORY_WORDS(128), .WAIT_STATES(2)) ram0 (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .ADR_I(s0_ADR), .DAT_I(s0_DAT_O), .DAT_O(s0_DAT_I), .SEL_I(s0_SEL),
        .CYC_I(s0_CYC), .STB_I(s0_STB), .WE_I(s0_WE), .CTI_I(s0_CTI), .BTE_I(s0_BTE),
        .ACK_O(s0_ACK), .ERR_O(s0_ERR)
    );

    Wishbone_RAM #(.MEMORY_WORDS(128), .WAIT_STATES(0)) ram1 (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .ADR_I(s1_ADR), .DAT_I(s1_DAT_O), .DAT_O(s1_DAT_I), .SEL_I(s1_SEL),
        .CYC_I(s1_CYC), .STB_I(s1_STB), .WE_I(s1_WE), .CTI_I(s1_CTI), .BTE_I(s1_BTE),
        .ACK_O(s1_ACK), .ERR_O(s1_ERR)
    );

    Wishbone_RAM #(.MEMORY_WORDS(128), .WAIT_STATES(1)) ram2 (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .ADR_I(s2_ADR), .DAT_I(s2_DAT_O), .DAT_O(s2_DAT_I), .SEL_I(s2_SEL),
        .CYC_I(s2_CYC), .STB_I(s2_STB), .WE_I(s2_WE), .CTI_I(s2_CTI), .BTE_I(s2_BTE),
        .ACK_O(s2_ACK), .ERR_O(s2_ERR)
    );

    Wishbone_RAM #(.MEMORY_WORDS(128), .WAIT_STATES(3)) ram3 (
        .CLK_I(CLK_I), .RST_I(RST_I),
        .ADR_I(s3_ADR), .DAT_I(s3_DAT_O), .DAT_O(s3_DAT_I), .SEL_I(s3_SEL),
        .CYC_I(s3_CYC), .STB_I(s3_STB), .WE_I(s3_WE), .CTI_I(s3_CTI), .BTE_I(s3_BTE),
        .ACK_O(s3_ACK), .ERR_O(s3_ERR)
    );


    // CLOCK


    initial begin
        CLK_I = 1'b0;
        forever #5 CLK_I = ~CLK_I;
    end


    // WAVEFORM SEQUENCE


    integer i;

    initial begin

        wave_section = 4'd0;

        direct_cpu_start = 1'b0;
        direct_cpu_write = 1'b0;
        direct_cpu_burst = 1'b0;
        direct_cpu_burst_length = 5'd1;
        direct_cpu_address = 64'd0;
        direct_cpu_write_data = 64'd0;
        direct_cpu_select = 8'h00;
        direct_cpu_burst_write_data = 1024'd0;

        m0_cpu_start = 1'b0;
        m0_cpu_write = 1'b0;
        m0_cpu_burst = 1'b0;
        m0_cpu_burst_length = 5'd1;
        m0_cpu_address = 64'd0;
        m0_cpu_write_data = 64'd0;
        m0_cpu_select = 8'h00;
        m0_cpu_burst_write_data = 1024'd0;

        m1_cpu_start = 1'b0;
        m1_cpu_write = 1'b0;
        m1_cpu_burst = 1'b0;
        m1_cpu_burst_length = 5'd1;
        m1_cpu_address = 64'd0;
        m1_cpu_write_data = 64'd0;
        m1_cpu_select = 8'h00;
        m1_cpu_burst_write_data = 1024'd0;

        RST_I = 1'b1;
        repeat (4) @(posedge CLK_I);
        RST_I = 1'b0;
        repeat (2) @(posedge CLK_I);

    
        // SECTION 1
        // Classic transfer with partial SEL and wait states
    

        wave_section = 4'd1;

        direct_cpu_address = 64'h0000_0000_0000_0040;
        direct_cpu_write_data = 64'h1122_3344_5566_7788;
        direct_cpu_select = 8'hFF;
        direct_cpu_write = 1'b1;
        direct_cpu_burst = 1'b0;
        direct_cpu_burst_length = 5'd1;
        direct_cpu_start = 1'b1;

        @(posedge CLK_I);
        @(negedge CLK_I);
        direct_cpu_start = 1'b0;

        while (!direct_cpu_done && !direct_cpu_error) begin
            @(posedge CLK_I);
        end

        @(negedge CLK_I);

        direct_cpu_address = 64'h0000_0000_0000_0040;
        direct_cpu_write_data = 64'hAABB_CCDD_0000_0000;
        direct_cpu_select = 8'hF0;
        direct_cpu_write = 1'b1;
        direct_cpu_burst = 1'b0;
        direct_cpu_burst_length = 5'd1;
        direct_cpu_start = 1'b1;

        @(posedge CLK_I);
        @(negedge CLK_I);
        direct_cpu_start = 1'b0;

        while (!direct_cpu_done && !direct_cpu_error) begin
            @(posedge CLK_I);
        end

        @(negedge CLK_I);

        direct_cpu_address = 64'h0000_0000_0000_0040;
        direct_cpu_write_data = 64'd0;
        direct_cpu_select = 8'hFF;
        direct_cpu_write = 1'b0;
        direct_cpu_burst = 1'b0;
        direct_cpu_burst_length = 5'd1;
        direct_cpu_start = 1'b1;

        @(posedge CLK_I);
        @(negedge CLK_I);
        direct_cpu_start = 1'b0;

        while (!direct_cpu_done && !direct_cpu_error) begin
            @(posedge CLK_I);
        end

        @(negedge CLK_I);
        repeat (5) @(posedge CLK_I);

    
        // SECTION 2
        // Eight-beat incrementing burst
    

        wave_section = 4'd2;

        direct_cpu_burst_write_data = 1024'd0;
        for (i = 0; i < 8; i = i + 1) begin
            direct_cpu_burst_write_data[i*64 +: 64] = 64'h2000_0000_0000_0000 + i;
        end

        direct_cpu_address = 64'h0000_0000_0000_0100;
        direct_cpu_write_data = 64'd0;
        direct_cpu_select = 8'hFF;
        direct_cpu_write = 1'b1;
        direct_cpu_burst = 1'b1;
        direct_cpu_burst_length = 5'd8;
        direct_cpu_start = 1'b1;

        @(posedge CLK_I);
        @(negedge CLK_I);
        direct_cpu_start = 1'b0;

        while (!direct_cpu_done && !direct_cpu_error) begin
            @(posedge CLK_I);
        end

        @(negedge CLK_I);
        repeat (5) @(posedge CLK_I);

        direct_cpu_address = 64'h0000_0000_0000_0100;
        direct_cpu_write_data = 64'd0;
        direct_cpu_select = 8'hFF;
        direct_cpu_write = 1'b0;
        direct_cpu_burst = 1'b1;
        direct_cpu_burst_length = 5'd8;
        direct_cpu_start = 1'b1;

        @(posedge CLK_I);
        @(negedge CLK_I);
        direct_cpu_start = 1'b0;

        while (!direct_cpu_done && !direct_cpu_error) begin
            @(posedge CLK_I);
        end

        @(negedge CLK_I);
        repeat (5) @(posedge CLK_I);

    
        // SECTION 3
        // Two-master arbitration
    

        wave_section = 4'd3;

        m0_cpu_address = 64'h0000_0000_0000_0080;
        m0_cpu_write_data = 64'hAAAA_AAAA_AAAA_AAAA;
        m0_cpu_select = 8'hFF;
        m0_cpu_write = 1'b1;
        m0_cpu_burst = 1'b0;
        m0_cpu_burst_length = 5'd1;

        m1_cpu_address = 64'h0000_0000_8000_0080;
        m1_cpu_write_data = 64'hBBBB_BBBB_BBBB_BBBB;
        m1_cpu_select = 8'hFF;
        m1_cpu_write = 1'b1;
        m1_cpu_burst = 1'b0;
        m1_cpu_burst_length = 5'd1;

        m0_cpu_start = 1'b1;
        m1_cpu_start = 1'b1;

        @(posedge CLK_I);
        @(negedge CLK_I);
        m0_cpu_start = 1'b0;
        m1_cpu_start = 1'b0;

        while (!m0_cpu_done && !m1_cpu_done) begin
            @(posedge CLK_I);
        end

        while (!m0_cpu_done || !m1_cpu_done) begin
            @(posedge CLK_I);
        end

        @(negedge CLK_I);
        repeat (5) @(posedge CLK_I);

        // Keep waveform open briefly after the final transaction.
        wave_section = 4'd3;
        repeat (10) @(posedge CLK_I);

        $finish;

    end


    // WAVEFORM DUMP


    initial begin
        $dumpfile("Sim_Wishbone.vcd");
        $dumpvars(0, Sim_Wishbone);
    end

endmodule
