`timescale 1ns/1ps
// SYSTEM CONTROL & WATCHDOG
// Memory-mapped, programmable watchdog timer.
//
// Register map (64-bit aligned Wishbone accesses):
// +0x00 TIMEOUT_LOAD - reload value in clock cycles
// +0x08 CONTROL      - bit 0 enable, bit 1 IRQ enable, bit 2 reset enable
// +0x10 COUNT        - current down-counter (read-only)
// +0x18 FEED         - any write reloads the down-counter
// +0x20 STATUS       - bit 0 expired, write 1 to clear
//
// The watchdog only requests a system reset. The SoC reset tree must route SYSTEM_RESET_O through reset synchronizers for every clock domain.
// Keep this watchdog in an always-on/reset-supervisor domain: do not feed SYSTEM_RESET_O back into this module's RST_I, or its reset counter clears.
// WB_ADR_I is expected to be a region-relative address from the interconnect.
module Watchdog_Timer #(
    parameter [63:0] DEFAULT_TIMEOUT = 64'd1000000,
    parameter integer RESET_PULSE_CYCLES = 16
)(
    input wire CLK_I,
    input wire RST_I,

    // 64-bit Wishbone slave interface.
    input wire [63:0] WB_ADR_I,
    input wire [63:0] WB_DAT_I,
    output reg [63:0] WB_DAT_O,
    input wire [7:0] WB_SEL_I,
    input wire WB_CYC_I,
    input wire WB_STB_I,
    input wire WB_WE_I,
    output reg WB_ACK_O,
    output reg WB_ERR_O,

    output wire IRQ_O,
    output wire SYSTEM_RESET_O,
    output wire TIMEOUT_O,
    output wire [63:0] DEBUG_COUNT_O
);

    localparam [63:0] SAFE_DEFAULT_TIMEOUT = (DEFAULT_TIMEOUT == 64'd0) ? 64'd1 : DEFAULT_TIMEOUT;
    localparam [31:0] SAFE_RESET_PULSE_CYCLES = (RESET_PULSE_CYCLES < 1) ? 32'd1 : RESET_PULSE_CYCLES;

    reg [63:0] timeout_load;
    reg [63:0] timeout_count;
    reg watchdog_enable;
    reg interrupt_enable;
    reg reset_enable;
    reg expired;
    reg [31:0] reset_count;

    reg accepted_transfer;
    reg response_guard;
    reg [63:0] last_accepted_address;

    reg [63:0] write_value;

    assign IRQ_O = expired && interrupt_enable;
    assign SYSTEM_RESET_O = (reset_count != 0);
    assign TIMEOUT_O = expired;
    assign DEBUG_COUNT_O = timeout_count;

    function [63:0] merge_bytes;

        input [63:0] old_value;
        input [63:0] new_value;
        input [7:0] byte_select;
        integer lane;
    
        begin
            merge_bytes = old_value;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if (byte_select[lane])
                    merge_bytes[lane*8 +: 8] = new_value[lane*8 +: 8];
            end
        end
    
    endfunction

    always @(posedge CLK_I or posedge RST_I) begin
    
        if (RST_I) begin
            timeout_load <= SAFE_DEFAULT_TIMEOUT;
            timeout_count <= SAFE_DEFAULT_TIMEOUT;
            watchdog_enable <= 1'b0;
            interrupt_enable <= 1'b0;
            reset_enable <= 1'b0;
            expired <= 1'b0;
            reset_count <= 32'd0;
    
            WB_DAT_O <= 64'd0;
            WB_ACK_O <= 1'b0;
            WB_ERR_O <= 1'b0;
            accepted_transfer <= 1'b0;
            response_guard <= 1'b0;
            last_accepted_address <= 64'd0;
    
        end
        else begin
    
            WB_ACK_O <= 1'b0;
            WB_ERR_O <= 1'b0;

            if (reset_count != 0)
                reset_count <= reset_count - 1'b1;

            // Watchdog countdown. A timeout is sticky until software clears STATUS, but the timer reloads to avoid continuous reset/interrupt pulses on every subsequent clock.
            if (watchdog_enable && (timeout_count != 0)) begin
                
                if (timeout_count == 64'd1) begin
                    timeout_count <= timeout_load;
                    watchdog_enable <= 1'b0;
                    expired <= 1'b1;
                
                    if (reset_enable)
                        reset_count <= SAFE_RESET_PULSE_CYCLES;
                end
                
                else
                    timeout_count <= timeout_count - 64'd1;
            
            end


            if (!(WB_CYC_I && WB_STB_I)) begin
                accepted_transfer <= 1'b0;
                response_guard <= 1'b0;
            end
            
            else if (response_guard) begin
                // Wait one clock after the registered ACK/ERR so that the master can present its next transfer, including a repeated access to the same register address.
                response_guard <= 1'b0;
                accepted_transfer <= 1'b0;
            end

            if (WB_CYC_I && WB_STB_I && !response_guard && (!accepted_transfer || (WB_ADR_I != last_accepted_address))) begin
                
                accepted_transfer <= 1'b1;
                response_guard <= 1'b1;
                last_accepted_address <= WB_ADR_I;

                if ((WB_ADR_I[63:8] != 56'd0) || (WB_ADR_I[2:0] != 3'b000)) begin
                    WB_ERR_O <= 1'b1;
                end
                
                else if (WB_WE_I) begin
                
                    case (WB_ADR_I[7:0])
                        8'h00: begin
                            write_value = merge_bytes(timeout_load, WB_DAT_I, WB_SEL_I);
                            if (write_value != 64'd0) begin
                                timeout_load <= write_value;
                                if (!watchdog_enable)
                                    timeout_count <= write_value;
                                WB_ACK_O <= 1'b1;
                            end
                
                            else begin
                                WB_ERR_O <= 1'b1;
                            end
                
                        end

                        8'h08: begin
                            write_value = merge_bytes({61'd0, reset_enable, interrupt_enable, watchdog_enable}, WB_DAT_I, WB_SEL_I);
                            watchdog_enable <= write_value[0];
                            interrupt_enable <= write_value[1];
                            reset_enable <= write_value[2];

                            if (write_value[0] && !watchdog_enable)
                                timeout_count <= (timeout_load == 64'd0) ? SAFE_DEFAULT_TIMEOUT : timeout_load;
                            
                            WB_ACK_O <= 1'b1;
                        
                        end

                        8'h18: begin
                            timeout_count <= (timeout_load == 64'd0) ? SAFE_DEFAULT_TIMEOUT : timeout_load;
                            WB_ACK_O <= 1'b1;
                        end

                        8'h20: begin
                            if (WB_SEL_I[0] && WB_DAT_I[0] &&
                                !(watchdog_enable && (timeout_count == 64'd1)))
                                expired <= 1'b0;
                            WB_ACK_O <= 1'b1;
                        end

                        default: WB_ERR_O <= 1'b1;
                    endcase
                end
                
                
                else begin
                
                    case (WB_ADR_I[7:0])
                        8'h00: WB_DAT_O <= timeout_load;
                        8'h08: WB_DAT_O <= {61'd0, reset_enable, interrupt_enable, watchdog_enable};
                        8'h10: WB_DAT_O <= timeout_count;
                        8'h18: WB_DAT_O <= 64'd0;
                        8'h20: WB_DAT_O <= {63'd0, expired};
                
                        default: begin
                            WB_DAT_O <= 64'd0;
                            WB_ERR_O <= 1'b1;
                        end
                
                    endcase
                    if ((WB_ADR_I[7:0] == 8'h00) || (WB_ADR_I[7:0] == 8'h08) || (WB_ADR_I[7:0] == 8'h10) || (WB_ADR_I[7:0] == 8'h18) || (WB_ADR_I[7:0] == 8'h20))
                        WB_ACK_O <= 1'b1;
                end
            end

        end


    end

endmodule