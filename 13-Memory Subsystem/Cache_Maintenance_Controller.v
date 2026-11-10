`timescale 1ns/1ps


// CACHE MAINTENANCE CONTROLLER
// Coordinates L1 and L2 clean / invalidate / discard operations.

module Cache_Maintenance_Controller (
    input wire CLK_I,
    input wire RST_I,

    // Command interface;
    // 0 = FENCE.I: clean data path, then invalidate instruction cache.
    // 1 = FLUSH_ALL: clean + invalidate data caches and invalidate I-cache.
    // 2 = CLEAN_FOR_DMA: clean the supplied range before an external DMA read.
    // 3 = INVALIDATE_I: invalidate instruction cache only.
    // 4 = INVALIDATE_AFTER_DMA: discard stale lines in the supplied range.
    // RANGE_LENGTH_I must be non-zero for commands 2 and 4.

    input wire CMD_VALID_I,
    input wire [2:0] CMD_I,

    // Physical byte range for DMA handoff operations. Length must be non-zero for CMD 2 and CMD 4; other commands operate globally.
    
    input wire [63:0] RANGE_BASE_I,
    input wire [63:0] RANGE_LENGTH_I,
    output wire CMD_READY_O,
    output reg BUSY_O,
    output reg DONE_O,
    output reg ERROR_O,

    // L1 adapter signals. RANGE_VALID_O is asserted for DMA range commands.
    // Branch 07 must add range-selective clean/invalidate and discard support to L1_Cache, then generate reliable done/error acknowledgements.
    // The current L1 implementation only has a full-cache d_flush input.

    output reg L1_D_FLUSH_O,
    output reg L1_D_INVALIDATE_O,
    output wire [63:0] L1_D_RANGE_BASE_O,
    output wire [63:0] L1_D_RANGE_LENGTH_O,
    output wire L1_D_RANGE_VALID_O,
    input wire L1_D_READY_I,
    input wire L1_D_DONE_I,
    input wire L1_D_ERROR_I,
    output reg L1_I_INVALIDATE_O,
    input wire L1_I_READY_I,
    input wire L1_I_DONE_I,
    input wire L1_I_ERROR_I,

    // L2 maintenance request: 0 = clean, 1 = clean+invalidate,
    // 2 = invalidate/discard without writeback.

    output reg L2_MAINT_REQ_O,
    output reg [1:0] L2_MAINT_OP_O,
    output wire [63:0] L2_MAINT_RANGE_BASE_O,
    output wire [63:0] L2_MAINT_RANGE_LENGTH_O,
    input wire L2_MAINT_READY_I,
    input wire L2_MAINT_DONE_I,
    input wire L2_MAINT_ERROR_I
);

    localparam [3:0] C_IDLE = 4'd0;
    localparam [3:0] C_L1_D_START = 4'd1;
    localparam [3:0] C_L1_D_WAIT = 4'd2;
    localparam [3:0] C_L2_START = 4'd3;
    localparam [3:0] C_L2_WAIT = 4'd4;
    localparam [3:0] C_L1_I_START = 4'd5;
    localparam [3:0] C_L1_I_WAIT = 4'd6;
    localparam [3:0] C_DONE = 4'd7;
    localparam [3:0] C_ERROR = 4'd8;
    localparam [3:0] C_L1_D_DISCARD_START = 4'd9;

    reg [3:0] state;
    reg [2:0] command;
    reg [63:0] range_base;
    reg [63:0] range_length;

    assign CMD_READY_O = (state == C_IDLE);
    assign L1_D_RANGE_BASE_O = range_base;
    assign L1_D_RANGE_LENGTH_O = range_length;
    assign L1_D_RANGE_VALID_O = (command == 3'd2) || (command == 3'd4);
    assign L2_MAINT_RANGE_BASE_O = range_base;
    assign L2_MAINT_RANGE_LENGTH_O = range_length;

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin
            state <= C_IDLE;
            command <= 3'd0;
            range_base <= 64'd0;
            range_length <= 64'd0;
            BUSY_O <= 1'b0;
            DONE_O <= 1'b0;
            ERROR_O <= 1'b0;
            L1_D_FLUSH_O <= 1'b0;
            L1_D_INVALIDATE_O <= 1'b0;
            L1_I_INVALIDATE_O <= 1'b0;
            L2_MAINT_REQ_O <= 1'b0;
            L2_MAINT_OP_O <= 2'd0;

        end


        else begin
            DONE_O <= 1'b0;
            ERROR_O <= 1'b0;
            L1_D_FLUSH_O <= 1'b0;
            L1_D_INVALIDATE_O <= 1'b0;
            L1_I_INVALIDATE_O <= 1'b0;
            L2_MAINT_REQ_O <= 1'b0;

            case (state)
                C_IDLE: begin
                    BUSY_O <= 1'b0;

                    if (CMD_VALID_I && CMD_READY_O) begin
                        if ((CMD_I <= 3'd4) && !(((CMD_I == 3'd2) || (CMD_I == 3'd4)) && (RANGE_LENGTH_I == 64'd0))) begin
                            command <= CMD_I;
                            range_base <= RANGE_BASE_I;
                            range_length <= RANGE_LENGTH_I;
                            BUSY_O <= 1'b1;

                            if (CMD_I == 3'd3)
                                state <= C_L1_I_START;
                            else if (CMD_I == 3'd4)
                                state <= C_L1_D_DISCARD_START;
                            else
                                state <= C_L1_D_START;

                        end

                        else begin

                            // A zero-length DMA range must never become a
                            // global discard or an accidental whole-cache
                            // clean request.
                            ERROR_O <= 1'b1;
                            DONE_O <= 1'b1;
                        end

                    end


                end


                C_L1_D_START: begin
                    if (L1_D_READY_I) begin
                        L1_D_FLUSH_O <= 1'b1;
                        state <= C_L1_D_WAIT;
                    end
                end

                C_L1_D_DISCARD_START: begin
                    if (L1_D_READY_I) begin
                        L1_D_INVALIDATE_O <= 1'b1;
                        state <= C_L1_D_WAIT;
                    end
                end

                C_L1_D_WAIT: begin
                    if (L1_D_ERROR_I)
                        state <= C_ERROR;
                    else if (L1_D_DONE_I)
                        state <= C_L2_START;
                end

                C_L2_START: begin
                    if (L2_MAINT_READY_I) begin
                        if (command == 3'd1)
                            L2_MAINT_OP_O <= 2'd1;
                        else if (command == 3'd4)
                            L2_MAINT_OP_O <= 2'd2;
                        else
                            L2_MAINT_OP_O <= 2'd0;
                        // range_length is zero for global FENCE.I / flush;
                        // it is non-zero for the selective DMA operations.
                        L2_MAINT_REQ_O <= 1'b1;
                        state <= C_L2_WAIT;
                    end
                end

                C_L2_WAIT: begin
                    if (L2_MAINT_ERROR_I)
                        state <= C_ERROR;
                    else if (L2_MAINT_DONE_I) begin
                        if ((command == 3'd0) || (command == 3'd1))
                            state <= C_L1_I_START;
                        else
                            state <= C_DONE;
                    end
                end

                C_L1_I_START: begin
                    if (L1_I_READY_I) begin

                        L1_I_INVALIDATE_O <= 1'b1;
                        state <= C_L1_I_WAIT;
                    end
                end

                C_L1_I_WAIT: begin
                    if (L1_I_ERROR_I)
                        state <= C_ERROR;
                    else if (L1_I_DONE_I)
                        state <= C_DONE;
                end

                C_DONE: begin
                    BUSY_O <= 1'b0;
                    DONE_O <= 1'b1;

                    state <= C_IDLE;
                end

                C_ERROR: begin
                    BUSY_O <= 1'b0;
                    ERROR_O <= 1'b1;
                    DONE_O <= 1'b1;
                    state <= C_IDLE;
                end

                default: state <= C_IDLE;
            endcase

        end


    end
    

endmodule