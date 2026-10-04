`timescale 1ns/1ps


// L1 CACHE
// 32 KiB Instruction Cache and 32 KiB Data Cache
//
// This version is designed to sit after the Sv39 translation unit.
// The cache receives physical addresses and does not perform virtual address translation itself.
//
// Features:
// - Separate instruction and data caches
// - 32 KiB per cache
// - 4-way set associative
// - 64-byte cache lines
// - 128 sets per cache
// - 64-bit data path
// - Incrementing WISHBONE bursts for line refill and writeback
// - Write-back data cache
// - Write-allocate data cache
// - Read-only instruction cache
// - Pseudo-LRU replacement
// - MMIO / uncached data access bypass
// - Instruction cache invalidation
// - Data cache flush and invalidate
// - FENCE.I compatible instruction cache invalidation input
// - Atomic data access is serialized through the data cache controller
// - Separate WISHBONE masters for instruction and data traffic
//
// The intended SoC path is:
//
// RV64GC -> Sv39 -> L1 Cache -> WISHBONE Interconnect
//
// Sv39 supplies physical addresses. The cache then decides whether the request is a cache hit, cache miss or uncached access.


module L1_Cache #(

    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter CACHE_SIZE = 32768,
    parameter LINE_BYTES = 64,
    parameter WAYS = 4,
    parameter WB_MAX_BURST_LENGTH = 8

)(

    input CLK_I,
    input RST_I,

    
    // INSTRUCTION CACHE CPU INTERFACE
    

    input i_req,
    input [ADDR_WIDTH-1:0] i_paddr,

    output reg i_ready,
    output reg i_done,
    output reg [31:0] i_rdata,
    output reg i_fault,

    // Invalidate the complete instruction cache.
    // This is used by FENCE.I and boot / software maintenance.

    input i_invalidate,

    
    // DATA CACHE CPU INTERFACE
    

    input d_req,
    input d_write,
    input d_amo,
    input d_lr,
    input d_sc,
    input d_amo_word,
    input [4:0] d_amo_op,
    input [ADDR_WIDTH-1:0] d_paddr,
    input [DATA_WIDTH-1:0] d_wdata,
    input [DATA_WIDTH/8-1:0] d_sel,
    input d_cacheable,

    output reg d_ready,
    output reg d_done,
    output reg [DATA_WIDTH-1:0] d_rdata,
    output reg d_fault,

    // The cache reports the old AMO value separately from the normal data response.
    // The CPU keeps the architectural LR/SC reservation.

    output reg [DATA_WIDTH-1:0] d_amo_old_data,
    output reg d_sc_success,

    // Flush and invalidate the complete data cache.
    // Dirty lines are written back before invalidation.

    input d_flush,

    
    // INSTRUCTION WISHBONE MASTER
    

    output reg [ADDR_WIDTH-1:0] I_ADR_O,
    output reg [DATA_WIDTH-1:0] I_DAT_O,
    input [DATA_WIDTH-1:0] I_DAT_I,
    output reg [DATA_WIDTH/8-1:0] I_SEL_O,
    output reg I_CYC_O,
    output reg I_STB_O,
    output reg I_WE_O,
    output reg [2:0] I_CTI_O,
    output reg [1:0] I_BTE_O,
    input I_ACK_I,
    input I_ERR_I,

    
    // DATA WISHBONE MASTER
    

    output reg [ADDR_WIDTH-1:0] D_ADR_O,
    output reg [DATA_WIDTH-1:0] D_DAT_O,
    input [DATA_WIDTH-1:0] D_DAT_I,
    output reg [DATA_WIDTH/8-1:0] D_SEL_O,
    output reg D_CYC_O,
    output reg D_STB_O,
    output reg D_WE_O,
    output reg [2:0] D_CTI_O,
    output reg [1:0] D_BTE_O,
    input D_ACK_I,
    input D_ERR_I,

    
    // DEBUG
    

    output wire [3:0] debug_i_state,
    output wire [3:0] debug_d_state,
    output wire debug_i_hit,
    output wire debug_d_hit,

    output wire debug_i_miss,
    output wire debug_d_miss,

    output wire debug_i_refill,
    output wire debug_d_refill,
    output wire debug_d_writeback,
    output wire debug_d_uncached,

    output wire [6:0] debug_i_set,
    output wire [6:0] debug_d_set,
    output wire [1:0] debug_i_way,
    output wire [1:0] debug_d_way

);

    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam integer WORDS_PER_LINE = LINE_BYTES / DATA_BYTES;
    localparam integer SETS = CACHE_SIZE / LINE_BYTES / WAYS;
    localparam integer SET_BITS = 7;
    localparam integer OFFSET_BITS = 6;
    localparam integer TAG_BITS = ADDR_WIDTH - SET_BITS - OFFSET_BITS;

    localparam [2:0] WB_CTI_CLASSIC = 3'b000;
    localparam [2:0] WB_CTI_INCREMENT = 3'b010;
    localparam [2:0] WB_CTI_END = 3'b111;
    localparam [1:0] WB_BTE_LINEAR = 2'b00;

    localparam [3:0] I_IDLE = 4'd0;
    localparam [3:0] I_LOOKUP = 4'd1;
    localparam [3:0] I_REFILL = 4'd2;
    localparam [3:0] I_RESPOND = 4'd3;
    localparam [3:0] I_INVALIDATE = 4'd4;
    localparam [3:0] I_ERROR = 4'd5;

    localparam [3:0] D_IDLE = 4'd0;
    localparam [3:0] D_LOOKUP = 4'd1;
    localparam [3:0] D_WRITEBACK = 4'd2;
    localparam [3:0] D_REFILL = 4'd3;
    localparam [3:0] D_ACCESS = 4'd4;
    localparam [3:0] D_UNCACHED = 4'd5;
    localparam [3:0] D_FLUSH = 4'd6;
    localparam [3:0] D_FLUSH_WRITEBACK = 4'd7;
    localparam [3:0] D_RESPOND = 4'd8;
    localparam [3:0] D_ERROR = 4'd9;

    
    // CACHE STORAGE

    reg [DATA_WIDTH-1:0] instruction_data [0:WAYS*SETS*WORDS_PER_LINE-1];
    reg [DATA_WIDTH-1:0] data_data [0:WAYS*SETS*WORDS_PER_LINE-1];

    reg [TAG_BITS-1:0] instruction_tag [0:WAYS*SETS-1];
    reg [TAG_BITS-1:0] data_tag [0:WAYS*SETS-1];

    reg instruction_valid [0:WAYS*SETS-1];
    reg data_valid [0:WAYS*SETS-1];
    reg data_dirty [0:WAYS*SETS-1];

    // Three bits are enough to encode a tree based pseudo-LRU state for a four-way set associative cache.

    reg [2:0] instruction_plru [0:SETS-1];
    reg [2:0] data_plru [0:SETS-1];

    integer reset_i;
    integer reset_j;
    integer reset_k;

    
    // INSTRUCTION CACHE REQUEST STATE
    

    reg [3:0] i_state;
    reg [ADDR_WIDTH-1:0] i_req_address;
    reg [6:0] i_req_set;
    reg [5:0] i_req_offset;
    reg [TAG_BITS-1:0] i_req_tag;
    reg [1:0] i_hit_way;
    reg i_hit_valid;
    reg [1:0] i_replace_way;
    reg [3:0] i_burst_count;
    reg [31:0] i_response_data;

    
    // DATA CACHE REQUEST STATE
    

    reg [3:0] d_state;
    reg [ADDR_WIDTH-1:0] d_req_address;
    reg d_req_write_r;
    reg d_req_amo_r;
    reg d_req_lr_r;
    reg d_req_sc_r;
    reg d_req_amo_word_r;
    reg [4:0] d_req_amo_op_r;
    reg [DATA_WIDTH-1:0] d_req_wdata_r;
    reg [DATA_WIDTH/8-1:0] d_req_sel_r;
    reg d_req_cacheable_r;

    reg [6:0] d_req_set;
    reg [5:0] d_req_offset;
    reg [TAG_BITS-1:0] d_req_tag;
    reg [1:0] d_hit_way;
    reg d_hit_valid;
    reg [1:0] d_replace_way;
    reg [1:0] d_selected_way;
    reg [3:0] d_burst_count;
    reg [DATA_WIDTH-1:0] d_response_data;

    
    // FLUSH STATE
    

    reg [6:0] flush_set;
    reg [1:0] flush_way;

    
    // HELPER FUNCTIONS
    

    function integer cache_line_index;
        input [1:0] way;

        input [6:0] set_index;
        begin
            cache_line_index = (way * SETS) + set_index;
        end

    endfunction

    function integer cache_word_index;
        input [1:0] way;
        input [6:0] set_index;
        input [2:0] word_index;

        begin
            cache_word_index = ((way * SETS) + set_index) * WORDS_PER_LINE + word_index;
        end


    endfunction


    function [1:0] choose_plru_way;
        input [2:0] plru;
        begin
            // Tree PLRU:
            // bit 2 selects left/right subtree.
            // bit 1 selects way 0/1 when left is selected.
            // bit 0 selects way 2/3 when right is selected.

            if (plru[2] == 1'b0) begin
                if (plru[1] == 1'b0)
                    choose_plru_way = 2'd0;
                else
                    choose_plru_way = 2'd1;
            end


            else begin
                if (plru[0] == 1'b0)
                    choose_plru_way = 2'd2;
                else
                    choose_plru_way = 2'd3;
            end
        end
    endfunction

    function [2:0] update_plru;

        input [2:0] plru;
        input [1:0] used_way;

        begin

            update_plru = plru;

            case (used_way)

                2'd0: begin
                    update_plru[2] = 1'b1;
                    update_plru[1] = 1'b1;
                end

                2'd1: begin
                    update_plru[2] = 1'b1;
                    update_plru[1] = 1'b0;
                end

                2'd2: begin
                    update_plru[2] = 1'b0;
                    update_plru[0] = 1'b1;
                end

                2'd3: begin
                    update_plru[2] = 1'b0;
                    update_plru[0] = 1'b0;
                end

                default: begin
                    update_plru = plru;
                end

            endcase
        end
    endfunction

    function [DATA_WIDTH-1:0] apply_byte_select;

        input [DATA_WIDTH-1:0] old_data;
        input [DATA_WIDTH-1:0] new_data;
        input [DATA_WIDTH/8-1:0] select;
        integer byte_number;
        
        begin
            apply_byte_select = old_data;

            for (byte_number = 0; byte_number < DATA_BYTES; byte_number = byte_number + 1) begin
                if (select[byte_number])
                    apply_byte_select[byte_number*8 +: 8] = new_data[byte_number*8 +: 8];
            end
        end

    endfunction

    function [DATA_WIDTH-1:0] calculate_amo_result;
        
        input [DATA_WIDTH-1:0] old_data;
        input [DATA_WIDTH-1:0] new_data;
        input [4:0] operation;
        input word_operation;
        reg [31:0] old_word;
        reg [31:0] new_word;
        
        reg [31:0] word_result;
        begin
            if (word_operation) begin

                old_word = old_data[31:0];
                new_word = new_data[31:0];

                case (operation)
                    5'b00001: word_result = new_word;
                    5'b00000: word_result = old_word + new_word;
                    5'b00100: word_result = old_word ^ new_word;
                    5'b01100: word_result = old_word & new_word;
                    5'b01000: word_result = old_word | new_word;
                    5'b10000: word_result = ($signed(old_word) < $signed(new_word)) ? old_word : new_word;
                    5'b10100: word_result = ($signed(old_word) > $signed(new_word)) ? old_word : new_word;
                    5'b11000: word_result = (old_word < new_word) ? old_word : new_word;
                    5'b11100: word_result = (old_word > new_word) ? old_word : new_word;
                    default: word_result = new_word;
                endcase

                calculate_amo_result = {{32{word_result[31]}}, word_result};

            end
            else begin

                case (operation)
                    5'b00001: calculate_amo_result = new_data;
                    5'b00000: calculate_amo_result = old_data + new_data;
                    5'b00100: calculate_amo_result = old_data ^ new_data;
                    5'b01100: calculate_amo_result = old_data & new_data;
                    5'b01000: calculate_amo_result = old_data | new_data;
                    5'b10000: calculate_amo_result = ($signed(old_data) < $signed(new_data)) ? old_data : new_data;
                    5'b10100: calculate_amo_result = ($signed(old_data) > $signed(new_data)) ? old_data : new_data;
                    5'b11000: calculate_amo_result = (old_data < new_data) ? old_data : new_data;
                    5'b11100: calculate_amo_result = (old_data > new_data) ? old_data : new_data;
        
                    default: calculate_amo_result = new_data;
        
                endcase

            end
        end
    endfunction

    
    // REPLACEMENT WAY SELECTION
    

    always @(*) begin

        d_selected_way = choose_plru_way(data_plru[d_req_set]);

        // Use an invalid line before replacing a valid line.

        if (!data_valid[cache_line_index(2'd0, d_req_set)])
            d_selected_way = 2'd0;
        
        else if (!data_valid[cache_line_index(2'd1, d_req_set)])
            d_selected_way = 2'd1;
        
        else if (!data_valid[cache_line_index(2'd2, d_req_set)])
            d_selected_way = 2'd2;
        
        else if (!data_valid[cache_line_index(2'd3, d_req_set)])
            d_selected_way = 2'd3;



    end

    
    // DEBUG OUTPUTS
    

    assign debug_i_state = i_state;
    assign debug_d_state = d_state;

    assign debug_i_hit = i_hit_valid;
    assign debug_d_hit = d_hit_valid;

    assign debug_i_miss = (i_state == I_REFILL);
    assign debug_d_miss = (d_state == D_REFILL) || (d_state == D_WRITEBACK);

    assign debug_i_refill = (i_state == I_REFILL);
    assign debug_d_refill = (d_state == D_REFILL);
    assign debug_d_writeback = (d_state == D_WRITEBACK) || (d_state == D_FLUSH_WRITEBACK);
    assign debug_d_uncached = (d_state == D_UNCACHED);

    assign debug_i_set = i_req_set;
    assign debug_d_set = d_req_set;
    assign debug_i_way = i_hit_way;
    assign debug_d_way = d_hit_way;

    
    // READY / REQUEST OUTPUT LOGIC
    

    always @(*) begin

        i_ready = (i_state == I_IDLE) && !i_invalidate;
        d_ready = (d_state == D_IDLE) && !d_flush;

    end

    
    // INSTRUCTION WISHBONE OUTPUTS
    

    always @(*) begin

        I_ADR_O = {ADDR_WIDTH{1'b0}};
        I_DAT_O = {DATA_WIDTH{1'b0}};
        I_SEL_O = {(DATA_WIDTH/8){1'b0}};
        I_CYC_O = 1'b0;
        I_STB_O = 1'b0;
        I_WE_O = 1'b0;
        I_CTI_O = WB_CTI_CLASSIC;
        I_BTE_O = WB_BTE_LINEAR;

        if (i_state == I_REFILL) begin

            I_ADR_O = {i_req_address[ADDR_WIDTH-1:OFFSET_BITS], 6'b0} + (i_burst_count * DATA_BYTES);
            
            I_SEL_O = {(DATA_WIDTH/8){1'b1}};
            I_CYC_O = 1'b1;
            I_STB_O = 1'b1;
            I_WE_O = 1'b0;

            if (i_burst_count == 4'd7)
                I_CTI_O = WB_CTI_END;
            else
                I_CTI_O = WB_CTI_INCREMENT;


        end


    end

    
    // DATA WISHBONE OUTPUTS
    

    always @(*) begin

        D_ADR_O = {ADDR_WIDTH{1'b0}};
        D_DAT_O = {DATA_WIDTH{1'b0}};
        D_SEL_O = {(DATA_WIDTH/8){1'b0}};
        D_CYC_O = 1'b0;
        D_STB_O = 1'b0;
        D_WE_O = 1'b0;
        D_CTI_O = WB_CTI_CLASSIC;
        D_BTE_O = WB_BTE_LINEAR;

        if (d_state == D_WRITEBACK) begin

            D_ADR_O = {data_tag[cache_line_index(d_replace_way, d_req_set)], d_req_set, 6'b0} + (d_burst_count * DATA_BYTES);
            
            D_DAT_O = data_data[cache_word_index(d_replace_way, d_req_set, d_burst_count[2:0])];
            
            D_SEL_O = {(DATA_WIDTH/8){1'b1}};
            D_CYC_O = 1'b1;
            D_STB_O = 1'b1;
            D_WE_O = 1'b1;

            if (d_burst_count == 4'd7)
                D_CTI_O = WB_CTI_END;
            else
                D_CTI_O = WB_CTI_INCREMENT;


        end

        else if (d_state == D_REFILL) begin

            D_ADR_O = {d_req_address[ADDR_WIDTH-1:OFFSET_BITS], 6'b0} + (d_burst_count * DATA_BYTES);
            D_SEL_O = {(DATA_WIDTH/8){1'b1}};
            D_CYC_O = 1'b1;
            D_STB_O = 1'b1;
            D_WE_O = 1'b0;

            if (d_burst_count == 4'd7)
                D_CTI_O = WB_CTI_END;
            else
                D_CTI_O = WB_CTI_INCREMENT;


        end

        else if (d_state == D_UNCACHED) begin

            D_ADR_O = d_req_address;
            D_DAT_O = d_req_wdata_r;
            D_SEL_O = d_req_sel_r;
            D_CYC_O = 1'b1;
            D_STB_O = 1'b1;
            D_WE_O = d_req_write_r;
            D_CTI_O = WB_CTI_CLASSIC;
            D_BTE_O = WB_BTE_LINEAR;

        end

        else if (d_state == D_FLUSH_WRITEBACK) begin

            D_ADR_O = {data_tag[cache_line_index(flush_way, flush_set)], flush_set, 6'b0} + (d_burst_count * DATA_BYTES);
            D_DAT_O = data_data[cache_word_index(flush_way, flush_set, d_burst_count[2:0])];
            D_SEL_O = {(DATA_WIDTH/8){1'b1}};
            D_CYC_O = 1'b1;
            D_STB_O = 1'b1;
            D_WE_O = 1'b1;

            if (d_burst_count == 4'd7)
                D_CTI_O = WB_CTI_END;
            else
                D_CTI_O = WB_CTI_INCREMENT;

        end


    end

    
    // INSTRUCTION CACHE
    

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            i_state <= I_IDLE;
            i_done <= 1'b0;
            i_fault <= 1'b0;
            i_rdata <= 32'd0;
            i_response_data <= 32'd0;
            i_burst_count <= 4'd0;

        end

        else begin

            i_done <= 1'b0;
            i_fault <= 1'b0;


            case (i_state)

                I_IDLE: begin

                    if (i_invalidate) begin
                        i_state <= I_INVALIDATE;
                        i_req_set <= 7'd0;
                        i_replace_way <= 2'd0;
                    end

                    else if (i_req && i_ready) begin

                        i_req_address <= i_paddr;
                        i_req_set <= i_paddr[OFFSET_BITS + SET_BITS - 1:OFFSET_BITS];
                        i_req_offset <= i_paddr[OFFSET_BITS-1:0];
                        i_req_tag <= i_paddr[ADDR_WIDTH-1:OFFSET_BITS + SET_BITS];
                        i_state <= I_LOOKUP;

                    end


                end

                I_LOOKUP: begin

                    i_hit_valid <= 1'b0;
                    i_hit_way <= 2'd0;
                    i_replace_way <= choose_plru_way(instruction_plru[i_req_set]);

                    if (instruction_valid[cache_line_index(2'd0, i_req_set)] && instruction_tag[cache_line_index(2'd0, i_req_set)] == i_req_tag) begin

                        i_hit_valid <= 1'b1;
                        i_hit_way <= 2'd0;
                        instruction_plru[i_req_set] <= update_plru(instruction_plru[i_req_set], 2'd0);

                        if (i_req_offset[2] == 1'b0)
                            i_response_data <= instruction_data[cache_word_index(2'd0, i_req_set, i_req_offset[5:3])][31:0];
                        else
                            i_response_data <= instruction_data[cache_word_index(2'd0, i_req_set, i_req_offset[5:3])][63:32];

                        i_state <= I_RESPOND;

                    end

                    else if (instruction_valid[cache_line_index(2'd1, i_req_set)] && instruction_tag[cache_line_index(2'd1, i_req_set)] == i_req_tag) begin

                        i_hit_valid <= 1'b1;
                        i_hit_way <= 2'd1;

                        instruction_plru[i_req_set] <= update_plru(instruction_plru[i_req_set], 2'd1);

                        if (i_req_offset[2] == 1'b0)
                            i_response_data <= instruction_data[cache_word_index(2'd1, i_req_set, i_req_offset[5:3])][31:0];
                        else
                            i_response_data <= instruction_data[cache_word_index(2'd1, i_req_set, i_req_offset[5:3])][63:32];


                        i_state <= I_RESPOND;

                    end
                    else if (instruction_valid[cache_line_index(2'd2, i_req_set)] && instruction_tag[cache_line_index(2'd2, i_req_set)] == i_req_tag) begin

                        i_hit_valid <= 1'b1;
                        i_hit_way <= 2'd2;

                        instruction_plru[i_req_set] <= update_plru(instruction_plru[i_req_set], 2'd2);

                        if (i_req_offset[2] == 1'b0)
                            i_response_data <= instruction_data[cache_word_index(2'd2, i_req_set, i_req_offset[5:3])][31:0];
                        else
                            i_response_data <= instruction_data[cache_word_index(2'd2, i_req_set, i_req_offset[5:3])][63:32];

                        i_state <= I_RESPOND;

                    end
                    else if (instruction_valid[cache_line_index(2'd3, i_req_set)] && instruction_tag[cache_line_index(2'd3, i_req_set)] == i_req_tag) begin

                        i_hit_valid <= 1'b1;
                        i_hit_way <= 2'd3;
                        instruction_plru[i_req_set] <= update_plru(instruction_plru[i_req_set], 2'd3);

                        if (i_req_offset[2] == 1'b0)
                            i_response_data <= instruction_data[cache_word_index(2'd3, i_req_set, i_req_offset[5:3])][31:0];
                        else
                            i_response_data <= instruction_data[cache_word_index(2'd3, i_req_set, i_req_offset[5:3])][63:32];

                        i_state <= I_RESPOND;


                    end

                    else begin

                        // Use an invalid line first before replacing a valid line.
                        if (!instruction_valid[cache_line_index(2'd0, i_req_set)])
                            i_replace_way <= 2'd0;

                        else if (!instruction_valid[cache_line_index(2'd1, i_req_set)])
                            i_replace_way <= 2'd1;

                        else if (!instruction_valid[cache_line_index(2'd2, i_req_set)])

                            i_replace_way <= 2'd2;

                        else if (!instruction_valid[cache_line_index(2'd3, i_req_set)])
                            i_replace_way <= 2'd3;

                        i_burst_count <= 4'd0;
                        i_state <= I_REFILL;

                    end

                end

                I_REFILL: begin

                    if (I_ERR_I) begin
                        i_fault <= 1'b1;
                        i_done <= 1'b1;
                        i_state <= I_ERROR;
                    end

                    else if (I_ACK_I) begin

                        instruction_data[cache_word_index(i_replace_way, i_req_set, i_burst_count[2:0])] <= I_DAT_I;

                        if (i_burst_count == 4'd7) begin

                            instruction_tag[cache_line_index(i_replace_way, i_req_set)] <= i_req_tag;
                            instruction_valid[cache_line_index(i_replace_way, i_req_set)] <= 1'b1;
                            instruction_plru[i_req_set] <= update_plru(instruction_plru[i_req_set], i_replace_way);

                            if (i_req_offset[5:3] == 3'd7) begin
                                if (i_req_offset[2] == 1'b0)
                                    i_response_data <= I_DAT_I[31:0];
                                else
                                    i_response_data <= I_DAT_I[63:32];
                            end
                            else begin
                                if (i_req_offset[2] == 1'b0)
                                    i_response_data <= instruction_data[cache_word_index(i_replace_way, i_req_set, i_req_offset[5:3])][31:0];
                                else
                                    i_response_data <= instruction_data[cache_word_index(i_replace_way, i_req_set, i_req_offset[5:3])][63:32];
                            end

                            i_state <= I_RESPOND;

                        end
                        else begin
                            i_burst_count <= i_burst_count + 1'b1;
                        end

                    end

                end

                I_RESPOND: begin
                    i_rdata <= i_response_data;
                    i_done <= 1'b1;
                    i_state <= I_IDLE;
                end

                I_INVALIDATE: begin

                    instruction_valid[cache_line_index(i_replace_way, i_req_set)] <= 1'b0;

                    if (i_replace_way == 2'd3) begin

                        if (i_req_set == SETS - 1) begin
                            i_state <= I_IDLE;
                        end
                        else begin
                            i_req_set <= i_req_set + 1'b1;
                            i_replace_way <= 2'd0;
                        end

                    end
                    else begin
                        i_replace_way <= i_replace_way + 1'b1;

                    end

                end

                I_ERROR: begin
                    i_state <= I_IDLE;
                end

                default: begin
                    i_state <= I_IDLE;
                end

            endcase

        end

    end

    
    // DATA CACHE
    

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            d_state <= D_IDLE;
            d_done <= 1'b0;
            d_fault <= 1'b0;
            d_rdata <= {DATA_WIDTH{1'b0}};
            d_amo_old_data <= {DATA_WIDTH{1'b0}};
            d_sc_success <= 1'b0;
            d_burst_count <= 4'd0;
            flush_set <= 7'd0;
            flush_way <= 2'd0;

        end

        else begin

            d_done <= 1'b0;
            d_fault <= 1'b0;
            d_sc_success <= 1'b0;

            case (d_state)

                D_IDLE: begin

                    if (d_flush) begin

                        flush_set <= 7'd0;
                        flush_way <= 2'd0;
                        d_burst_count <= 4'd0;
                        d_state <= D_FLUSH;

                    end

                    else if (d_req && d_ready) begin

                        d_req_address <= d_paddr;
                        d_req_write_r <= d_write;
                        d_req_amo_r <= d_amo;

                        d_req_lr_r <= d_lr;
                        d_req_sc_r <= d_sc;
                        
                        d_req_amo_word_r <= d_amo_word;
                        d_req_amo_op_r <= d_amo_op;
                        d_req_wdata_r <= d_wdata;
                        
                        d_req_sel_r <= d_sel;
                        d_req_cacheable_r <= d_cacheable;

                        d_req_set <= d_paddr[OFFSET_BITS + SET_BITS - 1:OFFSET_BITS];
                        d_req_offset <= d_paddr[OFFSET_BITS-1:0];
                        d_req_tag <= d_paddr[ADDR_WIDTH-1:OFFSET_BITS + SET_BITS];

                        if (!d_cacheable)
                            d_state <= D_UNCACHED;
                        else
                            d_state <= D_LOOKUP;

                    end

                end

                D_LOOKUP: begin

                    d_hit_valid <= 1'b0;
                    d_hit_way <= 2'd0;
                    d_replace_way <= d_selected_way;

                    if (data_valid[cache_line_index(2'd0, d_req_set)] && data_tag[cache_line_index(2'd0, d_req_set)] == d_req_tag) begin

                        d_hit_valid <= 1'b1;
                        d_hit_way <= 2'd0;
                        data_plru[d_req_set] <= update_plru(data_plru[d_req_set], 2'd0);
                        d_state <= D_ACCESS;

                    end

                    else if (data_valid[cache_line_index(2'd1, d_req_set)] && data_tag[cache_line_index(2'd1, d_req_set)] == d_req_tag) begin

                        d_hit_valid <= 1'b1;
                        d_hit_way <= 2'd1;
                        data_plru[d_req_set] <= update_plru(data_plru[d_req_set], 2'd1);
                        d_state <= D_ACCESS;

                    end
                    else if (data_valid[cache_line_index(2'd2, d_req_set)] && data_tag[cache_line_index(2'd2, d_req_set)] == d_req_tag) begin

                        d_hit_valid <= 1'b1;
                        d_hit_way <= 2'd2;
                        data_plru[d_req_set] <= update_plru(data_plru[d_req_set], 2'd2);
                        d_state <= D_ACCESS;

                    end
                    else if (data_valid[cache_line_index(2'd3, d_req_set)] && data_tag[cache_line_index(2'd3, d_req_set)] == d_req_tag) begin

                        d_hit_valid <= 1'b1;
                        d_hit_way <= 2'd3;
                        data_plru[d_req_set] <= update_plru(data_plru[d_req_set], 2'd3);
                        d_state <= D_ACCESS;

                    end
                    else begin

                        if (data_valid[cache_line_index(d_selected_way, d_req_set)] && data_dirty[cache_line_index(d_selected_way, d_req_set)]) begin

                            d_burst_count <= 4'd0;
                            d_state <= D_WRITEBACK;

                        end
                        else begin

                            d_burst_count <= 4'd0;
                            d_state <= D_REFILL;

                        end

                    end

                end

                D_WRITEBACK: begin

                    if (D_ERR_I) begin
                        d_fault <= 1'b1;
                        d_done <= 1'b1;
                        d_state <= D_ERROR;
                    end

                    else if (D_ACK_I) begin

                        if (d_burst_count == 4'd7) begin

                            data_dirty[cache_line_index(d_replace_way, d_req_set)] <= 1'b0;
                            data_valid[cache_line_index(d_replace_way, d_req_set)] <= 1'b0;
                            d_burst_count <= 4'd0;
                            d_state <= D_REFILL;


                        end
                        else begin
                            d_burst_count <= d_burst_count + 1'b1;
                        end

                    end

                end

                D_REFILL: begin

                    if (D_ERR_I) begin
                        d_fault <= 1'b1;
                        d_done <= 1'b1;
                        d_state <= D_ERROR;
                    end

                    else if (D_ACK_I) begin

                        data_data[cache_word_index(d_replace_way, d_req_set, d_burst_count[2:0])] <= D_DAT_I;

                        if (d_burst_count == 4'd7) begin

                            data_tag[cache_line_index(d_replace_way, d_req_set)] <= d_req_tag;
                            
                            data_valid[cache_line_index(d_replace_way, d_req_set)] <= 1'b1;
                            data_dirty[cache_line_index(d_replace_way, d_req_set)] <= 1'b0;
                            data_plru[d_req_set] <= update_plru(data_plru[d_req_set], d_replace_way);
                            
                            d_hit_way <= d_replace_way;
                            d_hit_valid <= 1'b1;
                            d_state <= D_ACCESS;

                        end
                        else begin
                            d_burst_count <= d_burst_count + 1'b1;
                        end

                    end

                end

                D_ACCESS: begin

                    d_response_data <= data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])];
                    d_amo_old_data <= data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])];

                    if (d_req_amo_r) begin

                        data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])] <= calculate_amo_result( data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])], d_req_wdata_r, d_req_amo_op_r, d_req_amo_word_r);

                        data_dirty[cache_line_index(d_hit_way, d_req_set)] <= 1'b1;

                    end
                    else if (d_req_sc_r) begin

                        // The CPU owns the architectural reservation state.
                        // The cache serializes the actual store operation.

                        data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])] <= apply_byte_select(data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])], d_req_wdata_r, d_req_sel_r);

                        data_dirty[cache_line_index(d_hit_way, d_req_set)] <= 1'b1;
                        d_sc_success <= 1'b1;

                    end
                    else if (d_req_write_r) begin

                        data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])] <= apply_byte_select(data_data[cache_word_index(d_hit_way, d_req_set, d_req_offset[5:3])], d_req_wdata_r, d_req_sel_r);

                        data_dirty[cache_line_index(d_hit_way, d_req_set)] <= 1'b1;

                    end

                    d_state <= D_RESPOND;

                end

                D_UNCACHED: begin

                    if (D_ERR_I) begin
                        d_fault <= 1'b1;
                        d_done <= 1'b1;
                        d_state <= D_ERROR;

                    end
                    else if (D_ACK_I) begin

                        if (!d_req_write_r)
                            d_response_data <= D_DAT_I;
                        else
                            d_response_data <= {DATA_WIDTH{1'b0}};

                        if (d_req_sc_r)
                            d_sc_success <= 1'b1;

                        d_state <= D_RESPOND;

                    end

                end

                D_FLUSH: begin

                    if (!data_valid[cache_line_index(flush_way, flush_set)]) begin

                        if (flush_way == 2'd3) begin
                            if (flush_set == SETS - 1) begin
                                d_state <= D_IDLE;
                            end
                            else begin
                                flush_set <= flush_set + 1'b1;
                                flush_way <= 2'd0;
                            end
                        end
                        else begin
                            flush_way <= flush_way + 1'b1;
                        end

                    end
                    else if (data_dirty[cache_line_index(flush_way, flush_set)]) begin

                        d_burst_count <= 4'd0;
                        d_state <= D_FLUSH_WRITEBACK;

                    end
                    else begin

                        data_valid[cache_line_index(flush_way, flush_set)] <= 1'b0;
                        data_dirty[cache_line_index(flush_way, flush_set)] <= 1'b0;

                        if (flush_way == 2'd3) begin
                            if (flush_set == SETS - 1) begin
                                d_state <= D_IDLE;
                            end
                            else begin
                                flush_set <= flush_set + 1'b1;
                                flush_way <= 2'd0;
                            end
                        end
                        else begin
                            flush_way <= flush_way + 1'b1;
                        end

                    end

                end

                D_FLUSH_WRITEBACK: begin

                    if (D_ERR_I) begin
                        d_fault <= 1'b1;
                        d_done <= 1'b1;
                        d_state <= D_ERROR;
                    end
                    else if (D_ACK_I) begin

                        if (d_burst_count == 4'd7) begin

                            data_valid[cache_line_index(flush_way, flush_set)] <= 1'b0;
                            data_dirty[cache_line_index(flush_way, flush_set)] <= 1'b0;
                            d_burst_count <= 4'd0;

                            if (flush_way == 2'd3) begin
                                if (flush_set == SETS - 1) begin
                                    d_state <= D_IDLE;
                                end
                                else begin
                                    flush_set <= flush_set + 1'b1;
                                    flush_way <= 2'd0;
                                    d_state <= D_FLUSH;
                                end
                            end
                            else begin
                                flush_way <= flush_way + 1'b1;
                                d_state <= D_FLUSH;
                            end

                        end
                        else begin
                            d_burst_count <= d_burst_count + 1'b1;
                        end

                    end

                end

                D_RESPOND: begin
                    d_rdata <= d_response_data;
                    d_done <= 1'b1;
                    d_state <= D_IDLE;
                end

                D_ERROR: begin
                    d_state <= D_IDLE;
                end

                default: begin
                    d_state <= D_IDLE;
                end

            endcase

        end

    end

    
    // CACHE INITIALIZATION
    

    // All cache lines start invalid.
    //
    // Memory contents themselves are not initialized here because cache lines become valid only after a WISHBONE refill.

    initial begin

        for (reset_i = 0; reset_i < WAYS*SETS; reset_i = reset_i + 1) begin
            instruction_valid[reset_i] = 1'b0;
            data_valid[reset_i] = 1'b0;
            data_dirty[reset_i] = 1'b0;
            instruction_tag[reset_i] = {TAG_BITS{1'b0}};
            data_tag[reset_i] = {TAG_BITS{1'b0}};
        end

        for (reset_j = 0; reset_j < SETS; reset_j = reset_j + 1) begin
            instruction_plru[reset_j] = 3'b000;
            data_plru[reset_j] = 3'b000;
        end

    end

endmodule
