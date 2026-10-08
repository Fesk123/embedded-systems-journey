`timescale 1ns/1ps


// BOOT ROM AND DDR WAVEFORM TESTBENCH
// Three documentation scenarios for GTKWave
//
// Scenario 1 shows reset, DDR initialization and Boot ROM reads.
// Scenario 2 shows DDR write, read, byte enable and burst traffic.
// Scenario 3 shows refresh, errors and the generic DDR interface.
//
// No display statements are used here. The VCD is intended for GTKWave screenshots and waveform inspection.

module Sim_Boot_ROM;

    localparam ADDR_WIDTH = 64;
    localparam DATA_WIDTH = 64;

    localparam [63:0] ROM_SIZE = 64'h0000_0000_0000_4000;
    localparam [63:0] BOOT_STATUS_ADDR = 64'h0000_0000_0000_4000;
    localparam [63:0] DDR_BASE_ADDR = 64'h0000_0000_8000_0000;
    localparam [63:0] INVALID_ADDRESS = 64'h0000_0000_9000_0000;

    reg CLK_I;
    reg RST_I;

    
    // SCENARIO MARKERS
    

    reg [3:0] scenario;
    reg [7:0] checkpoint;

    
    // WISHBONE INTERFACE
    

    reg [ADDR_WIDTH-1:0] ADR_I;
    reg [DATA_WIDTH-1:0] DAT_I;
    wire [DATA_WIDTH-1:0] DAT_O;
    reg [DATA_WIDTH/8-1:0] SEL_I;

    reg CYC_I;
    reg STB_I;
    reg WE_I;

    reg [2:0] CTI_I;
    reg [1:0] BTE_I;

    wire ACK_O;
    wire ERR_O;

    
    // STATUS
    

    wire boot_rom_ready;
    wire ddr_init_done;
    wire ddr_busy;
    wire ddr_refresh_active;

    
    // DEBUG
    

    wire debug_rom_select;
    wire debug_status_select;
    wire debug_ddr_select;

    wire [2:0] debug_ddr_state;
    wire [ADDR_WIDTH-1:0] debug_ddr_address;

    wire [31:0] debug_ddr_access_counter;
    wire [31:0] debug_ddr_init_counter;
    wire [31:0] debug_ddr_refresh_counter;

    wire debug_ddr_request_write;

    
    // GENERIC DDR COMMAND INTERFACE
    

    wire ddr_cmd_valid;
    wire ddr_cmd_write;

    wire [ADDR_WIDTH-1:0] ddr_cmd_address;
    wire [DATA_WIDTH-1:0] ddr_write_data;
    wire [DATA_WIDTH/8-1:0] ddr_write_sel;

    reg ddr_cmd_ready;
    reg ddr_read_valid;
    reg [DATA_WIDTH-1:0] ddr_read_data;
    reg ddr_error;

    
    // GENERIC DDR COMMAND INTERFACE TEST INSTANCE
    

    reg [ADDR_WIDTH-1:0] PHY_ADR_I;
    reg [DATA_WIDTH-1:0] PHY_DAT_I;
    wire [DATA_WIDTH-1:0] PHY_DAT_O;
    reg [DATA_WIDTH/8-1:0] PHY_SEL_I;

    reg PHY_CYC_I;
    reg PHY_STB_I;
    reg PHY_WE_I;

    reg [2:0] PHY_CTI_I;
    reg [1:0] PHY_BTE_I;

    wire PHY_ACK_O;
    wire PHY_ERR_O;

    wire phy_init_done;
    wire phy_busy;
    wire phy_refresh_active;
    wire phy_cmd_valid;
    wire phy_cmd_write;

    wire [ADDR_WIDTH-1:0] phy_cmd_address;
    wire [DATA_WIDTH-1:0] phy_write_data;
    wire [DATA_WIDTH/8-1:0] phy_write_sel;

    reg phy_cmd_ready;
    reg phy_read_valid;
    reg [DATA_WIDTH-1:0] phy_read_data;
    reg phy_error;

    integer i;
    integer burst_index;
    integer timeout;

    
    // DEVICE UNDER TEST
    

    Boot_ROM #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ROM_SIZE(16384),
        .DDR_BASE_ADDR(DDR_BASE_ADDR),
        .DDR_SIZE(64'h0000_0000_2000_0000),

        .DDR_SIM_WORDS(16384),
        .DDR_INIT_CYCLES(8),
        .DDR_REFRESH_INTERVAL(16),
        .DDR_REFRESH_CYCLES(3),
        .DDR_READ_LATENCY(2),
        .DDR_WRITE_LATENCY(1),

        .DDR_TIMEOUT_CYCLES(32),
        .SIMULATION_MODE(1'b1)
    ) dut (

        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .SEL_I(SEL_I),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .CTI_I(CTI_I),
        .BTE_I(BTE_I),
        .ACK_O(ACK_O),
        .ERR_O(ERR_O),

        .boot_rom_ready(boot_rom_ready),
        .ddr_init_done(ddr_init_done),
        .ddr_busy(ddr_busy),
        .ddr_refresh_active(ddr_refresh_active),

        .debug_rom_select(debug_rom_select),
        .debug_status_select(debug_status_select),
        .debug_ddr_select(debug_ddr_select),
        .debug_ddr_state(debug_ddr_state),
        .debug_ddr_address(debug_ddr_address),
        .debug_ddr_access_counter(debug_ddr_access_counter),
        .debug_ddr_init_counter(debug_ddr_init_counter),
        .debug_ddr_refresh_counter(debug_ddr_refresh_counter),
        .debug_ddr_request_write(debug_ddr_request_write),

        .ddr_cmd_valid(ddr_cmd_valid),
        .ddr_cmd_write(ddr_cmd_write),
        .ddr_cmd_address(ddr_cmd_address),
        .ddr_write_data(ddr_write_data),
        .ddr_write_sel(ddr_write_sel),
        .ddr_cmd_ready(ddr_cmd_ready),

        .ddr_read_valid(ddr_read_valid),
        .ddr_read_data(ddr_read_data),
        .ddr_error(ddr_error)

    );

    
    // GENERIC DDR COMMAND INTERFACE TEST INSTANCE
    

    DDR_Controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DDR_BASE_ADDR(DDR_BASE_ADDR),
        .DDR_SIZE(64'h0000_0000_2000_0000),


        .DDR_SIM_WORDS(16384),
        .DDR_INIT_CYCLES(4),
        .DDR_REFRESH_INTERVAL(32),
        .DDR_REFRESH_CYCLES(2),
        .DDR_READ_LATENCY(2),
        .DDR_WRITE_LATENCY(1),
        .DDR_TIMEOUT_CYCLES(32),
        .SIMULATION_MODE(1'b0)
    ) phy_dut (

        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .ADR_I(PHY_ADR_I),
        .DAT_I(PHY_DAT_I),
        .DAT_O(PHY_DAT_O),
        .SEL_I(PHY_SEL_I),
        .CYC_I(PHY_CYC_I),
        .STB_I(PHY_STB_I),
        .WE_I(PHY_WE_I),
        .CTI_I(PHY_CTI_I),
        .BTE_I(PHY_BTE_I),
        .ACK_O(PHY_ACK_O),
        .ERR_O(PHY_ERR_O),

        .ddr_init_done(phy_init_done),
        .ddr_busy(phy_busy),
        .ddr_refresh_active(phy_refresh_active),

        .debug_state(),
        .debug_address(),
        .debug_access_counter(),
        .debug_init_counter(),
        .debug_refresh_counter(),
        .debug_request_write(),

        .ddr_cmd_valid(phy_cmd_valid),
        .ddr_cmd_write(phy_cmd_write),
        .ddr_cmd_address(phy_cmd_address),
        .ddr_write_data(phy_write_data),
        .ddr_write_sel(phy_write_sel),
        .ddr_cmd_ready(phy_cmd_ready),

        .ddr_read_valid(phy_read_valid),
        .ddr_read_data(phy_read_data),
        .ddr_error(phy_error)

    );

    
    // CLOCK
    

    initial begin
        CLK_I = 1'b0;
        forever #5 CLK_I = ~CLK_I;

    end

    
    // WISHBONE READ
    

    task wb_read;
        input [63:0] address;
        begin

            @(negedge CLK_I);
            ADR_I = address;
            DAT_I = 64'd0;
            SEL_I = 8'hFF;
            WE_I = 1'b0;
            CTI_I = 3'b000;
            BTE_I = 2'b00;
            CYC_I = 1'b1;
            STB_I = 1'b1;

            timeout = 0;

            begin : read_wait

                while (1) begin

                    @(posedge CLK_I);
                    #1;
                    timeout = timeout + 1;

                    if (ACK_O || ERR_O)
                        disable read_wait;

                    if (timeout >= 1000)
                        disable read_wait;
                end
            end

            @(negedge CLK_I);
            CYC_I = 1'b0;
            STB_I = 1'b0;

        end
    endtask

    
    // WISHBONE WRITE
    

    task wb_write;
        input [63:0] address;
        input [63:0] value;
        input [7:0] select_value;
        input [2:0] cycle_type;

        begin

            @(negedge CLK_I);
            ADR_I = address;
            DAT_I = value;
            SEL_I = select_value;
            WE_I = 1'b1;
            CTI_I = cycle_type;
            BTE_I = 2'b00;
            CYC_I = 1'b1;
            STB_I = 1'b1;

            timeout = 0;

            begin : write_wait
                while (1) begin
                    @(posedge CLK_I);
                    #1;
                    timeout = timeout + 1;

                    if (ACK_O || ERR_O)
                        disable write_wait;

                    if (timeout >= 1000)
                        disable write_wait;
                end
            end

            @(negedge CLK_I);
            CYC_I = 1'b0;
            STB_I = 1'b0;
            WE_I = 1'b0;

        end
    endtask

    
    // TEST PROGRAM
    

    initial begin

        $dumpfile("Sim_boot_rom.vcd");
        $dumpvars(0, Sim_Boot_ROM);

        ADR_I = 64'd0;
        DAT_I = 64'd0;
        SEL_I = 8'hFF;

        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;
        CTI_I = 3'b000;
        BTE_I = 2'b00;

        ddr_cmd_ready = 1'b0;
        ddr_read_valid = 1'b0;
        ddr_read_data = 64'd0;
        ddr_error = 1'b0;

        PHY_ADR_I = 64'd0;
        PHY_DAT_I = 64'd0;
        PHY_SEL_I = 8'hFF;
        PHY_CYC_I = 1'b0;
        PHY_STB_I = 1'b0;

        PHY_WE_I = 1'b0;
        PHY_CTI_I = 3'b000;
        PHY_BTE_I = 2'b00;
        phy_cmd_ready = 1'b0;
        phy_read_valid = 1'b0;
        phy_read_data = 64'd0;
        phy_error = 1'b0;

        scenario = 4'd0;
        checkpoint = 8'd0;

        RST_I = 1'b1;

        repeat (3) @(posedge CLK_I);

        RST_I = 1'b0;

        
        // SCENARIO 1
        // Reset, DDR initialization and Boot ROM
        

        scenario = 4'd1;
        checkpoint = 8'd1;

        repeat (4) @(posedge CLK_I);

        checkpoint = 8'd2;

        while (!ddr_init_done)
            @(posedge CLK_I);

        checkpoint = 8'd3;

        wb_read(64'h0000_0000);
        wb_read(64'h0000_0010);

        checkpoint = 8'd4;

        wb_read(BOOT_STATUS_ADDR);

        repeat (4) @(posedge CLK_I);

        
        // SCENARIO 2
        // DDR read, write, byte enable and burst traffic
        

        scenario = 4'd2;
        checkpoint = 8'd5;

        wb_write(DDR_BASE_ADDR + 64'h100, 64'h1122334455667788, 8'hFF, 3'b000);

        checkpoint = 8'd6;

        wb_read(DDR_BASE_ADDR + 64'h100);

        checkpoint = 8'd7;

        wb_write(DDR_BASE_ADDR + 64'h100, 64'hAAAABBBBCCCCDDDD, 8'h0F, 3'b000);

        checkpoint = 8'd8;

        wb_read(DDR_BASE_ADDR + 64'h100);

        checkpoint = 8'd9;

        for (burst_index = 0; burst_index < 8; burst_index = burst_index + 1) begin

            wb_write(DDR_BASE_ADDR + 64'h200 + (burst_index * 8), 64'h1000000000000000 + burst_index, 8'hFF, (burst_index == 7) ? 3'b111 : 3'b010);
       
        end

        checkpoint = 8'd10;

        for (burst_index = 0; burst_index < 8; burst_index = burst_index + 1)
            wb_read(DDR_BASE_ADDR + 64'h200 + (burst_index * 8));

        repeat (4) @(posedge CLK_I);

        
        // SCENARIO 3
        // Refresh, error handling and DDR command interface
        

        scenario = 4'd3;
        checkpoint = 8'd11;


        while (!ddr_refresh_active)
            @(posedge CLK_I);

        checkpoint = 8'd12;

        while (ddr_refresh_active)
            @(posedge CLK_I);

        checkpoint = 8'd13;


        wb_read(INVALID_ADDRESS);

        checkpoint = 8'd14;

        while (!phy_init_done)
            @(posedge CLK_I);

        PHY_ADR_I = DDR_BASE_ADDR + 64'h300;
        PHY_DAT_I = 64'hCAFEBABE12345678;
        PHY_SEL_I = 8'hFF;
        PHY_WE_I = 1'b1;

        PHY_CTI_I = 3'b000;
        PHY_BTE_I = 2'b00;
        PHY_CYC_I = 1'b1;
        PHY_STB_I = 1'b1;
        phy_cmd_ready = 1'b1;

        while (!PHY_ACK_O && !PHY_ERR_O)
            @(posedge CLK_I);

        @(negedge CLK_I);

        PHY_CYC_I = 1'b0;
        PHY_STB_I = 1'b0;
        PHY_WE_I = 1'b0;
        phy_cmd_ready = 1'b0;

        checkpoint = 8'd15;

        PHY_ADR_I = DDR_BASE_ADDR + 64'h308;
        PHY_DAT_I = 64'd0;
        PHY_SEL_I = 8'hFF;
        PHY_WE_I = 1'b0;

        PHY_CTI_I = 3'b000;
        PHY_BTE_I = 2'b00;
        PHY_CYC_I = 1'b1;

        PHY_STB_I = 1'b1;
        phy_cmd_ready = 1'b1;

        while (!phy_cmd_valid)
            @(posedge CLK_I);

        phy_read_data = 64'h123456789ABCDEF0;
        phy_read_valid = 1'b1;

        @(posedge CLK_I);
        #1;
        phy_read_valid = 1'b0;

        while (!PHY_ACK_O && !PHY_ERR_O)
            @(posedge CLK_I);

        @(negedge CLK_I);
        PHY_CYC_I = 1'b0;
        PHY_STB_I = 1'b0;
        phy_cmd_ready = 1'b0;

        repeat (4) @(posedge CLK_I);

        $finish;
    end


endmodule