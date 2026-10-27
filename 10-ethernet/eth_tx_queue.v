`timescale 1ns/1ps


// Ethernet Transmit Queue Notification
// The PS backend owns the VirtIO descriptor ring in shared DDR.
// Notifications are coalesced, but the counter prevents a new kick from
// being lost while the PS backend is processing an older notification.
// The host acknowledges the counter value that it has finished processing.

module eth_tx_queue (
    input clk,
    input rst,
    input device_reset_i,
    input kick_i,
    input host_ack_i,
    input [31:0] host_ack_count_i,
    output pending_o,
    output reg [31:0] kick_count_o
);

    reg [31:0] ack_count;

    assign pending_o = (kick_count_o != ack_count);

    always @(posedge clk) begin
        if (rst || device_reset_i) begin
            ack_count <= 32'd0;
            kick_count_o <= 32'd0;
        end else begin
            if (kick_i)
                kick_count_o <= kick_count_o + 1'b1;

            if (host_ack_i)
                ack_count <= host_ack_count_i;
        end
    end

endmodule