
`timescale 1ns/1ps


// GPU Texture Cache

// Small 2-way set-associative cache with 64-bit cache lines.
// Each line contains two adjacent 32-bit texels.
// A miss requests one aligned 64-bit word from the shared read DMA path.

module gpu_texture_cache #(
    parameter integer XLEN = 64,
    parameter integer SETS = 64,
    parameter integer INDEX_WIDTH = 6,
    parameter integer TAG_WIDTH = XLEN - 3 - INDEX_WIDTH
)(
    input clk_i,
    input rst_i,

    input req_valid_i,
    output req_ready_o,
    input [XLEN-1:0] req_addr_i,

    output reg resp_valid_o,
    input resp_ready_i,
    output reg [63:0] resp_data_o,
    output reg resp_error_o,

    output reg mem_req_valid_o,
    input mem_req_ready_i,
    output reg [XLEN-1:0] mem_req_addr_o,
    input mem_valid_i,
    output mem_ready_o,
    input [63:0] mem_data_i,
    input mem_done_i,
    input mem_error_i
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_MISS_REQ = 2'd1;
    localparam [1:0] S_MISS_WAIT = 2'd2;
    localparam [1:0] S_RESP = 2'd3;

    reg [1:0] state;

    reg [63:0] data_way0 [0:SETS-1];
    reg [63:0] data_way1 [0:SETS-1];
    reg [TAG_WIDTH-1:0] tag_way0 [0:SETS-1];
    reg [TAG_WIDTH-1:0] tag_way1 [0:SETS-1];
    reg [SETS-1:0] valid_way0;
    reg [SETS-1:0] valid_way1;
    reg [SETS-1:0] lru_way;

    reg [XLEN-1:0] miss_addr;
    reg [INDEX_WIDTH-1:0] miss_index;
    reg [TAG_WIDTH-1:0] miss_tag;
    reg miss_victim;

    reg [63:0] mem_data_buffer;
    reg mem_data_seen;
    reg mem_error_seen;

    wire [INDEX_WIDTH-1:0] request_index = req_addr_i[3+INDEX_WIDTH-1:3];
    wire [TAG_WIDTH-1:0] request_tag = req_addr_i[XLEN-1:3+INDEX_WIDTH];
    wire hit_way0 = valid_way0[request_index] && (tag_way0[request_index] == request_tag);
    wire hit_way1 = valid_way1[request_index] && (tag_way1[request_index] == request_tag);

    assign req_ready_o = (state == S_IDLE);
    assign mem_ready_o = (state == S_MISS_WAIT);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            valid_way0 <= {SETS{1'b0}};
            valid_way1 <= {SETS{1'b0}};
            lru_way <= {SETS{1'b0}};
            miss_addr <= {XLEN{1'b0}};
            miss_index <= {INDEX_WIDTH{1'b0}};
            miss_tag <= {TAG_WIDTH{1'b0}};
            miss_victim <= 1'b0;
            mem_data_buffer <= 64'd0;
            mem_data_seen <= 1'b0;
            mem_error_seen <= 1'b0;
            resp_valid_o <= 1'b0;
            resp_data_o <= 64'd0;
            resp_error_o <= 1'b0;
            mem_req_valid_o <= 1'b0;
            mem_req_addr_o <= {XLEN{1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    resp_valid_o <= 1'b0;
                    resp_error_o <= 1'b0;
                    mem_req_valid_o <= 1'b0;

                    if (req_valid_i && req_ready_o) begin
                        if (req_addr_i[2:0] != 3'b000) begin
                            resp_data_o <= 64'd0;
                            resp_error_o <= 1'b1;
                            resp_valid_o <= 1'b1;
                            state <= S_RESP;
                        end else if (hit_way0) begin
                            resp_data_o <= data_way0[request_index];
                            lru_way[request_index] <= 1'b1;
                            resp_valid_o <= 1'b1;
                            state <= S_RESP;
                        end else if (hit_way1) begin
                            resp_data_o <= data_way1[request_index];
                            lru_way[request_index] <= 1'b0;
                            resp_valid_o <= 1'b1;
                            state <= S_RESP;
                        end else begin
                            miss_addr <= {req_addr_i[XLEN-1:3], 3'b000};
                            miss_index <= request_index;
                            miss_tag <= request_tag;
                            miss_victim <= lru_way[request_index];
                            mem_req_addr_o <= {req_addr_i[XLEN-1:3], 3'b000};
                            mem_req_valid_o <= 1'b1;
                            mem_data_buffer <= 64'd0;
                            mem_data_seen <= 1'b0;
                            mem_error_seen <= 1'b0;
                            state <= S_MISS_REQ;
                        end
                    end
                end

                S_MISS_REQ: begin
                    if (mem_req_valid_o && mem_req_ready_i) begin
                        mem_req_valid_o <= 1'b0;
                        state <= S_MISS_WAIT;
                    end
                end

                S_MISS_WAIT: begin
                    if (mem_valid_i && mem_ready_o) begin
                        mem_data_buffer <= mem_data_i;
                        mem_data_seen <= 1'b1;
                    end

                    if (mem_error_i) begin
                        mem_error_seen <= 1'b1;
                    end

                    if (mem_done_i) begin
                        if (mem_error_seen || mem_error_i ||
                            !(mem_data_seen || (mem_valid_i && mem_ready_o))) begin
                            resp_data_o <= 64'd0;
                            resp_error_o <= 1'b1;
                        end else begin
                            resp_data_o <= (mem_valid_i && mem_ready_o) ?
                                           mem_data_i : mem_data_buffer;

                            if (!miss_victim) begin
                                data_way0[miss_index] <=
                                    (mem_valid_i && mem_ready_o) ? mem_data_i : mem_data_buffer;
                                tag_way0[miss_index] <= miss_tag;
                                valid_way0[miss_index] <= 1'b1;
                                lru_way[miss_index] <= 1'b1;
                            end else begin
                                data_way1[miss_index] <=
                                    (mem_valid_i && mem_ready_o) ? mem_data_i : mem_data_buffer;
                                tag_way1[miss_index] <= miss_tag;
                                valid_way1[miss_index] <= 1'b1;
                                lru_way[miss_index] <= 1'b0;
                            end
                        end

                        resp_valid_o <= 1'b1;
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    if (resp_valid_o && resp_ready_i) begin
                        resp_valid_o <= 1'b0;
                        resp_error_o <= 1'b0;
                        mem_data_seen <= 1'b0;
                        mem_error_seen <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
