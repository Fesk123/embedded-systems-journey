`timescale 1ns/1ps

// WISHBONE
//
// 64-bit WISHBONE Master, RAM Slave and SoC Interconnect
//
// This version builds on the previous WISHBONE design and combines the features needed for the planned RV64 SoC system.
//
// Features:
// - 64-bit address bus
// - 64-bit data bus
// - 8-bit byte select
// - Classic WISHBONE cycles
// - Registered Feedback style slave response
// - Incrementing bursts
// - CTI and BTE tags
// - ACK and ERR termination
// - Partial byte writes
// - Burst read and write data storage
// - Configurable RAM wait states
// - Multiple bus masters
// - Round-robin master arbitration
// - Address-decoded multi-slave interconnect
// - Configurable slave address regions
//
// The interconnect uses a shared WISHBONE bus with a round-robin arbiter. This provides the multi-master structure needed for the CPU and future DMA controller.
//
// Linear incrementing bursts are supported.
// Wrapped bursts are not implemented in this version.
//
// The interface remains compatible with Classic WISHBONE, while burst traffic can be used for cache fills, cache writes and DMA-style transfers later in the SoC.


module Wishbone_Master #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter MAX_BURST_LENGTH = 16
)(
    input CLK_I,
    input RST_I,

    input cpu_start,
    input cpu_write,
    input cpu_burst,
    input [4:0] cpu_burst_length,
    input [ADDR_WIDTH-1:0] cpu_address,
    input [DATA_WIDTH-1:0] cpu_write_data,
    input [DATA_WIDTH/8-1:0] cpu_select,
    input [DATA_WIDTH*MAX_BURST_LENGTH-1:0] cpu_burst_write_data,

    output reg [DATA_WIDTH-1:0] cpu_read_data,
    output reg [DATA_WIDTH*MAX_BURST_LENGTH-1:0] cpu_burst_read_data,
    output reg [4:0] cpu_beat_index,
    output reg cpu_beat_done,
    output reg cpu_done,
    output reg cpu_error,

    // WISHBONE interface
    output reg [ADDR_WIDTH-1:0] ADR_O,
    output reg [DATA_WIDTH-1:0] DAT_O,
    input [DATA_WIDTH-1:0] DAT_I,

    output reg [DATA_WIDTH/8-1:0] SEL_O,
    output reg CYC_O,
    output reg STB_O,
    output reg WE_O,

    // Cycle Type Identifier
    // 000 = Classic cycle
    // 010 = Incrementing burst
    // 111 = End-of-Burst
    output reg [2:0] CTI_O,

    // Burst Type Extension
    // 00 = Linear burst
    output reg [1:0] BTE_O,

    input ACK_I,
    input ERR_I
);

    localparam IDLE = 2'b00;
    localparam ACTIVE = 2'b01;
    localparam CTI_CLASSIC = 3'b000;
    localparam CTI_INCREMENT = 3'b010;
    localparam CTI_END = 3'b111;

    localparam DATA_BYTES = DATA_WIDTH / 8;

    reg [1:0] state;
    reg current_write;
    reg [4:0] current_burst_length;

    integer i;

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin


            state <= IDLE;

            ADR_O <= {ADDR_WIDTH{1'b0}};
            DAT_O <= {DATA_WIDTH{1'b0}};
            SEL_O <= {(DATA_WIDTH/8){1'b0}};

            CYC_O <= 1'b0;
            STB_O <= 1'b0;
            WE_O <= 1'b0;

            CTI_O <= CTI_CLASSIC;
            BTE_O <= 2'b00;

            current_write <= 1'b0;
            current_burst_length <= 5'd1;

            cpu_read_data <= {DATA_WIDTH{1'b0}};
            cpu_burst_read_data <= {(DATA_WIDTH*MAX_BURST_LENGTH){1'b0}};
            cpu_beat_index <= 5'd0;
            cpu_beat_done <= 1'b0;
            cpu_done <= 1'b0;
            cpu_error <= 1'b0;

        end

        else begin

            cpu_beat_done <= 1'b0;
            cpu_done <= 1'b0;
            cpu_error <= 1'b0;

            case (state)

                IDLE: begin

                    CYC_O <= 1'b0;
                    STB_O <= 1'b0;
                    WE_O <= 1'b0;
                    CTI_O <= CTI_CLASSIC;
                    BTE_O <= 2'b00;

                    if (cpu_start) begin


                        ADR_O <= cpu_address;
                        SEL_O <= cpu_select;

                        current_write <= cpu_write;
                        cpu_beat_index <= 5'd0;

                        if (cpu_burst && (cpu_burst_length > 5'd0)) begin
                            current_burst_length <= (cpu_burst_length > MAX_BURST_LENGTH) ? MAX_BURST_LENGTH : cpu_burst_length;
                        end
                        else begin
                            current_burst_length <= 5'd1;
                        end

                        // 1 = write
                        // 0 = read
                        WE_O <= cpu_write;

                        if (cpu_write) begin
                            if (cpu_burst) begin
                                DAT_O <= cpu_burst_write_data[DATA_WIDTH-1:0];
                            end
                            else begin
                                DAT_O <= cpu_write_data;
                            end
                        end
                        else begin
                            DAT_O <= {DATA_WIDTH{1'b0}};
                        end

                        // Start WISHBONE cycle
                        CYC_O <= 1'b1;
                        STB_O <= 1'b1;

                        // Use Classic for normal accesses.
                        // Use Incrementing Burst for multi-beat traffic.
                        if (cpu_burst && (cpu_burst_length > 5'd1)) begin
                            CTI_O <= CTI_INCREMENT;
                            BTE_O <= 2'b00;
                        end
                        else if (cpu_burst && (cpu_burst_length == 5'd1)) begin
                            CTI_O <= CTI_END;
                            BTE_O <= 2'b00;
                        end
                        else begin
                            CTI_O <= CTI_CLASSIC;
                            BTE_O <= 2'b00;
                        end


                        state <= ACTIVE;
                    end

                end


                // Keep the cycle active and allow one transfer per ACK.
                ACTIVE: begin

                    if (ERR_I) begin

                        CYC_O <= 1'b0;
                        STB_O <= 1'b0;
                        WE_O <= 1'b0;
                        CTI_O <= CTI_CLASSIC;

                        cpu_error <= 1'b1;
                        cpu_done <= 1'b1;

                        state <= IDLE;
                    end

                    else if (ACK_I) begin

                        // Read data from the current beat
                        if (!current_write) begin

                            cpu_read_data <= DAT_I;

                            if (cpu_beat_index < MAX_BURST_LENGTH) begin
                                cpu_burst_read_data[cpu_beat_index*DATA_WIDTH +: DATA_WIDTH] <= DAT_I;
                            end

                        end

                        cpu_beat_done <= 1'b1;

                        // Last beat is complete
                        if (cpu_beat_index + 5'd1 >= current_burst_length) begin

                            CYC_O <= 1'b0;
                            STB_O <= 1'b0;
                            WE_O <= 1'b0;
                            CTI_O <= CTI_CLASSIC;
                            BTE_O <= 2'b00;

                            cpu_done <= 1'b1;

                            state <= IDLE;


                        end

                        else begin

                            // Prepare the next beat.
                            cpu_beat_index <= cpu_beat_index + 5'd1;

                            ADR_O <= ADR_O + DATA_BYTES;

                            // The next transfer remains inside the same cycle.
                            CTI_O <= (cpu_beat_index + 5'd2 >= current_burst_length) ? CTI_END : CTI_INCREMENT;

                            if (current_write) begin
                                DAT_O <= cpu_burst_write_data[(cpu_beat_index + 5'd1)*DATA_WIDTH +: DATA_WIDTH];
                            end

                        end

                    end

                end

            endcase

        end

    end

endmodule


module Wishbone_RAM #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter MEMORY_WORDS = 256,
    parameter WAIT_STATES = 0
)(
    input CLK_I,
    input RST_I,

    // WISHBONE interface
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
    output reg ERR_O
);

    localparam DATA_BYTES = DATA_WIDTH / 8;
    localparam MEMORY_ADDR_WIDTH = (MEMORY_WORDS <= 1) ? 1 : $clog2(MEMORY_WORDS);
    localparam MEMORY_BYTES = MEMORY_WORDS * DATA_BYTES;

    // DATA_WIDTH bits per memory word
    reg [DATA_WIDTH-1:0] memory [0:MEMORY_WORDS-1];

    wire [MEMORY_ADDR_WIDTH-1:0] memory_index;
    wire address_valid;

    reg pending_transfer;
    reg pending_write;
    reg [MEMORY_ADDR_WIDTH-1:0] pending_index;
    reg [ADDR_WIDTH-1:0] pending_address;
    reg pending_address_valid;
    reg [DATA_WIDTH-1:0] pending_data;
    reg [DATA_WIDTH/8-1:0] pending_select;
    reg [31:0] wait_counter;

    // Prevent the same registered transfer from being captured twice
    // while CYC and STB remain asserted for a burst.
    reg accepted_transfer;
    reg [ADDR_WIDTH-1:0] last_accepted_address;

    integer i;
    integer byte_index;

    assign memory_index = ADR_I[MEMORY_ADDR_WIDTH+2:3];
    assign address_valid = (ADR_I < MEMORY_BYTES);

    initial begin
        for (i = 0; i < MEMORY_WORDS; i = i + 1) begin
            memory[i] = {DATA_WIDTH{1'b0}};
        end

    end

    // Registered Feedback response.
    // ACK and ERR are registered so that the slave can insert wait states before completing a transfer.
    //
    // WAIT_STATES = 0 still uses a registered response. The value represents the number of additional waiting clocks before ACK.
    //
    // A burst keeps CYC and STB asserted. The address-change check prevents a completed beat from being accepted twice before the master presents the next beat.
    
    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            ACK_O <= 1'b0;
            ERR_O <= 1'b0;

            pending_transfer <= 1'b0;
            pending_write <= 1'b0;
            pending_index <= {MEMORY_ADDR_WIDTH{1'b0}};
            pending_address <= {ADDR_WIDTH{1'b0}};
            pending_address_valid <= 1'b0;
            pending_data <= {DATA_WIDTH{1'b0}};
            pending_select <= {(DATA_WIDTH/8){1'b0}};
            wait_counter <= 32'd0;

            accepted_transfer <= 1'b0;
            last_accepted_address <= {ADDR_WIDTH{1'b0}};

        end

        else begin

            // Default response is inactive.
            ACK_O <= 1'b0;
            ERR_O <= 1'b0;

            // End of the WISHBONE cycle allows the same address to be used again for a new transaction.
            if (!CYC_I) begin
                accepted_transfer <= 1'b0;
            end

            if (pending_transfer) begin


                if (wait_counter != 32'd0) begin
                    wait_counter <= wait_counter - 32'd1;

                end

                else begin

                    if (!pending_address_valid || (pending_index >= MEMORY_WORDS)) begin
                        ERR_O <= 1'b1;

                    end

                    else begin

                        ACK_O <= 1'b1;

                        if (pending_write) begin

                            // Partial byte write
                            for (byte_index = 0; byte_index < DATA_BYTES; byte_index = byte_index + 1) begin

                                if (pending_select[byte_index]) begin
                                    memory[pending_index][byte_index*8 +: 8] <= pending_data[byte_index*8 +: 8];
                                
                                end

                            end

                        end


                    end

                    pending_transfer <= 1'b0;
                    accepted_transfer <= 1'b1;
                    last_accepted_address <= pending_address;

                end

            end

            else if (CYC_I && STB_I && (!accepted_transfer || (ADR_I != last_accepted_address))) begin

                // Capture the request. The response is generated on a later clock edge, allowing configurable wait states.
                pending_transfer <= 1'b1;
                pending_write <= WE_I;
                pending_index <= memory_index;
                pending_address <= ADR_I;
                pending_address_valid <= address_valid;
                pending_data <= DAT_I;
                pending_select <= SEL_I;
                wait_counter <= WAIT_STATES;

            end

        end

    end



    // Read data follows the current address during an active cycle.
    // The master samples DAT_I when ACK_O is asserted.
    always @(*) begin

        if (address_valid) begin
            DAT_O = memory[memory_index];
        end
        else begin
            DAT_O = {DATA_WIDTH{1'b0}};
        end

    end

endmodule


module Wishbone_Interconnect #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,

    // Default address map. These values are configurable for the final SoC.

    parameter SLAVE0_BASE = 64'h0000_0000_0000_0000,
    parameter SLAVE0_MASK = 64'hFFFF_FFFF_FFFF_0000,

    parameter SLAVE1_BASE = 64'h0000_0000_8000_0000,
    parameter SLAVE1_MASK = 64'hFFFF_FFFF_E000_0000,

    parameter SLAVE2_BASE = 64'h0000_0000_1000_0000,
    parameter SLAVE2_MASK = 64'hFFFF_FFFF_FFF0_0000,

    parameter SLAVE3_BASE = 64'h0000_0000_4000_0000,
    parameter SLAVE3_MASK = 64'hFFFF_FFFF_C000_0000
)(
    input CLK_I,
    input RST_I,


    // MASTER 0

    input [ADDR_WIDTH-1:0] M0_ADR_I,
    input [DATA_WIDTH-1:0] M0_DAT_O,
    output reg [DATA_WIDTH-1:0] M0_DAT_I,
    input [DATA_WIDTH/8-1:0] M0_SEL_I,
    input M0_CYC_I,
    input M0_STB_I,
    input M0_WE_I,
    input [2:0] M0_CTI_I,
    input [1:0] M0_BTE_I,
    output reg M0_ACK_O,
    output reg M0_ERR_O,


    // MASTER 1

    input [ADDR_WIDTH-1:0] M1_ADR_I,
    input [DATA_WIDTH-1:0] M1_DAT_O,
    output reg [DATA_WIDTH-1:0] M1_DAT_I,
    input [DATA_WIDTH/8-1:0] M1_SEL_I,
    input M1_CYC_I,
    input M1_STB_I,
    input M1_WE_I,
    input [2:0] M1_CTI_I,
    input [1:0] M1_BTE_I,
    output reg M1_ACK_O,
    output reg M1_ERR_O,

    // ARBITRATION / DEBUG

    output reg M0_GRANT_O,
    output reg M1_GRANT_O,


    // SLAVE 0

    output reg [ADDR_WIDTH-1:0] S0_ADR_O,
    output reg [DATA_WIDTH-1:0] S0_DAT_O,
    input [DATA_WIDTH-1:0] S0_DAT_I,
    output reg [DATA_WIDTH/8-1:0] S0_SEL_O,
    output reg S0_CYC_O,
    output reg S0_STB_O,
    output reg S0_WE_O,
    output reg [2:0] S0_CTI_O,
    output reg [1:0] S0_BTE_O,
    input S0_ACK_I,
    input S0_ERR_I,


    // SLAVE 1

    output reg [ADDR_WIDTH-1:0] S1_ADR_O,
    output reg [DATA_WIDTH-1:0] S1_DAT_O,
    input [DATA_WIDTH-1:0] S1_DAT_I,

    output reg [DATA_WIDTH/8-1:0] S1_SEL_O,
    output reg S1_CYC_O,
    output reg S1_STB_O,
    output reg S1_WE_O,
    output reg [2:0] S1_CTI_O,
    output reg [1:0] S1_BTE_O,
    input S1_ACK_I,
    input S1_ERR_I,


    // SLAVE 2
 
    output reg [ADDR_WIDTH-1:0] S2_ADR_O,
    output reg [DATA_WIDTH-1:0] S2_DAT_O,
    input [DATA_WIDTH-1:0] S2_DAT_I,
    output reg [DATA_WIDTH/8-1:0] S2_SEL_O,
    output reg S2_CYC_O,
    output reg S2_STB_O,
    output reg S2_WE_O,
    output reg [2:0] S2_CTI_O,
    output reg [1:0] S2_BTE_O,
    input S2_ACK_I,
    input S2_ERR_I,

 
    // SLAVE 3

    output reg [ADDR_WIDTH-1:0] S3_ADR_O,
    output reg [DATA_WIDTH-1:0] S3_DAT_O,
    input [DATA_WIDTH-1:0] S3_DAT_I,
    output reg [DATA_WIDTH/8-1:0] S3_SEL_O,
    output reg S3_CYC_O,
    output reg S3_STB_O,
    output reg S3_WE_O,
    output reg [2:0] S3_CTI_O,
    output reg [1:0] S3_BTE_O,
    input S3_ACK_I,
    input S3_ERR_I
);

    reg grant_valid;
    reg grant_master;
    reg last_grant;

    wire master0_request = M0_CYC_I;
    wire master1_request = M1_CYC_I;

    reg [ADDR_WIDTH-1:0] active_adr;
    reg [DATA_WIDTH-1:0] active_dat;
    reg [DATA_WIDTH/8-1:0] active_sel;
    reg active_cyc;
    reg active_stb;
    reg active_we;
    reg [2:0] active_cti;
    reg [1:0] active_bte;

    reg slave0_selected;
    reg slave1_selected;
    reg slave2_selected;
    reg slave3_selected;
    reg no_slave_selected;

 
    // MASTER ARBITRATION
 
    // The arbiter keeps ownership for the entire WISHBONE cycle. This allows a burst to complete without another master interrupting it.
    // When both masters are waiting, round-robin arbitration alternates the starting priority.

    always @(posedge CLK_I or posedge RST_I) begin
        if (RST_I) begin
            grant_valid <= 1'b0;
            grant_master <= 1'b0;
            last_grant <= 1'b1;

        end

        else begin

            if (grant_valid) begin

                if ((grant_master == 1'b0) && !master0_request) begin
                    last_grant <= 1'b0;
                    grant_valid <= 1'b0;
                end

                else if ((grant_master == 1'b1) && !master1_request) begin
                    last_grant <= 1'b1;
                    grant_valid <= 1'b0;
                end

            end

            else begin

                if (master0_request && master1_request) begin

                    if (last_grant == 1'b0) begin
                        grant_master <= 1'b1;
                    end
                    else begin
                        grant_master <= 1'b0;
                    end


                    grant_valid <= 1'b1;

                end

                else if (master0_request) begin

                    grant_master <= 1'b0;
                    grant_valid <= 1'b1;

                end

                else if (master1_request) begin

                    grant_master <= 1'b1;
                    grant_valid <= 1'b1;

                end

            end

        end

    end

 
    // ACTIVE MASTER
 

    always @(*) begin

        active_adr = {ADDR_WIDTH{1'b0}};
        active_dat = {DATA_WIDTH{1'b0}};
        active_sel = {(DATA_WIDTH/8){1'b0}};
        active_cyc = 1'b0;
        active_stb = 1'b0;
        active_we = 1'b0;
        active_cti = 3'b000;
        active_bte = 2'b00;

        if (grant_valid) begin

            if (grant_master == 1'b0) begin

                active_adr = M0_ADR_I;
                active_dat = M0_DAT_O;
                active_sel = M0_SEL_I;
                active_cyc = M0_CYC_I;
                active_stb = M0_STB_I;
                active_we = M0_WE_I;
                active_cti = M0_CTI_I;
                active_bte = M0_BTE_I;

            end

            else begin

                active_adr = M1_ADR_I;
                active_dat = M1_DAT_O;
                active_sel = M1_SEL_I;
                active_cyc = M1_CYC_I;
                active_stb = M1_STB_I;
                active_we = M1_WE_I;
                active_cti = M1_CTI_I;
                active_bte = M1_BTE_I;

            end


        end

    end

 
    // ADDRESS DECODE
 

    always @(*) begin

        slave0_selected = active_cyc && ((active_adr & SLAVE0_MASK) == (SLAVE0_BASE & SLAVE0_MASK));

        slave1_selected = active_cyc && ((active_adr & SLAVE1_MASK) == (SLAVE1_BASE & SLAVE1_MASK));

        slave2_selected = active_cyc && ((active_adr & SLAVE2_MASK) == (SLAVE2_BASE & SLAVE2_MASK));

        slave3_selected = active_cyc && ((active_adr & SLAVE3_MASK) == (SLAVE3_BASE & SLAVE3_MASK));

        no_slave_selected = active_cyc && active_stb && !slave0_selected && !slave1_selected && !slave2_selected && !slave3_selected;

    end

 
    // SLAVE OUTPUT ROUTING
 

    always @(*) begin

        // Default outputs
        S0_ADR_O = {ADDR_WIDTH{1'b0}};
        S0_DAT_O = {DATA_WIDTH{1'b0}};
        S0_SEL_O = {(DATA_WIDTH/8){1'b0}};
        S0_CYC_O = 1'b0;
        S0_STB_O = 1'b0;
        S0_WE_O = 1'b0;
        S0_CTI_O = 3'b000;
        S0_BTE_O = 2'b00;

        S1_ADR_O = {ADDR_WIDTH{1'b0}};
        S1_DAT_O = {DATA_WIDTH{1'b0}};
        S1_SEL_O = {(DATA_WIDTH/8){1'b0}};
        S1_CYC_O = 1'b0;
        S1_STB_O = 1'b0;
        S1_WE_O = 1'b0;
        S1_CTI_O = 3'b000;
        S1_BTE_O = 2'b00;

        S2_ADR_O = {ADDR_WIDTH{1'b0}};
        S2_DAT_O = {DATA_WIDTH{1'b0}};
        S2_SEL_O = {(DATA_WIDTH/8){1'b0}};
        S2_CYC_O = 1'b0;
        S2_STB_O = 1'b0;
        S2_WE_O = 1'b0;
        S2_CTI_O = 3'b000;
        S2_BTE_O = 2'b00;

        S3_ADR_O = {ADDR_WIDTH{1'b0}};
        S3_DAT_O = {DATA_WIDTH{1'b0}};
        S3_SEL_O = {(DATA_WIDTH/8){1'b0}};
        S3_CYC_O = 1'b0;
        S3_STB_O = 1'b0;
        S3_WE_O = 1'b0;
        S3_CTI_O = 3'b000;
        S3_BTE_O = 2'b00;

        if (slave0_selected) begin

            // Slaves receive an address relative to their region.
            S0_ADR_O = active_adr - SLAVE0_BASE;
            S0_DAT_O = active_dat;
            S0_SEL_O = active_sel;
            S0_CYC_O = active_cyc;
            S0_STB_O = active_stb;
            S0_WE_O = active_we;
            S0_CTI_O = active_cti;
            S0_BTE_O = active_bte;

        end

        if (slave1_selected) begin

            S1_ADR_O = active_adr - SLAVE1_BASE;
            S1_DAT_O = active_dat;
            S1_SEL_O = active_sel;
            S1_CYC_O = active_cyc;
            S1_STB_O = active_stb;
            S1_WE_O = active_we;
            S1_CTI_O = active_cti;
            S1_BTE_O = active_bte;

        end

        if (slave2_selected) begin

            S2_ADR_O = active_adr - SLAVE2_BASE;
            S2_DAT_O = active_dat;
            S2_SEL_O = active_sel;
            S2_CYC_O = active_cyc;
            S2_STB_O = active_stb;
            S2_WE_O = active_we;
            S2_CTI_O = active_cti;
            S2_BTE_O = active_bte;

        end

        if (slave3_selected) begin

            S3_ADR_O = active_adr - SLAVE3_BASE;
            S3_DAT_O = active_dat;
            S3_SEL_O = active_sel;
            S3_CYC_O = active_cyc;
            S3_STB_O = active_stb;
            S3_WE_O = active_we;
            S3_CTI_O = active_cti;
            S3_BTE_O = active_bte;

        end

    end

 
    // MASTER RESPONSE ROUTING
 

    always @(*) begin

        M0_DAT_I = {DATA_WIDTH{1'b0}};
        M1_DAT_I = {DATA_WIDTH{1'b0}};

        M0_ACK_O = 1'b0;
        M1_ACK_O = 1'b0;

        M0_ERR_O = 1'b0;
        M1_ERR_O = 1'b0;

        if (grant_valid) begin

            if (grant_master == 1'b0) begin

                if (slave0_selected) begin
                    M0_DAT_I = S0_DAT_I;
                    M0_ACK_O = S0_ACK_I;
                    M0_ERR_O = S0_ERR_I;
                end

                else if (slave1_selected) begin
                    M0_DAT_I = S1_DAT_I;
                    M0_ACK_O = S1_ACK_I;
                    M0_ERR_O = S1_ERR_I;
                end

                else if (slave2_selected) begin
                    M0_DAT_I = S2_DAT_I;
                    M0_ACK_O = S2_ACK_I;
                    M0_ERR_O = S2_ERR_I;
                end

                else if (slave3_selected) begin
                    M0_DAT_I = S3_DAT_I;
                    M0_ACK_O = S3_ACK_I;
                    M0_ERR_O = S3_ERR_I;
                end

                else if (no_slave_selected) begin
                    M0_ERR_O = 1'b1;
                end

            end

            else begin

                if (slave0_selected) begin
                    M1_DAT_I = S0_DAT_I;
                    M1_ACK_O = S0_ACK_I;
                    M1_ERR_O = S0_ERR_I;
                end

                else if (slave1_selected) begin
                    M1_DAT_I = S1_DAT_I;
                    M1_ACK_O = S1_ACK_I;
                    M1_ERR_O = S1_ERR_I;
                end

                else if (slave2_selected) begin
                    M1_DAT_I = S2_DAT_I;
                    M1_ACK_O = S2_ACK_I;
                    M1_ERR_O = S2_ERR_I;
                end

                else if (slave3_selected) begin
                    M1_DAT_I = S3_DAT_I;
                    M1_ACK_O = S3_ACK_I;
                    M1_ERR_O = S3_ERR_I;
                end

                else if (no_slave_selected) begin
                    M1_ERR_O = 1'b1;
                end

            end


        end


    end

 
    // ARBITRATION DEBUG OUTPUTS
 

    always @(*) begin

        M0_GRANT_O = grant_valid && (grant_master == 1'b0);
        M1_GRANT_O = grant_valid && (grant_master == 1'b1);

    end

endmodule