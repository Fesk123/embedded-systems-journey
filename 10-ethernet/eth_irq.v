`timescale 1ns/1ps


// Ethernet Interrupt Controller
// Holds VirtIO interrupt status until the guest acknowledges it.
// Bit 0: Used buffer notification
// Bit 1: Configuration change

module eth_irq (
    input clk,
    input rst,
    input [1:0] irq_set_i,
    input [1:0] irq_ack_i,
    output reg [1:0] irq_status_o,
    output irq_o
);

    always @(posedge clk) begin
        if (rst) begin
            irq_status_o <= 2'b00;
        end else begin
            irq_status_o <= (irq_status_o & ~irq_ack_i) | irq_set_i;
        end
    end

    assign irq_o = |irq_status_o;

endmodule