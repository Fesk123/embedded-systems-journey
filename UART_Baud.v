module Baud_Generator #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input clk,
    input reset,
    output reg baud_tick
);

    // number of clock cycles in one UART bit period
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 50 000 000 / 115 200 ≈ 434 CLKS_PER_BIT

    reg [15:0] counter; // counts clock cycles until next baud tick

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter  <= 0;
            baud_tick <= 0;
        end
        else begin
            if (counter == CLKS_PER_BIT - 1) begin
                counter  <= 0;
                baud_tick <= 1;
            end
            else begin
                counter  <= counter + 1;
                baud_tick <= 0;
            end
        end
    end

endmodule