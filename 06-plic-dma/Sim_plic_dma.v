`timescale 1ns/1ps

module Sim_plic_dma;

    reg CLK_I;
    reg RST_I;
    reg [1:0] scenario;
    reg [7:0] checkpoint;

    // CPU WISHBONE INTERFACE

    reg [63:0] ADR_I;
    reg [63:0] DAT_I;
    wire [63:0] DAT_O;
    reg [7:0] SEL_I;

    reg CYC_I;
    reg STB_I;
    reg WE_I;

    wire ACK_O;
    wire ERR_O;


    // SHARED WISHBONE INTERFACE


    wire [63:0] WB_ADR_O;
    wire [63:0] WB_DAT_O;
    wire [63:0] WB_DAT_I;
    wire [7:0] WB_SEL_O;

    wire WB_CYC_O;
    wire WB_STB_O;
    wire WB_WE_O;

    reg WB_ACK_I;
    reg WB_ERR_I;


    // INTERRUPT INTERFACE

    reg [31:0] IRQ_SOURCES_I;
    wire PLIC_IRQ_O;
    wire [3:0] DMA_IRQ_O;

    // TESTBENCH MEMORY / DEBUG SIGNALS

    localparam [63:0] PLIC_BASE = 64'h0000_0000_0C00_0000;
    localparam [63:0] DMA_BASE  = 64'h0000_0000_1000_0000;
    localparam [63:0] MEM_BASE  = 64'h0000_0000_8000_0000;
    localparam [63:0] BAD_ADDR  = 64'h0000_0000_DEAD_0000;

    reg [63:0] memory [0:255];

    reg wb_served;
    reg wb_delay;

    integer memory_index;
    integer byte_index;
    
    integer reset_index;
    integer timeout_count;

    reg [31:0] wb_transaction_count;
    reg [31:0] wb_read_count;
    reg [31:0] wb_write_count;
    reg [31:0] wb_error_count;

    reg [63:0] read_value;
    reg transaction_error;
    reg transaction_timeout;

    wire [63:0] dbg_mem_src0;
    wire [63:0] dbg_mem_dst0;
    wire [63:0] dbg_mem_dst1;
    wire [63:0] dbg_mem_dst2;
    wire [63:0] dbg_mem_desc0;
    wire [63:0] dbg_mem_desc_dst0;
    wire [63:0] dbg_mem_desc_dst1;

    wire dbg_engine_start;
    wire dbg_engine_busy;
    wire dbg_engine_done;
    wire dbg_engine_error;
    wire [63:0] dbg_engine_src;
    wire [63:0] dbg_engine_dst;
    wire [63:0] dbg_engine_length;

    wire dbg_descriptor_start;
    wire dbg_descriptor_busy;
    wire dbg_descriptor_valid;
    wire dbg_descriptor_error;
    wire [63:0] dbg_descriptor_address;

    wire [31:0] dbg_plic_pending;
    wire [31:0] dbg_plic_enable;
    wire [5:0] dbg_plic_claim_id;
    wire [2:0] dbg_plic_threshold;

    assign dbg_mem_src0 = memory[0];
    assign dbg_mem_dst0 = memory[16];
    assign dbg_mem_dst1 = memory[17];
    assign dbg_mem_dst2 = memory[18];
    assign dbg_mem_desc0 = memory[32];
    assign dbg_mem_desc_dst0 = memory[80];
    assign dbg_mem_desc_dst1 = memory[81];

    assign dbg_engine_start = dut.engine_start;
    assign dbg_engine_busy = dut.engine_busy;
    assign dbg_engine_done = dut.engine_done;
    assign dbg_engine_error = dut.engine_error;
    assign dbg_engine_src = dut.engine_src;
    assign dbg_engine_dst = dut.engine_dst;
    assign dbg_engine_length = dut.engine_length;

    assign dbg_descriptor_start = dut.descriptor_start;
    assign dbg_descriptor_busy = dut.descriptor_busy;
    assign dbg_descriptor_valid = dut.descriptor_valid;
    assign dbg_descriptor_error = dut.descriptor_error;
    assign dbg_descriptor_address = dut.descriptor_address;

    assign dbg_plic_pending = dut.plic_unit.irq_pending;
    assign dbg_plic_enable = dut.plic_unit.irq_enable;
    assign dbg_plic_claim_id = dut.plic_unit.claim_id;
    assign dbg_plic_threshold = dut.plic_unit.threshold;


    // DEVICE UNDER TEST


    plic_dma dut (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(ADR_I),
        .DAT_I(DAT_I),
        .DAT_O(DAT_O),
        .SEL_I(SEL_I),
        .CYC_I(CYC_I),
        .STB_I(STB_I),
        .WE_I(WE_I),
        .ACK_O(ACK_O),
        .ERR_O(ERR_O),
        .WB_ADR_O(WB_ADR_O),
        .WB_DAT_O(WB_DAT_O),
        .WB_DAT_I(WB_DAT_I),
        .WB_SEL_O(WB_SEL_O),
        .WB_CYC_O(WB_CYC_O),
        .WB_STB_O(WB_STB_O),
        .WB_WE_O(WB_WE_O),
        .WB_ACK_I(WB_ACK_I),
        .WB_ERR_I(WB_ERR_I),
        .IRQ_SOURCES_I(IRQ_SOURCES_I),
        .PLIC_IRQ_O(PLIC_IRQ_O),
        .DMA_IRQ_O(DMA_IRQ_O)
    );

    // CLOCK GENERATION

    initial begin
        CLK_I = 1'b0;
        forever #5 CLK_I = ~CLK_I;
    end

    // EXTERNAL WISHBONE MEMORY MODEL

    assign WB_DAT_I = memory[WB_ADR_O[10:3]];

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin
            WB_ACK_I <= 1'b0;
            WB_ERR_I <= 1'b0;
            wb_served <= 1'b0;
            wb_delay <= 1'b0;
            wb_transaction_count <= 32'd0;
            wb_read_count <= 32'd0;
            wb_write_count <= 32'd0;
            wb_error_count <= 32'd0;
        end

        else begin

            WB_ACK_I <= 1'b0;
            WB_ERR_I <= 1'b0;

            if (!WB_CYC_O || !WB_STB_O) begin
                wb_served <= 1'b0;
                wb_delay <= 1'b0;
        
            end
            else if (!wb_served) begin


                if (!wb_delay) begin
                    wb_delay <= 1'b1;
                end

                else begin

                    wb_transaction_count <= wb_transaction_count + 32'd1;
                    wb_served <= 1'b1;
                    wb_delay <= 1'b0;

                    if (WB_ADR_O == BAD_ADDR) begin
                        WB_ERR_I <= 1'b1;
                        wb_error_count <= wb_error_count + 32'd1;
                    end

                    else begin
                        WB_ACK_I <= 1'b1;

                        if (WB_WE_O) begin

                            wb_write_count <= wb_write_count + 32'd1;
                            memory_index = WB_ADR_O[10:3];

                            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin

                                if (WB_SEL_O[byte_index]) begin
                                    memory[memory_index][byte_index*8 +: 8] <=
                                        WB_DAT_O[byte_index*8 +: 8];
                                end

                            end
                        end

                        else begin
                            wb_read_count <= wb_read_count + 32'd1;
                        end
                    end
                end


            end
        end
    end


    // WISHBONE CPU ACCESS TASKS


    task cpu_write;

        input [63:0] address;
        input [63:0] data;
        integer wait_cycles;

        reg completed;

        begin

            @(negedge CLK_I);

            ADR_I = address;
            DAT_I = data;
            SEL_I = 8'hFF;
            WE_I = 1'b1;
            CYC_I = 1'b1;
            STB_I = 1'b1;
            transaction_error = 1'b0;
            transaction_timeout = 1'b0;
            completed = 1'b0;
            wait_cycles = 0;

            while (!completed && wait_cycles < 200) begin

                @(posedge CLK_I);
                #1;

                if (ACK_O === 1'b1) begin
                    completed = 1'b1;
                end

                else if (ERR_O === 1'b1) begin
                    completed = 1'b1;
                    transaction_error = 1'b1;

                end

                wait_cycles = wait_cycles + 1;
            end


            if (!completed) begin
                transaction_timeout = 1'b1;
                timeout_count = timeout_count + 1;
            end

            @(negedge CLK_I);

            CYC_I = 1'b0;
            STB_I = 1'b0;
            WE_I = 1'b0;
            SEL_I = 8'd0;

            @(negedge CLK_I);

        end
    endtask


    task cpu_read;

        input [63:0] address;
        integer wait_cycles;
        reg completed;

        begin

            @(negedge CLK_I);

            ADR_I = address;
            DAT_I = 64'd0;
            SEL_I = 8'hFF;
            WE_I = 1'b0;
            CYC_I = 1'b1;
            STB_I = 1'b1;

            transaction_error = 1'b0;
            transaction_timeout = 1'b0;
            read_value = 64'd0;
            completed = 1'b0;
            wait_cycles = 0;

            while (!completed && wait_cycles < 200) begin

                @(posedge CLK_I);
                #1;

                if (ACK_O === 1'b1) begin
                    read_value = DAT_O;
                    completed = 1'b1;

                end

                else if (ERR_O === 1'b1) begin
                    completed = 1'b1;
                    transaction_error = 1'b1;
                end

                wait_cycles = wait_cycles + 1;
            end


            if (!completed) begin
                transaction_timeout = 1'b1;
                timeout_count = timeout_count + 1;
            end

            @(negedge CLK_I);

            CYC_I = 1'b0;
            STB_I = 1'b0;
            WE_I = 1'b0;
            SEL_I = 8'd0;
            @(negedge CLK_I);

        end

    endtask

    task wait_for_dma_done;

        input [63:0] status_address;
        integer wait_cycles;
        reg completed;

        begin

            wait_cycles = 0;
            completed = 1'b0;

            while (!completed && wait_cycles < 200) begin

                cpu_read(status_address);

                if (!transaction_error && !transaction_timeout && (read_value[1] || read_value[2])) begin
                    completed = 1'b1;

                end

                wait_cycles = wait_cycles + 1;

            end

            if (!completed) begin
                transaction_timeout = 1'b1;
                timeout_count = timeout_count + 1;

            end

        end

    endtask

    // TEST SEQUENCE / VCD OUTPUT

    initial begin

        $dumpfile("Sim_plic_dma.vcd");
        $dumpvars(0, Sim_plic_dma);

        RST_I = 1'b1;
        scenario = 2'd0;
        checkpoint = 8'd0;
        ADR_I = 64'd0;
        DAT_I = 64'd0;
        SEL_I = 8'd0;
        CYC_I = 1'b0;
        STB_I = 1'b0;
        WE_I = 1'b0;

        IRQ_SOURCES_I = 32'd0;
        read_value = 64'd0;
        transaction_error = 1'b0;
        transaction_timeout = 1'b0;
        timeout_count = 0;

        for (reset_index = 0; reset_index < 256; reset_index = reset_index + 1) begin
            memory[reset_index] = 64'd0;
        end

        repeat (5) @(posedge CLK_I);
        @(negedge CLK_I);
        RST_I = 1'b0;
        repeat (3) @(posedge CLK_I);

    
        // SCENARIO 1
        // PLIC PRIORITY / PENDING / CLAIM
    

        scenario = 2'd1;
        checkpoint = 8'd1;

        cpu_write(PLIC_BASE + 64'h28, 64'd3);
        cpu_write(PLIC_BASE + 64'h2000, 64'h20);
        cpu_write(PLIC_BASE + 64'h200000, 64'd0);
        IRQ_SOURCES_I[5] = 1'b1;
        repeat (6) @(posedge CLK_I);
   
        checkpoint = 8'd2;
        cpu_read(PLIC_BASE + 64'h1000);
        IRQ_SOURCES_I[5] = 1'b0;
        repeat (5) @(posedge CLK_I);
   
        checkpoint = 8'd3;
        cpu_read(PLIC_BASE + 64'h200008);
        checkpoint = 8'd4;
        repeat (5) @(posedge CLK_I);

    
        // SCENARIO 2
        // DMA DATA COPY / BYTE ENABLE / COMPLETION IRQ
    

        scenario = 2'd2;
        checkpoint = 8'd10;

        cpu_write(MEM_BASE + 64'h000, 64'h0123_4567_89AB_CDEF);
        cpu_write(MEM_BASE + 64'h008, 64'h1020_3040_5060_7080);
        cpu_write(MEM_BASE + 64'h010, 64'hFEDC_BA98_7654_3210);
        cpu_write(DMA_BASE + 64'h00, MEM_BASE);
        cpu_write(DMA_BASE + 64'h08, MEM_BASE + 64'h80);
        cpu_write(DMA_BASE + 64'h10, 64'd19);
        cpu_write(DMA_BASE + 64'h18, 64'd1);
   
        wait_for_dma_done(DMA_BASE + 64'h20);
        checkpoint = 8'd11;
        cpu_read(MEM_BASE + 64'h80);
        cpu_read(MEM_BASE + 64'h88);
        cpu_read(MEM_BASE + 64'h90);
   
        checkpoint = 8'd12;
        cpu_write(DMA_BASE + 64'h30, 64'd1);
        repeat (5) @(posedge CLK_I);

    
        // SCENARIO 3
        // DESCRIPTOR DMA / PLIC ROUTING / ERROR HANDLING
    

        scenario = 2'd3;
        checkpoint = 8'd20;

        cpu_write(PLIC_BASE + 64'h10, 64'd4);
        cpu_write(PLIC_BASE + 64'h2000, 64'h4);
        cpu_write(PLIC_BASE + 64'h200000, 64'd0);

        cpu_write(MEM_BASE + 64'h200, 64'hA1A2_A3A4_A5A6_A7A8);
        cpu_write(MEM_BASE + 64'h208, 64'hB1B2_B3B4_B5B6_B7B8);
        cpu_write(MEM_BASE + 64'h100, MEM_BASE + 64'h200);
        cpu_write(MEM_BASE + 64'h108, MEM_BASE + 64'h280);
        cpu_write(MEM_BASE + 64'h110, 64'd16);
        cpu_write(MEM_BASE + 64'h118, 64'd0);
        cpu_write(MEM_BASE + 64'h120, 64'd0);

        cpu_write(DMA_BASE + 64'h68, MEM_BASE + 64'h100);
        cpu_write(DMA_BASE + 64'h58, 64'd3);
        wait_for_dma_done(DMA_BASE + 64'h60);
        checkpoint = 8'd21;
        repeat (6) @(posedge CLK_I);
        cpu_read(MEM_BASE + 64'h280);
        cpu_read(MEM_BASE + 64'h288);
        cpu_write(DMA_BASE + 64'h70, 64'd1);
        repeat (5) @(posedge CLK_I);
        cpu_read(PLIC_BASE + 64'h200008);
        checkpoint = 8'd22;

        cpu_write(DMA_BASE + 64'h80, MEM_BASE);
        cpu_write(DMA_BASE + 64'h88, MEM_BASE + 64'h180);
        cpu_write(DMA_BASE + 64'h90, 64'd0);
        cpu_write(DMA_BASE + 64'h98, 64'd1);
        wait_for_dma_done(DMA_BASE + 64'hA0);
        checkpoint = 8'd23;
        cpu_read(DMA_BASE + 64'hA0);
        cpu_read(BAD_ADDR);
        checkpoint = 8'd24;

        repeat (10) @(posedge CLK_I);
        $finish;

    end

endmodule