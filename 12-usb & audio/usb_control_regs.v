`timescale 1ns/1ps

// USB control and interrupt registers.

module usb_control_regs(
    input wire clk,
    input wire rst,

    input wire write_i,
    input wire [7:0] address_i,
    input wire [63:0] write_data_i,
    input wire [7:0] byte_enable_i,

    input wire hid_event_i,
    input wire audio_almost_full_i,

    output reg [63:0] read_data_o,

    output reg [31:0] control_o,
    output reg [31:0] interrupt_enable_o,
    output reg [31:0] interrupt_status_o,

    output wire irq_o
);

    localparam REG_CONTROL = 8'h08;
    localparam REG_IRQ_STATUS = 8'h20;
    localparam REG_IRQ_ENABLE = 8'h28;

    assign irq_o = |(interrupt_status_o & interrupt_enable_o);

    always @(*) begin
        read_data_o = 64'd0;

        case (address_i)

            REG_CONTROL:
                read_data_o = {32'd0, control_o};

            REG_IRQ_STATUS:
                read_data_o = {32'd0, interrupt_status_o};

            REG_IRQ_ENABLE:
                read_data_o = {32'd0, interrupt_enable_o};

            default:
                read_data_o = 64'd0;
        endcase

    end

    always @(posedge clk) begin

        if (rst) begin
            control_o <= 32'd0;
            interrupt_enable_o <= 32'd0;
            interrupt_status_o <= 32'd0;

        end else begin
            if (write_i) begin

                case (address_i)

                    REG_CONTROL: begin
                        if (byte_enable_i[0])
                            control_o[7:0] <= write_data_i[7:0];
                        if (byte_enable_i[1])
                            control_o[15:8] <= write_data_i[15:8];
                        if (byte_enable_i[2])
                            control_o[23:16] <= write_data_i[23:16];
                        if (byte_enable_i[3])
                            control_o[31:24] <= write_data_i[31:24];
                    end

                    // Write one to clear.
                    REG_IRQ_STATUS: begin
                        if (byte_enable_i[0])
                            interrupt_status_o[7:0] <= interrupt_status_o[7:0] & ~write_data_i[7:0];
                        if (byte_enable_i[1])
                            interrupt_status_o[15:8] <= interrupt_status_o[15:8] & ~write_data_i[15:8];
                        if (byte_enable_i[2])
                            interrupt_status_o[23:16] <= interrupt_status_o[23:16] & ~write_data_i[23:16];
                        if (byte_enable_i[3])
                            interrupt_status_o[31:24] <= interrupt_status_o[31:24] & ~write_data_i[31:24];
                    end

                    REG_IRQ_ENABLE: begin
                        if (byte_enable_i[0])
                            interrupt_enable_o[7:0] <= write_data_i[7:0];
                        if (byte_enable_i[1])
                            interrupt_enable_o[15:8] <= write_data_i[15:8];
                        if (byte_enable_i[2])
                            interrupt_enable_o[23:16] <= write_data_i[23:16];
                        if (byte_enable_i[3])
                            interrupt_enable_o[31:24] <= write_data_i[31:24];
                    end

                    default: begin
                    end
                endcase
            end

            // New events take priority over a simultaneous clear.
            if (hid_event_i)
                interrupt_status_o[0] <= 1'b1;

            if (audio_almost_full_i)
                interrupt_status_o[1] <= 1'b1;
        end
    end

endmodule