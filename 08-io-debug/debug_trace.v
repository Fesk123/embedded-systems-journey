`timescale 1ns/1ps

// Non-blocking instruction trace ring buffer with a Wishbone read interface.
// The CPU never waits for the trace buffer. When full, the oldest entry is overwritten.

module debug_trace #(
    parameter TRACE_DEPTH = 64
)(
    input wire clk_i,
    input wire rst_i,

    input wire wb_cyc_i,
    input wire wb_stb_i,
    input wire wb_we_i,
    input wire [63:0] wb_adr_i,
    input wire [63:0] wb_dat_i,
    input wire [7:0] wb_sel_i,
    output reg [63:0] wb_dat_o,
    output reg wb_ack_o,
    output wire wb_err_o,

    input wire trace_valid_i,
    input wire [63:0] trace_pc_i,
    input wire [31:0] trace_instruction_i,
    input wire [1:0] trace_privilege_i,
    input wire trace_exception_i,
    output wire trace_irq_o
);

    localparam PTR_WIDTH = $clog2(TRACE_DEPTH);
    localparam COUNT_WIDTH = $clog2(TRACE_DEPTH + 1);

    reg [127:0] trace_mem [0:TRACE_DEPTH-1];
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [COUNT_WIDTH-1:0] trace_count;
    reg [PTR_WIDTH-1:0] read_index;
    reg trace_enable;
    reg trace_overflow;
    reg [31:0] overflow_count;
    reg [127:0] trace_read_latch;
    reg trace_read_latch_valid;

    reg ack_seen;
    wire wb_fire = wb_cyc_i && wb_stb_i && !ack_seen;
    wire [4:0] reg_index = wb_adr_i[7:3];
    wire [PTR_WIDTH-1:0] oldest_index = write_ptr - trace_count[PTR_WIDTH-1:0];
    wire [PTR_WIDTH-1:0] selected_index = oldest_index + read_index;

    assign wb_err_o = 1'b0;
    assign trace_irq_o = trace_overflow && trace_enable;

    always @(posedge clk_i) begin

        if (rst_i) begin
            wb_dat_o <= 64'd0;
            wb_ack_o <= 1'b0;
            ack_seen <= 1'b0;
            write_ptr <= 0;
            trace_count <= 0;
            read_index <= 0;
            trace_enable <= 1'b0;
            trace_overflow <= 1'b0;
            overflow_count <= 0;
            trace_read_latch <= 0;
            trace_read_latch_valid <= 1'b0;

        end else begin
            wb_ack_o <= 1'b0;

            if (!wb_cyc_i || !wb_stb_i) begin
                ack_seen <= 1'b0;
            end else if (wb_fire) begin
                ack_seen <= 1'b1;
                wb_ack_o <= 1'b1;
                wb_dat_o <= 64'd0;

                if (wb_we_i && wb_sel_i[0]) begin

                    case (reg_index)
                        5'd0: begin

                            trace_enable <= wb_dat_i[0];
                            if (wb_dat_i[1]) begin
                                trace_count <= 0;
                                write_ptr <= 0;
                                read_index <= 0;
                                trace_overflow <= 1'b0;
                                overflow_count <= 0;
                                trace_read_latch_valid <= 1'b0;
                            end
                        end

                        5'd2: read_index <= wb_dat_i[PTR_WIDTH-1:0];
                        5'd3: trace_overflow <= trace_overflow & ~wb_dat_i[0];
                        default: begin end

                    endcase

                end else if (!wb_we_i) begin

                    case (reg_index)
                        5'd0: wb_dat_o[0] <= trace_enable;
                        5'd1: begin
                            wb_dat_o[COUNT_WIDTH-1:0] <= trace_count;
                            wb_dat_o[32] <= trace_overflow;
                        end
                        5'd2: wb_dat_o[PTR_WIDTH-1:0] <= read_index;
                        5'd3: begin
                            wb_dat_o <= trace_mem[selected_index][63:0];
                            trace_read_latch <= trace_mem[selected_index];
                            trace_read_latch_valid <= 1'b1;
                        end
                        5'd4: begin
                            wb_dat_o <= trace_read_latch_valid ? trace_read_latch[127:64] : trace_mem[selected_index][127:64];
                            trace_read_latch_valid <= 1'b0;
                        end

                        5'd5: wb_dat_o[31:0] <= overflow_count;
                        default: wb_dat_o <= 64'd0;
                    endcase
                end

            end

            if (trace_valid_i && trace_enable) begin
                trace_mem[write_ptr] <= {trace_pc_i, trace_instruction_i, trace_privilege_i, trace_exception_i, 29'd0};
                write_ptr <= write_ptr + 1'b1;

                if (trace_count < TRACE_DEPTH)
                    trace_count <= trace_count + 1'b1;
                else begin
                    trace_overflow <= 1'b1;
                    overflow_count <= overflow_count + 1'b1;
                end


            end
        end
        
    end

endmodule