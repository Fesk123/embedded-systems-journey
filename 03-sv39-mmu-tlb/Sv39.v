`timescale 1ns/1ps

// Sv39 virtual memory translation unit for an RV64 system.
//
// This version is split from the normal memory access path so that instruction and data caches can use physical addresses directly.
// The MMU only translates virtual addresses. It does not perform the final instruction/data memory transfer itself.
//
// Features:
// - Sv39 virtual-to-physical address translation
// - Separate instruction and data TLBs
// - Configurable fully associative TLBs
// - 4 KiB, 2 MiB and 1 GiB pages
// - ASID and global mappings
// - SFENCE.VMA based TLB invalidation
// - MXR and SUM permission handling
// - Hardware-managed A/D bits
// - Separate instruction and data translation requests
// - One outstanding translation per I/D port
// - Shared page-table walker for TLB misses
// - Page-walk cache for non-leaf PTEs
// - Sv39 canonical-address checking
// - Page faults and page-table access faults
// - Wishbone B4 master used only for page-table accesses
//
// The intended SoC path is:
//
// CPU -> Sv39 -> I/D cache -> Wishbone interconnect -> physical memory
//
// The page-table walker inside Sv39 is a separate Wishbone master path.

module Sv39 #(

    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter ITLB_ENTRIES = 16,
    parameter DTLB_ENTRIES = 16,
    parameter PWC_ENTRIES = 8

)(

    input CLK_I,
    input RST_I,

    // SATP / privilege state

    input [63:0] satp,

    // 01 = S-mode, 00 = U-mode, 11 = M-mode.
    // The CPU should already apply MPRV/MPP rules for data accesses.

    input [1:0] i_priv_mode,
    input [1:0] d_priv_mode,

    input d_sum,
    input d_mxr,

    // Instruction translation port

    // The request is accepted when i_ready is high.
    // i_done and i_fault are one cycle completion pulses.

    input i_req,
    input [63:0] i_vaddr,

    output reg i_ready,
    output reg i_done,
    output reg [63:0] i_paddr,
    output reg i_fault,
    output reg [4:0] i_cause,
    output reg [63:0] i_tval,

    // Data translation port

    // The request is accepted when d_ready is high.
    // d_done and d_fault are one-cycle complesion pulses.

    input d_req,
    input d_write,
    input d_amo,
    input [63:0] d_vaddr,

    output reg d_ready,
    output reg d_done,
    output reg [63:0] d_paddr,
    output reg d_fault,
    output reg [4:0] d_cause,
    output reg [63:0] d_tval,

    // SFENCE.VMA

    // rs1_zero / rs2_zero must reflect whether the corresponding
    // instruction register is x0. This removes the ambiguitey between
    // an actual address/ASID of zero and the SFENCE.VMA wildcard form.

    input sfence_vma_valid,
    input sfence_vma_rs1_zero,
    input [63:0] sfence_vma_vaddr,
    input sfence_vma_rs2_zero,
    input [15:0] sfence_vma_asid,

    output wire sfence_vma_ready,
    output reg sfence_vma_done,

    // Wishbone master used by the page-table walker

    output reg [ADDR_WIDTH-1:0] ADR_O,
    output reg [DATA_WIDTH-1:0] DAT_O,
    input [DATA_WIDTH-1:0] DAT_I,
    output reg [DATA_WIDTH/8-1:0] SEL_O,

    output reg CYC_O,
    output reg STB_O,
    output reg WE_O,
    output reg [2:0] CTI_O,
    output reg [1:0] BTE_O,

    input ACK_I,
    input ERR_I,

    // Debug

    output wire debug_i_busy,
    output wire debug_d_busy,
    output wire debug_i_tlb_hit,
    output wire debug_d_tlb_hit,
    output wire [3:0] debug_state,
    output wire [1:0] debug_walk_level,
    output wire [63:0] debug_virtual_address,
    output wire [63:0] debug_physical_address,
    output wire debug_page_walk,
    output wire debug_pte_update,
    output wire debug_pwc_hit

);

    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    localparam [3:0] SATP_MODE_BARE = 4'd0;
    localparam [3:0] SATP_MODE_SV39 = 4'd8;

    localparam [4:0] CAUSE_INST_ACCESS_FAULT  = 5'd1;
    localparam [4:0] CAUSE_LOAD_ACCESS_FAULT  = 5'd5;
    localparam [4:0] CAUSE_STORE_ACCESS_FAULT = 5'd7;
    localparam [4:0] CAUSE_INST_PAGE_FAULT   = 5'd12;
    localparam [4:0] CAUSE_LOAD_PAGE_FAULT   = 5'd13;
    localparam [4:0] CAUSE_STORE_PAGE_FAULT  = 5'd15;

    localparam [2:0] WB_CTI_CLASSIC = 3'b000;
    localparam [1:0] WB_BTE_LINEAR = 2'b00;

    // REQUEST STATE

    reg i_active;
    reg d_active;
    reg i_waiting_walk;
    reg d_waiting_walk;

    reg [63:0] i_req_vaddr;
    reg [1:0] i_req_priv_mode;
    reg [63:0] i_req_satp;

    reg [63:0] d_req_vaddr;
    reg d_req_write;
    reg d_req_amo;
    reg [1:0] d_req_priv_mode;
    reg d_req_sum;
    reg d_req_mxr;
    reg [63:0] d_req_satp;

    // INSTRUCTION TLB

    reg itlb_valid [0:ITLB_ENTRIES-1];
    reg [26:0] itlb_vpn [0:ITLB_ENTRIES-1];
    reg [43:0] itlb_ppn [0:ITLB_ENTRIES-1];
    reg [15:0] itlb_asid [0:ITLB_ENTRIES-1];
    reg itlb_global [0:ITLB_ENTRIES-1];
    reg [1:0] itlb_level [0:ITLB_ENTRIES-1];
    reg itlb_r [0:ITLB_ENTRIES-1];
    reg itlb_w [0:ITLB_ENTRIES-1];
    reg itlb_x [0:ITLB_ENTRIES-1];
    reg itlb_u [0:ITLB_ENTRIES-1];
    reg itlb_d [0:ITLB_ENTRIES-1];
    reg [55:0] itlb_pte_address [0:ITLB_ENTRIES-1];
    reg [63:0] itlb_pte_value [0:ITLB_ENTRIES-1];
    reg [4:0] itlb_replace_index;

    // DATA TLB

    reg dtlb_valid [0:DTLB_ENTRIES-1];
    reg [26:0] dtlb_vpn [0:DTLB_ENTRIES-1];
    reg [43:0] dtlb_ppn [0:DTLB_ENTRIES-1];
    reg [15:0] dtlb_asid [0:DTLB_ENTRIES-1];
    reg dtlb_global [0:DTLB_ENTRIES-1];
    reg [1:0] dtlb_level [0:DTLB_ENTRIES-1];
    reg dtlb_r [0:DTLB_ENTRIES-1];
    reg dtlb_w [0:DTLB_ENTRIES-1];
    reg dtlb_x [0:DTLB_ENTRIES-1];
    reg dtlb_u [0:DTLB_ENTRIES-1];
    reg dtlb_d [0:DTLB_ENTRIES-1];
    reg [55:0] dtlb_pte_address [0:DTLB_ENTRIES-1];
    reg [63:0] dtlb_pte_value [0:DTLB_ENTRIES-1];
    reg [4:0] dtlb_replace_index;

    // PAGE WALK CACHE

    // The PWC caches non-leaf PTEs by their physical PTE address.
    // It avoids repeatedly reading the same upper-level page-table entries for nearby virtual pages.

    reg pwc_valid [0:PWC_ENTRIES-1];
    reg [55:0] pwc_address [0:PWC_ENTRIES-1];
    reg [63:0] pwc_value [0:PWC_ENTRIES-1];
    reg [4:0] pwc_replace_index;

    // TLB LOOKUP RESULTS

    reg itlb_hit;
    reg [4:0] itlb_hit_index;
    reg [43:0] itlb_hit_ppn;
    reg [1:0] itlb_hit_level;
    reg itlb_hit_r;
    reg itlb_hit_w;
    reg itlb_hit_x;
    reg itlb_hit_u;
    reg itlb_hit_d;
    reg itlb_hit_global;
    reg [55:0] itlb_hit_pte_address;
    reg [63:0] itlb_hit_pte_value;

    reg dtlb_hit;
    reg [4:0] dtlb_hit_index;
    reg [43:0] dtlb_hit_ppn;
    reg [1:0] dtlb_hit_level;
    reg dtlb_hit_r;
    reg dtlb_hit_w;
    reg dtlb_hit_x;
    reg dtlb_hit_u;
    reg dtlb_hit_d;
    reg dtlb_hit_global;
    reg [55:0] dtlb_hit_pte_address;
    reg [63:0] dtlb_hit_pte_value;

    integer index;

    always @(*) begin

        itlb_hit = 1'b0;
        itlb_hit_index = 5'd0;
        itlb_hit_ppn = 44'd0;
        itlb_hit_level = 2'd0;
        itlb_hit_r = 1'b0;
        itlb_hit_w = 1'b0;
        itlb_hit_x = 1'b0;
        itlb_hit_u = 1'b0;
        itlb_hit_d = 1'b0;
        itlb_hit_global = 1'b0;
        itlb_hit_pte_address = 56'd0;
        itlb_hit_pte_value = 64'd0;

        for (index = 0; index < ITLB_ENTRIES; index = index + 1) begin

            if (!itlb_hit && itlb_valid[index] &&
                (itlb_global[index] || (itlb_asid[index] == i_req_satp[59:44]))) begin

                case (itlb_level[index])

                    2'd2: begin
                        if (itlb_vpn[index][26:18] == i_req_vaddr[38:30])
                            itlb_hit = 1'b1;
                    end

                    2'd1: begin
                        if (itlb_vpn[index][26:9] == i_req_vaddr[38:21])
                            itlb_hit = 1'b1;
                    end

                    default: begin
                        if (itlb_vpn[index] == i_req_vaddr[38:12])
                            itlb_hit = 1'b1;
                    end

                endcase

                if (itlb_hit) begin
                    itlb_hit_index = index[4:0];
                    itlb_hit_ppn = itlb_ppn[index];
                    itlb_hit_level = itlb_level[index];
                    itlb_hit_r = itlb_r[index];
                    itlb_hit_w = itlb_w[index];
                    itlb_hit_x = itlb_x[index];
                    itlb_hit_u = itlb_u[index];
                    itlb_hit_d = itlb_d[index];
                    itlb_hit_global = itlb_global[index];
                    itlb_hit_pte_address = itlb_pte_address[index];
                    itlb_hit_pte_value = itlb_pte_value[index];
                end

            end

        end

    end

    always @(*) begin

        dtlb_hit = 1'b0;
        dtlb_hit_index = 5'd0;
        dtlb_hit_ppn = 44'd0;
        dtlb_hit_level = 2'd0;
        dtlb_hit_r = 1'b0;
        dtlb_hit_w = 1'b0;
        dtlb_hit_x = 1'b0;
        dtlb_hit_u = 1'b0;
        dtlb_hit_d = 1'b0;
        dtlb_hit_global = 1'b0;
        dtlb_hit_pte_address = 56'd0;
        dtlb_hit_pte_value = 64'd0;

        for (index = 0; index < DTLB_ENTRIES; index = index + 1) begin

            if (!dtlb_hit && dtlb_valid[index] &&
                (dtlb_global[index] || (dtlb_asid[index] == d_req_satp[59:44]))) begin

                case (dtlb_level[index])

                    2'd2: begin
                        if (dtlb_vpn[index][26:18] == d_req_vaddr[38:30])
                            dtlb_hit = 1'b1;
                    end

                    2'd1: begin
                        if (dtlb_vpn[index][26:9] == d_req_vaddr[38:21])
                            dtlb_hit = 1'b1;
                    end

                    default: begin
                        if (dtlb_vpn[index] == d_req_vaddr[38:12])
                            dtlb_hit = 1'b1;
                    end

                endcase

                if (dtlb_hit) begin
                    dtlb_hit_index = index[4:0];
                    dtlb_hit_ppn = dtlb_ppn[index];
                    dtlb_hit_level = dtlb_level[index];
                    dtlb_hit_r = dtlb_r[index];
                    dtlb_hit_w = dtlb_w[index];
                    dtlb_hit_x = dtlb_x[index];
                    dtlb_hit_u = dtlb_u[index];
                    dtlb_hit_d = dtlb_d[index];
                    dtlb_hit_global = dtlb_global[index];
                    dtlb_hit_pte_address = dtlb_pte_address[index];
                    dtlb_hit_pte_value = dtlb_pte_value[index];
                end

            end

        end

    end


    // PAGE WALK CACHE LOOKUP


    reg pwc_hit;
    reg [4:0] pwc_hit_index;
    reg [63:0] pwc_hit_value;

    always @(*) begin

        pwc_hit = 1'b0;
        pwc_hit_index = 5'd0;
        pwc_hit_value = 64'd0;

        for (index = 0; index < PWC_ENTRIES; index = index + 1) begin

            if (!pwc_hit && pwc_valid[index] &&
                (pwc_address[index] == walk_pte_address)) begin

                pwc_hit = 1'b1;
                pwc_hit_index = index[4:0];
                pwc_hit_value = pwc_value[index];

            end

        end

    end


    // WALKER STATE


    localparam [3:0] WALK_IDLE    = 4'd0;
    localparam [3:0] WALK_CHECK   = 4'd1;
    localparam [3:0] WALK_READ    = 4'd2;
    localparam [3:0] WALK_PROCESS = 4'd3;
    localparam [3:0] WALK_WRITE   = 4'd4;

    reg [3:0] walker_state;
    reg walker_owner;
    reg [1:0] walk_level;
    reg [55:0] walk_pte_address;
    reg [63:0] walk_pte_value;
    reg walk_global;

    // Pending A/D update information.
    reg [63:0] pending_pte_value;
    reg [55:0] pending_pte_address;
    reg [63:0] pending_physical_address;
    reg pending_leaf_global;
    reg [1:0] pending_leaf_level;
    reg [43:0] pending_leaf_ppn;
    reg pending_from_tlb_hit;
    reg [4:0] pending_tlb_index;


    // TRANSLATION HELPERS


    reg [43:0] itlb_translated_ppn;
    reg [63:0] itlb_translated_pa;
    reg [43:0] dtlb_translated_ppn;
    reg [63:0] dtlb_translated_pa;
    reg [43:0] walk_translated_ppn;
    reg [63:0] walk_translated_pa;

    always @(*) begin

        itlb_translated_ppn = itlb_hit_ppn;

        case (itlb_hit_level)
            2'd2: itlb_translated_ppn[17:0] = i_req_vaddr[29:12];
            2'd1: itlb_translated_ppn[8:0] = i_req_vaddr[20:12];
            default: begin
            end
        endcase

        itlb_translated_pa = {itlb_translated_ppn, i_req_vaddr[11:0]};

    end

    always @(*) begin

        dtlb_translated_ppn = dtlb_hit_ppn;

        case (dtlb_hit_level)
            2'd2: dtlb_translated_ppn[17:0] = d_req_vaddr[29:12];
            2'd1: dtlb_translated_ppn[8:0] = d_req_vaddr[20:12];
            default: begin
            end
        endcase

        dtlb_translated_pa = {dtlb_translated_ppn, d_req_vaddr[11:0]};

    end

    always @(*) begin

        walk_translated_ppn = walk_pte_value[53:10];

        case (walk_level)
            2'd2: walk_translated_ppn[17:0] = walker_owner ? d_req_vaddr[29:12] : i_req_vaddr[29:12];
            2'd1: walk_translated_ppn[8:0] = walker_owner ? d_req_vaddr[20:12] : i_req_vaddr[20:12];
            default: begin
            end
        endcase

        walk_translated_pa = {walk_translated_ppn,
                              walker_owner ? d_req_vaddr[11:0] : i_req_vaddr[11:0]};

    end


    // PTE CHECKS


    wire pte_v = walk_pte_value[0];
    wire pte_r = walk_pte_value[1];
    wire pte_w = walk_pte_value[2];
    wire pte_x = walk_pte_value[3];
    wire pte_u = walk_pte_value[4];
    wire pte_g = walk_pte_value[5];
    wire pte_a = walk_pte_value[6];
    wire pte_d = walk_pte_value[7];

    wire pte_is_leaf = pte_r || pte_x;

    // Base Sv39 implementation only.
    // Svnapot and Svpbmt are not implemented, so their PTE fields remain reserved.

    wire pte_reserved_bits_bad =
        walk_pte_value[63] ||
        (walk_pte_value[62:61] != 2'b00) ||
        (walk_pte_value[60:54] != 7'b0000000);

    wire pte_invalid_permission = (!pte_r && pte_w);

    wire pte_nonleaf_reserved_bad =
        !pte_is_leaf &&
        (pte_u || pte_a || pte_d);

    wire pte_invalid =
        !pte_v ||
        pte_reserved_bits_bad ||
        pte_invalid_permission ||
        pte_nonleaf_reserved_bad;

    wire pte_misaligned_superpage =
        pte_is_leaf &&
        ((walk_level == 2'd2 && (walk_pte_value[27:10] != 18'd0)) ||
         (walk_level == 2'd1 && (walk_pte_value[18:10] != 9'd0)));

    reg walk_permission_fault;

    always @(*) begin

        walk_permission_fault = 1'b0;

        if (walker_owner == 1'b0) begin

            if (!pte_x)
                walk_permission_fault = 1'b1;

            if ((i_req_priv_mode == PRIV_S) && pte_u)
                walk_permission_fault = 1'b1;

            if ((i_req_priv_mode == PRIV_U) && !pte_u)
                walk_permission_fault = 1'b1;

        end

        else begin

            if ((d_req_priv_mode == PRIV_U) && !pte_u)
                walk_permission_fault = 1'b1;

            if ((d_req_priv_mode == PRIV_S) && pte_u && !d_req_sum)
                walk_permission_fault = 1'b1;

            if (!d_req_write) begin

                if (!(pte_r || (d_req_mxr && pte_x)))
                    walk_permission_fault = 1'b1;

            end

            else begin

                if (!pte_w)
                    walk_permission_fault = 1'b1;

                if (d_req_amo && !pte_r)
                    walk_permission_fault = 1'b1;

            end

        end

    end


    // REQUEST VALIDATION


    wire i_sv39_active =
        i_active &&
        (i_req_priv_mode != PRIV_M) &&
        (i_req_satp[63:60] == SATP_MODE_SV39) &&
        (i_req_vaddr[63:39] == {25{i_req_vaddr[38]}});

    wire d_sv39_active =
        d_active &&
        (d_req_priv_mode != PRIV_M) &&
        (d_req_satp[63:60] == SATP_MODE_SV39) &&
        (d_req_vaddr[63:39] == {25{d_req_vaddr[38]}});

    wire i_tlb_permission_fault =
        itlb_hit &&
        (!itlb_hit_x ||
         ((i_req_priv_mode == PRIV_S) && itlb_hit_u) ||
         ((i_req_priv_mode == PRIV_U) && !itlb_hit_u));

    wire d_tlb_permission_fault =
        dtlb_hit &&
        ((d_req_priv_mode == PRIV_U && !dtlb_hit_u) ||
         (d_req_priv_mode == PRIV_S && dtlb_hit_u && !d_req_sum) ||
         (!d_req_write && !(dtlb_hit_r || (d_req_mxr && dtlb_hit_x))) ||
         (d_req_write && !dtlb_hit_w) ||
         (d_req_write && d_req_amo && !dtlb_hit_r));

    wire i_tlb_ad_needed =
        itlb_hit && !itlb_hit_pte_value[6];

    wire d_tlb_ad_needed =
        dtlb_hit &&
        (!dtlb_hit_pte_value[6] ||
         (d_req_write && !dtlb_hit_pte_value[7]));

    wire i_needs_walk =
        i_sv39_active &&
        !i_waiting_walk &&
        !i_tlb_permission_fault &&
        (!itlb_hit || i_tlb_ad_needed);

    wire d_needs_walk =
        d_sv39_active &&
        !d_waiting_walk &&
        !d_tlb_permission_fault &&
        (!dtlb_hit || d_tlb_ad_needed);


    // READY / DEBUG


    always @(*) begin

        i_ready = !i_active && !sfence_vma_valid;
        d_ready = !d_active && !sfence_vma_valid;

    end

    assign sfence_vma_ready =
        !i_active &&
        !d_active &&
        (walker_state == WALK_IDLE);

    assign debug_i_busy = i_active;
    assign debug_d_busy = d_active;
    assign debug_i_tlb_hit = itlb_hit;
    assign debug_d_tlb_hit = dtlb_hit;
    assign debug_state = walker_state;
    assign debug_walk_level = walk_level;
    assign debug_virtual_address = walker_owner ? d_req_vaddr : i_req_vaddr;
    assign debug_physical_address = walker_owner ? d_paddr : i_paddr;
    assign debug_page_walk = (walker_state != WALK_IDLE);
    assign debug_pte_update = (walker_state == WALK_WRITE);
    assign debug_pwc_hit = pwc_hit;


    // WISHBONE PAGE-TABLE WALKER


    always @(*) begin

        ADR_O = {ADDR_WIDTH{1'b0}};
        DAT_O = {DATA_WIDTH{1'b0}};
        SEL_O = {(DATA_WIDTH/8){1'b0}};
        CYC_O = 1'b0;
        STB_O = 1'b0;
        WE_O = 1'b0;
        CTI_O = WB_CTI_CLASSIC;
        BTE_O = WB_BTE_LINEAR;

        case (walker_state)

            WALK_READ: begin

                ADR_O = {{(ADDR_WIDTH-56){1'b0}}, walk_pte_address};
                DAT_O = {DATA_WIDTH{1'b0}};
                SEL_O = {(DATA_WIDTH/8){1'b1}};
                CYC_O = 1'b1;
                STB_O = 1'b1;
                WE_O = 1'b0;

            end

            WALK_WRITE: begin

                ADR_O = {{(ADDR_WIDTH-56){1'b0}}, pending_pte_address};
                DAT_O = pending_pte_value;
                SEL_O = {(DATA_WIDTH/8){1'b1}};
                CYC_O = 1'b1;
                STB_O = 1'b1;
                WE_O = 1'b1;

            end

            default: begin
            end

        endcase

    end


    // MAIN CONTROL


    integer reset_index;

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            i_active <= 1'b0;
            d_active <= 1'b0;
            i_waiting_walk <= 1'b0;
            d_waiting_walk <= 1'b0;

            i_req_vaddr <= 64'd0;
            i_req_priv_mode <= PRIV_M;
            i_req_satp <= 64'd0;

            d_req_vaddr <= 64'd0;
            d_req_write <= 1'b0;
            d_req_amo <= 1'b0;
            d_req_priv_mode <= PRIV_M;
            d_req_sum <= 1'b0;
            d_req_mxr <= 1'b0;
            d_req_satp <= 64'd0;


            i_done <= 1'b0;
            i_paddr <= 64'd0;
            i_fault <= 1'b0;
            i_cause <= 5'd0;
            i_tval <= 64'd0;

            d_done <= 1'b0;
            d_paddr <= 64'd0;
            d_fault <= 1'b0;
            d_cause <= 5'd0;
            d_tval <= 64'd0;

            sfence_vma_done <= 1'b0;

            walker_state <= WALK_IDLE;
            walker_owner <= 1'b0;
            walk_level <= 2'd0;
            walk_pte_address <= 56'd0;
            walk_pte_value <= 64'd0;
            walk_global <= 1'b0;


            pending_pte_value <= 64'd0;
            pending_pte_address <= 56'd0;
            pending_physical_address <= 64'd0;
            pending_leaf_global <= 1'b0;
            pending_leaf_level <= 2'd0;
            pending_leaf_ppn <= 44'd0;
            pending_from_tlb_hit <= 1'b0;
            pending_tlb_index <= 5'd0;

            itlb_replace_index <= 5'd0;
            dtlb_replace_index <= 5'd0;
            pwc_replace_index <= 5'd0;

            for (reset_index = 0; reset_index < ITLB_ENTRIES; reset_index = reset_index + 1) begin
                itlb_valid[reset_index] <= 1'b0;
                itlb_vpn[reset_index] <= 27'd0;
                itlb_ppn[reset_index] <= 44'd0;
                itlb_asid[reset_index] <= 16'd0;
                itlb_global[reset_index] <= 1'b0;
                itlb_level[reset_index] <= 2'd0;
                itlb_r[reset_index] <= 1'b0;
                itlb_w[reset_index] <= 1'b0;
                itlb_x[reset_index] <= 1'b0;
                itlb_u[reset_index] <= 1'b0;
                itlb_d[reset_index] <= 1'b0;
                itlb_pte_address[reset_index] <= 56'd0;
                itlb_pte_value[reset_index] <= 64'd0;


            end



            for (reset_index = 0; reset_index < DTLB_ENTRIES; reset_index = reset_index + 1) begin

                dtlb_valid[reset_index] <= 1'b0;
                dtlb_vpn[reset_index] <= 27'd0;
                dtlb_ppn[reset_index] <= 44'd0;
                dtlb_asid[reset_index] <= 16'd0;
                dtlb_global[reset_index] <= 1'b0;

                dtlb_level[reset_index] <= 2'd0;
                dtlb_r[reset_index] <= 1'b0;
                dtlb_w[reset_index] <= 1'b0;
                dtlb_x[reset_index] <= 1'b0;
                dtlb_u[reset_index] <= 1'b0;

                dtlb_d[reset_index] <= 1'b0;
                dtlb_pte_address[reset_index] <= 56'd0;

                dtlb_pte_value[reset_index] <= 64'd0;
            end

            for (reset_index = 0; reset_index < PWC_ENTRIES; reset_index = reset_index + 1) begin
                pwc_valid[reset_index] <= 1'b0;
                pwc_address[reset_index] <= 56'd0;
                pwc_value[reset_index] <= 64'd0;
            end

        end

        else begin

            i_done <= 1'b0;
            i_fault <= 1'b0;
            d_done <= 1'b0;
            d_fault <= 1'b0;
            sfence_vma_done <= 1'b0;

        
            // ACCEPT NEW TRANSLATION REQUESTS
        

            if (i_req && i_ready) begin
                i_active <= 1'b1;
                i_waiting_walk <= 1'b0;
                i_req_vaddr <= i_vaddr;
                i_req_priv_mode <= i_priv_mode;
                i_req_satp <= satp;
            end

            if (d_req && d_ready) begin

                d_active <= 1'b1;
                d_waiting_walk <= 1'b0;
                d_req_vaddr <= d_vaddr;
                d_req_write <= d_write;
                d_req_amo <= d_amo;
                d_req_priv_mode <= d_priv_mode;
                d_req_sum <= d_sum;
                d_req_mxr <= d_mxr;
                d_req_satp <= satp;
            end

        
            // SFENCE.VMA
        

            if (sfence_vma_valid && sfence_vma_ready) begin

                for (reset_index = 0; reset_index < ITLB_ENTRIES; reset_index = reset_index + 1) begin

                    if (itlb_valid[reset_index]) begin

                        if (sfence_vma_rs1_zero && sfence_vma_rs2_zero) begin
                            itlb_valid[reset_index] <= 1'b0;
                        end


                        else if (sfence_vma_rs1_zero && !sfence_vma_rs2_zero) begin

                            if (!itlb_global[reset_index] &&
                                (itlb_asid[reset_index] == sfence_vma_asid))
                                itlb_valid[reset_index] <= 1'b0;

                        end

                        else if (!sfence_vma_rs1_zero && sfence_vma_rs2_zero) begin

                            case (itlb_level[reset_index])
                                2'd2: if (itlb_vpn[reset_index][26:18] == sfence_vma_vaddr[38:30]) itlb_valid[reset_index] <= 1'b0;
                                2'd1: if (itlb_vpn[reset_index][26:9] == sfence_vma_vaddr[38:21]) itlb_valid[reset_index] <= 1'b0;
                                default: if (itlb_vpn[reset_index] == sfence_vma_vaddr[38:12]) itlb_valid[reset_index] <= 1'b0;
                            endcase

                        end


                        else begin

                            if (!itlb_global[reset_index] &&
                                (itlb_asid[reset_index] == sfence_vma_asid)) begin

                                case (itlb_level[reset_index])
                                    2'd2: if (itlb_vpn[reset_index][26:18] == sfence_vma_vaddr[38:30]) itlb_valid[reset_index] <= 1'b0;
                                    2'd1: if (itlb_vpn[reset_index][26:9] == sfence_vma_vaddr[38:21]) itlb_valid[reset_index] <= 1'b0;
                                    default: if (itlb_vpn[reset_index] == sfence_vma_vaddr[38:12]) itlb_valid[reset_index] <= 1'b0;
                                endcase

                            end

                        end

                    end

                end

                for (reset_index = 0; reset_index < DTLB_ENTRIES; reset_index = reset_index + 1) begin

                    if (dtlb_valid[reset_index]) begin

                        if (sfence_vma_rs1_zero && sfence_vma_rs2_zero) begin
                            dtlb_valid[reset_index] <= 1'b0;
                        end

                        else if (sfence_vma_rs1_zero && !sfence_vma_rs2_zero) begin


                            if (!dtlb_global[reset_index] &&
                                (dtlb_asid[reset_index] == sfence_vma_asid))
                                dtlb_valid[reset_index] <= 1'b0;

                        end

                        else if (!sfence_vma_rs1_zero && sfence_vma_rs2_zero) begin

                            case (dtlb_level[reset_index])
                                2'd2: if (dtlb_vpn[reset_index][26:18] == sfence_vma_vaddr[38:30]) dtlb_valid[reset_index] <= 1'b0;
                                2'd1: if (dtlb_vpn[reset_index][26:9] == sfence_vma_vaddr[38:21]) dtlb_valid[reset_index] <= 1'b0;
                                default: if (dtlb_vpn[reset_index] == sfence_vma_vaddr[38:12]) dtlb_valid[reset_index] <= 1'b0;
                            endcase

                        end




                        else begin

                            if (!dtlb_global[reset_index] &&
                                (dtlb_asid[reset_index] == sfence_vma_asid)) begin

                                case (dtlb_level[reset_index])
                                    2'd2: if (dtlb_vpn[reset_index][26:18] == sfence_vma_vaddr[38:30]) dtlb_valid[reset_index] <= 1'b0;
                                    2'd1: if (dtlb_vpn[reset_index][26:9] == sfence_vma_vaddr[38:21]) dtlb_valid[reset_index] <= 1'b0;
                                    default: if (dtlb_vpn[reset_index] == sfence_vma_vaddr[38:12]) dtlb_valid[reset_index] <= 1'b0;
                                endcase


                            end

                        end

                    end

                end

                // Page-walk cache entries are physical page-table metadata and
                // are conservatively flushed by every SFENCE.VMA.


                for (reset_index = 0; reset_index < PWC_ENTRIES; reset_index = reset_index + 1) begin
                    pwc_valid[reset_index] <= 1'b0;
                end

                sfence_vma_done <= 1'b1;

            end

        
            // INSTRUCTION TLB HIT / DIRECT TRANSLATION
        

            if (i_active && !i_waiting_walk) begin

                if ((i_req_priv_mode == PRIV_M) ||
                    (i_req_satp[63:60] == SATP_MODE_BARE)) begin

                    i_paddr <= i_req_vaddr;
                    i_done <= 1'b1;
                    i_active <= 1'b0;

                end


                else if (i_req_satp[63:60] != SATP_MODE_SV39) begin

                    i_fault <= 1'b1;
                    i_cause <= CAUSE_INST_PAGE_FAULT;
                    i_tval <= i_req_vaddr;
                    i_done <= 1'b1;
                    i_active <= 1'b0;

                end

                else if (i_req_vaddr[63:39] != {25{i_req_vaddr[38]}}) begin

                    i_fault <= 1'b1;
                    i_cause <= CAUSE_INST_PAGE_FAULT;
                    i_tval <= i_req_vaddr;

                    i_done <= 1'b1;

                    i_active <= 1'b0;

                end

                else if (itlb_hit) begin

                    if (i_tlb_permission_fault) begin

                        i_fault <= 1'b1;
                        i_cause <= CAUSE_INST_PAGE_FAULT;
                        i_tval <= i_req_vaddr;
                        i_done <= 1'b1;
                        i_active <= 1'b0;

                    end

                    else if (!i_tlb_ad_needed) begin

                        i_paddr <= itlb_translated_pa;
                        i_done <= 1'b1;
                        i_active <= 1'b0;

                    end


                end

            end

        
            // DATA TLB HIT / DIRECT TRANSLATION
        

            if (d_active && !d_waiting_walk) begin

                if ((d_req_priv_mode == PRIV_M) ||
                    (d_req_satp[63:60] == SATP_MODE_BARE)) begin


                    d_paddr <= d_req_vaddr;
                    d_done <= 1'b1;
                    d_active <= 1'b0;

                end

                else if (d_req_satp[63:60] != SATP_MODE_SV39) begin

                    d_fault <= 1'b1;
                    d_cause <= d_req_write ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT;

                    d_tval <= d_req_vaddr;
                    d_done <= 1'b1;
                    d_active <= 1'b0;

                end

                else if (d_req_vaddr[63:39] != {25{d_req_vaddr[38]}}) begin

                    d_fault <= 1'b1;
                    d_cause <= d_req_write ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT;
                    d_tval <= d_req_vaddr;

                    d_done <= 1'b1;
                    d_active <= 1'b0;

                end


                else if (dtlb_hit) begin

                    if (d_tlb_permission_fault) begin

                        d_fault <= 1'b1;
                        d_cause <= d_req_write ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT;
                        d_tval <= d_req_vaddr;
                        d_done <= 1'b1;
                        d_active <= 1'b0;

                    end


                    else if (!d_tlb_ad_needed) begin

                        d_paddr <= dtlb_translated_pa;
                        d_done <= 1'b1;
                        d_active <= 1'b0;



                    end


                end

            end


        
            // START TRANSLATION MISS OR A/D UPDATE
        

            if ((walker_state == WALK_IDLE) && !sfence_vma_valid) begin

                if (i_needs_walk && d_needs_walk) begin

                    if (walker_owner == 1'b0) begin

                        i_waiting_walk <= 1'b1;
                        walker_owner <= 1'b0;

                        if (itlb_hit) begin

                            walker_state <= WALK_WRITE;
                            pending_from_tlb_hit <= 1'b1;
                            pending_tlb_index <= itlb_hit_index;

                            pending_pte_value <= itlb_hit_pte_value | 64'h0000_0000_0000_0040;

                            pending_pte_address <= itlb_hit_pte_address;
                            pending_physical_address <= itlb_translated_pa;
                            pending_leaf_global <= itlb_hit_global;
                            pending_leaf_level <= itlb_hit_level;
                            pending_leaf_ppn <= itlb_hit_ppn;

                        end
                        else begin


                            walker_state <= WALK_CHECK;
                            pending_from_tlb_hit <= 1'b0;
                            walk_level <= 2'd2;
                            walk_global <= 1'b0;
                            walk_pte_address <=
                                {i_req_satp[43:0], 12'b0} +
                                ({47'd0, i_req_vaddr[38:30]} << 3);

                        end

                    end

                    else begin


                        d_waiting_walk <= 1'b1;
                        walker_owner <= 1'b1;

                        if (dtlb_hit) begin

                            walker_state <= WALK_WRITE;
                            pending_from_tlb_hit <= 1'b1;
                            pending_tlb_index <= dtlb_hit_index;
                            pending_pte_value <=
                                dtlb_hit_pte_value |
                                64'h0000_0000_0000_0040 |
                                (d_req_write ? 64'h0000_0000_0000_0080 : 64'd0);
                            pending_pte_address <= dtlb_hit_pte_address;
                            pending_physical_address <= dtlb_translated_pa;
                            pending_leaf_global <= dtlb_hit_global;
                            pending_leaf_level <= dtlb_hit_level;
                            pending_leaf_ppn <= dtlb_hit_ppn;

                        end
                        else begin


                            walker_state <= WALK_CHECK;
                            pending_from_tlb_hit <= 1'b0;
                            walk_level <= 2'd2;
                            walk_global <= 1'b0;
                            walk_pte_address <=
                                {d_req_satp[43:0], 12'b0} +
                                ({47'd0, d_req_vaddr[38:30]} << 3);

                        end


                    end

                end

                else if (i_needs_walk) begin

                    i_waiting_walk <= 1'b1;
                    walker_owner <= 1'b0;

                    if (itlb_hit) begin

                        walker_state <= WALK_WRITE;

                        pending_from_tlb_hit <= 1'b1;
                        pending_tlb_index <= itlb_hit_index;
                        pending_pte_value <= itlb_hit_pte_value | 64'h0000_0000_0000_0040;
                        pending_pte_address <= itlb_hit_pte_address;
                        pending_physical_address <= itlb_translated_pa;
                        pending_leaf_global <= itlb_hit_global;
                        pending_leaf_level <= itlb_hit_level;
                        pending_leaf_ppn <= itlb_hit_ppn;

                    end
                    else begin

                        walker_state <= WALK_CHECK;
                        pending_from_tlb_hit <= 1'b0;
                        walk_level <= 2'd2;
                        walk_global <= 1'b0;
                        walk_pte_address <=
                            {i_req_satp[43:0], 12'b0} +

                            ({47'd0, i_req_vaddr[38:30]} << 3);

                    end

                end

                else if (d_needs_walk) begin

                    d_waiting_walk <= 1'b1;
                    walker_owner <= 1'b1;

                    if (dtlb_hit) begin

                        walker_state <= WALK_WRITE;
                        pending_from_tlb_hit <= 1'b1;
                        pending_tlb_index <= dtlb_hit_index;
                        pending_pte_value <=
                            dtlb_hit_pte_value |
                            64'h0000_0000_0000_0040 |
                            (d_req_write ? 64'h0000_0000_0000_0080 : 64'd0);
                        pending_pte_address <= dtlb_hit_pte_address;
                        pending_physical_address <= dtlb_translated_pa;
                        pending_leaf_global <= dtlb_hit_global;
                        pending_leaf_level <= dtlb_hit_level;

                        pending_leaf_ppn <= dtlb_hit_ppn;

                    end
                    else begin

                        walker_state <= WALK_CHECK;
                        pending_from_tlb_hit <= 1'b0;
                        walk_level <= 2'd2;
                        walk_global <= 1'b0;
                        walk_pte_address <=
                            {d_req_satp[43:0], 12'b0} +
                            ({47'd0, d_req_vaddr[38:30]} << 3);

                    end

                end


            end

        
            // PAGE WALKER
        

            case (walker_state)

                WALK_IDLE: begin
                    // A new translation miss may have started above.
                    // Keep the walker idle here and do not override the
                    // WALK_CHECK state assigned by the request-start logic.
                end

                WALK_CHECK: begin

                    if (pwc_hit) begin
                        walk_pte_value <= pwc_hit_value;
                        walk_global <= walk_global || pwc_hit_value[5];
                        walker_state <= WALK_PROCESS;
                    end
                    else begin
                        walker_state <= WALK_READ;
                    end

                end

                WALK_READ: begin

                    if (ERR_I) begin

                        if (walker_owner == 1'b0) begin
                            i_fault <= 1'b1;
                            i_cause <= CAUSE_INST_ACCESS_FAULT;
                            i_tval <= i_req_vaddr;
                            i_done <= 1'b1;
                            i_active <= 1'b0;
                            i_waiting_walk <= 1'b0;
                        end
                        else begin
                            d_fault <= 1'b1;
                            d_cause <= d_req_write ? CAUSE_STORE_ACCESS_FAULT : CAUSE_LOAD_ACCESS_FAULT;

                            d_tval <= d_req_vaddr;
                            d_done <= 1'b1;
                            d_active <= 1'b0;
                            d_waiting_walk <= 1'b0;
                        end

                        walker_state <= WALK_IDLE;

                    end

                    else if (ACK_I) begin

                        walk_pte_value <= DAT_I;
                        walker_state <= WALK_PROCESS;

                    end

                end

                WALK_PROCESS: begin

                    // Invalid PTE.

                    if (pte_invalid) begin

                        if (walker_owner == 1'b0) begin
                            i_fault <= 1'b1;

                            i_cause <= CAUSE_INST_PAGE_FAULT;
                            i_tval <= i_req_vaddr;
                            i_done <= 1'b1;
                            i_active <= 1'b0;
                            i_waiting_walk <= 1'b0;
                        end
                        else begin
                            d_fault <= 1'b1;
                            d_cause <= d_req_write ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT;
                            d_tval <= d_req_vaddr;
                            d_done <= 1'b1;
                            d_active <= 1'b0;
                            d_waiting_walk <= 1'b0;
                        end

                        walker_state <= WALK_IDLE;

                    end

                    // Non-leaf PTE.

                    else if (!pte_is_leaf) begin

                        if (walk_level == 2'd0) begin

                            if (walker_owner == 1'b0) begin
                                i_fault <= 1'b1;
                                i_cause <= CAUSE_INST_PAGE_FAULT;
                                i_tval <= i_req_vaddr;
                                i_done <= 1'b1;
                                i_active <= 1'b0;

                                i_waiting_walk <= 1'b0;
                            end
                            else begin
                                d_fault <= 1'b1;
                                d_cause <= d_req_write ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT;
                                d_tval <= d_req_vaddr;
                                d_done <= 1'b1;
                                d_active <= 1'b0;
                                d_waiting_walk <= 1'b0;
                            end

                            walker_state <= WALK_IDLE;

                        end


                        else begin

                            // Cache the upper-level PTE.
                            pwc_valid[pwc_replace_index] <= 1'b1;
                            pwc_address[pwc_replace_index] <= walk_pte_address;
                            pwc_value[pwc_replace_index] <= walk_pte_value;

                            if (pwc_replace_index + 5'd1 >= PWC_ENTRIES)
                                pwc_replace_index <= 5'd0;
                            else
                                pwc_replace_index <= pwc_replace_index + 5'd1;

                            walk_global <= walk_global || pte_g;
                            walk_level <= walk_level - 2'd1;

                            if (walk_level == 2'd2) begin


                                walk_pte_address <=
                                    {walk_pte_value[53:10], 12'b0} +
                                    ({47'd0,
                                      walker_owner ? d_req_vaddr[29:21] : i_req_vaddr[29:21]} << 3);

                            end

                            else begin

                                walk_pte_address <=
                                    {walk_pte_value[53:10], 12'b0} +
                                    ({47'd0,
                                      walker_owner ? d_req_vaddr[20:12] : i_req_vaddr[20:12]} << 3);

                            end

                            walker_state <= WALK_CHECK;

                        end


                    end

                    // Leaf PTE.

                    else if (pte_misaligned_superpage || walk_permission_fault) begin

                        if (walker_owner == 1'b0) begin
                            i_fault <= 1'b1;
                            i_cause <= CAUSE_INST_PAGE_FAULT;
                            i_tval <= i_req_vaddr;
                            i_done <= 1'b1;
                            i_active <= 1'b0;
                            i_waiting_walk <= 1'b0;
                        end
                        else begin
                            d_fault <= 1'b1;

                            d_cause <= d_req_write ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT;
                            d_tval <= d_req_vaddr;
                            d_done <= 1'b1;
                            d_active <= 1'b0;
                            d_waiting_walk <= 1'b0;
                        end

                        walker_state <= WALK_IDLE;

                    end

                    else begin


                        pending_leaf_global <= walk_global || pte_g;
                        pending_leaf_level <= walk_level;
                        pending_leaf_ppn <= walk_pte_value[53:10];
                        pending_pte_address <= walk_pte_address;
                        pending_physical_address <= walk_translated_pa;

                        // A/D management.

                        if (!pte_a || ((walker_owner == 1'b1) && d_req_write && !pte_d)) begin

                            pending_pte_value <=
                                walk_pte_value |
                                64'h0000_0000_0000_0040 |
                                (((walker_owner == 1'b1) && d_req_write) ?
                                 64'h0000_0000_0000_0080 : 64'd0);
                            pending_from_tlb_hit <= 1'b0;

                            walker_state <= WALK_WRITE;


                        end

                        else begin

                            if (walker_owner == 1'b0) begin

                                itlb_valid[itlb_replace_index] <= 1'b1;
                                itlb_vpn[itlb_replace_index] <= i_req_vaddr[38:12];
                                itlb_ppn[itlb_replace_index] <= walk_pte_value[53:10];
                                itlb_asid[itlb_replace_index] <= i_req_satp[59:44];
                                itlb_global[itlb_replace_index] <= walk_global || pte_g;
                                itlb_level[itlb_replace_index] <= walk_level;
                                itlb_r[itlb_replace_index] <= pte_r;
                                itlb_w[itlb_replace_index] <= pte_w;

                                itlb_x[itlb_replace_index] <= pte_x;
                                itlb_u[itlb_replace_index] <= pte_u;
                                itlb_d[itlb_replace_index] <= pte_d;
                                itlb_pte_address[itlb_replace_index] <= walk_pte_address;
                                itlb_pte_value[itlb_replace_index] <= walk_pte_value;

                                if (itlb_replace_index + 5'd1 >= ITLB_ENTRIES)
                                    itlb_replace_index <= 5'd0;
                                else
                                    itlb_replace_index <= itlb_replace_index + 5'd1;

                                i_paddr <= walk_translated_pa;
                                i_done <= 1'b1;
                                i_active <= 1'b0;
                                i_waiting_walk <= 1'b0;

                            end
                            else begin

                                dtlb_valid[dtlb_replace_index] <= 1'b1;
                                dtlb_vpn[dtlb_replace_index] <= d_req_vaddr[38:12];
                                dtlb_ppn[dtlb_replace_index] <= walk_pte_value[53:10];
                                dtlb_asid[dtlb_replace_index] <= d_req_satp[59:44];
                                dtlb_global[dtlb_replace_index] <= walk_global || pte_g;
                                dtlb_level[dtlb_replace_index] <= walk_level;
                                dtlb_r[dtlb_replace_index] <= pte_r;
                                dtlb_w[dtlb_replace_index] <= pte_w;
                                dtlb_x[dtlb_replace_index] <= pte_x;
                                dtlb_u[dtlb_replace_index] <= pte_u;
                                dtlb_d[dtlb_replace_index] <= pte_d;
                                dtlb_pte_address[dtlb_replace_index] <= walk_pte_address;

                                dtlb_pte_value[dtlb_replace_index] <= walk_pte_value;

                                if (dtlb_replace_index + 5'd1 >= DTLB_ENTRIES)
                                    dtlb_replace_index <= 5'd0;
                                else
                                    dtlb_replace_index <= dtlb_replace_index + 5'd1;

                                d_paddr <= walk_translated_pa;
                                d_done <= 1'b1;
                                d_active <= 1'b0;
                                d_waiting_walk <= 1'b0;

                            end

                            walker_state <= WALK_IDLE;

                        end

                    end

                end

                WALK_WRITE: begin


                    if (ERR_I) begin

                        if (walker_owner == 1'b0) begin
                            i_fault <= 1'b1;
                            i_cause <= CAUSE_INST_ACCESS_FAULT;
                            i_tval <= i_req_vaddr;
                            i_done <= 1'b1;
                            i_active <= 1'b0;
                            i_waiting_walk <= 1'b0;
                        end
                        else begin
                            d_fault <= 1'b1;
                            d_cause <= d_req_write ? CAUSE_STORE_ACCESS_FAULT : CAUSE_LOAD_ACCESS_FAULT;
                            d_tval <= d_req_vaddr;
                            d_done <= 1'b1;
                            d_active <= 1'b0;
                            d_waiting_walk <= 1'b0;
                        end

                        walker_state <= WALK_IDLE;

                    end

                    else if (ACK_I) begin

                        if (walker_owner == 1'b0) begin

                            if (pending_from_tlb_hit) begin


                                itlb_valid[pending_tlb_index] <= 1'b1;
                                itlb_d[pending_tlb_index] <= pending_pte_value[7];
                                itlb_pte_value[pending_tlb_index] <= pending_pte_value;

                            end
                            else begin

                                itlb_valid[itlb_replace_index] <= 1'b1;
                                itlb_vpn[itlb_replace_index] <= i_req_vaddr[38:12];
                                itlb_ppn[itlb_replace_index] <= pending_leaf_ppn;
                                itlb_asid[itlb_replace_index] <= i_req_satp[59:44];
                                itlb_global[itlb_replace_index] <= pending_leaf_global;
                                itlb_level[itlb_replace_index] <= pending_leaf_level;
                                itlb_r[itlb_replace_index] <= pending_pte_value[1];
                                itlb_w[itlb_replace_index] <= pending_pte_value[2];
                                itlb_x[itlb_replace_index] <= pending_pte_value[3];
                                itlb_u[itlb_replace_index] <= pending_pte_value[4];
                                itlb_d[itlb_replace_index] <= pending_pte_value[7];
                                itlb_pte_address[itlb_replace_index] <= pending_pte_address;
                                itlb_pte_value[itlb_replace_index] <= pending_pte_value;

                                if (itlb_replace_index + 5'd1 >= ITLB_ENTRIES)
                                    itlb_replace_index <= 5'd0;
                                else
                                    itlb_replace_index <= itlb_replace_index + 5'd1;


                            end

                            i_paddr <= pending_physical_address;
                            i_done <= 1'b1;
                            i_active <= 1'b0;
                            i_waiting_walk <= 1'b0;

                        end
                        else begin

                            if (pending_from_tlb_hit) begin

                                dtlb_valid[pending_tlb_index] <= 1'b1;
                                dtlb_d[pending_tlb_index] <= pending_pte_value[7];
                                dtlb_pte_value[pending_tlb_index] <= pending_pte_value;

                            end
                            else begin

                                dtlb_valid[dtlb_replace_index] <= 1'b1;
                                dtlb_vpn[dtlb_replace_index] <= d_req_vaddr[38:12];
                                dtlb_ppn[dtlb_replace_index] <= pending_leaf_ppn;
                                dtlb_asid[dtlb_replace_index] <= d_req_satp[59:44];

                                dtlb_global[dtlb_replace_index] <= pending_leaf_global;
                                dtlb_level[dtlb_replace_index] <= pending_leaf_level;
                                dtlb_r[dtlb_replace_index] <= pending_pte_value[1];
                                dtlb_w[dtlb_replace_index] <= pending_pte_value[2];
                                dtlb_x[dtlb_replace_index] <= pending_pte_value[3];
                                dtlb_u[dtlb_replace_index] <= pending_pte_value[4];
                                dtlb_d[dtlb_replace_index] <= pending_pte_value[7];
                                dtlb_pte_address[dtlb_replace_index] <= pending_pte_address;
                                dtlb_pte_value[dtlb_replace_index] <= pending_pte_value;

                                if (dtlb_replace_index + 5'd1 >= DTLB_ENTRIES)
                                    dtlb_replace_index <= 5'd0;
                                else
                                    dtlb_replace_index <= dtlb_replace_index + 5'd1;

                            end

                            d_paddr <= pending_physical_address;
                            d_done <= 1'b1;
                            d_active <= 1'b0;
                            d_waiting_walk <= 1'b0;

                        end

                        pending_from_tlb_hit <= 1'b0;
                        walker_state <= WALK_IDLE;

                    end

                end


                default: begin
                    walker_state <= WALK_IDLE;
                end

            endcase

        end

    end

endmodule
