`timescale 1ns/1ps

// GTKWave testbench for the Sv39 MMU / TLB.
//
// The testbench contains three focused scenarios for waveform capture:
//
// TEST 1
// Instruction page walk and ITLB hit.
//
// TEST 2
// Data page walk, PWC reuse and DTLB hit.
//
// TEST 3
// SFENCE.VMA, repeated page walk and page-fault handling.
//
// The testbench intentionally uses no $display calls. Use GTKWave to inspect the debug and request signals for the three scenarios.

module Sim_Sv39;

    reg CLK_I;
    reg RST_I;

    reg [63:0] satp;

    reg [1:0] i_priv_mode;
    reg [1:0] d_priv_mode;
    reg d_sum;
    reg d_mxr;

    reg i_req;
    reg [63:0] i_vaddr;
    wire i_ready;
    wire i_done;
    wire [63:0] i_paddr;
    wire i_fault;
    wire [4:0] i_cause;
    wire [63:0] i_tval;

    reg d_req;
    reg d_write;
    reg d_amo;
    reg [63:0] d_vaddr;
    wire d_ready;
    wire d_done;
    wire [63:0] d_paddr;
    wire d_fault;
    wire [4:0] d_cause;
    wire [63:0] d_tval;

    reg sfence_vma_valid;
    reg sfence_vma_rs1_zero;
    reg [63:0] sfence_vma_vaddr;
    reg sfence_vma_rs2_zero;
    reg [15:0] sfence_vma_asid;
    wire sfence_vma_ready;
    wire sfence_vma_done;

    wire [63:0] ADR_O;
    wire [63:0] DAT_O;
    reg [63:0] DAT_I;
    wire [7:0] SEL_O;
    wire CYC_O;
    wire STB_O;
    wire WE_O;
    wire [2:0] CTI_O;
    wire [1:0] BTE_O;
    wire ACK_I;
    wire ERR_I;

    wire debug_i_busy;
    wire debug_d_busy;
    wire debug_i_tlb_hit;
    wire debug_d_tlb_hit;
    wire [3:0] debug_state;
    wire [1:0] debug_walk_level;
    wire [63:0] debug_virtual_address;
    wire [63:0] debug_physical_address;
    wire debug_page_walk;
    wire debug_pte_update;
    wire debug_pwc_hit;

    // Waveform markers used to find the three pictures quickly in GTKWave.
    reg [1:0] scenario;
    reg [7:0] checkpoint;

    localparam integer MEM_WORDS = 8192;
    reg [63:0] memory [0:MEM_WORDS-1];
    wire [12:0] memory_index = ADR_O[15:3];

    integer i;

    assign DAT_I = (ADR_O < 64'h0000_0000_0001_0000) ? memory[memory_index] : 64'd0;
    assign ACK_I = CYC_O && STB_O;
    assign ERR_I = 1'b0;

    always @(posedge CLK_I) begin
        if (CYC_O && STB_O && WE_O && (ADR_O < 64'h0000_0000_0001_0000))
            memory[memory_index] <= DAT_O;
    end

    Sv39 dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .satp(satp),
        .i_priv_mode(i_priv_mode),
        .d_priv_mode(d_priv_mode),
        
        .d_sum(d_sum),
        .d_mxr(d_mxr),
        
        .i_req(i_req),
        .i_vaddr(i_vaddr),
        .i_ready(i_ready),
        .i_done(i_done),
        .i_paddr(i_paddr),
        .i_fault(i_fault),
        .i_cause(i_cause),
        .i_tval(i_tval),
        
        .d_req(d_req),
        .d_write(d_write),
        .d_amo(d_amo),
        .d_vaddr(d_vaddr),
        .d_ready(d_ready),
        .d_done(d_done),
        .d_paddr(d_paddr),
        .d_fault(d_fault),
        .d_cause(d_cause),
        .d_tval(d_tval),
        
        .sfence_vma_valid(sfence_vma_valid),
        .sfence_vma_rs1_zero(sfence_vma_rs1_zero),
        .sfence_vma_vaddr(sfence_vma_vaddr),
        .sfence_vma_rs2_zero(sfence_vma_rs2_zero),
        .sfence_vma_asid(sfence_vma_asid),
        .sfence_vma_ready(sfence_vma_ready),
        .sfence_vma_done(sfence_vma_done),
        
        .ADR_O(ADR_O),
        
        .DAT_O(DAT_O),
        .DAT_I(DAT_I),
        
        .SEL_O(SEL_O),
        
        .CYC_O(CYC_O),
        
        .STB_O(STB_O),
    
        .WE_O(WE_O),
    
        .CTI_O(CTI_O),
        .BTE_O(BTE_O),
        .ACK_I(ACK_I),
        .ERR_I(ERR_I),
    
        .debug_i_busy(debug_i_busy),
        .debug_d_busy(debug_d_busy),
        .debug_i_tlb_hit(debug_i_tlb_hit),
        .debug_d_tlb_hit(debug_d_tlb_hit),
        .debug_state(debug_state),
        .debug_walk_level(debug_walk_level),
        .debug_virtual_address(debug_virtual_address),
        .debug_physical_address(debug_physical_address),
        .debug_page_walk(debug_page_walk),
        .debug_pte_update(debug_pte_update),
        .debug_pwc_hit(debug_pwc_hit)
    );

    always #5 CLK_I = ~CLK_I;

    function [63:0] make_pte;
        input [43:0] ppn;
        input v;
        input r;
        input w;
        input x;
        input u;
        input g;
        input a;
        input d;
        begin
            make_pte = {10'd0, ppn, 2'b00, d, a, g, u, x, w, r, v};
        end
    endfunction

    task automatic clear_memory;
        begin
            for (i = 0; i < MEM_WORDS; i = i + 1)
                memory[i] = 64'd0;
        end
    endtask

    task automatic reset_cpu;
        begin
            RST_I = 1'b1;
            repeat (3) @(posedge CLK_I);
            @(negedge CLK_I);
            
            RST_I = 1'b0;
            repeat (2) @(posedge CLK_I);
            @(negedge CLK_I);
        end
    endtask

    task automatic setup_common;
        begin
            i_req = 1'b0;
            i_vaddr = 64'd0;
            i_priv_mode = 2'b01;
            d_req = 1'b0;
            d_write = 1'b0;
            d_amo = 1'b0;
            d_vaddr = 64'd0;
            d_priv_mode = 2'b01;
            d_sum = 1'b0;
            d_mxr = 1'b0;
            sfence_vma_valid = 1'b0;
            sfence_vma_rs1_zero = 1'b0;
            sfence_vma_vaddr = 64'd0;
            sfence_vma_rs2_zero = 1'b0;
            sfence_vma_asid = 16'd0;
            scenario = 2'd0;
            checkpoint = 8'd0;
        end
    endtask

    task automatic set_root;
        input [15:0] asid;
        input [63:0] root_address;
        begin
            satp = (64'h8 << 60) |
                   ({48'd0, asid} << 44) |
                   (root_address >> 12);
        end
    endtask

    task automatic request_instruction;
        input [63:0] va;
        begin
            wait (i_ready);
            @(negedge CLK_I);
            i_vaddr = va;
            i_req = 1'b1;
            @(posedge CLK_I);
            @(negedge CLK_I);
            i_req = 1'b0;
            wait (i_done);
            @(posedge CLK_I);
            #1;
        end
    endtask

    task automatic request_data;
        input [63:0] va;
        input wr;
        input amo;
        begin
            wait (d_ready);
            @(negedge CLK_I);
            d_vaddr = va;
            d_write = wr;
            d_amo = amo;
            d_req = 1'b1;
            @(posedge CLK_I);
            @(negedge CLK_I);
            d_req = 1'b0;
            wait (d_done);
            @(posedge CLK_I);
            #1;
        end
    endtask

    task automatic do_sfence_all;
        begin
            wait (sfence_vma_ready);
            @(negedge CLK_I);
            sfence_vma_valid = 1'b1;
            sfence_vma_rs1_zero = 1'b1;
            sfence_vma_vaddr = 64'd0;
            sfence_vma_rs2_zero = 1'b1;
            sfence_vma_asid = 16'd0;
            @(posedge CLK_I);
            @(negedge CLK_I);
            sfence_vma_valid = 1'b0;
            wait (sfence_vma_done);
            @(posedge CLK_I);
            #1;
        end
    endtask


    // TEST 1
    // Instruction page walk and ITLB hit


    initial begin

        CLK_I = 1'b0;
        RST_I = 1'b0;
        satp = 64'd0;
        setup_common();
        clear_memory();

        // Root page table = 0x1000
        // L1 page table   = 0x2000
        // L0 page table   = 0x3000
        // VA page 1       -> PA page 8

        memory['h200] = make_pte(44'h2, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h400] = make_pte(44'h3, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h601] = make_pte(44'h8, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1);

        set_root(16'd1, 64'h0000_0000_0000_1000);
        reset_cpu();

        scenario = 2'd1;
        checkpoint = 8'd1;
        request_instruction(64'h0000_0000_0000_1100);

        checkpoint = 8'd2;
        repeat (4) @(posedge CLK_I);
        request_instruction(64'h0000_0000_0000_1200);

        repeat (10) @(posedge CLK_I);

    
        // TEST 2
        // Data walk, A/D update and PWC reuse
    

        clear_memory();

        memory['h200] = make_pte(44'h2, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h400] = make_pte(44'h3, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h601] = make_pte(44'h9, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h602] = make_pte(44'hA, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);

        set_root(16'd2, 64'h0000_0000_0000_1000);
        reset_cpu();

        scenario = 2'd2;
        checkpoint = 8'd11;
        request_data(64'h0000_0000_0000_1100, 1'b0, 1'b0);

        checkpoint = 8'd12;
        repeat (4) @(posedge CLK_I);
        request_data(64'h0000_0000_0000_1100, 1'b1, 1'b0);

        checkpoint = 8'd13;
        repeat (4) @(posedge CLK_I);
        request_data(64'h0000_0000_0000_2100, 1'b0, 1'b0);

        checkpoint = 8'd14;
        repeat (4) @(posedge CLK_I);
        request_data(64'h0000_0000_0000_2100, 1'b0, 1'b0);

        repeat (10) @(posedge CLK_I);

    
        // TEST 3
        // SFENCE.VMA and page-fault handling
    

        clear_memory();

        memory['h200] = make_pte(44'h2, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h400] = make_pte(44'h3, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        memory['h601] = make_pte(44'h8, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1);

        set_root(16'd3, 64'h0000_0000_0000_1000);
        reset_cpu();

        scenario = 2'd3;
        checkpoint = 8'd21;
        request_data(64'h0000_0000_0000_1100, 1'b0, 1'b0);

        checkpoint = 8'd22;
        memory['h601] = make_pte(44'hB, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1);
        do_sfence_all();

        checkpoint = 8'd23;
        request_data(64'h0000_0000_0000_1100, 1'b0, 1'b0);

        checkpoint = 8'd24;
        // Non-canonical virtual address must fault.
        request_data(64'h0000_8000_0000_0000, 1'b0, 1'b0);

        repeat (20) @(posedge CLK_I);

        $finish;

    end

    initial begin
        $dumpfile("Sim_Sv39.vcd");
        $dumpvars(0, Sim_Sv39);
    end

endmodule
