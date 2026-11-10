`timescale 1ns/1ps


// CLOCK / RESET / CDC SYNCHRONIZERS
// Single-bit, pulse and bundled-data handshake crossings.
// Use Async_FIFO.v for high-throughput multi-bit streams.

module Clock_Synchronizer #(
    parameter integer WIDTH = 1,
    parameter integer STAGES = 2
)(
    input wire CLK_I,
    input wire RST_I,
    input wire [WIDTH-1:0] DATA_I,
    output wire [WIDTH-1:0] DATA_O
);

    localparam integer SYNC_STAGES = (STAGES < 1) ? 1 : STAGES;

    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_stage [0:SYNC_STAGES-1];
    integer sync_index;

    always @(posedge CLK_I or posedge RST_I) begin
        if (RST_I) begin
            for (sync_index = 0; sync_index < SYNC_STAGES; sync_index = sync_index + 1)
                sync_stage[sync_index] <= {WIDTH{1'b0}};
        end
        else begin
            sync_stage[0] <= DATA_I;
            for (sync_index = 1; sync_index < SYNC_STAGES; sync_index = sync_index + 1)
                sync_stage[sync_index] <= sync_stage[sync_index-1];
        end
    end

    assign DATA_O = sync_stage[SYNC_STAGES-1];

endmodule


module Reset_Synchronizer #(
    parameter integer STAGES = 2
)(
    input wire CLK_I,
    input wire ASYNC_RST_I,
    output wire SYNC_RST_O
);

    localparam integer RESET_STAGES = (STAGES < 1) ? 1 : STAGES;

    (* ASYNC_REG = "TRUE" *) reg [RESET_STAGES-1:0] reset_pipeline;

    always @(posedge CLK_I or posedge ASYNC_RST_I) begin
        if (ASYNC_RST_I)
            reset_pipeline <= {RESET_STAGES{1'b1}};
        else
            reset_pipeline <= reset_pipeline << 1;
    end

    assign SYNC_RST_O = reset_pipeline[RESET_STAGES-1];

endmodule


module Pulse_Synchronizer (
    input wire SRC_CLK_I,
    input wire SRC_RST_I,
    input wire SRC_PULSE_I,
    output wire SRC_READY_O,

    input wire DST_CLK_I,
    input wire DST_RST_I,
    output reg DST_PULSE_O
);

    reg request_toggle;
    reg acknowledge_toggle;

    (* ASYNC_REG = "TRUE" *) reg acknowledge_sync1;
    (* ASYNC_REG = "TRUE" *) reg acknowledge_sync2;
    (* ASYNC_REG = "TRUE" *) reg request_sync1;
    (* ASYNC_REG = "TRUE" *) reg request_sync2;

    assign SRC_READY_O = (request_toggle == acknowledge_sync2);

    // Source domain: accept one pulse and toggle the request bit.
    always @(posedge SRC_CLK_I or posedge SRC_RST_I) begin
        if (SRC_RST_I) begin
            request_toggle <= 1'b0;
            acknowledge_sync1 <= 1'b0;
            acknowledge_sync2 <= 1'b0;
        end
        else begin
            acknowledge_sync1 <= acknowledge_toggle;
            acknowledge_sync2 <= acknowledge_sync1;
            if (SRC_PULSE_I && SRC_READY_O)
                request_toggle <= ~request_toggle;
        end
    end

    // Destination domain: detect the changed toggle and acknowledge it.
    always @(posedge DST_CLK_I or posedge DST_RST_I) begin
        if (DST_RST_I) begin
            request_sync1 <= 1'b0;
            request_sync2 <= 1'b0;
            acknowledge_toggle <= 1'b0;
            DST_PULSE_O <= 1'b0;
        end

        else begin
            request_sync1 <= request_toggle;
            request_sync2 <= request_sync1;
            DST_PULSE_O <= 1'b0;

            if (request_sync2 != acknowledge_toggle) begin
                DST_PULSE_O <= 1'b1;
                acknowledge_toggle <= request_sync2;
            end

        end


    end

endmodule


module Handshake_Synchronizer #(
    parameter integer DATA_WIDTH = 64
)(
    input wire SRC_CLK_I,
    input wire SRC_RST_I,
    input wire SRC_SEND_I,
    input wire [DATA_WIDTH-1:0] SRC_DATA_I,
    output wire SRC_READY_O,

    input wire DST_CLK_I,
    input wire DST_RST_I,
    input wire DST_READY_I,
    output reg DST_VALID_O,
    output reg [DATA_WIDTH-1:0] DST_DATA_O
);

    reg [DATA_WIDTH-1:0] source_data_hold;
    reg request_toggle;
    reg acknowledge_toggle;
    (* ASYNC_REG = "TRUE" *) reg request_sync1;
    (* ASYNC_REG = "TRUE" *) reg request_sync2;
    (* ASYNC_REG = "TRUE" *) reg acknowledge_sync1;
    (* ASYNC_REG = "TRUE" *) reg acknowledge_sync2;

    assign SRC_READY_O = (request_toggle == acknowledge_sync2);

    // Source domain: hold payload stable until destination acknowledges it.
    always @(posedge SRC_CLK_I or posedge SRC_RST_I) begin
        if (SRC_RST_I) begin
            source_data_hold <= {DATA_WIDTH{1'b0}};
            request_toggle <= 1'b0;
            acknowledge_sync1 <= 1'b0;
            acknowledge_sync2 <= 1'b0;
        end
        else begin
            acknowledge_sync1 <= acknowledge_toggle;
            acknowledge_sync2 <= acknowledge_sync1;
            if (SRC_SEND_I && SRC_READY_O) begin
                source_data_hold <= SRC_DATA_I;
                request_toggle <= ~request_toggle;
            end
        end
    end

    // Destination domain: sample only after request has crossed the synchronizer.
    // The bundled data has been stable for at least two destination clock periods by this point.
    always @(posedge DST_CLK_I or posedge DST_RST_I) begin
        
        if (DST_RST_I) begin
            request_sync1 <= 1'b0;
            request_sync2 <= 1'b0;
            acknowledge_toggle <= 1'b0;
            DST_VALID_O <= 1'b0;
            DST_DATA_O <= {DATA_WIDTH{1'b0}};
        end
        
        else begin
            request_sync1 <= request_toggle;
            request_sync2 <= request_sync1;
            if (!DST_VALID_O && (request_sync2 != acknowledge_toggle)) begin
                DST_DATA_O <= source_data_hold;
                DST_VALID_O <= 1'b1;
            end
        
            else if (DST_VALID_O && DST_READY_I) begin
                DST_VALID_O <= 1'b0;
                acknowledge_toggle <= request_sync2;
            end
        
        end
    end



endmodule