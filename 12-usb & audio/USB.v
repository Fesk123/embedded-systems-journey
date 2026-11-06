`timescale 1ns/1ps

// USB bridge for the RV64GC SoC and KV260 PS USB host controller.

// The KV260 USB connectors are connected to the PS USB controller.
// PS software must provide HID events and consume the PCM audio stream.
// This module does not implement the USB protocol, xHCI, or USB PHY.

// Wishbone: 32-bit address, 64-bit data, 8 byte enables.
// PS stream interface and Wishbone interface must use the same clock.
// Add an asynchronous FIFO or clock converter if the clocks differ.

module USB(
    input wire clk,
    input wire rst,

    // Wishbone interface
    input wire [31:0] wb_adr_i,
    input wire [63:0] wb_dat_i,
    output reg [63:0] wb_dat_o,
    input wire [7:0] wb_sel_i,
    input wire wb_we_i,
    input wire wb_cyc_i,
    input wire wb_stb_i,
    output reg wb_ack_o,

    // PS HID event stream
    input wire ps_hid_valid_i,
    input wire [31:0] ps_hid_data_i,
    output wire ps_hid_ready_o,
    input wire ps_hid_connected_i,

    // PS USB Audio OUT stream
    output wire ps_audio_valid_o,
    output wire [31:0] ps_audio_data_o,
    input wire ps_audio_ready_i,
    input wire ps_audio_connected_i,

    output wire irq_o
);

    localparam REG_STATUS = 8'h00;
    localparam REG_CONTROL = 8'h08;
    localparam REG_HID_DATA = 8'h10;
    localparam REG_AUDIO_DATA = 8'h18;
    localparam REG_IRQ_STATUS = 8'h20;
    localparam REG_IRQ_ENABLE = 8'h28;
    localparam REG_FIFO_STATUS = 8'h30;

    wire [7:0] address;
    assign address = wb_adr_i[7:0];

    // Control registers
    wire [63:0] control_read_data;
    wire [31:0] control;
    wire [31:0] interrupt_enable;
    wire [31:0] interrupt_status;
    wire control_write;

    // HID FIFO
    wire [31:0] hid_data;
    wire hid_valid;
    wire [8:0] hid_count;
    wire hid_read;
    wire hid_ready;

    // Audio FIFO
    wire audio_full;
    wire audio_almost_full;
    wire [10:0] audio_count;
    wire audio_write;

    wire audio_write_wait;
    wire wb_accept;

    assign audio_write_wait = wb_we_i && (address == REG_AUDIO_DATA) && control[1] && audio_full;

    // One acknowledge pulse per Wishbone request.
    // The master must lower STB or CYC before issuing the next request.
    assign wb_accept = wb_cyc_i && wb_stb_i && !wb_ack_o && !audio_write_wait;

    assign ps_hid_ready_o = control[0] && hid_ready;

    assign hid_read = wb_accept && !wb_we_i && (address == REG_HID_DATA) && hid_valid;

    usb_hid_fifo #(
        .DEPTH(256)
    ) hid_buffer (
        .clk(clk),
        .rst(rst),

        .ps_valid_i(ps_hid_valid_i && control[0]),
        .ps_data_i(ps_hid_data_i),
        .ps_ready_o(hid_ready),

        .cpu_read_i(hid_read),
        .cpu_data_o(hid_data),
        .cpu_valid_o(hid_valid),

        .count_o(hid_count)
    );

    assign audio_write = wb_accept && wb_we_i && (address == REG_AUDIO_DATA) && control[1] && (wb_sel_i[3:0] == 4'hf);

    usb_audio_fifo #(
        .DEPTH(1024)
    ) audio_buffer (
        .clk(clk),
        .rst(rst),

        .cpu_write_i(audio_write),
        .cpu_data_i(wb_dat_i[31:0]),
        .full_o(audio_full),

        .ps_ready_i(ps_audio_ready_i && ps_audio_connected_i),
        .ps_valid_o(ps_audio_valid_o),
        .ps_data_o(ps_audio_data_o),

        .almost_full_o(audio_almost_full),
        .count_o(audio_count)
    );

    assign control_write =wb_accept && wb_we_i && ((address == REG_CONTROL) || (address == REG_IRQ_STATUS) || (address == REG_IRQ_ENABLE));

    usb_control_regs control_registers (
        .clk(clk),
        .rst(rst),

        .write_i(control_write),
        .address_i(address),
        .write_data_i(wb_dat_i),
        .byte_enable_i(wb_sel_i),

        .hid_event_i(hid_valid),
        .audio_almost_full_i(audio_almost_full),

        .read_data_o(control_read_data),

        .control_o(control),
        .interrupt_enable_o(interrupt_enable),
        .interrupt_status_o(interrupt_status),

        .irq_o(irq_o)
    );

    always @(posedge clk) begin
        if (rst) begin
            
            wb_ack_o <= 1'b0;
            wb_dat_o <= 64'd0;
        end else begin
            wb_ack_o <= 1'b0;

            if (wb_accept) begin
                wb_ack_o <= 1'b1;

                if (!wb_we_i) begin

                    case (address)


                        REG_STATUS: begin

                            wb_dat_o <= {

                                56'd0,
                                ps_audio_connected_i,
                                ps_hid_connected_i,
                                audio_almost_full,

                                audio_full,
                                ps_audio_valid_o,
                                hid_valid,
                                control[1],
                                control[0]
                            };
                        end

                        REG_CONTROL,
                        REG_IRQ_STATUS,

                        REG_IRQ_ENABLE: begin
                            wb_dat_o <= control_read_data;
                        end

                        REG_HID_DATA: begin
                            if (hid_valid)
                                wb_dat_o <= {32'd0, hid_data};
                            else
                                wb_dat_o <= 64'd0;
                        end

                        REG_AUDIO_DATA: begin
                            wb_dat_o <= 64'd0;
                        end

                        REG_FIFO_STATUS: begin
                            wb_dat_o <= {
                                32'd0,
                                11'd0,
                                audio_count,
                                1'd0,
                                hid_count
                            };
                        end

                        default: begin
                            wb_dat_o <= 64'd0;
                        end
                    endcase
                end


            end

        end

    end

endmodule