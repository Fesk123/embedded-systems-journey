`timescale 1ns/1ps


// Ethernet PS Bridge
// AXI4-Lite register interface from the KV260 Processing System.
// Packet payloads and VirtIO split rings remain in shared DDR.
// This bridge exposes queue addresses and coalesces queue notifications.

module eth_ps_bridge (
    input clk,
    input rst,

    input [31:0] s_axi_awaddr_i,
    input s_axi_awvalid_i,
    output s_axi_awready_o,
    input [31:0] s_axi_wdata_i,
    input [3:0] s_axi_wstrb_i,
    input s_axi_wvalid_i,
    output s_axi_wready_o,
    output reg [1:0] s_axi_bresp_o,
    output reg s_axi_bvalid_o,
    input s_axi_bready_i,

    input [31:0] s_axi_araddr_i,
    input s_axi_arvalid_i,
    output s_axi_arready_o,
    output reg [31:0] s_axi_rdata_o,
    output reg [1:0] s_axi_rresp_o,
    output reg s_axi_rvalid_o,
    input s_axi_rready_i,

    input tx_pending_i,
    input [31:0] tx_kick_count_i,
    output reg tx_ack_o,
    output reg [31:0] tx_ack_count_o,
    input rx_pending_i,
    input [31:0] rx_kick_count_i,
    output reg rx_ack_o,
    output reg [31:0] rx_ack_count_o,
    output reg [1:0] host_irq_set_o,
    output ps_irq_o,

    input [31:0] device_status_i,
    input [63:0] driver_features_i,
    input [31:0] queue0_num_i,
    input queue0_ready_i,
    input [63:0] queue0_desc_i,
    input [63:0] queue0_driver_i,
    input [63:0] queue0_device_i,
    input [31:0] queue1_num_i,
    input queue1_ready_i,
    input [63:0] queue1_desc_i,
    input [63:0] queue1_driver_i,
    input [63:0] queue1_device_i,
    input [1:0] irq_status_i
);

    reg aw_pending;
    reg [31:0] awaddr_reg;
    reg w_pending;
    reg [31:0] wdata_reg;
    reg [3:0] wstrb_reg;

    wire aw_handshake = s_axi_awvalid_i && s_axi_awready_o;
    wire w_handshake  = s_axi_wvalid_i && s_axi_wready_o;
    wire write_commit = !s_axi_bvalid_o && (aw_pending || aw_handshake) && (w_pending || w_handshake);
    wire [31:0] write_addr = aw_pending ? awaddr_reg : s_axi_awaddr_i;
    wire [31:0] write_data = w_pending ? wdata_reg : s_axi_wdata_i;
    wire [3:0] write_strb = w_pending ? wstrb_reg : s_axi_wstrb_i;

    reg [31:0] read_data;

    assign s_axi_awready_o = !aw_pending && !s_axi_bvalid_o;
    assign s_axi_wready_o  = !w_pending && !s_axi_bvalid_o;
    assign s_axi_arready_o = !s_axi_rvalid_o;
    assign ps_irq_o = tx_pending_i | rx_pending_i;

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] byte_select;
        integer i;
        begin
            merge_bytes = old_value;
            for (i = 0; i < 4; i = i + 1) begin
                if (byte_select[i])
                    merge_bytes[i*8 +: 8] = new_value[i*8 +: 8];
            end
        end
    endfunction

    always @* begin
        read_data = 32'd0;
        case (s_axi_araddr_i[11:0])
            12'h000: read_data = 32'h45544831;
            12'h004: read_data = {24'd0, device_status_i[7:0]};
            12'h008: read_data = {31'd0, tx_pending_i};
            12'h010: read_data = {31'd0, rx_pending_i};
            12'h020: read_data = tx_kick_count_i;
            12'h024: read_data = rx_kick_count_i;
            12'h028: read_data = queue0_num_i;
            12'h02C: read_data = {31'd0, queue0_ready_i};
            12'h030: read_data = queue0_desc_i[31:0];
            12'h034: read_data = queue0_desc_i[63:32];
            12'h038: read_data = queue0_driver_i[31:0];
            12'h03C: read_data = queue0_driver_i[63:32];
            12'h040: read_data = queue0_device_i[31:0];
            12'h044: read_data = queue0_device_i[63:32];
            12'h048: read_data = queue1_num_i;
            12'h04C: read_data = {31'd0, queue1_ready_i};
            12'h050: read_data = queue1_desc_i[31:0];
            12'h054: read_data = queue1_desc_i[63:32];
            12'h058: read_data = queue1_driver_i[31:0];
            12'h05C: read_data = queue1_driver_i[63:32];
            12'h060: read_data = queue1_device_i[31:0];
            12'h064: read_data = queue1_device_i[63:32];
            12'h068: read_data = driver_features_i[31:0];
            12'h06C: read_data = driver_features_i[63:32];
            12'h070: read_data = {30'd0, irq_status_i};
            default: read_data = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            aw_pending <= 1'b0;
            awaddr_reg <= 32'd0;
            w_pending <= 1'b0;
            wdata_reg <= 32'd0;
            wstrb_reg <= 4'd0;
            s_axi_bresp_o <= 2'b00;
            s_axi_bvalid_o <= 1'b0;
            s_axi_rdata_o <= 32'd0;
            s_axi_rresp_o <= 2'b00;
            s_axi_rvalid_o <= 1'b0;
            tx_ack_o <= 1'b0;
            tx_ack_count_o <= 32'd0;
            rx_ack_o <= 1'b0;
            rx_ack_count_o <= 32'd0;
            host_irq_set_o <= 2'b00;
        end else begin
            tx_ack_o <= 1'b0;
            rx_ack_o <= 1'b0;
            host_irq_set_o <= 2'b00;

            if (aw_handshake) begin
                aw_pending <= 1'b1;
                awaddr_reg <= s_axi_awaddr_i;
            end

            if (w_handshake) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axi_wdata_i;
                wstrb_reg <= s_axi_wstrb_i;
            end

            if (write_commit) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_bvalid_o <= 1'b1;
                s_axi_bresp_o <= 2'b00;

                case (write_addr[11:0])
                    12'h00C: begin
                        if (|write_strb) begin
                            tx_ack_o <= 1'b1;
                            tx_ack_count_o <= merge_bytes(tx_ack_count_o, write_data, write_strb);
                        end
                    end
                    12'h014: begin
                        if (|write_strb) begin
                            rx_ack_o <= 1'b1;
                            rx_ack_count_o <= merge_bytes(rx_ack_count_o, write_data, write_strb);
                        end
                    end
                    12'h018: host_irq_set_o <= write_data[1:0] & {write_strb[0], write_strb[0]};
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid_o && s_axi_bready_i) begin
                s_axi_bvalid_o <= 1'b0;
            end

            if (s_axi_arvalid_i && s_axi_arready_o) begin
                s_axi_rdata_o <= read_data;
                s_axi_rresp_o <= 2'b00;
                s_axi_rvalid_o <= 1'b1;
            end else if (s_axi_rvalid_o && s_axi_rready_i) begin
                s_axi_rvalid_o <= 1'b0;
            end
        end
    end

endmodule