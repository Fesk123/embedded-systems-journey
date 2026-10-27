`timescale 1ns/1ps

// Ethernet VirtIO Network Bridge
// Connects the RV64 Wishbone bus to a VirtIO-MMIO network device.
// The PS backend owns the virtqueue data in shared DDR and uses KV260 GEM0.
// Payload data does not pass through AXI-Lite registers.

module eth_virtio_net #(
    parameter [47:0] MAC_ADDR = 48'h020000000001,
    parameter [31:0] VENDOR_ID = 32'h0000F3E5,
    parameter [31:0] MAX_QUEUE_SIZE = 32'd64
)(
    input clk,
    input rst,

    input [63:0] wb_adr_i,
    input [63:0] wb_dat_i,
    input [7:0]  wb_sel_i,
    input wb_cyc_i,
    input wb_stb_i,
    input wb_we_i,
    output [63:0] wb_dat_o,
    output wb_ack_o,
    output wb_err_o,

    input [31:0] s_axi_awaddr_i,
    input s_axi_awvalid_i,
    output s_axi_awready_o,
    input [31:0] s_axi_wdata_i,
    input [3:0] s_axi_wstrb_i,
    input s_axi_wvalid_i,
    output s_axi_wready_o,
    output [1:0] s_axi_bresp_o,
    output s_axi_bvalid_o,
    input s_axi_bready_i,

    input [31:0] s_axi_araddr_i,
    input s_axi_arvalid_i,
    output s_axi_arready_o,
    output [31:0] s_axi_rdata_o,
    output [1:0] s_axi_rresp_o,
    output s_axi_rvalid_o,
    input s_axi_rready_i,

    output cpu_irq_o,
    output ps_irq_o
);

    wire queue_notify_pulse;
    wire [1:0] queue_notify_sel;

    wire [31:0] queue0_num;
    wire queue0_ready;
    wire [63:0] queue0_desc;
    wire [63:0] queue0_driver;
    wire [63:0] queue0_device;

    wire [31:0] queue1_num;
    wire queue1_ready;
    wire [63:0] queue1_desc;
    wire [63:0] queue1_driver;
    wire [63:0] queue1_device;

    wire [31:0] device_status;
    wire [63:0] driver_features;
    wire [1:0] irq_status;
    wire [1:0] host_irq_set;
    wire device_reset;

    wire tx_pending;
    wire [31:0] tx_kick_count;
    wire tx_ack;
    wire [31:0] tx_ack_count;
    wire rx_pending;
    wire [31:0] rx_kick_count;
    wire rx_ack;
    wire [31:0] rx_ack_count;

    assign device_reset = (device_status == 32'd0);

    eth_virtio_mmio #(
        .MAC_ADDR(MAC_ADDR),
        .VENDOR_ID(VENDOR_ID),
        .MAX_QUEUE_SIZE(MAX_QUEUE_SIZE)
    ) virtio_mmio (
        .clk(clk),
        .rst(rst),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_stb_i(wb_stb_i),
        .wb_we_i(wb_we_i),
        .wb_dat_o(wb_dat_o),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),
        .queue_notify_pulse_o(queue_notify_pulse),
        .queue_notify_sel_o(queue_notify_sel),

        .queue0_num_o(queue0_num),
        .queue0_ready_o(queue0_ready),
        .queue0_desc_o(queue0_desc),
        .queue0_driver_o(queue0_driver),
        .queue0_device_o(queue0_device),
        .queue1_num_o(queue1_num),
        .queue1_ready_o(queue1_ready),
        .queue1_desc_o(queue1_desc),
        .queue1_driver_o(queue1_driver),
        .queue1_device_o(queue1_device),
        .device_status_o(device_status),
        .driver_features_o(driver_features),
        .irq_status_o(irq_status),
        .cpu_irq_o(cpu_irq_o),
        .host_irq_set_i(host_irq_set)
    );

    eth_tx_queue tx_queue (
        .clk(clk),
        .rst(rst),
        .device_reset_i(device_reset),
        .kick_i(queue_notify_pulse && (queue_notify_sel == 2'd0)),
        .host_ack_i(tx_ack),
        .host_ack_count_i(tx_ack_count),
        .pending_o(tx_pending),
        .kick_count_o(tx_kick_count)
    );

    eth_rx_queue rx_queue (
        .clk(clk),
        .rst(rst),
        .device_reset_i(device_reset),
        .kick_i(queue_notify_pulse && (queue_notify_sel == 2'd1)),
        .host_ack_i(rx_ack),
        .host_ack_count_i(rx_ack_count),
        .pending_o(rx_pending),
        .kick_count_o(rx_kick_count)
    );

    eth_ps_bridge ps_bridge (
        .clk(clk),
        .rst(rst),
        .s_axi_awaddr_i(s_axi_awaddr_i),
        .s_axi_awvalid_i(s_axi_awvalid_i),
        .s_axi_awready_o(s_axi_awready_o),
        .s_axi_wdata_i(s_axi_wdata_i),
        .s_axi_wstrb_i(s_axi_wstrb_i),
        .s_axi_wvalid_i(s_axi_wvalid_i),
        .s_axi_wready_o(s_axi_wready_o),
        .s_axi_bresp_o(s_axi_bresp_o),
        .s_axi_bvalid_o(s_axi_bvalid_o),
        .s_axi_bready_i(s_axi_bready_i),
        .s_axi_araddr_i(s_axi_araddr_i),
        .s_axi_arvalid_i(s_axi_arvalid_i),
        .s_axi_arready_o(s_axi_arready_o),
        .s_axi_rdata_o(s_axi_rdata_o),
        .s_axi_rresp_o(s_axi_rresp_o),
        .s_axi_rvalid_o(s_axi_rvalid_o),
        .s_axi_rready_i(s_axi_rready_i),

        .tx_pending_i(tx_pending),
        .tx_kick_count_i(tx_kick_count),
        .tx_ack_o(tx_ack),
        .tx_ack_count_o(tx_ack_count),
        .rx_pending_i(rx_pending),
        .rx_kick_count_i(rx_kick_count),
        .rx_ack_o(rx_ack),
        .rx_ack_count_o(rx_ack_count),
        .host_irq_set_o(host_irq_set),
        .ps_irq_o(ps_irq_o),
        .device_status_i(device_status),
        .driver_features_i(driver_features),
        .queue0_num_i(queue0_num),
        .queue0_ready_i(queue0_ready),
        .queue0_desc_i(queue0_desc),
        .queue0_driver_i(queue0_driver),
        .queue0_device_i(queue0_device),
        .queue1_num_i(queue1_num),
        .queue1_ready_i(queue1_ready),
        .queue1_desc_i(queue1_desc),
        .queue1_driver_i(queue1_driver),
        .queue1_device_i(queue1_device),
        .irq_status_i(irq_status)
    );

endmodule