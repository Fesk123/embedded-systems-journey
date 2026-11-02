`timescale 1ns/1ps


// GPU AXI4 DMA

// Independent AXI4 read and write burst channels.
// The data bus is 64-bit and each beat transfers 8 bytes.
// Bursts are limited to 16 beats and may not cross a 4 KiB boundary.
// The read and write channels can operate at the same time.

module gpu_axi_dma #(
    parameter integer XLEN = 64,
    parameter integer ID_WIDTH = 4,
    parameter integer MAX_BURST = 16
)(
    input clk_i,
    input rst_i,

    // Write request and streaming data interface.
    input wr_start_i,
    input [XLEN-1:0] wr_addr_i,
    input [7:0] wr_beats_i,
    output wr_busy_o,
    input wr_data_valid_i,
    input [63:0] wr_data_i,
    input [7:0] wr_strb_i,
    output wr_data_ready_o,
    output reg wr_done_o,
    output reg wr_error_o,

    // Read request and streaming data interface.
    input rd_start_i,
    input [XLEN-1:0] rd_addr_i,
    input [7:0] rd_beats_i,
    output rd_busy_o,
    output rd_valid_o,
    output [63:0] rd_data_o,
    output rd_last_o,
    input rd_ready_i,
    output reg rd_done_o,
    output reg rd_error_o,

    // AXI4 write address channel.
    output reg [ID_WIDTH-1:0] m_axi_awid_o,
    output reg [XLEN-1:0] m_axi_awaddr_o,
    output reg [7:0] m_axi_awlen_o,
    output [2:0] m_axi_awsize_o,
    output [1:0] m_axi_awburst_o,
    output m_axi_awlock_o,
    output [3:0] m_axi_awcache_o,
    output [2:0] m_axi_awprot_o,
    output [3:0] m_axi_awqos_o,
    output reg m_axi_awvalid_o,
    input m_axi_awready_i,

    // AXI4 write data channel.
    output [63:0] m_axi_wdata_o,
    output [7:0] m_axi_wstrb_o,
    output reg m_axi_wlast_o,
    output reg m_axi_wvalid_o,
    input m_axi_wready_i,

    // AXI4 write response channel.
    input [ID_WIDTH-1:0] m_axi_bid_i,
    input [1:0] m_axi_bresp_i,
    input m_axi_bvalid_i,
    output reg m_axi_bready_o,

    // AXI4 read address channel.
    output reg [ID_WIDTH-1:0] m_axi_arid_o,
    output reg [XLEN-1:0] m_axi_araddr_o,
    output reg [7:0] m_axi_arlen_o,
    output [2:0] m_axi_arsize_o,
    output [1:0] m_axi_arburst_o,
    output m_axi_arlock_o,
    output [3:0] m_axi_arcache_o,
    output [2:0] m_axi_arprot_o,
    output [3:0] m_axi_arqos_o,
    output reg m_axi_arvalid_o,
    input m_axi_arready_i,

    // AXI4 read data channel.
    input [ID_WIDTH-1:0] m_axi_rid_i,
    input [63:0] m_axi_rdata_i,
    input [1:0] m_axi_rresp_i,
    input m_axi_rlast_i,
    input m_axi_rvalid_i,
    output reg m_axi_rready_o
);

    localparam [1:0] AXI_OKAY = 2'b00;

    localparam [1:0] W_IDLE = 2'd0;
    localparam [1:0] W_ADDR = 2'd1;
    localparam [1:0] W_DATA = 2'd2;
    localparam [1:0] W_RESP = 2'd3;

    localparam [1:0] R_IDLE = 2'd0;
    localparam [1:0] R_ADDR = 2'd1;
    localparam [1:0] R_DATA = 2'd2;

    reg [1:0] write_state;
    reg [1:0] read_state;

    reg [7:0] write_beats;
    reg [7:0] write_count;
    reg [7:0] read_beats;
    reg [7:0] read_count;
    reg read_error_seen;

    wire [12:0] write_end_offset = {1'b0, wr_addr_i[11:0]} + ({5'd0, wr_beats_i} << 3);
    wire [12:0] read_end_offset = {1'b0, rd_addr_i[11:0]} + ({5'd0, rd_beats_i} << 3);

    assign wr_busy_o = (write_state != W_IDLE);
    assign rd_busy_o = (read_state != R_IDLE);

    assign wr_data_ready_o = (write_state == W_DATA) && m_axi_wready_i;
    assign m_axi_wdata_o = wr_data_i;
    assign m_axi_wstrb_o = wr_strb_i;

    assign rd_valid_o = (read_state == R_DATA) && m_axi_rvalid_i;
    assign rd_data_o = m_axi_rdata_i;
    assign rd_last_o = m_axi_rlast_i;

    assign m_axi_awsize_o = 3'b011;
    assign m_axi_awburst_o = 2'b01;
    assign m_axi_awlock_o = 1'b0;
    assign m_axi_awcache_o = 4'b0011;
    assign m_axi_awprot_o = 3'b000;
    assign m_axi_awqos_o = 4'b0000;

    assign m_axi_arsize_o = 3'b011;
    assign m_axi_arburst_o = 2'b01;
    assign m_axi_arlock_o = 1'b0;
    assign m_axi_arcache_o = 4'b0011;
    assign m_axi_arprot_o = 3'b000;
    assign m_axi_arqos_o = 4'b0000;

    always @* begin
        m_axi_wvalid_o = (write_state == W_DATA) && wr_data_valid_i;
        m_axi_wlast_o = (write_state == W_DATA) && (write_count == write_beats - 1'b1);
        m_axi_bready_o = (write_state == W_RESP);
        m_axi_rready_o = (read_state == R_DATA) && rd_ready_i;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            write_state <= W_IDLE;
            write_beats <= 8'd0;
            write_count <= 8'd0;
            m_axi_awid_o <= {ID_WIDTH{1'b0}};
            m_axi_awaddr_o <= {XLEN{1'b0}};
            m_axi_awlen_o <= 8'd0;
            m_axi_awvalid_o <= 1'b0;
            wr_done_o <= 1'b0;
            wr_error_o <= 1'b0;
        end else begin
            wr_done_o <= 1'b0;
            wr_error_o <= 1'b0;

            case (write_state)
                W_IDLE: begin
                    m_axi_awvalid_o <= 1'b0;
                    if (wr_start_i) begin
                        if ((wr_addr_i[2:0] != 3'b000) ||
                            (wr_beats_i == 0) ||
                            (wr_beats_i > MAX_BURST) ||
                            (write_end_offset > 13'd4096)) begin
                            wr_done_o <= 1'b1;
                            wr_error_o <= 1'b1;
                        end else begin
                            write_beats <= wr_beats_i;
                            write_count <= 8'd0;
                            m_axi_awid_o <= {ID_WIDTH{1'b0}};
                            m_axi_awaddr_o <= wr_addr_i;
                            m_axi_awlen_o <= wr_beats_i - 1'b1;
                            m_axi_awvalid_o <= 1'b1;
                            write_state <= W_ADDR;
                        end
                    end
                end

                W_ADDR: begin
                    if (m_axi_awvalid_o && m_axi_awready_i) begin
                        m_axi_awvalid_o <= 1'b0;
                        write_state <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (m_axi_wvalid_o && m_axi_wready_i) begin
                        write_count <= write_count + 1'b1;
                        if (m_axi_wlast_o)
                            write_state <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (m_axi_bvalid_i && m_axi_bready_o) begin
                        wr_done_o <= 1'b1;
                        if ((m_axi_bresp_i != AXI_OKAY) || (m_axi_bid_i != {ID_WIDTH{1'b0}}))
                            wr_error_o <= 1'b1;
                        write_state <= W_IDLE;
                    end
                end

                default: write_state <= W_IDLE;
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            read_state <= R_IDLE;
            read_beats <= 8'd0;
            read_count <= 8'd0;
            read_error_seen <= 1'b0;
            m_axi_arid_o <= {ID_WIDTH{1'b0}};
            m_axi_araddr_o <= {XLEN{1'b0}};
            m_axi_arlen_o <= 8'd0;
            m_axi_arvalid_o <= 1'b0;
            rd_done_o <= 1'b0;
            rd_error_o <= 1'b0;
        end else begin
            rd_done_o <= 1'b0;
            rd_error_o <= 1'b0;

            case (read_state)
                R_IDLE: begin
                    m_axi_arvalid_o <= 1'b0;
                    if (rd_start_i) begin
                        if ((rd_addr_i[2:0] != 3'b000) ||
                            (rd_beats_i == 0) ||
                            (rd_beats_i > MAX_BURST) ||
                            (read_end_offset > 13'd4096)) begin
                            rd_done_o <= 1'b1;
                            rd_error_o <= 1'b1;
                        end else begin
                            read_beats <= rd_beats_i;
                            read_count <= 8'd0;
                            read_error_seen <= 1'b0;
                            m_axi_arid_o <= {ID_WIDTH{1'b0}};
                            m_axi_araddr_o <= rd_addr_i;
                            m_axi_arlen_o <= rd_beats_i - 1'b1;
                            m_axi_arvalid_o <= 1'b1;
                            read_state <= R_ADDR;
                        end
                    end
                end

                R_ADDR: begin
                    if (m_axi_arvalid_o && m_axi_arready_i) begin
                        m_axi_arvalid_o <= 1'b0;
                        read_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (m_axi_rvalid_i && m_axi_rready_o) begin
                        read_count <= read_count + 1'b1;
                        if ((m_axi_rresp_i != AXI_OKAY) || (m_axi_rid_i != {ID_WIDTH{1'b0}}))
                            read_error_seen <= 1'b1;

                        if (m_axi_rlast_i) begin
                            rd_done_o <= 1'b1;
                            if ((read_count != read_beats - 1'b1) ||
                                (m_axi_rresp_i != AXI_OKAY) ||
                                (m_axi_rid_i != {ID_WIDTH{1'b0}}) || read_error_seen)
                                rd_error_o <= 1'b1;
                            read_state <= R_IDLE;
                        end
                    end
                end

                default: read_state <= R_IDLE;
            endcase
        end
    end

endmodule