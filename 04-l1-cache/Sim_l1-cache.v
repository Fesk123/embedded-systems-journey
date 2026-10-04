`timescale 1ns/1ps


// L1 CACHE WAVEFORM TESTBENCH
// Three documentation scenarios for GTKWave
//
// Scenario 1 shows instruction refill and instruction cache hit.
// Scenario 2 shows data refill, data hit, store and AMO activity.
// Scenario 3 shows dirty writeback, instruction invalidation and an uncached access.

module Sim_L1_Cache;

    localparam ADDR_WIDTH = 64;
    localparam DATA_WIDTH = 64;
    localparam [63:0] BAD_ADDRESS = 64'h0000_0000_DEAD_DEAD;

    reg CLK_I;
    reg RST_I;

    
    // SCENARIO MARKERS
    

    reg [3:0] scenario;
    reg [7:0] checkpoint;

    
    // INSTRUCTION CACHE INTERFACE
    

    reg i_req;
    reg [ADDR_WIDTH-1:0] i_paddr;
    wire i_ready;
    wire i_done;
    wire [31:0] i_rdata;
    wire i_fault;
    reg i_invalidate;

    
    // DATA CACHE INTERFACE
    

    reg d_req;
    reg d_write;
    reg d_amo;
    reg d_lr;
    reg d_sc;
    reg d_amo_word;
    reg [4:0] d_amo_op;
    reg [ADDR_WIDTH-1:0] d_paddr;
    reg [DATA_WIDTH-1:0] d_wdata;
    reg [DATA_WIDTH/8-1:0] d_sel;
    reg d_cacheable;

    wire d_ready;
    wire d_done;
    wire [DATA_WIDTH-1:0] d_rdata;
    wire d_fault;
    wire [DATA_WIDTH-1:0] d_amo_old_data;
    wire d_sc_success;
    reg d_flush;

    
    // INSTRUCTION WISHBONE
    

    wire [ADDR_WIDTH-1:0] I_ADR_O;
    wire [DATA_WIDTH-1:0] I_DAT_O;
    reg [DATA_WIDTH-1:0] I_DAT_I;
    wire [DATA_WIDTH/8-1:0] I_SEL_O;
    wire I_CYC_O;
    wire I_STB_O;
    wire I_WE_O;
    wire [2:0] I_CTI_O;
    wire [1:0] I_BTE_O;
    reg I_ACK_I;
    reg I_ERR_I;

    
    // DATA WISHBONE
    

    wire [ADDR_WIDTH-1:0] D_ADR_O;
    wire [DATA_WIDTH-1:0] D_DAT_O;
    reg [DATA_WIDTH-1:0] D_DAT_I;
    wire [DATA_WIDTH/8-1:0] D_SEL_O;
    wire D_CYC_O;
    wire D_STB_O;
    wire D_WE_O;
    wire [2:0] D_CTI_O;
    wire [1:0] D_BTE_O;
    reg D_ACK_I;
    reg D_ERR_I;

    
    // DEBUG
    

    wire [3:0] debug_i_state;
    wire [3:0] debug_d_state;
    wire debug_i_hit;
    wire debug_d_hit;
    wire debug_i_miss;
    wire debug_d_miss;
    wire debug_i_refill;
    wire debug_d_refill;
    wire debug_d_writeback;
    wire debug_d_uncached;
    wire [6:0] debug_i_set;
    wire [6:0] debug_d_set;
    wire [1:0] debug_i_way;
    wire [1:0] debug_d_way;

    
    // MEMORY MODEL
    

    reg [63:0] memory [0:16383];
    integer I_memory_index;
    integer D_memory_index;
    integer i;

    always @(*) begin

        I_ACK_I = 1'b0;
        I_ERR_I = 1'b0;
        I_DAT_I = 64'd0;

        if (I_CYC_O && I_STB_O) begin
            if (I_ADR_O == BAD_ADDRESS) begin
                I_ERR_I = 1'b1;
            end
            else begin
                I_memory_index = I_ADR_O[16:3];
                I_ACK_I = 1'b1;
                I_DAT_I = memory[I_memory_index];
            end
        end

    end

    always @(*) begin

        D_ACK_I = 1'b0;
        D_ERR_I = 1'b0;
        D_DAT_I = 64'd0;

        if (D_CYC_O && D_STB_O) begin
            if (D_ADR_O == BAD_ADDRESS) begin
                D_ERR_I = 1'b1;
            end
            else begin
                D_memory_index = D_ADR_O[16:3];
                D_ACK_I = 1'b1;
                D_DAT_I = memory[D_memory_index];
            end
        end

    end

    always @(posedge CLK_I) begin

        if (D_CYC_O && D_STB_O && D_WE_O && !D_ERR_I)
            memory[D_ADR_O[16:3]] <= D_DAT_O;

    end

    
    // DEVICE UNDER TEST
    

    L1_Cache dut (

        .CLK_I(CLK_I),
        .RST_I(RST_I),

        .i_req(i_req),
        .i_paddr(i_paddr),
        .i_ready(i_ready),
        .i_done(i_done),
        .i_rdata(i_rdata),
        .i_fault(i_fault),
        .i_invalidate(i_invalidate),

        .d_req(d_req),
        .d_write(d_write),
        .d_amo(d_amo),
        .d_lr(d_lr),
        .d_sc(d_sc),
        .d_amo_word(d_amo_word),
        .d_amo_op(d_amo_op),
        .d_paddr(d_paddr),
        .d_wdata(d_wdata),
        .d_sel(d_sel),
        .d_cacheable(d_cacheable),
        .d_ready(d_ready),
        .d_done(d_done),
        .d_rdata(d_rdata),
        .d_fault(d_fault),
        .d_amo_old_data(d_amo_old_data),
        .d_sc_success(d_sc_success),
        .d_flush(d_flush),

        .I_ADR_O(I_ADR_O),
        .I_DAT_O(I_DAT_O),
        .I_DAT_I(I_DAT_I),
        .I_SEL_O(I_SEL_O),
        .I_CYC_O(I_CYC_O),
        .I_STB_O(I_STB_O),
        .I_WE_O(I_WE_O),
        .I_CTI_O(I_CTI_O),
        .I_BTE_O(I_BTE_O),
        .I_ACK_I(I_ACK_I),
        .I_ERR_I(I_ERR_I),

        .D_ADR_O(D_ADR_O),
        .D_DAT_O(D_DAT_O),
        .D_DAT_I(D_DAT_I),
        .D_SEL_O(D_SEL_O),
        .D_CYC_O(D_CYC_O),
        .D_STB_O(D_STB_O),
        .D_WE_O(D_WE_O),
        .D_CTI_O(D_CTI_O),
        .D_BTE_O(D_BTE_O),
        .D_ACK_I(D_ACK_I),
        .D_ERR_I(D_ERR_I),

        .debug_i_state(debug_i_state),
        .debug_d_state(debug_d_state),
        .debug_i_hit(debug_i_hit),
        .debug_d_hit(debug_d_hit),
        .debug_i_miss(debug_i_miss),
        .debug_d_miss(debug_d_miss),
        .debug_i_refill(debug_i_refill),
        .debug_d_refill(debug_d_refill),
        .debug_d_writeback(debug_d_writeback),
        .debug_d_uncached(debug_d_uncached),
        .debug_i_set(debug_i_set),
        .debug_d_set(debug_d_set),
        .debug_i_way(debug_i_way),
        .debug_d_way(debug_d_way)

    );

    
    // CLOCK
    

    initial begin
        CLK_I = 1'b0;
        forever #5 CLK_I = ~CLK_I;
    end

    
    // TEST HELPERS
    

    task instruction_read;
        input [63:0] address;
        begin

            while (!i_ready)
                @(posedge CLK_I);

            @(negedge CLK_I);
            i_paddr = address;
            i_req = 1'b1;

            @(posedge CLK_I);
            #1;
            i_req = 1'b0;

            while (!i_done && !i_fault)
                @(posedge CLK_I);

        end
    endtask

    task data_read;
        input [63:0] address;
        input cacheable_value;
        begin

            while (!d_ready)
                @(posedge CLK_I);

            @(negedge CLK_I);
            d_paddr = address;
            d_write = 1'b0;
            d_amo = 1'b0;
            d_lr = 1'b0;
            d_sc = 1'b0;
            d_amo_word = 1'b0;
            d_amo_op = 5'd0;
            d_wdata = 64'd0;
            d_sel = 8'hFF;
            d_cacheable = cacheable_value;
            d_req = 1'b1;

            @(posedge CLK_I);
            #1;
            d_req = 1'b0;

            while (!d_done && !d_fault)
                @(posedge CLK_I);

        end
    endtask

    task data_store;
        input [63:0] address;
        input [63:0] write_value;
        input cacheable_value;
        begin

            while (!d_ready)
                @(posedge CLK_I);

            @(negedge CLK_I);
            d_paddr = address;
            d_write = 1'b1;
            d_amo = 1'b0;
            d_lr = 1'b0;
            d_sc = 1'b0;
            d_amo_word = 1'b0;
            d_amo_op = 5'd0;
            d_wdata = write_value;
            d_sel = 8'hFF;
            d_cacheable = cacheable_value;
            d_req = 1'b1;

            @(posedge CLK_I);
            #1;
            d_req = 1'b0;

            while (!d_done && !d_fault)
                @(posedge CLK_I);

        end
    endtask

    task amo_add;
        input [63:0] address;
        input [63:0] write_value;
        begin

            while (!d_ready)
                @(posedge CLK_I);

            @(negedge CLK_I);
            d_paddr = address;
            d_write = 1'b1;
            d_amo = 1'b1;
            d_lr = 1'b0;
            d_sc = 1'b0;
            d_amo_word = 1'b0;
            d_amo_op = 5'b00000;
            d_wdata = write_value;
            d_sel = 8'hFF;
            d_cacheable = 1'b1;
            d_req = 1'b1;

            @(posedge CLK_I);
            #1;
            d_req = 1'b0;

            while (!d_done && !d_fault)
                @(posedge CLK_I);

        end
    endtask

    task invalidate_instruction_cache;
        begin

            @(negedge CLK_I);
            i_invalidate = 1'b1;

            @(posedge CLK_I);
            #1;
            i_invalidate = 1'b0;

            while (!i_ready)
                @(posedge CLK_I);

        end
    endtask

    
    // WAVEFORM TEST PROGRAM
    

    initial begin

        $dumpfile("Sim_l1_cache.vcd");
        $dumpvars(0, Sim_L1_Cache);

        i_req = 1'b0;
        i_paddr = 64'd0;
        i_invalidate = 1'b0;

        d_req = 1'b0;
        d_write = 1'b0;
        d_amo = 1'b0;
        d_lr = 1'b0;
        d_sc = 1'b0;
        d_amo_word = 1'b0;
        d_amo_op = 5'd0;
        d_paddr = 64'd0;
        d_wdata = 64'd0;
        d_sel = 8'hFF;
        d_cacheable = 1'b1;
        d_flush = 1'b0;

        scenario = 4'd0;
        checkpoint = 8'd0;

        for (i = 0; i < 16384; i = i + 1)
            memory[i] = 64'd0;

        // Instruction data.
        memory[64'h0000_0100 >> 3] = 64'h1122334455667788;
        memory[64'h0000_0108 >> 3] = 64'h99AABBCCDDEEFF00;

        // Data data.
        memory[64'h0000_0200 >> 3] = 64'h0102030405060708;
        memory[64'h0000_0208 >> 3] = 64'h1112131415161718;
        memory[64'h0000_1000 >> 3] = 64'h0000000000000005;
        memory[64'h0000_0000 >> 3] = 64'h0000000000000010;
        memory[64'h0000_2000 >> 3] = 64'h0000000000000020;
        memory[64'h0000_4000 >> 3] = 64'h0000000000000030;
        memory[64'h0000_6000 >> 3] = 64'h0000000000000040;
        memory[64'h0000_8000 >> 3] = 64'h0000000000000050;
        memory[64'h0001_0000 >> 3] = 64'hDEADBEEFCAFEBABE;

        RST_I = 1'b1;
        repeat (3) @(posedge CLK_I);
        RST_I = 1'b0;
        repeat (2) @(posedge CLK_I);

        
        // SCENARIO 1
        // Instruction refill and hit
        

        scenario = 4'd1;
        checkpoint = 8'd1;

        instruction_read(64'h0000_0100);

        checkpoint = 8'd2;

        instruction_read(64'h0000_0104);

        repeat (4) @(posedge CLK_I);

        
        // SCENARIO 2
        // Data refill, hit, store and AMO
        

        scenario = 4'd2;
        checkpoint = 8'd3;

        data_read(64'h0000_0200, 1'b1);

        checkpoint = 8'd4;

        data_read(64'h0000_0208, 1'b1);

        checkpoint = 8'd5;

        data_store(64'h0000_0200, 64'hAABBCCDDEEFF0011, 1'b1);

        checkpoint = 8'd6;

        data_read(64'h0000_0200, 1'b1);

        checkpoint = 8'd7;

        amo_add(64'h0000_1000, 64'd3);

        repeat (4) @(posedge CLK_I);

        
        // SCENARIO 3
        // Dirty writeback and invalidation
        

        scenario = 4'd3;
        checkpoint = 8'd8;

        data_read(64'h0000_0000, 1'b1);
        data_read(64'h0000_2000, 1'b1);
        data_read(64'h0000_4000, 1'b1);
        data_read(64'h0000_6000, 1'b1);

        checkpoint = 8'd9;

        data_store(64'h0000_0000, 64'h1111222233334444, 1'b1);
        data_read(64'h0000_8000, 1'b1);

        checkpoint = 8'd10;

        memory[64'h0000_0100 >> 3] = 64'hABCDEF0123456789;
        instruction_read(64'h0000_0100);

        checkpoint = 8'd11;

        invalidate_instruction_cache;
        instruction_read(64'h0000_0100);

        checkpoint = 8'd12;

        data_read(64'h0001_0000, 1'b0);

        repeat (10) @(posedge CLK_I);

        $finish;

    end

endmodule
