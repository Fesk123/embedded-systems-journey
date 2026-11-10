`timescale 1ns/1ps

// PMU - PERFORMANCE MONITORING UNIT
// RV64 cycle, instruction-retired and HPM counters.

module PMU_RV64 #(
    parameter integer HPM_COUNTERS = 8
    // HPM_COUNTERS must be between 1 and 29 (mcountinhibit bits 3..31).
)(
    input wire CLK_I,
    input wire RST_I,

    // One-cycle event pulses. A counter increments once when any selected event bit is high in the current cycle. 
    // SoC event mapping:
    // [0] I-cache hit, [1] I-cache miss, [2] D-cache hit, [3] D-cache miss,
    // [4] L2 hit, [5] L2 miss, [6] ITLB hit, [7] ITLB miss,
    // [8] DTLB hit, [9] DTLB miss, [10] pipeline stall, [11] branch mispredict,
    // [12] Wishbone wait cycle, [13] DMA active, [14] GPU active,
    // [15] exception, [16] interrupt. The event pulses must be wired in 07.
    input wire [31:0] EVENT_I,
    input wire INSTRUCTION_RETIRED_I,
    input wire COUNTER_ENABLE_I,

    // Machine CSR interface.
    input wire [11:0] CSR_ADDR_I,
    input wire [63:0] CSR_WDATA_I,
    input wire CSR_WE_I,
    output reg [63:0] CSR_RDATA_O,

    output wire [63:0] DEBUG_MCYCLE_O,
    output wire [63:0] DEBUG_MINSTRET_O
);

    reg [63:0] mcycle;
    reg [63:0] minstret;
    reg [63:0] hpm_counter [0:HPM_COUNTERS-1];
    reg [31:0] hpm_event_select [0:HPM_COUNTERS-1];
    reg [31:0] mcountinhibit;

    localparam [31:0] MCOUNTINHIBIT_MASK = 32'h0000_0005 | (((32'h0000_0001 << HPM_COUNTERS) - 32'd1) << 3);

    integer counter_index;
    integer reset_index;

    assign DEBUG_MCYCLE_O = mcycle;
    assign DEBUG_MINSTRET_O = minstret;

    // Machine and user aliases are read-only for the user view.
    always @(*) begin
        CSR_RDATA_O = 64'd0;

        case (CSR_ADDR_I)
            12'hB00, 12'hC00: CSR_RDATA_O = mcycle;
            12'hB02, 12'hC02: CSR_RDATA_O = minstret;
            12'h320: CSR_RDATA_O = {32'd0, mcountinhibit};
        
            default: begin
                for (counter_index = 0; counter_index < HPM_COUNTERS; counter_index = counter_index + 1) begin
        
                    if (CSR_ADDR_I == (12'hB03 + counter_index))
                        CSR_RDATA_O = hpm_counter[counter_index];
                    else if (CSR_ADDR_I == (12'hC03 + counter_index))
                        CSR_RDATA_O = hpm_counter[counter_index];
                    else if (CSR_ADDR_I == (12'h323 + counter_index))
                        CSR_RDATA_O = {32'd0, hpm_event_select[counter_index]};
        
                end
            end
        
        endcase
    end

    always @(posedge CLK_I or posedge RST_I) begin
        
        if (RST_I) begin
            mcycle <= 64'd0;
            minstret <= 64'd0;
            mcountinhibit <= 32'd0;
        
            for (reset_index = 0; reset_index < HPM_COUNTERS; reset_index = reset_index + 1) begin
                hpm_counter[reset_index] <= 64'd0;
                hpm_event_select[reset_index] <= 32'd0;
            end
        
        end
        else begin
        
            if (!mcountinhibit[0] && COUNTER_ENABLE_I)
                mcycle <= mcycle + 64'd1;

            if (!mcountinhibit[2] && COUNTER_ENABLE_I && INSTRUCTION_RETIRED_I)
                minstret <= minstret + 64'd1;

            for (reset_index = 0; reset_index < HPM_COUNTERS; reset_index = reset_index + 1) begin
                if (!mcountinhibit[3+reset_index] && COUNTER_ENABLE_I && ((EVENT_I & hpm_event_select[reset_index]) != 32'd0))
                    hpm_counter[reset_index] <= hpm_counter[reset_index] + 64'd1;
            end

            if (CSR_WE_I) begin
                case (CSR_ADDR_I)
                    12'hB00: mcycle <= CSR_WDATA_I;
                    12'hB02: minstret <= CSR_WDATA_I;
                    12'h320: mcountinhibit <= CSR_WDATA_I[31:0] & MCOUNTINHIBIT_MASK;
                    
                    default: begin
                    
                        for (reset_index = 0; reset_index < HPM_COUNTERS; reset_index = reset_index + 1) begin
                            if (CSR_ADDR_I == (12'hB03 + reset_index))
                                hpm_counter[reset_index] <= CSR_WDATA_I;
                            else if (CSR_ADDR_I == (12'h323 + reset_index))
                                hpm_event_select[reset_index] <= CSR_WDATA_I[31:0];
                        end
                    
                    end
                endcase
            
            end

        
        end
    
    
    end

endmodule