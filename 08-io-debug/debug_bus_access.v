`timescale 1ns/1ps

// Independent Wishbone master used by the RISC-V Debug Module for System Bus Access.
// This master must enter the system bus through an arbiter; it does not stall the CPU pipeline.

module debug_bus_access #(
    parameter TIMEOUT_CYCLES = 1024
)(
    input wire clk_i,
    input wire rst_i,

    input wire req_i,
    input wire we_i,
    input wire [63:0] addr_i,
    input wire [63:0] wdata_i,
    input wire [7:0] sel_i,
    output reg busy_o,
    output reg done_o,
    output reg error_o,
    output reg [63:0] rdata_o,

    output reg wb_cyc_o,
    output reg wb_stb_o,
    output reg wb_we_o,
    output reg [63:0] wb_adr_o,
    output reg [63:0] wb_dat_o,
    output reg [7:0] wb_sel_o,
    input wire [63:0] wb_dat_i,
    input wire wb_ack_i,
    input wire wb_err_i
);

    localparam IDLE = 1'b0;
    localparam WAIT_BUS = 1'b1;

    reg state;
    reg [$clog2(TIMEOUT_CYCLES+1)-1:0] timeout_count;

    always @(posedge clk_i) begin

        if (rst_i) begin
            state <= IDLE;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            rdata_o <= 64'd0;
            wb_cyc_o <= 1'b0;
            wb_stb_o <= 1'b0;
            wb_we_o <= 1'b0;
            wb_adr_o <= 64'd0;
            wb_dat_o <= 64'd0;
            wb_sel_o <= 8'd0;
            timeout_count <= 0;

        end else begin
            done_o <= 1'b0;

            case (state)
                IDLE: begin
                    busy_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_stb_o <= 1'b0;
                    timeout_count <= 0;

                    if (req_i) begin
                        busy_o <= 1'b1;
                        wb_cyc_o <= 1'b1;
                        wb_stb_o <= 1'b1;
                        wb_we_o <= we_i;
                        wb_adr_o <= addr_i;
                        wb_dat_o <= wdata_i;
                        wb_sel_o <= sel_i;
                        error_o <= 1'b0;
                        state <= WAIT_BUS;
                    end
                end

                WAIT_BUS: begin
                    if (wb_ack_i || wb_err_i) begin
                        rdata_o <= wb_dat_i;
                        error_o <= wb_err_i;
                        done_o <= 1'b1;
                        busy_o <= 1'b0;
                        wb_cyc_o <= 1'b0;
                        wb_stb_o <= 1'b0;
                        state <= IDLE;

                    end else if (timeout_count >= TIMEOUT_CYCLES-1) begin
                        rdata_o <= 64'd0;
                        error_o <= 1'b1;
                        done_o <= 1'b1;
                        busy_o <= 1'b0;
                        wb_cyc_o <= 1'b0;
                        wb_stb_o <= 1'b0;
                        state <= IDLE;

                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    busy_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_stb_o <= 1'b0;
                end
            endcase
        
        end

    end

endmodule