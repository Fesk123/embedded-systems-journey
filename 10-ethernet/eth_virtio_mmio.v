`timescale 1ns/1ps

// VirtIO MMIO Network Device

// Implements the guest-facing VirtIO MMIO register interface.
// Packet queues and packet buffers are stored in shared DDR.
// The PS backend processes the split virtqueues and uses GEM0 for Ethernet.
//
// The Wishbone data path is 64 bits wide. VirtIO MMIO registers are 32 bits.
// wb_adr_i[2] selects the lower or upper 32-bit lane.

module eth_virtio_mmio #(
    parameter [47:0] MAC_ADDR = 48'h020000000001,
    parameter [31:0] VENDOR_ID = 32'h0000F3E5,
    parameter [31:0] MAX_QUEUE_SIZE = 32'd64
)(
    input clk,
    input rst,

    input [63:0] wb_adr_i,
    input [63:0] wb_dat_i,
    input [7:0] wb_sel_i,
    input wb_cyc_i,
    input wb_stb_i,
    input wb_we_i,
    output reg [63:0] wb_dat_o,
    output reg wb_ack_o,
    output reg wb_err_o,

    output reg queue_notify_pulse_o,
    output reg [1:0] queue_notify_sel_o,

    output [31:0] queue0_num_o,
    output queue0_ready_o,
    output [63:0] queue0_desc_o,
    output [63:0] queue0_driver_o,
    output [63:0] queue0_device_o,

    output [31:0] queue1_num_o,
    output queue1_ready_o,
    output [63:0] queue1_desc_o,
    output [63:0] queue1_driver_o,
    output [63:0] queue1_device_o,

    output [31:0] device_status_o,
    output [63:0] driver_features_o,
    output [1:0] irq_status_o,
    output cpu_irq_o,
    input [1:0] host_irq_set_i
);

    localparam [31:0] VIRTIO_MAGIC = 32'h74726976;
    localparam [31:0] VIRTIO_VERSION = 32'd2;
    localparam [31:0] VIRTIO_DEVICE_ID = 32'd1;
    localparam [31:0] MAX_QUEUE_SIZE_CONST = MAX_QUEUE_SIZE;

    reg [31:0] device_features_sel;
    reg [31:0] driver_features_sel;
    reg [31:0] queue_sel;
    reg [31:0] device_status;
    reg [31:0] driver_features_low;
    reg [31:0] driver_features_high;
    reg [31:0] queue_num [0:1];
    reg queue_ready [0:1];
    reg [63:0] queue_desc [0:1];
    reg [63:0] queue_driver [0:1];
    reg [63:0] queue_device [0:1];
    reg wb_seen;
    reg [1:0] irq_ack;
    reg [31:0] read_data;
    reg [31:0] write_data;
    reg [3:0] write_sel;
    reg [31:0] merged_data;
    wire [1:0] irq_set;
    wire feature_set_valid;

    assign queue0_num_o = queue_num[0];
    assign queue0_ready_o = queue_ready[0];
    assign queue0_desc_o = queue_desc[0];
    assign queue0_driver_o = queue_driver[0];
    assign queue0_device_o = queue_device[0];

    assign queue1_num_o = queue_num[1];
    assign queue1_ready_o = queue_ready[1];
    assign queue1_desc_o = queue_desc[1];
    assign queue1_driver_o = queue_driver[1];
    assign queue1_device_o = queue_device[1];

    assign device_status_o = device_status;
    assign driver_features_o = {driver_features_high, driver_features_low};
    assign irq_set = host_irq_set_i;

    assign feature_set_valid = (driver_features_low  & ~32'h00000020) == 32'd0 && (driver_features_high & ~32'h00000001) == 32'd0 && driver_features_high[0];

    function [31:0] merge_bytes;

        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] byte_select;
        integer i;

        begin
            merge_bytes = old_value;
            for (i = 0; i < 4; i = i + 1) begin
                if (byte_select[i]) begin
                    merge_bytes[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end

        end

    endfunction

    function queue_size_valid;
        input [31:0] size;
        begin
            queue_size_valid = (size != 0) && (size <= MAX_QUEUE_SIZE_CONST) && ((size & (size - 1'b1)) == 0);
        end
    endfunction

    always @* begin
        if (wb_adr_i[2]) begin
            write_data = wb_dat_i[63:32];
            write_sel = wb_sel_i[7:4];
        end else begin
            write_data = wb_dat_i[31:0];
            write_sel = wb_sel_i[3:0];
        end

        read_data = 32'd0;

        case (wb_adr_i[9:2])
            8'h00: read_data = VIRTIO_MAGIC;
            8'h01: read_data = VIRTIO_VERSION;
            8'h02: read_data = VIRTIO_DEVICE_ID;
            8'h03: read_data = VENDOR_ID;
            8'h04: begin
                if (device_features_sel == 0)
                    read_data = 32'h00000020;
                else if (device_features_sel == 1)
                    read_data = 32'h00000001;
                else
                    read_data = 32'd0;
            end
            8'h05: read_data = device_features_sel;
            8'h08: read_data = driver_features_sel == 0 ? driver_features_low : driver_features_high;
            8'h09: read_data = driver_features_sel;
            8'h0C: read_data = queue_sel;
            8'h0D: read_data = (queue_sel < 2) ? MAX_QUEUE_SIZE_CONST : 32'd0;
            8'h0E: read_data = (queue_sel < 2) ? queue_num[queue_sel[0]] : 32'd0;
            8'h11: read_data = (queue_sel < 2) ? {31'd0, queue_ready[queue_sel[0]]} : 32'd0;
            8'h14: read_data = 32'd0;
            8'h18: read_data = {30'd0, irq_status_o};
            8'h19: read_data = 32'd0;
            8'h1C: read_data = device_status;
            8'h20: read_data = (queue_sel < 2) ? queue_desc[queue_sel[0]][31:0] : 32'd0;
            8'h21: read_data = (queue_sel < 2) ? queue_desc[queue_sel[0]][63:32] : 32'd0;
            8'h24: read_data = (queue_sel < 2) ? queue_driver[queue_sel[0]][31:0] : 32'd0;
            8'h25: read_data = (queue_sel < 2) ? queue_driver[queue_sel[0]][63:32] : 32'd0;
            8'h28: read_data = (queue_sel < 2) ? queue_device[queue_sel[0]][31:0] : 32'd0;
            8'h29: read_data = (queue_sel < 2) ? queue_device[queue_sel[0]][63:32] : 32'd0;
            8'h3F: read_data = 32'd0;
            8'h40: read_data = {MAC_ADDR[23:16], MAC_ADDR[31:24], MAC_ADDR[39:32], MAC_ADDR[47:40]};
            8'h41: read_data = {16'd0, MAC_ADDR[7:0], MAC_ADDR[15:8]};
            default: read_data = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            device_features_sel <= 32'd0;
            driver_features_sel <= 32'd0;
            queue_sel <= 32'd0;
            device_status <= 32'd0;
            driver_features_low <= 32'd0;
            driver_features_high <= 32'd0;
            queue_num[0] <= 32'd0;
            queue_num[1] <= 32'd0;
            queue_ready[0] <= 1'b0;
            queue_ready[1] <= 1'b0;
            queue_desc[0] <= 64'd0;
            queue_desc[1] <= 64'd0;
            queue_driver[0] <= 64'd0;
            queue_driver[1] <= 64'd0;
            queue_device[0] <= 64'd0;
            queue_device[1] <= 64'd0;
            wb_seen <= 1'b0;
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            wb_dat_o <= 64'd0;
            queue_notify_pulse_o <= 1'b0;
            queue_notify_sel_o <= 2'd0;
            irq_ack <= 2'b00;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            queue_notify_pulse_o <= 1'b0;
            irq_ack <= 2'b00;

            if (!(wb_cyc_i && wb_stb_i)) begin
                wb_seen <= 1'b0;
            end else if (!wb_seen) begin
                wb_seen <= 1'b1;
                wb_ack_o <= 1'b1;

                if (!wb_we_i) begin
                    if (wb_adr_i[2])
                        wb_dat_o <= {read_data, 32'd0};
                    else
                        wb_dat_o <= {32'd0, read_data};
                end else begin
                    merged_data = write_data;
                    case (wb_adr_i[9:2])
                        8'h05: device_features_sel <= merge_bytes(device_features_sel, write_data, write_sel);
                        8'h09: driver_features_sel <= merge_bytes(driver_features_sel, write_data, write_sel);
                        8'h08: begin
                            if (driver_features_sel == 0)
                                driver_features_low <= merge_bytes(driver_features_low, write_data, write_sel);
                            else if (driver_features_sel == 1)
                                driver_features_high <= merge_bytes(driver_features_high, write_data, write_sel);
                        end
                        8'h0C: queue_sel <= merge_bytes(queue_sel, write_data, write_sel);
                        8'h0E: begin
                            if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) begin
                                merged_data = merge_bytes(queue_num[queue_sel[0]], write_data, write_sel);
                                if (queue_size_valid(merged_data))
                                    queue_num[queue_sel[0]] <= merged_data;
                            end
                        end
                        8'h11: begin
                            if (queue_sel < 2) begin
                                if (write_data[0] && queue_size_valid(queue_num[queue_sel[0]]))
                                    queue_ready[queue_sel[0]] <= 1'b1;
                                else if (!write_data[0])
                                    queue_ready[queue_sel[0]] <= 1'b0;
                            end
                        end
                        8'h14: begin
                            if (write_data < 2) begin
                                if (write_data == 0 && queue_ready[0]) begin
                                    queue_notify_pulse_o <= 1'b1;
                                    queue_notify_sel_o <= 2'd0;
                                end else if (write_data == 1 && queue_ready[1]) begin
                                    queue_notify_pulse_o <= 1'b1;
                                    queue_notify_sel_o <= 2'd1;
                                end
                            end
                        end
                        8'h19: irq_ack <= write_data[1:0];
                        8'h20: if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) queue_desc[queue_sel[0]][31:0] <= merge_bytes(queue_desc[queue_sel[0]][31:0], write_data, write_sel);
                        8'h21: if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) queue_desc[queue_sel[0]][63:32] <= merge_bytes(queue_desc[queue_sel[0]][63:32], write_data, write_sel);
                        8'h24: if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) queue_driver[queue_sel[0]][31:0] <= merge_bytes(queue_driver[queue_sel[0]][31:0], write_data, write_sel);
                        8'h25: if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) queue_driver[queue_sel[0]][63:32] <= merge_bytes(queue_driver[queue_sel[0]][63:32], write_data, write_sel);
                        8'h28: if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) queue_device[queue_sel[0]][31:0] <= merge_bytes(queue_device[queue_sel[0]][31:0], write_data, write_sel);
                        8'h29: if ((queue_sel < 2) && !queue_ready[queue_sel[0]]) queue_device[queue_sel[0]][63:32] <= merge_bytes(queue_device[queue_sel[0]][63:32], write_data, write_sel);
                        8'h1C: begin
                            if (write_data == 0) begin
                                device_status <= 32'd0;
                                driver_features_low <= 32'd0;
                                driver_features_high <= 32'd0;
                                queue_num[0] <= 32'd0;
                                queue_num[1] <= 32'd0;
                                queue_ready[0] <= 1'b0;
                                queue_ready[1] <= 1'b0;
                                queue_desc[0] <= 64'd0;
                                queue_desc[1] <= 64'd0;
                                queue_driver[0] <= 64'd0;
                                queue_driver[1] <= 64'd0;
                                queue_device[0] <= 64'd0;
                                queue_device[1] <= 64'd0;
                            end else if (write_data[3] && !feature_set_valid) begin
                                device_status <= write_data & ~32'h00000008;
                            end else begin
                                device_status <= write_data;
                            end
                        end
                        default: begin
                        end
                    endcase
                end
            end
        end
    end

    eth_irq irq_controller (
        .clk(clk),
        .rst(rst || (device_status == 32'd0)),
        .irq_set_i(irq_set),
        .irq_ack_i(irq_ack),
        .irq_status_o(irq_status_o),
        .irq_o(cpu_irq_o)
    );

endmodule