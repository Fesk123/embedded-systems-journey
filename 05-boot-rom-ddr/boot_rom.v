`timescale 1ns/1ps

// BOOT ROM AND DDR CONTROLLER
// Boot ROM plus 64-bit DDR memory controller interface
//
// This version is designed to sit after the L1 cache.
// The Boot ROM is mapped at the beginning of the physical address space and DDR is mapped from DDR_BASE_ADDR.
//
// Features:
// - 64-bit Wishbone slave interface
// - 16 KiB boot ROM by default
// - Reset boot image that waits for DDR initialization
// - Jump to DDR after initialization
// - 64-bit DDR data path
// - Wishbone burst support through repeated transfers
// - Write byte enables
// - DDR initialization state and status
// - DDR refresh handling
// - Configurable read and write latency
// - Simulation DDR memory model
// - Generic DDR command interface for later FPGA PHY integration
// - Out of range access error handling
//
// The current version keeps the DDR command interface separate from the simulation memory model so the controller can later be connected to an FPGA specific DDR PHY without changing the Wishbone side.


module Boot_ROM #(

    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter ROM_SIZE = 16384,
    parameter DDR_BASE_ADDR = 64'h0000_0000_8000_0000,
    parameter DDR_SIZE = 64'h0000_0000_2000_0000,

    parameter DDR_SIM_WORDS = 16384,
    parameter DDR_INIT_CYCLES = 32,
    parameter DDR_REFRESH_INTERVAL = 1024,
    parameter DDR_REFRESH_CYCLES = 4,

    parameter DDR_READ_LATENCY = 2,
    parameter DDR_WRITE_LATENCY = 1,

    parameter DDR_TIMEOUT_CYCLES = 1024,
    parameter SIMULATION_MODE = 1'b1

)(

    input CLK_I,
    input RST_I,

    
    // WISHBONE SLAVE INTERFACE
    

    input [ADDR_WIDTH-1:0] ADR_I,
    input [DATA_WIDTH-1:0] DAT_I,
    output [DATA_WIDTH-1:0] DAT_O,
    input [DATA_WIDTH/8-1:0] SEL_I,

    input CYC_I,
    input STB_I,
    input WE_I,

    input [2:0] CTI_I,
    input [1:0] BTE_I,

    output ACK_O,
    output ERR_O,

    
    // STATUS
    

    output boot_rom_ready,
    output ddr_init_done,
    output ddr_busy,
    output ddr_refresh_active,

    
    // DEBUG
    

    output debug_rom_select,
    output debug_status_select,
    output debug_ddr_select,

    output [2:0] debug_ddr_state,
    output [ADDR_WIDTH-1:0] debug_ddr_address,

    output [31:0] debug_ddr_access_counter,
    output [31:0] debug_ddr_init_counter,
    output [31:0] debug_ddr_refresh_counter,

    output debug_ddr_request_write,


    
    // GENERIC DDR COMMAND INTERFACE
    

    output ddr_cmd_valid,
    output ddr_cmd_write,

    output [ADDR_WIDTH-1:0] ddr_cmd_address,
    output [DATA_WIDTH-1:0] ddr_write_data,
    output [DATA_WIDTH/8-1:0] ddr_write_sel,

    input ddr_cmd_ready,

    input ddr_read_valid,
    input [DATA_WIDTH-1:0] ddr_read_data,
    input ddr_error

);

    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam integer ROM_WORDS = ROM_SIZE / DATA_BYTES;

    localparam [ADDR_WIDTH-1:0] ROM_BASE_ADDR = {ADDR_WIDTH{1'b0}};
    localparam [ADDR_WIDTH-1:0] BOOT_STATUS_ADDR = ROM_SIZE;

    reg [DATA_WIDTH-1:0] rom_memory [0:ROM_WORDS-1];

    integer rom_i;

    wire rom_select;
    wire status_select;
    wire ddr_select;
    wire invalid_select;

    wire ddr_ack;
    wire ddr_err;

    wire [DATA_WIDTH-1:0] ddr_data_out;
    wire [2:0] ddr_state_debug;
    wire [ADDR_WIDTH-1:0] ddr_address_debug;

    wire [31:0] ddr_access_counter_debug;
    wire [31:0] ddr_init_counter_debug;
    wire [31:0] ddr_refresh_counter_debug;

    wire ddr_request_write_debug;

    
    // ADDRESS DECODE
    

    assign rom_select = CYC_I && STB_I && (ADR_I >= ROM_BASE_ADDR) && (ADR_I < ROM_SIZE);

    assign status_select = CYC_I && STB_I && (ADR_I == BOOT_STATUS_ADDR);

    assign ddr_select = CYC_I && STB_I && (ADR_I >= DDR_BASE_ADDR) && (ADR_I < (DDR_BASE_ADDR + DDR_SIZE));

    assign invalid_select = CYC_I && STB_I && !rom_select && !status_select && !ddr_select;

    
    // BOOT ROM
    

    // The initial boot image waits until DDR initialization has completed and then jumps to DDR_BASE_ADDR. The image can later be replaced by a real bootloader loaded from SPI / QSPI flash.

    initial begin

        for (rom_i = 0; rom_i < ROM_WORDS; rom_i = rom_i + 1)
            rom_memory[rom_i] = 64'h0000001300000013;

        
        // RESET BOOT CODE
        //
        // 0x0000: lui   x5, 0x00004
        // 0x0004: lw    x6, 0(x5)
        // 0x0008: andi  x6, x6, 1
        // 0x000C: beq   x6, x0, 0x0004
        // 0x0010: lui   x5, 0x80000
        // 0x0014: jalr  x0, 0(x5)
        //
        // Status address = 0x0000_0000_0000_4000.
        // Bit 0 becomes one when DDR initialization is complete.

        if (ROM_WORDS > 0)
            rom_memory[0] = 64'h0002_A303_0000_42B7;

        if (ROM_WORDS > 1)
            rom_memory[1] = 64'hFE03_0CE3_0013_7313;

        if (ROM_WORDS > 2)
            rom_memory[2] = 64'h0002_8067_8000_02B7;


    end

    
    // DDR CONTROLLER
    

    DDR_Controller #(

        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),

        .DDR_BASE_ADDR(DDR_BASE_ADDR),
        .DDR_SIZE(DDR_SIZE),
        .DDR_SIM_WORDS(DDR_SIM_WORDS),
        .DDR_INIT_CYCLES(DDR_INIT_CYCLES),

        .DDR_REFRESH_INTERVAL(DDR_REFRESH_INTERVAL),
        .DDR_REFRESH_CYCLES(DDR_REFRESH_CYCLES),
        .DDR_READ_LATENCY(DDR_READ_LATENCY),
        .DDR_WRITE_LATENCY(DDR_WRITE_LATENCY),
        .DDR_TIMEOUT_CYCLES(DDR_TIMEOUT_CYCLES),

        .SIMULATION_MODE(SIMULATION_MODE)

    ) ddr_controller (

        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(ddr_data_out),
        .SEL_I(SEL_I),
        .CYC_I(ddr_select),
        .STB_I(ddr_select),
        .WE_I(WE_I),
        .CTI_I(CTI_I),
        .BTE_I(BTE_I),
        .ACK_O(ddr_ack),
        .ERR_O(ddr_err),

        .ddr_init_done(ddr_init_done),
        .ddr_busy(ddr_busy),
        .ddr_refresh_active(ddr_refresh_active),

        .debug_state(ddr_state_debug),
        .debug_address(ddr_address_debug),
        .debug_access_counter(ddr_access_counter_debug),
        .debug_init_counter(ddr_init_counter_debug),
        .debug_refresh_counter(ddr_refresh_counter_debug),
        .debug_request_write(ddr_request_write_debug),

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

    
    // WISHBONE RESPONSE
    

    assign DAT_O = rom_select ? rom_memory[ADR_I[ADDR_WIDTH-1:3] - ROM_BASE_ADDR[ADDR_WIDTH-1:3]] : status_select ? {{(DATA_WIDTH-8){1'b0}}, 5'b00000, ddr_refresh_active, ddr_busy, ddr_init_done} : ddr_data_out;

    assign ACK_O = (rom_select && !WE_I) || (status_select && !WE_I) || ddr_ack;

    assign ERR_O = (rom_select && WE_I) || (status_select && WE_I) || invalid_select || ddr_err;

    assign boot_rom_ready = !RST_I;

    assign debug_rom_select = rom_select;
    assign debug_status_select = status_select;
    assign debug_ddr_select = ddr_select;

    assign debug_ddr_state = ddr_state_debug;
    assign debug_ddr_address = ddr_address_debug;
    assign debug_ddr_access_counter = ddr_access_counter_debug;
    assign debug_ddr_init_counter = ddr_init_counter_debug;
    assign debug_ddr_refresh_counter = ddr_refresh_counter_debug;
    assign debug_ddr_request_write = ddr_request_write_debug;

endmodule


module DDR_Controller #(

    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter DDR_BASE_ADDR = 64'h0000_0000_8000_0000,
    parameter DDR_SIZE = 64'h0000_0000_2000_0000,

    parameter DDR_SIM_WORDS = 16384,
    parameter DDR_INIT_CYCLES = 32,
    parameter DDR_REFRESH_INTERVAL = 1024,
    parameter DDR_REFRESH_CYCLES = 4,

    parameter DDR_READ_LATENCY = 2,
    parameter DDR_WRITE_LATENCY = 1,
    parameter DDR_TIMEOUT_CYCLES = 1024,
    parameter SIMULATION_MODE = 1'b1

)(

    input CLK_I,
    input RST_I,

    
    // WISHBONE SLAVE INTERFACE
    

    input [ADDR_WIDTH-1:0] ADR_I,
    input [DATA_WIDTH-1:0] DAT_I,
    output reg [DATA_WIDTH-1:0] DAT_O,
    input [DATA_WIDTH/8-1:0] SEL_I,

    input CYC_I,
    input STB_I,
    input WE_I,

    input [2:0] CTI_I,
    input [1:0] BTE_I,
    output reg ACK_O,
    output reg ERR_O,

    
    // STATUS
    

    output reg ddr_init_done,
    output reg ddr_busy,
    output reg ddr_refresh_active,

    
    // DEBUG
    

    output wire [2:0] debug_state,
    output wire [ADDR_WIDTH-1:0] debug_address,

    output wire [31:0] debug_access_counter,
    output wire [31:0] debug_init_counter,
    output wire [31:0] debug_refresh_counter,

    output wire debug_request_write,

    
    // GENERIC DDR COMMAND INTERFACE
    

    output reg ddr_cmd_valid,
    output reg ddr_cmd_write,

    output reg [ADDR_WIDTH-1:0] ddr_cmd_address,
    output reg [DATA_WIDTH-1:0] ddr_write_data,
    output reg [DATA_WIDTH/8-1:0] ddr_write_sel,

    input ddr_cmd_ready,

    input ddr_read_valid,
    input [DATA_WIDTH-1:0] ddr_read_data,
    input ddr_error

);

    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam integer DDR_SIM_INDEX_BITS = 14;

    localparam [2:0] STATE_INIT = 3'd0;
    localparam [2:0] STATE_IDLE = 3'd1;
    localparam [2:0] STATE_ACCESS = 3'd2;
    localparam [2:0] STATE_READ_WAIT = 3'd3;
    localparam [2:0] STATE_WRITE_WAIT = 3'd4;
    localparam [2:0] STATE_REFRESH = 3'd5;

    reg [2:0] state;

    reg [31:0] init_counter;
    reg [31:0] refresh_counter;
    reg [31:0] refresh_cycle_counter;
    reg [31:0] access_counter;
    reg [31:0] timeout_counter;

    reg [ADDR_WIDTH-1:0] request_address;
    reg [DATA_WIDTH-1:0] request_wdata;
    reg [DATA_WIDTH/8-1:0] request_sel;

    reg request_write;
    reg [2:0] request_cti;
    reg [1:0] request_bte;

    reg command_issued;
    reg [DATA_WIDTH-1:0] read_data_buffer;

    reg [DATA_WIDTH-1:0] ddr_memory [0:DDR_SIM_WORDS-1];

    integer memory_i;
    integer memory_index;
    integer byte_i;

    
    // DEBUG OUTPUTS

    assign debug_state = state;
    assign debug_address = request_address;
    assign debug_access_counter = access_counter;
    assign debug_init_counter = init_counter;
    assign debug_refresh_counter = refresh_counter;
    assign debug_request_write = request_write;

    
    // DDR MEMORY HELPERS
    

    function integer ddr_memory_word_index;
        input [ADDR_WIDTH-1:0] address;


        begin
            ddr_memory_word_index = (address - DDR_BASE_ADDR) >> 3;
        end

    endfunction

    function [DATA_WIDTH-1:0] apply_byte_select;

        input [DATA_WIDTH-1:0] old_data;
        input [DATA_WIDTH-1:0] new_data;
        input [DATA_WIDTH/8-1:0] select_value;
        integer byte_number;

        begin

            apply_byte_select = old_data;

            for (byte_number = 0; byte_number < DATA_BYTES; byte_number = byte_number + 1) begin
                if (select_value[byte_number])
                    apply_byte_select[byte_number*8 +: 8] = new_data[byte_number*8 +: 8];
            end


        end
    endfunction

    
    // DDR INITIALIZATION
    

    initial begin

        for (memory_i = 0; memory_i < DDR_SIM_WORDS; memory_i = memory_i + 1)
            ddr_memory[memory_i] = {DATA_WIDTH{1'b0}};

    end

    
    // DDR CONTROLLER
    

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            state <= STATE_INIT;
            ddr_init_done <= 1'b0;
            ddr_busy <= 1'b1;
            ddr_refresh_active <= 1'b0;

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            DAT_O <= {DATA_WIDTH{1'b0}};

            ddr_cmd_valid <= 1'b0;
            ddr_cmd_write <= 1'b0;
            ddr_cmd_address <= {ADDR_WIDTH{1'b0}};
            ddr_write_data <= {DATA_WIDTH{1'b0}};
            ddr_write_sel <= {(DATA_WIDTH/8){1'b0}};

            init_counter <= 32'd0;
            refresh_counter <= 32'd0;
            refresh_cycle_counter <= 32'd0;
            access_counter <= 32'd0;
            timeout_counter <= 32'd0;

            request_address <= {ADDR_WIDTH{1'b0}};
            request_wdata <= {DATA_WIDTH{1'b0}};
            request_sel <= {(DATA_WIDTH/8){1'b0}};
            request_write <= 1'b0;
            request_cti <= 3'b000;
            request_bte <= 2'b00;

            command_issued <= 1'b0;
            read_data_buffer <= {DATA_WIDTH{1'b0}};

        end

        else begin

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;
            ddr_cmd_valid <= 1'b0;

            case (state)

                STATE_INIT: begin

                    ddr_busy <= 1'b1;
                    ddr_refresh_active <= 1'b0;

                    if (init_counter >= DDR_INIT_CYCLES - 1) begin
                        ddr_init_done <= 1'b1;
                        ddr_busy <= 1'b0;
                        refresh_counter <= 32'd0;
                        state <= STATE_IDLE;
                    end
                    else begin
                        init_counter <= init_counter + 1'b1;
                    end

                end

                STATE_IDLE: begin

                    ddr_busy <= 1'b0;
                    ddr_refresh_active <= 1'b0;

                    if (refresh_counter >= DDR_REFRESH_INTERVAL - 1) begin

                        refresh_cycle_counter <= 32'd0;
                        ddr_busy <= 1'b1;
                        ddr_refresh_active <= 1'b1;
                        state <= STATE_REFRESH;

                    end
                    else if (CYC_I && STB_I) begin

                        request_address <= ADR_I;
                        request_wdata <= DAT_I;
                        request_sel <= SEL_I;
                        request_write <= WE_I;
                        request_cti <= CTI_I;
                        request_bte <= BTE_I;

                        access_counter <= 32'd0;
                        timeout_counter <= 32'd0;
                        command_issued <= 1'b0;
                        ddr_busy <= 1'b1;
                        state <= STATE_ACCESS;

                    end

                    else begin
                        refresh_counter <= refresh_counter + 1'b1;

                    end


                end

                STATE_ACCESS: begin

                    ddr_busy <= 1'b1;

                    timeout_counter <= timeout_counter + 1'b1;

                    if (timeout_counter >= DDR_TIMEOUT_CYCLES - 1) begin

                        ERR_O <= 1'b1;
                        ddr_busy <= 1'b0;
                        state <= STATE_IDLE;


                    end

                    else if (!SIMULATION_MODE) begin

                        ddr_cmd_write <= request_write;
                        ddr_cmd_address <= request_address;
                        ddr_write_data <= request_wdata;
                        ddr_write_sel <= request_sel;

                        if (!command_issued) begin

                            ddr_cmd_valid <= 1'b1;

                            if (ddr_error) begin

                                ERR_O <= 1'b1;
                                ddr_busy <= 1'b0;
                                state <= STATE_IDLE;


                            end
                            else if (ddr_cmd_ready) begin

                                command_issued <= 1'b1;

                                if (request_write) begin

                                    ACK_O <= 1'b1;
                                    ddr_busy <= 1'b0;
                                    state <= STATE_IDLE;
                                end


                            end
                        end

                        else if (ddr_error) begin

                            ERR_O <= 1'b1;
                            ddr_busy <= 1'b0;
                            state <= STATE_IDLE;

                        end
                        else if (!request_write && ddr_read_valid) begin

                            DAT_O <= ddr_read_data;
                            ACK_O <= 1'b1;
                            ddr_busy <= 1'b0;
                            state <= STATE_IDLE;

                        end

                    end
                    else begin

                        if (request_address < DDR_BASE_ADDR || request_address >= (DDR_BASE_ADDR + DDR_SIZE)) begin

                            ERR_O <= 1'b1;
                            ddr_busy <= 1'b0;
                            state <= STATE_IDLE;

                        end
                        else if (ddr_memory_word_index(request_address) >= DDR_SIM_WORDS) begin

                            ERR_O <= 1'b1;
                            ddr_busy <= 1'b0;
                            state <= STATE_IDLE;

                        end
                        else if (request_write) begin

                            if (access_counter >= DDR_WRITE_LATENCY) begin

                                memory_index = ddr_memory_word_index(request_address);

                                ddr_memory[memory_index] <= apply_byte_select(ddr_memory[memory_index], request_wdata, request_sel);

                                ACK_O <= 1'b1;
                                refresh_counter <= refresh_counter + 1'b1;
                                ddr_busy <= 1'b0;
                                state <= STATE_IDLE;

                            end

                            else begin
                                access_counter <= access_counter + 1'b1;
                            
                            end

                        end

                        else begin

                            if (access_counter >= DDR_READ_LATENCY) begin

                                memory_index = ddr_memory_word_index(request_address);
                                DAT_O <= ddr_memory[memory_index];

                                ACK_O <= 1'b1;
                                refresh_counter <= refresh_counter + 1'b1;
                                ddr_busy <= 1'b0;
                                state <= STATE_IDLE;

                            end
                            else begin
                                access_counter <= access_counter + 1'b1;
                            end

                        end


                    end

                end

                STATE_READ_WAIT: begin
                    state <= STATE_ACCESS;
                end

                STATE_WRITE_WAIT: begin
                    state <= STATE_ACCESS;
                end

                STATE_REFRESH: begin

                    ddr_busy <= 1'b1;
                    ddr_refresh_active <= 1'b1;

                    if (refresh_cycle_counter >= DDR_REFRESH_CYCLES - 1) begin

                        refresh_counter <= 32'd0;
                        refresh_cycle_counter <= 32'd0;
                        ddr_refresh_active <= 1'b0;

                        ddr_busy <= 1'b0;
                        state <= STATE_IDLE;
                    end
                    else begin
                        refresh_cycle_counter <= refresh_cycle_counter + 1'b1;
                    end

                end

                default: begin
                    state <= STATE_INIT;
                    ddr_init_done <= 1'b0;
                end

            endcase
        end


    end


endmodule