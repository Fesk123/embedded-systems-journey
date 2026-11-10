`timescale 1ns/1ps

// L2 CACHE
// 256 KiB, 4-way, 64-byte cache lines by default.
// Blocking cache with Wishbone slave and memory master.

module L2_Cache #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter CACHE_SIZE = 262144,
    parameter LINE_BYTES = 64,
    parameter WAYS = 4
)(
    input wire CLK_I,
    input wire RST_I,

    // Wishbone slave: requests from the shared SoC interconnect.
    input wire [ADDR_WIDTH-1:0] WB_ADR_I,
    input wire [DATA_WIDTH-1:0] WB_DAT_I,
    output reg [DATA_WIDTH-1:0] WB_DAT_O,
    input wire [DATA_WIDTH/8-1:0] WB_SEL_I,
    input wire WB_CYC_I,
    input wire WB_STB_I,
    input wire WB_WE_I,
    input wire [2:0] WB_CTI_I,
    input wire [1:0] WB_BTE_I,
    input wire WB_CACHEABLE_I,
    output reg WB_ACK_O,
    output reg WB_ERR_O,

    // Physical memory Wishbone master.
    output reg [ADDR_WIDTH-1:0] MEM_ADR_O,
    output reg [DATA_WIDTH-1:0] MEM_DAT_O,
    input wire [DATA_WIDTH-1:0] MEM_DAT_I,
    output reg [DATA_WIDTH/8-1:0] MEM_SEL_O,
    output reg MEM_CYC_O,
    output reg MEM_STB_O,
    output reg MEM_WE_O,
    output reg [2:0] MEM_CTI_O,
    output reg [1:0] MEM_BTE_O,
    input wire MEM_ACK_I,
    input wire MEM_ERR_I,

    // Maintenance command: 0 = clean, 1 = clean + invalidate,
    // 2 = invalidate/discard without writeback (after an external DMA write).
    // A non-zero byte range selects only overlapping cache lines.
    // A zero length selects the full cache for operations 0/1; operation 2 rejects it.

    input wire MAINT_REQ_I,
    input wire [1:0] MAINT_OP_I,

    // A zero length selects the complete cache for clean / flush.
    // Discard operations require an explicit non-zero byte range.

    input wire [ADDR_WIDTH-1:0] MAINT_RANGE_BASE_I,
    input wire [ADDR_WIDTH-1:0] MAINT_RANGE_LENGTH_I,
    output wire MAINT_READY_O,
    output reg MAINT_DONE_O,
    output reg MAINT_ERROR_O,

    // Debug counters, useful for later performance measurement.
    output reg [31:0] DEBUG_HIT_COUNT_O,
    output reg [31:0] DEBUG_MISS_COUNT_O,
    output reg [31:0] DEBUG_WRITEBACK_COUNT_O
);

    localparam integer DATA_BYTES = DATA_WIDTH / 8;
    localparam integer OFFSET_BITS = $clog2(LINE_BYTES);
    localparam integer WORDS_PER_LINE = LINE_BYTES / DATA_BYTES;
    localparam integer SETS = CACHE_SIZE / (LINE_BYTES * WAYS);
    localparam integer SET_BITS = (SETS <= 1) ? 1 : $clog2(SETS);
    localparam integer WAY_BITS = (WAYS <= 1) ? 1 : $clog2(WAYS);
    localparam integer BYTE_BITS = $clog2(DATA_BYTES);
    localparam integer TAG_BITS = ADDR_WIDTH - OFFSET_BITS - SET_BITS;

    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_LOOKUP = 4'd1;
    localparam [3:0] S_ACCESS = 4'd2;
    localparam [3:0] S_BYPASS = 4'd3;
    localparam [3:0] S_EVICT = 4'd4;
    localparam [3:0] S_REFILL = 4'd5;
    localparam [3:0] S_MAINT_SCAN = 4'd6;
    localparam [3:0] S_MAINT_WRITEBACK = 4'd7;

    localparam [2:0] WB_CTI_INCREMENT = 3'b010;
    localparam [2:0] WB_CTI_END = 3'b111;

    reg [3:0] state;

    reg [DATA_WIDTH-1:0] data_memory [0:WAYS*SETS*WORDS_PER_LINE-1];
    reg [TAG_BITS-1:0] tag_memory [0:WAYS*SETS-1];
    reg valid_memory [0:WAYS*SETS-1];
    reg dirty_memory [0:WAYS*SETS-1];
    reg [WAY_BITS-1:0] replacement_way [0:SETS-1];

    reg [ADDR_WIDTH-1:0] request_address;
    reg [DATA_WIDTH-1:0] request_write_data;
    reg [DATA_WIDTH/8-1:0] request_select;
    reg request_write;
    reg [SET_BITS-1:0] request_set;
    reg [TAG_BITS-1:0] request_tag;
    reg [OFFSET_BITS-1:0] request_offset;

    reg [WAY_BITS-1:0] selected_way;
    reg [WAY_BITS-1:0] victim_way;
    reg [TAG_BITS-1:0] victim_tag;
    reg [4:0] burst_index;

    reg request_seen;
    reg response_guard;
    reg [ADDR_WIDTH-1:0] last_request_address;

    reg [1:0] maintenance_operation;
    reg [ADDR_WIDTH-1:0] maintenance_range_base;
    reg [ADDR_WIDTH:0] maintenance_range_end;
    reg maintenance_range_enabled;
    reg [SET_BITS-1:0] maintenance_set;
    reg [WAY_BITS-1:0] maintenance_way;
    reg [TAG_BITS-1:0] maintenance_tag;

    reg lookup_hit;
    reg [WAY_BITS-1:0] lookup_way;
    reg [WAY_BITS-1:0] lookup_victim_way;
    reg lookup_invalid_found;
    reg [DATA_WIDTH-1:0] memory_writeback_data;
    integer lookup_index;
    integer reset_index;

    wire [SET_BITS-1:0] incoming_set;
    wire [TAG_BITS-1:0] incoming_tag;
    wire [OFFSET_BITS-1:0] incoming_offset;

    assign incoming_set = WB_ADR_I[OFFSET_BITS+SET_BITS-1:OFFSET_BITS];
    assign incoming_tag = WB_ADR_I[ADDR_WIDTH-1:OFFSET_BITS+SET_BITS];
    assign incoming_offset = WB_ADR_I[OFFSET_BITS-1:0];

    function integer line_index;
        input integer way;
        input integer set_number;
        begin
            line_index = way * SETS + set_number;
        end
    endfunction

    function integer word_index;
        input integer way;
        input integer set_number;
        input integer word_number;
        begin
            word_index = ((way * SETS) + set_number) * WORDS_PER_LINE + word_number;
        end
    endfunction

    function [DATA_WIDTH-1:0] merge_bytes;
        input [DATA_WIDTH-1:0] old_value;
        input [DATA_WIDTH-1:0] new_value;
        input [DATA_WIDTH/8-1:0] byte_select;
        integer byte_number;
        begin
            merge_bytes = old_value;
            for (byte_number = 0; byte_number < DATA_WIDTH/8; byte_number = byte_number + 1) begin
                if (byte_select[byte_number])
                    merge_bytes[byte_number*8 +: 8] = new_value[byte_number*8 +: 8];
            end
        end
    endfunction

    // A small fully parallel tag lookup. The default WAYS=4 maps well to a modest FPGA comparator tree; increase ways only after timing and BRAM/LUT utilization have been measured.

    always @(*) begin
        lookup_hit = 1'b0;
        lookup_way = {WAY_BITS{1'b0}};
        lookup_victim_way = replacement_way[request_set];
        lookup_invalid_found = 1'b0;

        for (lookup_index = 0; lookup_index < WAYS; lookup_index = lookup_index + 1) begin
            if (!lookup_hit && valid_memory[line_index(lookup_index, request_set)] &&
                (tag_memory[line_index(lookup_index, request_set)] == request_tag)) begin
                lookup_hit = 1'b1;
                lookup_way = lookup_index[WAY_BITS-1:0];
            end

            // Prefer an invalid way over evicting a valid line.
            // This avoids unnecessary writebacks immediately after invalidate operations.

            if (!lookup_invalid_found && !valid_memory[line_index(lookup_index, request_set)]) begin
                lookup_victim_way = lookup_index[WAY_BITS-1:0];
                lookup_invalid_found = 1'b1;
            end
        end
    end

    // Build the physical address of the currently scanned cache line.
    // The 65-bit end addresses let a range include the top of the address space without silently wrapping at ADDR_WIDTH.

    wire [ADDR_WIDTH-1:0] maintenance_line_address;
    wire [ADDR_WIDTH:0] maintenance_line_end;
    wire maintenance_line_in_range;

    assign maintenance_line_address = {tag_memory[line_index(maintenance_way, maintenance_set)], maintenance_set, {OFFSET_BITS{1'b0}}};
    assign maintenance_line_end = {1'b0, maintenance_line_address} + LINE_BYTES;
    assign maintenance_line_in_range = !maintenance_range_enabled || (({1'b0, maintenance_line_address} < maintenance_range_end) && (maintenance_line_end > {1'b0, maintenance_range_base}));

    assign MAINT_READY_O = (state == S_IDLE) && !(WB_CYC_I && WB_STB_I);

    // MEMORY BUS OUTPUTS


    always @(*) begin
        MEM_ADR_O = {ADDR_WIDTH{1'b0}};
        MEM_DAT_O = {DATA_WIDTH{1'b0}};
        MEM_SEL_O = {DATA_WIDTH/8{1'b1}};
        MEM_CYC_O = 1'b0;
        MEM_STB_O = 1'b0;
        MEM_WE_O = 1'b0;
        MEM_CTI_O = 3'b000;
        MEM_BTE_O = 2'b00;

        case (state)
            S_BYPASS: begin
                MEM_ADR_O = request_address;
                MEM_DAT_O = request_write_data;
                MEM_SEL_O = request_select;
                MEM_CYC_O = 1'b1;
                MEM_STB_O = 1'b1;
                MEM_WE_O = request_write;
            end

            S_EVICT: begin
                MEM_ADR_O = {victim_tag, request_set, {OFFSET_BITS{1'b0}}} + (burst_index * DATA_BYTES);
                MEM_DAT_O = memory_writeback_data;
                MEM_CYC_O = 1'b1;
                MEM_STB_O = 1'b1;
                MEM_WE_O = 1'b1;
                MEM_CTI_O = (burst_index == WORDS_PER_LINE-1) ? WB_CTI_END : WB_CTI_INCREMENT;
                MEM_BTE_O = 2'b00;
            end

            S_REFILL: begin
                MEM_ADR_O = {request_tag, request_set, {OFFSET_BITS{1'b0}}} + (burst_index * DATA_BYTES);
                MEM_CYC_O = 1'b1;
                MEM_STB_O = 1'b1;
                MEM_WE_O = 1'b0;
                MEM_CTI_O = (burst_index == WORDS_PER_LINE-1) ? WB_CTI_END : WB_CTI_INCREMENT;
                MEM_BTE_O = 2'b00;
            end

            S_MAINT_WRITEBACK: begin
                MEM_ADR_O = {maintenance_tag, maintenance_set, {OFFSET_BITS{1'b0}}} + (burst_index * DATA_BYTES);
                MEM_DAT_O = memory_writeback_data;
                MEM_CYC_O = 1'b1;
                MEM_STB_O = 1'b1;
                MEM_WE_O = 1'b1;
                MEM_CTI_O = (burst_index == WORDS_PER_LINE-1) ? WB_CTI_END : WB_CTI_INCREMENT;
                MEM_BTE_O = 2'b00;
            end

            default: begin
                MEM_ADR_O = {ADDR_WIDTH{1'b0}};
            end
        endcase
    end


    // CACHE STATE MACHINE


    always @(posedge CLK_I or posedge RST_I) begin
        if (RST_I) begin
            state <= S_IDLE;
            WB_DAT_O <= {DATA_WIDTH{1'b0}};
            WB_ACK_O <= 1'b0;
            WB_ERR_O <= 1'b0;
            MAINT_DONE_O <= 1'b0;
            MAINT_ERROR_O <= 1'b0;

            request_address <= {ADDR_WIDTH{1'b0}};
            request_write_data <= {DATA_WIDTH{1'b0}};
            request_select <= {DATA_WIDTH/8{1'b0}};
            request_write <= 1'b0;
            request_set <= {SET_BITS{1'b0}};
            request_tag <= {TAG_BITS{1'b0}};
            request_offset <= {OFFSET_BITS{1'b0}};
            selected_way <= {WAY_BITS{1'b0}};
            victim_way <= {WAY_BITS{1'b0}};
            victim_tag <= {TAG_BITS{1'b0}};
            memory_writeback_data <= {DATA_WIDTH{1'b0}};
            burst_index <= 5'd0;
            request_seen <= 1'b0;
            response_guard <= 1'b0;
            last_request_address <= {ADDR_WIDTH{1'b0}};
            maintenance_operation <= 2'd0;
            maintenance_range_base <= {ADDR_WIDTH{1'b0}};
            maintenance_range_end <= {(ADDR_WIDTH+1){1'b0}};
            maintenance_range_enabled <= 1'b0;
            maintenance_set <= {SET_BITS{1'b0}};
            maintenance_way <= {WAY_BITS{1'b0}};
            maintenance_tag <= {TAG_BITS{1'b0}};
            DEBUG_HIT_COUNT_O <= 32'd0;
            DEBUG_MISS_COUNT_O <= 32'd0;
            DEBUG_WRITEBACK_COUNT_O <= 32'd0;

            for (reset_index = 0; reset_index < WAYS*SETS; reset_index = reset_index + 1) begin
                valid_memory[reset_index] <= 1'b0;
                dirty_memory[reset_index] <= 1'b0;
                tag_memory[reset_index] <= {TAG_BITS{1'b0}};
            end
            for (reset_index = 0; reset_index < SETS; reset_index = reset_index + 1)
                replacement_way[reset_index] <= {WAY_BITS{1'b0}};
        end
        else begin
            WB_ACK_O <= 1'b0;
            WB_ERR_O <= 1'b0;
            MAINT_DONE_O <= 1'b0;
            MAINT_ERROR_O <= 1'b0;

            if (!(WB_CYC_I && WB_STB_I))
                request_seen <= 1'b0;

            case (state)
                S_IDLE: begin

                    // Registered Wishbone responses are sampled by the master on the following edge.
                    // Do not mistake the old request for a new transfer during that response edge.
                    // A different address may still be accepted immediately.

                    if (response_guard && !(WB_CYC_I && WB_STB_I && (WB_ADR_I != last_request_address))) begin
                        response_guard <= 1'b0;
                        request_seen <= 1'b0;
                    end
                    else if (MAINT_REQ_I && MAINT_READY_O && !response_guard) begin
                        if ((MAINT_OP_I <= 2'd2) && !((MAINT_OP_I == 2'd2) && (MAINT_RANGE_LENGTH_I == {ADDR_WIDTH{1'b0}}))) begin
                            maintenance_operation <= MAINT_OP_I;
                            maintenance_range_base <= MAINT_RANGE_BASE_I;
                            maintenance_range_end <= {1'b0, MAINT_RANGE_BASE_I} + {1'b0, MAINT_RANGE_LENGTH_I};
                            maintenance_range_enabled <= (MAINT_RANGE_LENGTH_I != {ADDR_WIDTH{1'b0}});
                            maintenance_set <= {SET_BITS{1'b0}};
                            maintenance_way <= {WAY_BITS{1'b0}};
                            state <= S_MAINT_SCAN;
                        end
                        else begin
                            MAINT_ERROR_O <= 1'b1;
                            MAINT_DONE_O <= 1'b1;
                        end
                    end
                    else if (WB_CYC_I && WB_STB_I && (!request_seen || (WB_ADR_I != last_request_address))) begin
                        response_guard <= 1'b0;
                        request_seen <= 1'b1;
                        last_request_address <= WB_ADR_I;
                        request_address <= WB_ADR_I;
                        request_write_data <= WB_DAT_I;
                        request_select <= WB_SEL_I;
                        request_write <= WB_WE_I;
                        request_set <= incoming_set;
                        request_tag <= incoming_tag;
                        request_offset <= incoming_offset;

                        if (WB_BTE_I != 2'b00) begin
                            WB_ERR_O <= 1'b1;
                            response_guard <= 1'b1;
                        end
                        else begin
                            if (WB_CACHEABLE_I)
                                state <= S_LOOKUP;
                            else
                                state <= S_BYPASS;
                        end
                    end
                    else if (response_guard) begin
                        response_guard <= 1'b0;
                        request_seen <= 1'b0;
                    end
                end

                S_LOOKUP: begin
                    if (lookup_hit) begin
                        selected_way <= lookup_way;
                        DEBUG_HIT_COUNT_O <= DEBUG_HIT_COUNT_O + 32'd1;
                        state <= S_ACCESS;
                    end
                    else begin
                        DEBUG_MISS_COUNT_O <= DEBUG_MISS_COUNT_O + 32'd1;
                        if (valid_memory[line_index(lookup_victim_way, request_set)] && dirty_memory[line_index(lookup_victim_way, request_set)]) begin
                            victim_way <= lookup_victim_way;
                            victim_tag <= tag_memory[line_index(lookup_victim_way, request_set)];
                            memory_writeback_data <= data_memory[word_index(lookup_victim_way, request_set, 0)];
                            burst_index <= 5'd0;
                            state <= S_EVICT;
                        end


                        else begin
                            victim_way <= lookup_victim_way;
                            burst_index <= 5'd0;
                            state <= S_REFILL;
                        end
                    end
                end

                S_ACCESS: begin
                    if (request_write) begin
                        data_memory[word_index(selected_way, request_set, request_offset[OFFSET_BITS-1:BYTE_BITS])] <= merge_bytes(data_memory[word_index(selected_way, request_set, request_offset[OFFSET_BITS-1:BYTE_BITS])], request_write_data, request_select);
                        dirty_memory[line_index(selected_way, request_set)] <= 1'b1;
                        WB_DAT_O <= {DATA_WIDTH{1'b0}};
                    end
                    else begin
                        WB_DAT_O <= data_memory[word_index(selected_way, request_set, request_offset[OFFSET_BITS-1:BYTE_BITS])];
                    end

                    WB_ACK_O <= 1'b1;
                    response_guard <= 1'b1;
                    state <= S_IDLE;
                end

                S_BYPASS: begin
                    if (MEM_ERR_I) begin
                        WB_ERR_O <= 1'b1;
                        response_guard <= 1'b1;
                        state <= S_IDLE;
                    end
                    
                    else if (MEM_ACK_I) begin
                        WB_DAT_O <= MEM_DAT_I;
                        WB_ACK_O <= 1'b1;
                        response_guard <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_EVICT: begin
                    if (MEM_ERR_I) begin
                        WB_ERR_O <= 1'b1;
                        response_guard <= 1'b1;
                        state <= S_IDLE;
                    end
                    else if (MEM_ACK_I) begin
                        if (burst_index == WORDS_PER_LINE-1) begin
                            burst_index <= 5'd0;
                            DEBUG_WRITEBACK_COUNT_O <= DEBUG_WRITEBACK_COUNT_O + 32'd1;
                            state <= S_REFILL;
                        end
                    
                    
                        else begin
                            burst_index <= burst_index + 5'd1;
                            memory_writeback_data <= data_memory[word_index(victim_way, request_set, burst_index + 1'b1)];
                        end
                
                    end
                

                end

                S_REFILL: begin
                    if (MEM_ERR_I) begin
                        valid_memory[line_index(victim_way, request_set)] <= 1'b0;
                        dirty_memory[line_index(victim_way, request_set)] <= 1'b0;
                        WB_ERR_O <= 1'b1;
                        response_guard <= 1'b1;
                        state <= S_IDLE;
                    end
                
                    else if (MEM_ACK_I) begin
                        data_memory[word_index(victim_way, request_set, burst_index)] <= MEM_DAT_I;
                
                        if (burst_index == WORDS_PER_LINE-1) begin
                            tag_memory[line_index(victim_way, request_set)] <= request_tag;
                            valid_memory[line_index(victim_way, request_set)] <= 1'b1;
                            dirty_memory[line_index(victim_way, request_set)] <= 1'b0;
                            replacement_way[request_set] <= (victim_way == WAYS-1) ? {WAY_BITS{1'b0}} : victim_way + 1'b1;
                            selected_way <= victim_way;
                            burst_index <= 5'd0;
                            state <= S_ACCESS;
                        end
                
                        else
                            burst_index <= burst_index + 5'd1;
                    end
                
                end

                S_MAINT_SCAN: begin
                    if (valid_memory[line_index(maintenance_way, maintenance_set)] && maintenance_line_in_range && dirty_memory[line_index(maintenance_way, maintenance_set)] && (maintenance_operation != 2'd2)) begin
                        maintenance_tag <= tag_memory[line_index(maintenance_way, maintenance_set)];
                        memory_writeback_data <= data_memory[word_index(maintenance_way, maintenance_set, 0)];
                        burst_index <= 5'd0;
                        state <= S_MAINT_WRITEBACK;
                    end
                    else begin

                        // Only modify lines that overlap the requested physical range. A zero range length means a full cache operation, except that discard rejects it.

                        if (valid_memory[line_index(maintenance_way, maintenance_set)] && maintenance_line_in_range) begin
                            if (maintenance_operation != 2'd0)
                                valid_memory[line_index(maintenance_way, maintenance_set)] <= 1'b0;
                            if (maintenance_operation == 2'd2)
                                dirty_memory[line_index(maintenance_way, maintenance_set)] <= 1'b0;
                        end

                        if (maintenance_way == WAYS-1) begin
                            if (maintenance_set == SETS-1) begin
                                MAINT_DONE_O <= 1'b1;
                                state <= S_IDLE;
                            end
                            else begin
                                maintenance_set <= maintenance_set + 1'b1;
                                maintenance_way <= {WAY_BITS{1'b0}};
                            end
                        end
                        else
                            maintenance_way <= maintenance_way + 1'b1;
                    end
                
                
                end

                S_MAINT_WRITEBACK: begin
                    if (MEM_ERR_I) begin
                        MAINT_ERROR_O <= 1'b1;
                        MAINT_DONE_O <= 1'b1;
                        state <= S_IDLE;
                    end
                
                
                    else if (MEM_ACK_I) begin
                        if (burst_index == WORDS_PER_LINE-1) begin
                
                            dirty_memory[line_index(maintenance_way, maintenance_set)] <= 1'b0;
                            if (maintenance_operation != 2'd0)
                                valid_memory[line_index(maintenance_way, maintenance_set)] <= 1'b0;
                            DEBUG_WRITEBACK_COUNT_O <= DEBUG_WRITEBACK_COUNT_O + 32'd1;
                
                            burst_index <= 5'd0;

                            if (maintenance_way == WAYS-1) begin
                                if (maintenance_set == SETS-1) begin
                                    MAINT_DONE_O <= 1'b1;
                                    state <= S_IDLE;
                                end
                                else begin
                                    maintenance_set <= maintenance_set + 1'b1;
                                    maintenance_way <= {WAY_BITS{1'b0}};
                                    state <= S_MAINT_SCAN;
                                end
                            end
                            else begin
                                maintenance_way <= maintenance_way + 1'b1;
                                state <= S_MAINT_SCAN;
                            end
                        end
                        else begin
                            burst_index <= burst_index + 5'd1;
                            memory_writeback_data <= data_memory[word_index(maintenance_way, maintenance_set, burst_index + 1'b1)];
                        end
                
                    end
                
                
                end

                default: state <= S_IDLE;
            endcase
        
        end
    
    
    end

endmodule