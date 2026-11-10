`timescale 1ns/1ps

// PMA CHECKER
// Platform-defined physical memory attributes and access checks.

module PMA_Checker #(
    // Attribute bits: [5]=device, [4]=read, [3]=write, [2]=execute, [1]=cacheable, [0]=idempotent.
    parameter [63:0] REGION0_BASE = 64'h0000_0000_0C00_0000,
    parameter [63:0] REGION0_MASK = 64'hFFFF_FFFF_FC00_0000,
    parameter [5:0] REGION0_ATTR = 6'b111000,
    parameter [63:0] REGION1_BASE = 64'h0000_0000_1000_0000,
    parameter [63:0] REGION1_MASK = 64'hFFFF_FFFF_F000_0000,
    parameter [5:0] REGION1_ATTR = 6'b111000,
    parameter [63:0] REGION2_BASE = 64'h0000_0000_A000_0000,
    parameter [63:0] REGION2_MASK = 64'hFFFF_FFFF_F000_0000,
    parameter [5:0] REGION2_ATTR = 6'b111000,
    parameter [63:0] REGION3_BASE = 64'h0000_0000_8000_0000,
    parameter [63:0] REGION3_MASK = 64'hFFFF_FFFF_E000_0000,
    parameter [5:0] REGION3_ATTR = 6'b011111,
    parameter [63:0] REGION4_BASE = 64'h0000_0000_0000_0000,
    parameter [63:0] REGION4_MASK = 64'hFFFF_FFFF_FFFF_C000,
    parameter [5:0] REGION4_ATTR = 6'b010111
)(
    input wire [63:0] paddr_i,
    input wire [2:0] size_i,       // log2(bytes): 0=1, 1=2, 2=4, 3=8
    input wire request_i,
    input wire read_i,
    input wire write_i,
    input wire execute_i,
    output reg access_fault_o,
    output reg cacheable_o,
    output reg idempotent_o,
    output reg executable_o,
    output reg device_o,
    output reg [5:0] attributes_o
);

    // PMA regions use contiguous address masks (high-order ones, low-order zeros).
    // An access that overlaps a higher-priority region must be checked against that region even when the access starts in a lower-priority region.

    function region_overlap;
        input [63:0] address;
        input [63:0] last;
        input [63:0] base;
        input [63:0] mask;
        reg [64:0] region_low;
        reg [64:0] region_high;
        begin
            region_low = {1'b0, (base & mask)};
            region_high = region_low + ({1'b0, ~mask} + 65'd1);
            region_overlap = ({1'b0, address} < region_high) && ({1'b0, last} >= region_low);
        end
    endfunction

    function region_contains;
        input [63:0] address;
        input [63:0] last;
        input [63:0] base;
        input [63:0] mask;
        reg [64:0] region_low;
        reg [64:0] region_high;
        begin
            region_low = {1'b0, (base & mask)};
            region_high = region_low + ({1'b0, ~mask} + 65'd1);
            region_contains = ({1'b0, address} >= region_low) && ({1'b0, last} < region_high);
        end
    endfunction

    reg region_found;
    reg region_complete;
    reg [63:0] last_address;

    always @(*) begin
        region_found = 1'b0;
        region_complete = 1'b0;
        attributes_o = 6'b000000;
        last_address = paddr_i + ((64'd1 << size_i) - 64'd1);

        // Region order defines priority. Select the first region that the access touches, not merely the first region containing both ends.
        // A partial overlap with that highest-priority region is an access fault; it must not fall through to a larger, lower-priority region.

        if (!region_found && region_overlap(paddr_i, last_address, REGION0_BASE, REGION0_MASK)) begin
            region_found = 1'b1;
            region_complete = region_contains(paddr_i, last_address, REGION0_BASE, REGION0_MASK);
            attributes_o = REGION0_ATTR;
        end

        if (!region_found && region_overlap(paddr_i, last_address, REGION1_BASE, REGION1_MASK)) begin
            region_found = 1'b1;
            region_complete = region_contains(paddr_i, last_address, REGION1_BASE, REGION1_MASK);
            attributes_o = REGION1_ATTR;
        end
        
        if (!region_found && region_overlap(paddr_i, last_address, REGION2_BASE, REGION2_MASK)) begin
            region_found = 1'b1;
            region_complete = region_contains(paddr_i, last_address, REGION2_BASE, REGION2_MASK);
            attributes_o = REGION2_ATTR;
        end
        
        if (!region_found && region_overlap(paddr_i, last_address, REGION3_BASE, REGION3_MASK)) begin
            region_found = 1'b1;
            region_complete = region_contains(paddr_i, last_address, REGION3_BASE, REGION3_MASK);
            attributes_o = REGION3_ATTR;
        end
        if (!region_found && region_overlap(paddr_i, last_address, REGION4_BASE, REGION4_MASK)) begin
            region_found = 1'b1;
            region_complete = region_contains(paddr_i, last_address, REGION4_BASE, REGION4_MASK);
            attributes_o = REGION4_ATTR;
        end

        access_fault_o = 1'b0;
        if (request_i) begin
            if ((size_i > 3'd3) || (last_address < paddr_i) || !region_found || !region_complete)
                access_fault_o = 1'b1;
            else if (read_i && !attributes_o[4])
                access_fault_o = 1'b1;
            else if (write_i && !attributes_o[3])
                access_fault_o = 1'b1;
            else if (execute_i && !attributes_o[2])
                access_fault_o = 1'b1;
        end

        // Keep the matched region attributes when the region is known but the requested operation is not permitted (read/write/execute) or the access size is unsupported. These attributes describe the physical region; access_fault_o independently reports whether the requested operation may proceed.
        // Clear attributes only when no single highest-priority region completely contains the access. This includes unmapped addresses, address overflow and accesses crossing a PMA region boundary.
        // In those cases it would be unsafe to expose attributes from only the first byte's region.
        if (request_i && (!region_found || !region_complete || (last_address < paddr_i)))
            attributes_o = 6'b000000;

        cacheable_o = attributes_o[1];
        idempotent_o = attributes_o[0];
        executable_o = attributes_o[2];
        device_o = attributes_o[5];
    end

endmodule