`timescale 1ns/1ps

// PMP - PHYSICAL MEMORY PROTECTION
// RV64, up to 16 entries, TOR / NA4 / NAPOT.

module PMP_RV64 #(
    parameter integer PMP_ENTRIES = 16
)(
    input wire CLK_I,
    input wire RST_I,

    // CSR port. RV64 pmpcfg0 and pmpcfg2 each hold eight entries.
    input wire [11:0] CSR_ADDR_I,
    input wire [63:0] CSR_WDATA_I,
    input wire CSR_WE_I,
    output reg [63:0] CSR_RDATA_O,

    // Physical access check.
    input wire ACCESS_VALID_I,
    input wire [63:0] ACCESS_ADDR_I,
    input wire [2:0] ACCESS_SIZE_I,     // log2(bytes), 0..3 for 1..8 bytes
    input wire ACCESS_READ_I,
    input wire ACCESS_WRITE_I,
    input wire ACCESS_EXECUTE_I,
    input wire [1:0] PRIVILEGE_I,      // 00=U, 01=S, 11=M
    output reg ACCESS_ALLOW_O,
    output reg ACCESS_MATCHED_O,
    output reg [4:0] ACCESS_ENTRY_O
);

    localparam [1:0] PRIV_M = 2'b11;

    localparam [1:0] PMP_OFF = 2'b00;
    localparam [1:0] PMP_TOR = 2'b01;
    localparam [1:0] PMP_NA4 = 2'b10;
    localparam [1:0] PMP_NAPOT = 2'b11;

    reg [7:0] pmp_config [0:PMP_ENTRIES-1];
    reg [53:0] pmp_address [0:PMP_ENTRIES-1];

    integer csr_index;
    integer access_index;
    integer bit_index;
    integer reset_index;

    reg [63:0] access_last;
    reg [63:0] region_low;
    reg [63:0] region_high;
    reg [63:0] region_size;
    reg [63:0] pmpaddr_extended;
    reg [5:0] napot_ones;
    reg napot_stop;
    reg overlap;
    reg full_match;
    reg [1:0] address_mode;
    reg matched_permission;
    reg matching_locked;

    // CSR READ PORT    

    always @(*) begin
        CSR_RDATA_O = 64'd0;

        if (CSR_ADDR_I == 12'h3A0) begin

            for (csr_index = 0; csr_index < PMP_ENTRIES; csr_index = csr_index + 1) begin
                if (csr_index < 8)
                    CSR_RDATA_O[csr_index*8 +: 8] = pmp_config[csr_index];
            end
        
        end

        else if (CSR_ADDR_I == 12'h3A2) begin
            for (csr_index = 8; csr_index < PMP_ENTRIES; csr_index = csr_index + 1) begin
                if (csr_index < 16)
                    CSR_RDATA_O[(csr_index-8)*8 +: 8] = pmp_config[csr_index];
            end
        end
        
        else begin
            for (csr_index = 0; csr_index < PMP_ENTRIES; csr_index = csr_index + 1) begin
                if (CSR_ADDR_I == (12'h3B0 + csr_index))
                    CSR_RDATA_O = {10'd0, pmp_address[csr_index]};
            end
        end
    
    
    end

    
    // CSR WRITE PORT
    

    always @(posedge CLK_I or posedge RST_I) begin
    
        if (RST_I) begin
            for (reset_index = 0; reset_index < PMP_ENTRIES; reset_index = reset_index + 1) begin
                pmp_config[reset_index] <= 8'd0;
                pmp_address[reset_index] <= 54'd0;
            end
    
    
        end
        else if (CSR_WE_I) begin
    
            if ((CSR_ADDR_I == 12'h3A0) || (CSR_ADDR_I == 12'h3A2)) begin
    
                for (reset_index = 0; reset_index < PMP_ENTRIES; reset_index = reset_index + 1) begin
    
                    if (((CSR_ADDR_I == 12'h3A0) && (reset_index < 8)) || ((CSR_ADDR_I == 12'h3A2) && (reset_index >= 8) && (reset_index < 16))) begin
                        if (!pmp_config[reset_index][7]) begin

                            if (CSR_ADDR_I == 12'h3A0) begin
                                pmp_config[reset_index] <= {
                                    CSR_WDATA_I[(reset_index*8)+7],
                                    2'b00,
                                    {CSR_WDATA_I[(reset_index*8)+4], CSR_WDATA_I[(reset_index*8)+3]},
                                    CSR_WDATA_I[(reset_index*8)+2],
                                    (CSR_WDATA_I[(reset_index*8)+1] & CSR_WDATA_I[(reset_index*8)]),
                                    CSR_WDATA_I[(reset_index*8)]
                                };
                            end
                            else begin
                                pmp_config[reset_index] <= {CSR_WDATA_I[((reset_index-8)*8)+7], 2'b00, {CSR_WDATA_I[((reset_index-8)*8)+4], CSR_WDATA_I[((reset_index-8)*8)+3]}, CSR_WDATA_I[((reset_index-8)*8)+2], (CSR_WDATA_I[((reset_index-8)*8)+1] & CSR_WDATA_I[((reset_index-8)*8)]), CSR_WDATA_I[((reset_index-8)*8)]};
                            end
                        end

                    end
                end


            end
            else begin
                for (reset_index = 0; reset_index < PMP_ENTRIES; reset_index = reset_index + 1) begin
                    if (CSR_ADDR_I == (12'h3B0 + reset_index)) begin
                        // A locked entry cannot change its address. The lower bound of a locked TOR entry is also locked.
                        if (!pmp_config[reset_index][7]) begin

                            if (reset_index < PMP_ENTRIES-1) begin
                                if (!(pmp_config[reset_index+1][7] && (pmp_config[reset_index+1][4:3] == PMP_TOR)))
                                    pmp_address[reset_index] <= CSR_WDATA_I[53:0];
                            end

                            else begin
                                pmp_address[reset_index] <= CSR_WDATA_I[53:0];
                            end

                        end
                    end

                end


            end

        end

    end

    
    // PMP ACCESS MATCHING
    

    always @(*) begin
        ACCESS_ALLOW_O = 1'b0;
        ACCESS_MATCHED_O = 1'b0;
        ACCESS_ENTRY_O = 5'd0;

        access_last = ACCESS_ADDR_I + ((64'd1 << ACCESS_SIZE_I) - 64'd1);
        overlap = 1'b0;
        full_match = 1'b0;
        region_low = 64'd0;
        region_high = 64'd0;
        region_size = 64'd0;
        pmpaddr_extended = 64'd0;
        napot_ones = 6'd0;
        napot_stop = 1'b0;
        address_mode = PMP_OFF;
        matched_permission = 1'b0;
        matching_locked = 1'b0;

        if (ACCESS_VALID_I && (ACCESS_SIZE_I <= 3'd3) && (access_last >= ACCESS_ADDR_I)) begin
            
            for (access_index = 0; access_index < PMP_ENTRIES; access_index = access_index + 1) begin
                if (!ACCESS_MATCHED_O) begin
                    address_mode = pmp_config[access_index][4:3];
                    region_low = 64'd0;
                    region_high = 64'd0;
                    overlap = 1'b0;
                    full_match = 1'b0;

                    case (address_mode)
                        PMP_TOR: begin
                            if (access_index == 0)
                                region_low = 64'd0;
                            else
                                region_low = {8'd0, pmp_address[access_index-1], 2'b00};
                            region_high = {8'd0, pmp_address[access_index], 2'b00};
                            overlap = (region_high > region_low) && (ACCESS_ADDR_I < region_high) && (access_last >= region_low);
                            full_match = (ACCESS_ADDR_I >= region_low) && (access_last < region_high);
                        end

                        PMP_NA4: begin
                            region_low = {8'd0, pmp_address[access_index], 2'b00};
                            region_high = region_low + 64'd4;
                            overlap = (ACCESS_ADDR_I < region_high) && (access_last >= region_low);
                            full_match = (ACCESS_ADDR_I >= region_low) && (access_last < region_high);
                        end

                        PMP_NAPOT: begin
                            napot_ones = 6'd0;
                            napot_stop = 1'b0;
                            for (bit_index = 0; bit_index < 54; bit_index = bit_index + 1) begin
                                if (!napot_stop) begin
                                    if (pmp_address[access_index][bit_index])
                                        napot_ones = napot_ones + 1'b1;
                                    else
                                        napot_stop = 1'b1;
                                end
                            end
                            pmpaddr_extended = {10'd0, pmp_address[access_index]};
                            region_size = 64'd1 << (napot_ones + 6'd3);
                            region_low = (pmpaddr_extended & ~((64'd1 << napot_ones) - 64'd1)) << 2;
                            region_high = region_low + region_size;
                            
                            overlap = (ACCESS_ADDR_I < region_high) && (access_last >= region_low);
                            full_match = (ACCESS_ADDR_I >= region_low) && (access_last < region_high);
                        end

                        default: begin
                            overlap = 1'b0;
                            full_match = 1'b0;
                        end

                    endcase

                    if (overlap) begin
                        ACCESS_MATCHED_O = 1'b1;
                        ACCESS_ENTRY_O = access_index[4:0];
                        matching_locked = pmp_config[access_index][7];
                        matched_permission = (!ACCESS_READ_I || pmp_config[access_index][0]) && (!ACCESS_WRITE_I || pmp_config[access_index][1]) && (!ACCESS_EXECUTE_I || pmp_config[access_index][2]);

                        // A matching entry must cover every byte of the access, independent of privilege and lock state.
                        // Only after a complete match may an unlocked entry bypass the R/W/X permissions in M-mode.
                        if (!full_match)
                            ACCESS_ALLOW_O = 1'b0;
                        else if ((PRIVILEGE_I == PRIV_M) && !matching_locked)
                            ACCESS_ALLOW_O = 1'b1;
                        else
                            ACCESS_ALLOW_O = matched_permission;
                    end
                end

            end

            // No PMP entry matches: M-mode access is allowed, while S-mode and U-mode access is denied when PMP is implemented.
            if (!ACCESS_MATCHED_O && (PRIVILEGE_I == PRIV_M))
                ACCESS_ALLOW_O = 1'b1;
    
    
        end
    
    end


endmodule