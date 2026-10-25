`timescale 1ns/1ps

// RISC-V machine software interrupt and timer block.
// The register map follows the common CLINT layout for one hart.
// This block uses a 64-bit Wishbone data bus and byte addresses.

module debug_timer(
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
    output reg wb_err_o,

    output wire msip_o,
    output wire mtip_o
);

    localparam MSIP_OFFSET = 16'h0000;
    localparam MTIMECMP_OFFSET = 16'h4000;
    localparam MTIME_OFFSET = 16'hBFF8;

    reg [63:0] mtime;
    reg [63:0] mtimecmp;
    reg msip;
    reg ack_seen;
    integer byte_index;

    wire wb_fire = wb_cyc_i && wb_stb_i && !ack_seen;
    wire [15:0] reg_offset = wb_adr_i[15:0];

    assign msip_o = msip;
    assign mtip_o = (mtime >= mtimecmp);

    always @(posedge clk_i) begin

        if (rst_i) begin
            wb_dat_o <= 64'd0;
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            ack_seen <= 1'b0;
            mtime <= 64'd0;
            mtimecmp <= 64'hFFFFFFFFFFFFFFFF;
            msip <= 1'b0;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            mtime <= mtime + 1'b1;

            if (!wb_cyc_i || !wb_stb_i) begin
                ack_seen <= 1'b0;
            end else if (wb_fire) begin
                ack_seen <= 1'b1;
                wb_ack_o <= 1'b1;
                wb_dat_o <= 64'd0;

                case (reg_offset)
                    MSIP_OFFSET: begin
                        if (wb_we_i && wb_sel_i[0])
                            msip <= wb_dat_i[0];
                        else if (!wb_we_i)
                            wb_dat_o <= {63'd0, msip};
                    end

                    MTIMECMP_OFFSET: begin

                        if (wb_we_i) begin
                            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                                if (wb_sel_i[byte_index])
                                    mtimecmp[byte_index*8 +: 8] <= wb_dat_i[byte_index*8 +: 8];
                            end
                        end else begin
                            wb_dat_o <= mtimecmp;
                        end
                    end

                    MTIME_OFFSET: begin
                        if (wb_we_i) begin
                            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                                if (wb_sel_i[byte_index])
                                    mtime[byte_index*8 +: 8] <= wb_dat_i[byte_index*8 +: 8];
                            end
                        end else begin
                            wb_dat_o <= mtime;
                        end
                    end

                    default: begin
                        wb_err_o <= 1'b1;
                    end
                endcase
            end
        end
        
    end

endmodule