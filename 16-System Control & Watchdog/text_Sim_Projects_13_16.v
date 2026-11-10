`timescale 1ns/1ps


// EXTENSIVE TEXT-BASED TESTBENCH
// Projects 13-16: Memory, Protection, CDC and System Control
//
// This testbench instantiates and tests every RTL module in the four project groups. 
// It intentionally uses independent clocks, variable response latency, backpressure, bus errors, reset events, partial accesses, overlapping regions and boundary conditions.

module text_Sim_Projects_13_16;

    wire done_pma, done_pmp, done_pmu, done_fifo_cdc;
    wire done_maint, done_l2, done_bridge, done_watchdog;
    wire [31:0] fail_pma, fail_pmp, fail_pmu, fail_fifo_cdc;
    wire [31:0] fail_maint, fail_l2, fail_bridge, fail_watchdog;

    PMA_Test test_pma(done_pma, fail_pma);
    PMP_Test test_pmp(done_pmp, fail_pmp);
    PMU_Test test_pmu(done_pmu, fail_pmu);
    FIFO_CDC_Test test_fifo_cdc(done_fifo_cdc, fail_fifo_cdc);
    Cache_Maint_Test test_maint(done_maint, fail_maint);
    L2_Cache_Test test_l2(done_l2, fail_l2);
    AXI_Bridge_Test test_bridge(done_bridge, fail_bridge);
    Watchdog_Test test_watchdog(done_watchdog, fail_watchdog);

    integer total_failures;
    integer total_tests;

    initial begin
        total_failures = 0;
        total_tests = 0;
        $display("============================================================");
        $display("PROJECTS 13-16: EXTENSIVE RTL TEST SUITE STARTED");
        $display("============================================================");

        wait (done_pma && done_pmp && done_pmu && done_fifo_cdc && done_maint && done_l2 && done_bridge && done_watchdog);
        #20;

        total_failures = fail_pma + fail_pmp + fail_pmu + fail_fifo_cdc + fail_maint + fail_l2 + fail_bridge + fail_watchdog;
        total_tests = 8;

        $display("------------------------------------------------------------");
        $display("GROUP RESULTS");
        $display("PMA                  failures: %0d", fail_pma);
        $display("PMP                  failures: %0d", fail_pmp);
        $display("PMU                  failures: %0d", fail_pmu);
        $display("Async FIFO + CDC     failures: %0d", fail_fifo_cdc);
        $display("Cache maintenance    failures: %0d", fail_maint);
        $display("L2 cache             failures: %0d", fail_l2);
        $display("Wishbone/AXI4 bridge failures: %0d", fail_bridge);
        $display("Watchdog             failures: %0d", fail_watchdog);
        $display("------------------------------------------------------------");
        if (total_failures == 0)
            $display("ALL %0d TEST GROUPS PASSED", total_tests);
        else
            $display("TEST SUITE FAILED: %0d TOTAL FAILURE(S)", total_failures);
        $display("============================================================");
        $finish;
    end

    initial begin
        #20000000;
        $display("FATAL: GLOBAL TESTBENCH TIMEOUT");
        $finish;
    end

endmodule



// 13 - PMA CHECKER

module PMA_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg [63:0] paddr;
    reg [2:0] size;
    reg request;
    reg read_access;
    reg write_access;
    reg execute_access;
    wire access_fault;
    wire cacheable;
    wire idempotent;
    wire executable;
    wire device;
    wire [5:0] attributes;
    integer checks;

    PMA_Checker #(
        .REGION0_BASE(64'h0000_0000_0000_1000),
        .REGION0_MASK(64'hFFFF_FFFF_FFFF_F000),
        .REGION0_ATTR(6'b111000),
        .REGION1_BASE(64'h0000_0000_0000_2000),
        .REGION1_MASK(64'hFFFF_FFFF_FFFF_F000),
        .REGION1_ATTR(6'b011111),
        .REGION2_BASE(64'h0000_0000_0000_3000),
        .REGION2_MASK(64'hFFFF_FFFF_FFFF_F000),
        .REGION2_ATTR(6'b010101),
        .REGION3_BASE(64'h0000_0000_0000_0000),
        .REGION3_MASK(64'hFFFF_FFFF_FFFF_8000),
        .REGION3_ATTR(6'b011011),
        .REGION4_BASE(64'h0000_0000_0000_0000),
        .REGION4_MASK(64'hFFFF_FFFF_FFFF_FFFF),
        .REGION4_ATTR(6'b000000)
    ) dut (
        .paddr_i(paddr), .size_i(size), .request_i(request),
        .read_i(read_access), .write_i(write_access), .execute_i(execute_access),
        .access_fault_o(access_fault), .cacheable_o(cacheable),
        .idempotent_o(idempotent), .executable_o(executable),
        .device_o(device), .attributes_o(attributes)
    );

    task check;

        input expected_fault;
        input [5:0] expected_attr;
        input [511:0] label_text;
        
        begin
            #1;
            checks = checks + 1;
            if ((access_fault !== expected_fault) || (attributes !== expected_attr)) begin
                FAILURES_O = FAILURES_O + 1;
                $display("FAIL PMA: %0s fault=%b attr=%b expected_fault=%b expected_attr=%b", label_text, access_fault, attributes, expected_fault, expected_attr);
            end
            else
                $display("PASS PMA: %0s", label_text);
        end
    endtask

    task check_fault_only;
        input expected_fault;
        input [511:0] label_text;

        begin
            #1;
            checks = checks + 1;
            if (access_fault !== expected_fault) begin
                FAILURES_O = FAILURES_O + 1;
                $display("FAIL PMA: %0s fault=%b expected_fault=%b", label_text, access_fault, expected_fault);
            end
            else
                $display("PASS PMA: %0s", label_text);
        end
    endtask

    initial begin
        DONE_O = 1'b0;
        FAILURES_O = 0;
        checks = 0;
        paddr = 0; size = 0; request = 0;
        read_access = 0; write_access = 0; execute_access = 0;
        #5;

        paddr = 64'h1000; size = 3; request = 1; read_access = 1;
        check(1'b0, 6'b111000, "device region permits 8-byte read");
        if (cacheable !== 1'b0 || device !== 1'b1 || executable !== 1'b0) begin
            FAILURES_O = FAILURES_O + 1;
            $display("FAIL PMA: device/cache/execute attribute outputs");
        end

        write_access = 1; read_access = 0;
        check(1'b0, 6'b111000, "device region permits write");
        execute_access = 1; write_access = 0;
        check(1'b1, 6'b111000, "device region rejects instruction fetch");

        paddr = 64'h2000; size = 3; read_access = 1; execute_access = 0;
        check(1'b0, 6'b011111, "specific PMA region overrides broad overlapping region");

        if (cacheable !== 1'b1 || idempotent !== 1'b1 || device !== 1'b0) begin
            FAILURES_O = FAILURES_O + 1;
            $display("FAIL PMA: normal-memory attribute outputs");
        end
        
        write_access = 1;
        check(1'b0, 6'b011111, "normal memory region permits write");
        execute_access = 1;
        check(1'b0, 6'b011111, "normal memory region permits execute");

        paddr = 64'h3000; size = 2; read_access = 1; write_access = 0; execute_access = 0;
        check(1'b0, 6'b010101, "read-only executable region permits read");
        write_access = 1;
        check(1'b1, 6'b010101, "read-only region rejects write");

        paddr = 64'h1FFC; size = 3; read_access = 1; write_access = 0;
        check_fault_only(1'b1, "access crossing a high-priority PMA subregion faults");

        paddr = 64'h7FF8; size = 3; read_access = 1;
        check(1'b0, 6'b011011, "last 8-byte access inside broad PMA region");
        paddr = 64'h7FFC; size = 3;
        check(1'b1, 6'b000000, "access crossing broad PMA region end faults");

        paddr = 64'h9000; size = 0;
        check(1'b1, 6'b000000, "unmapped physical address faults");

        paddr = 64'h2000; size = 4;
        check(1'b1, 6'b011111, "unsupported 16-byte access size faults");

        paddr = 64'hFFFF_FFFF_FFFF_FFFE; size = 2;
        check(1'b1, 6'b000000, "physical address overflow faults");

        request = 0; read_access = 0; write_access = 0; execute_access = 0;
        paddr = 64'hDEAD_BEEF; size = 7;
        check(1'b0, 6'b000000, "inactive PMA request never faults");

        $display("PMA TESTS COMPLETE: %0d checks, %0d failures", checks, FAILURES_O);
        DONE_O = 1'b1;
    end
endmodule



// 14 - PMP RV64

module PMP_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg clk, rst;
    reg [11:0] csr_addr;
    reg [63:0] csr_wdata;
    reg csr_we;
    wire [63:0] csr_rdata;
    reg access_valid;
    reg [63:0] access_addr;
    reg [2:0] access_size;
    reg access_read, access_write, access_execute;
    reg [1:0] privilege;
    wire access_allow, access_matched;
    wire [4:0] access_entry;
    integer checks;

    PMP_RV64 #(.PMP_ENTRIES(16)) dut (
        .CLK_I(clk), .RST_I(rst),
        .CSR_ADDR_I(csr_addr), .CSR_WDATA_I(csr_wdata), .CSR_WE_I(csr_we),
        .CSR_RDATA_O(csr_rdata),
        .ACCESS_VALID_I(access_valid), .ACCESS_ADDR_I(access_addr),
        .ACCESS_SIZE_I(access_size), .ACCESS_READ_I(access_read),
        .ACCESS_WRITE_I(access_write), .ACCESS_EXECUTE_I(access_execute),
        .PRIVILEGE_I(privilege), .ACCESS_ALLOW_O(access_allow),
        .ACCESS_MATCHED_O(access_matched), .ACCESS_ENTRY_O(access_entry)
    );

    always #5 clk = ~clk;

    task write_csr;
        input [11:0] address;
        input [63:0] value;
        begin
            @(negedge clk); csr_addr = address; csr_wdata = value; csr_we = 1;
            @(negedge clk); csr_we = 0; csr_wdata = 0;
            #1;
        end
    endtask

    task check_access;
        input [63:0] address;
        input [2:0] bytes_log2;
        input [1:0] mode;
        input rd, wr, ex;
        input expected_allow, expected_match;
        input [4:0] expected_entry;
        input [511:0] label_text;
        begin
            access_addr = address; access_size = bytes_log2; privilege = mode;
            access_read = rd; access_write = wr; access_execute = ex;
            access_valid = 1;
            #1;
            checks = checks + 1;
            if (access_allow !== expected_allow || access_matched !== expected_match || (expected_match && access_entry !== expected_entry)) begin
                FAILURES_O = FAILURES_O + 1;
                $display("FAIL PMP: %0s allow=%b matched=%b entry=%0d expected=%b/%b/%0d", label_text, access_allow, access_matched, access_entry, expected_allow, expected_match, expected_entry);
            end
            else $display("PASS PMP: %0s", label_text);
        end

    endtask

    initial begin
        clk=0; rst=1; csr_addr=0; csr_wdata=0; csr_we=0;
        access_valid=0; access_addr=0; access_size=0;
        access_read=0; access_write=0; access_execute=0; privilege=2'b11;
        DONE_O=0; FAILURES_O=0; checks=0;
        repeat (3) @(negedge clk); rst=0;

        check_access(64'h1000, 3, 2'b11, 1,0,0, 1,0,0, "M-mode no PMP match allowed");
        check_access(64'h1000, 3, 2'b01, 1,0,0, 0,0,0, "S-mode no PMP match denied");
        check_access(64'h1000, 3, 2'b00, 0,1,0, 0,0,0, "U-mode no PMP match denied");

        // Entry 0: NA4 [0x1000,0x1004), unlocked, RX.
        write_csr(12'h3B0, 64'h400);
        write_csr(12'h3A0, 64'h15);
        check_access(64'h1000, 2, 2'b01, 1,0,0, 1,1,0, "NA4 S-mode read allowed");
        check_access(64'h1000, 2, 2'b01, 0,1,0, 0,1,0, "NA4 S-mode write denied");
        check_access(64'h1000, 2, 2'b01, 0,0,1, 1,1,0, "NA4 S-mode execute allowed");
        check_access(64'h1000, 2, 2'b11, 0,1,0, 1,1,0, "unlocked PMP entry bypassed in M-mode");
        check_access(64'h0FFE, 2, 2'b11, 1,0,0, 0,1,0, "partial PMP overlap denied in M-mode");
        check_access(64'h0FFC, 2, 2'b01, 1,0,0, 0,0,0, "access immediately before NA4 no match");

        // Lock entry 0: M-mode must now obey its permissions.
        write_csr(12'h3A0, 64'h95);
        check_access(64'h1000, 2, 2'b11, 0,1,0, 0,1,0, "locked NA4 denies M-mode write");
        check_access(64'h1000, 2, 2'b11, 1,0,0, 1,1,0, "locked NA4 permits M-mode read");
        write_csr(12'h3B0, 64'h500);
        #1;
        if (csr_rdata !== 64'h400) begin
            FAILURES_O = FAILURES_O + 1;
            $display("FAIL PMP: locked pmpaddr changed, got %h", csr_rdata);
        end

        // Entries 2/3 define TOR [0x2000,0x3000), RWX.
        write_csr(12'h3B2, 64'h800);
        write_csr(12'h3B3, 64'hC00);
        write_csr(12'h3A0, 64'h0000_0000_0F00_9500);
        check_access(64'h2000, 3, 2'b01, 1,0,0, 1,1,3, "TOR lower boundary included");
        check_access(64'h2FF8, 3, 2'b01, 0,1,0, 1,1,3, "TOR last 8-byte access included");
        check_access(64'h2FFE, 2, 2'b01, 1,0,0, 0,1,3, "TOR partial overlap at upper boundary denied");
        check_access(64'h2000, 3, 2'b01, 1,1,0, 1,1,3, "TOR simultaneous read/write permissions");

        // Entry 4: 4 KiB NAPOT region [0x4000,0x5000), RWX.
        write_csr(12'h3B4, 64'h11FF);
        write_csr(12'h3A0, 64'h0000_001F_0F00_9595);
        check_access(64'h4000, 3, 2'b00, 1,0,0, 1,1,4, "NAPOT base address");
        check_access(64'h4FF8, 3, 2'b00, 1,0,0, 1,1,4, "NAPOT final complete doubleword");
        check_access(64'h4FFE, 2, 2'b00, 1,0,0, 0,1,4, "NAPOT partial overlap beyond end");
        check_access(64'h5000, 3, 2'b00, 1,0,0, 0,0,0, "NAPOT address immediately after region");

        // Entry 5 overlaps entry 4 with a denying NA4 region. Entry 4 must win.
        write_csr(12'h3B5, 64'h1000);
        write_csr(12'h3A0, 64'h0000_101F_0F00_9595);
        check_access(64'h4000, 0, 2'b01, 1,0,0, 1,1,4, "lowest-numbered matching PMP entry wins");

        check_access(64'h1000, 4, 2'b11, 1,0,0, 0,0,0, "unsupported PMP 16-byte access denied");
        check_access(64'hFFFF_FFFF_FFFF_FFFE, 2, 2'b11, 1,0,0, 0,0,0, "PMP address overflow denied");

        // Illegal W=1,R=0 is WARL-sanitized to W=0.
        write_csr(12'h3A0, 64'h0000_0000_001A_0000);
        #1;
        if (csr_rdata[23:16] !== 8'h18) begin
            FAILURES_O = FAILURES_O + 1;
            $display("FAIL PMP: W=1,R=0 WARL encoding not sanitized: %h", csr_rdata[23:16]);
        end

        // RV64 pmpcfg2 maps entries 8..15.
        write_csr(12'h3B8, 64'h2000);
        write_csr(12'h3A2, 64'h0000_0000_0000_0015);
        csr_addr = 12'h3A2; #1;
        if (csr_rdata[7:0] !== 8'h15) begin
            FAILURES_O = FAILURES_O + 1;
            $display("FAIL PMP: pmpcfg2 entry 8 readback mismatch");
        end
        check_access(64'h8000, 0, 2'b00, 1,0,0, 1,1,8, "pmpcfg2 and pmpaddr8 protect the ninth entry correctly");

        access_valid=0;
        $display("PMP TESTS COMPLETE: %0d checks, %0d failures", checks, FAILURES_O);
        DONE_O=1;
    end
endmodule



// 14 - PMU RV64

module PMU_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg clk, rst;
    reg [31:0] events;
    reg retired;
    reg counter_enable;
    reg [11:0] csr_addr;
    reg [63:0] csr_wdata;
    reg csr_we;
    wire [63:0] csr_rdata;
    wire [63:0] debug_mcycle, debug_minstret;
    integer checks;

    PMU_RV64 #(.HPM_COUNTERS(4)) dut (
        .CLK_I(clk), .RST_I(rst), .EVENT_I(events),
        .INSTRUCTION_RETIRED_I(retired), .COUNTER_ENABLE_I(counter_enable),
        .CSR_ADDR_I(csr_addr), .CSR_WDATA_I(csr_wdata), .CSR_WE_I(csr_we),
        .CSR_RDATA_O(csr_rdata), .DEBUG_MCYCLE_O(debug_mcycle),
        .DEBUG_MINSTRET_O(debug_minstret)
    );
    always #5 clk = ~clk;

    task write_csr;
        input [11:0] address;
        input [63:0] value;
        begin
            @(negedge clk); csr_addr=address; csr_wdata=value; csr_we=1;
            @(negedge clk); csr_we=0; csr_wdata=0; #1;
        end
    endtask

    task read_check;
        input [11:0] address;
        input [63:0] expected;
        input [511:0] label_text;
        begin
            csr_addr=address; #1; checks=checks+1;
            if (csr_rdata !== expected) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL PMU: %0s got=%h expected=%h",label_text,csr_rdata,expected);
            end
            else $display("PASS PMU: %0s",label_text);
        end
    endtask

    initial begin
        clk=0; rst=1; events=0; retired=0; counter_enable=1;
        csr_addr=0; csr_wdata=0; csr_we=0; checks=0;
        DONE_O=0; FAILURES_O=0;
        repeat (3) @(negedge clk); rst=0;

        repeat (5) @(posedge clk); #1;
        read_check(12'hB00, 64'd5, "mcycle increments each enabled clock");
        retired=1; events=32'h0000_0005;
        repeat (3) @(posedge clk); #1; retired=0; events=0;
        read_check(12'hB02, 64'd3, "minstret counts retire pulses");

        write_csr(12'h323, 64'h0000_0005);
        events=32'h0000_0004;
        repeat (2) @(posedge clk); #1; events=0;
        read_check(12'hB03, 64'd2, "HPM counter increments once per selected event cycle");
        events=32'h0000_0005;
        @(posedge clk); #1; events=0;
        read_check(12'hC03, 64'd3, "user counter alias reads same HPM counter");
        read_check(12'hC04, 64'd0, "unconfigured HPM counter reads zero");

        // Counter write has priority over a simultaneous increment.
        @(negedge clk); events=32'h5; csr_addr=12'hB03;
        csr_wdata=64'h1234; csr_we=1;
        @(negedge clk); csr_we=0; events=0; csr_wdata=0;
        read_check(12'hB03, 64'h1234, "CSR write overrides same-cycle counter increment");

        // The external counter enable must gate every counter independently of the individual mcountinhibit bits.
        begin : counter_enable_test
            reg [63:0] before_cycle, before_inst, before_hpm;
            csr_addr=12'hB00; #1; before_cycle=csr_rdata;
            csr_addr=12'hB02; #1; before_inst=csr_rdata;
            csr_addr=12'hB03; #1; before_hpm=csr_rdata;
            counter_enable=0; retired=1; events=32'h5;
            repeat (4) @(posedge clk); #1;
            csr_addr=12'hB00; #1;
            if (csr_rdata !== before_cycle) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: COUNTER_ENABLE did not gate mcycle"); end
            csr_addr=12'hB02; #1;
            if (csr_rdata !== before_inst) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: COUNTER_ENABLE did not gate minstret"); end
            csr_addr=12'hB03; #1;
            if (csr_rdata !== before_hpm) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: COUNTER_ENABLE did not gate HPM"); end
            counter_enable=1; retired=0; events=0;
        end

        write_csr(12'h320, 64'h0000_000D); // inhibit mcycle, minstret, HPM0
        begin : inhibit_test

            reg [63:0] old_cycle, old_inst, old_hpm;
            csr_addr=12'hB00; #1; old_cycle=csr_rdata;
            csr_addr=12'hB02; #1; old_inst=csr_rdata;
            csr_addr=12'hB03; #1; old_hpm=csr_rdata;
            retired=1; events=32'h5;

            repeat (4) @(posedge clk); #1; retired=0; events=0;
            csr_addr=12'hB00; #1;

            if (csr_rdata !== old_cycle) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: mcycle inhibit"); end
            csr_addr=12'hB02; #1;
           
            if (csr_rdata !== old_inst) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: minstret inhibit"); end
            csr_addr=12'hB03; #1;
            
            if (csr_rdata !== old_hpm) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: HPM inhibit"); end
        end

        write_csr(12'h320, 64'd0);
        write_csr(12'hB00, 64'hFFFF_FFFF_FFFF_FFFE);
        @(posedge clk); #1;
        
        read_check(12'hB00, 64'hFFFF_FFFF_FFFF_FFFF, "mcycle increments up to maximum");
        @(posedge clk); #1;
        read_check(12'hB00, 64'h0000_0000_0000_0000, "mcycle wraps at 64-bit overflow");

        write_csr(12'hB02, 64'hFFFF_FFFF_FFFF_FFFF);
        retired=1; @(posedge clk); #1; retired=0;
        read_check(12'hB02, 64'd0, "minstret wraps at 64-bit overflow");

        // Only machine counter CSRs are writable; C aliases are read-only here.
        csr_addr=12'hC00; csr_wdata=99; csr_we=1;
        @(negedge clk); csr_we=0; csr_addr=12'hB00; #1;
        if (csr_rdata == 99) begin FAILURES_O=FAILURES_O+1; $display("FAIL PMU: user alias unexpectedly writable"); end

        $display("PMU TESTS COMPLETE: %0d checks, %0d failures", checks, FAILURES_O);
        DONE_O=1;
    end
endmodule



// 15 - ASYNC FIFO AND CDC SYNCHRONIZERS

module FIFO_CDC_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg wr_clk, rd_clk;
    reg wr_rst, rd_rst;
    reg wr_en, rd_en;
    reg [31:0] wr_data;
    wire wr_full;
    wire [31:0] rd_data;
    wire rd_valid, rd_empty;

    Async_FIFO #(.DATA_WIDTH(32), .ADDR_WIDTH(2)) fifo_dut (
        .WR_CLK_I(wr_clk), .WR_RST_I(wr_rst), .WR_EN_I(wr_en),
        .WR_DATA_I(wr_data), .WR_FULL_O(wr_full),
        .RD_CLK_I(rd_clk), .RD_RST_I(rd_rst), .RD_EN_I(rd_en),
        .RD_DATA_O(rd_data), .RD_VALID_O(rd_valid), .RD_EMPTY_O(rd_empty)
    );

    // Minimum supported FIFO depth catches pointer-width and full-flag bugs.
    reg wr2_en, rd2_en;
    reg [31:0] wr2_data;
    wire wr2_full, rd2_empty, rd2_valid;
    wire [31:0] rd2_data;

    Async_FIFO #(.DATA_WIDTH(32), .ADDR_WIDTH(1)) fifo_depth2_dut (
        .WR_CLK_I(wr_clk), .WR_RST_I(wr_rst), .WR_EN_I(wr2_en),
        .WR_DATA_I(wr2_data), .WR_FULL_O(wr2_full),
        .RD_CLK_I(rd_clk), .RD_RST_I(rd_rst), .RD_EN_I(rd2_en),
        .RD_DATA_O(rd2_data), .RD_VALID_O(rd2_valid), .RD_EMPTY_O(rd2_empty)
    );

    reg cdc_src_clk, cdc_dst_clk;
    reg cdc_src_rst, cdc_dst_rst;
    reg [3:0] sync_data;
    wire [3:0] sync_data_out;
    wire reset_sync2, reset_sync1;
    reg pulse_in;
    wire pulse_ready;
    wire pulse_out;
    reg handshake_send;
    reg [31:0] handshake_data;
    wire handshake_src_ready;
    reg handshake_dst_ready;
    wire handshake_dst_valid;
    wire [31:0] handshake_dst_data;

    Clock_Synchronizer #(.WIDTH(4), .STAGES(3)) clock_sync_dut (
        .CLK_I(cdc_dst_clk), .RST_I(cdc_dst_rst),
        .DATA_I(sync_data), .DATA_O(sync_data_out)
    );
    Reset_Synchronizer #(.STAGES(2)) reset_sync2_dut (
        .CLK_I(cdc_dst_clk), .ASYNC_RST_I(cdc_dst_rst), .SYNC_RST_O(reset_sync2)
    );
    Reset_Synchronizer #(.STAGES(1)) reset_sync1_dut (
        .CLK_I(cdc_dst_clk), .ASYNC_RST_I(cdc_dst_rst), .SYNC_RST_O(reset_sync1)
    );
    Pulse_Synchronizer pulse_sync_dut (
        .SRC_CLK_I(cdc_src_clk), .SRC_RST_I(cdc_src_rst),
        .SRC_PULSE_I(pulse_in), .SRC_READY_O(pulse_ready),
        .DST_CLK_I(cdc_dst_clk), .DST_RST_I(cdc_dst_rst), .DST_PULSE_O(pulse_out)
    );
    Handshake_Synchronizer #(.DATA_WIDTH(32)) handshake_sync_dut (
        .SRC_CLK_I(cdc_src_clk), .SRC_RST_I(cdc_src_rst),
        .SRC_SEND_I(handshake_send), .SRC_DATA_I(handshake_data),
        .SRC_READY_O(handshake_src_ready),
        .DST_CLK_I(cdc_dst_clk), .DST_RST_I(cdc_dst_rst),
        .DST_READY_I(handshake_dst_ready), .DST_VALID_O(handshake_dst_valid),
        .DST_DATA_O(handshake_dst_data)
    );

    integer pulse_count;
    integer checks;
    integer i;
    integer timeout;
    reg [31:0] expected_fifo [0:15];

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;
    always #4 cdc_src_clk = ~cdc_src_clk;
    always #6 cdc_dst_clk = ~cdc_dst_clk;

    always @(posedge cdc_dst_clk or posedge cdc_dst_rst) begin
        if (cdc_dst_rst) pulse_count <= 0;
        else if (pulse_out) pulse_count <= pulse_count + 1;
    end

    task fifo_write;
        input [31:0] value;
        begin
            @(negedge wr_clk);
            wr_data=value; wr_en=1;
            @(posedge wr_clk); #1;
            @(negedge wr_clk); wr_en=0;
        end
    endtask

    task fifo_read_check;
        
        input [31:0] expected;
        input [511:0] label_text;
        
        begin
            timeout=0;
            while (rd_empty && timeout<20) begin
                @(negedge rd_clk); timeout=timeout+1;
            end
            if (timeout>=20) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL FIFO: timeout waiting for non-empty (%0s)",label_text);
            end
        
            else begin
                @(negedge rd_clk); rd_en=1;
                @(posedge rd_clk); #1;
                rd_en=0;
                checks=checks+1;
                if (rd_valid !== 1'b1 || rd_data !== expected) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL FIFO: %0s valid=%b data=%h expected=%h",
                             label_text,rd_valid,rd_data,expected);
                end
                else $display("PASS FIFO: %0s",label_text);
            end
        
        end
    
    
    endtask

    task pulse_send;
    
        begin
    
            timeout=0;
            while (!pulse_ready && timeout<30) begin @(negedge cdc_src_clk); timeout=timeout+1; end
            if (timeout>=30) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL CDC: pulse source never became ready");
            end
            else begin
                @(negedge cdc_src_clk); pulse_in=1;
                @(negedge cdc_src_clk); pulse_in=0;
            end
        end
    endtask

    initial begin
    
        wr_clk=0; rd_clk=0; wr_rst=1; rd_rst=1; wr_en=0; rd_en=0; wr_data=0;
        wr2_en=0; rd2_en=0; wr2_data=0;
        cdc_src_clk=0; cdc_dst_clk=0; cdc_src_rst=1; cdc_dst_rst=1;
        sync_data=0; pulse_in=0; handshake_send=0; handshake_data=0;
        handshake_dst_ready=0; pulse_count=0;
        DONE_O=0; FAILURES_O=0; checks=0;
    
        repeat (4) @(negedge wr_clk); wr_rst=0;
        repeat (4) @(negedge rd_clk); rd_rst=0;
        repeat (4) @(negedge cdc_src_clk); cdc_src_rst=0;
        repeat (4) @(negedge cdc_dst_clk); cdc_dst_rst=0;

        // FIFO fill-to-full, attempted overflow and exact-order drain.
        for (i=0;i<4;i=i+1) begin
            expected_fifo[i]=32'hA500_0000+i;
            fifo_write(expected_fifo[i]);
        end
        #1;
        if (wr_full !== 1'b1) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL FIFO: full did not assert at exact capacity");
        end
        else $display("PASS FIFO: full asserts at exact capacity");

        fifo_write(32'hDEAD_BEEF);
        if (wr_full !== 1'b1) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL FIFO: overflow attempt changed full state");
        end

        for (i=0;i<4;i=i+1)
            fifo_read_check(expected_fifo[i],"FIFO preserves order through full/empty boundary");
        repeat (4) @(negedge rd_clk);
    
        if (rd_empty !== 1'b1) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL FIFO: empty did not assert after final read");
        end
        else $display("PASS FIFO: empty asserts after drain");

        // Pointer wrap-around and a second fill/drain sequence.
        for (i=0;i<4;i=i+1) begin
            expected_fifo[i]=32'h5A00_1000+i;
            fifo_write(expected_fifo[i]);
        end
        for (i=0;i<4;i=i+1)
            fifo_read_check(expected_fifo[i],"FIFO pointer wrap-around retains data order");

        // Empty-read attempt must not generate a valid result.
        repeat (4) @(negedge rd_clk);
        @(negedge rd_clk); rd_en=1;
        @(posedge rd_clk); #1; rd_en=0;
        if (rd_valid !== 1'b0) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL FIFO: empty read incorrectly asserted valid");
        end
        else $display("PASS FIFO: empty read safely ignored");

        // Reset while a word is queued. Both pointer domains must discard
        // the in-flight contents and return to a consistent empty state.
        fifo_write(32'hFACE_CAFE);
        timeout=0;
        while (rd_empty && timeout<20) begin @(negedge rd_clk); timeout=timeout+1; end
        
        if (timeout>=20) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL FIFO: could not queue data before reset-in-flight test");
        end
        
        wr_rst=1; rd_rst=1;
        repeat (2) @(negedge wr_clk);
        wr_rst=0; rd_rst=0;
        repeat (4) @(negedge rd_clk);
        
        if (rd_empty !== 1'b1 || wr_full !== 1'b0) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL FIFO: reset did not restore empty/not-full state");
        end

        // Clock synchronizer must settle after the configured stages.
        sync_data=4'hA;
        repeat (4) @(negedge cdc_dst_clk);
        
        if (sync_data_out !== 4'hA) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL CDC: clock synchronizer output mismatch");
        end
        
        else $display("PASS CDC: clock synchronizer settles after configured latency");

        // Reset synchronizer: asynchronous assertion, synchronous release.
        cdc_dst_rst=1; #1;
        if (reset_sync2 !== 1'b1 || reset_sync1 !== 1'b1) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL CDC: reset synchronizer did not assert asynchronously");
        end
        
        cdc_dst_rst=0;
        @(negedge cdc_dst_clk); #1;
        
        if (reset_sync2 !== 1'b1) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL CDC: two-stage reset released too early");
        end
        
        repeat (2) @(negedge cdc_dst_clk); #1;
        
        if (reset_sync2 !== 1'b0 || reset_sync1 !== 1'b0) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL CDC: reset synchronizer did not release synchronously");
        end
        else $display("PASS CDC: asynchronous assert and synchronous release");

        // Pulse synchronizer: an attempted pulse while SRC_READY is low must be ignored rather than queued or duplicated.
        pulse_send();
        if (pulse_ready !== 1'b0) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL CDC: pulse source did not apply busy backpressure");
        end

        @(negedge cdc_src_clk); pulse_in=1;
        @(negedge cdc_src_clk); pulse_in=0;
        timeout=0;
        
        while (pulse_count<1 && timeout<50) begin @(negedge cdc_dst_clk); timeout=timeout+1; end
        
        if (pulse_count != 1) begin FAILURES_O=FAILURES_O+1; $display("FAIL CDC: first pulse missing/duplicated"); end
        
        pulse_send(); pulse_send();
        
        timeout=0;
        while (pulse_count<3 && timeout<100) begin @(negedge cdc_dst_clk); timeout=timeout+1; end
        repeat (8) @(negedge cdc_dst_clk);
        if (pulse_count != 3) begin FAILURES_O=FAILURES_O+1; $display("FAIL CDC: pulse count expected 3 got %0d",pulse_count); end
        else $display("PASS CDC: three accepted pulses delivered exactly once");

        // Multi-bit bundled-data handshake: hold destination under backpressure.
        timeout=0;
        while (!handshake_src_ready && timeout<40) begin @(negedge cdc_src_clk); timeout=timeout+1; end
        
        handshake_data=32'hCAFE_BABE;
        @(negedge cdc_src_clk); handshake_send=1;
        @(negedge cdc_src_clk); handshake_send=0;
        
        timeout=0;
        while (!handshake_dst_valid && timeout<50) begin @(negedge cdc_dst_clk); timeout=timeout+1; end
        
        if (timeout>=50 || handshake_dst_data !== 32'hCAFE_BABE) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL CDC: handshake payload did not arrive");
        end
        
        else begin
            $display("PASS CDC: handshake payload arrives under destination stall");
            repeat (5) @(negedge cdc_dst_clk);
            if (handshake_dst_valid !== 1'b1 || handshake_dst_data !== 32'hCAFE_BABE) begin
        
                FAILURES_O=FAILURES_O+1;
                $display("FAIL CDC: destination valid/data not held under backpressure");
            end
        
            else $display("PASS CDC: valid and payload remain stable under backpressure");
            if (handshake_src_ready !== 1'b0) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL CDC: source became ready before destination accepted data");
            end
        
            // Try to overwrite the outstanding transfer while the source is busy. The original bundled payload must remain unchanged.
            handshake_data=32'hDEAD_BEEF;
            @(negedge cdc_src_clk); handshake_send=1;
            @(negedge cdc_src_clk); handshake_send=0;
            
            repeat (2) @(negedge cdc_dst_clk);
            if (handshake_dst_valid !== 1'b1 || handshake_dst_data !== 32'hCAFE_BABE) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL CDC: busy source overwrote outstanding handshake payload");
            end
            
            handshake_dst_ready=1;
            timeout=0;
            
            while (!handshake_src_ready && timeout<50) begin @(negedge cdc_src_clk); timeout=timeout+1; end
            
            if (timeout>=50) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL CDC: source did not become ready after destination accept");
            end
            
            handshake_dst_ready=0;
        end

        // A second transfer after full handshake proves toggle re-arming.
        if (handshake_src_ready) begin
            handshake_data=32'h0123_4567;
            @(negedge cdc_src_clk); handshake_send=1;
            @(negedge cdc_src_clk); handshake_send=0;
            timeout=0;
            while (!handshake_dst_valid && timeout<50) begin @(negedge cdc_dst_clk); timeout=timeout+1; end
            if (timeout>=50 || handshake_dst_data !== 32'h0123_4567) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL CDC: second handshake payload incorrect");
            end
            
            else begin
                handshake_dst_ready=1;
                timeout=0;
                while (!handshake_src_ready && timeout<50) begin @(negedge cdc_src_clk); timeout=timeout+1; end
                handshake_dst_ready=0;
                $display("PASS CDC: handshake re-arms for a second transaction");
            
            end
        end

        $display("FIFO/CDC TESTS COMPLETE: %0d FIFO reads checked, %0d failures",checks,FAILURES_O);
        DONE_O=1;
    end
endmodule


// 13 - CACHE MAINTENANCE CONTROLLER

module Cache_Maint_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg clk, rst;
    reg cmd_valid;
    reg [2:0] cmd;
    reg [63:0] range_base, range_length;
    wire cmd_ready;
    wire busy, done, error;
    wire l1_d_flush, l1_d_invalidate;
    wire [63:0] l1_d_range_base, l1_d_range_length;
    wire l1_d_range_valid;
    reg l1_d_ready, l1_d_done, l1_d_error;
    wire l1_i_invalidate;
    reg l1_i_ready, l1_i_done, l1_i_error;
    wire l2_req;
    wire [1:0] l2_op;
    wire [63:0] l2_range_base, l2_range_length;
    reg l2_ready, l2_done, l2_error;
    integer command_count;
    integer timeout;

    Cache_Maintenance_Controller dut (
        .CLK_I(clk), .RST_I(rst),
        .CMD_VALID_I(cmd_valid), .CMD_I(cmd),
        .RANGE_BASE_I(range_base), .RANGE_LENGTH_I(range_length),
        .CMD_READY_O(cmd_ready), .BUSY_O(busy), .DONE_O(done), .ERROR_O(error),
        .L1_D_FLUSH_O(l1_d_flush), .L1_D_INVALIDATE_O(l1_d_invalidate),
        .L1_D_RANGE_BASE_O(l1_d_range_base), .L1_D_RANGE_LENGTH_O(l1_d_range_length),
        .L1_D_RANGE_VALID_O(l1_d_range_valid), .L1_D_READY_I(l1_d_ready),
        .L1_D_DONE_I(l1_d_done), .L1_D_ERROR_I(l1_d_error),
        .L1_I_INVALIDATE_O(l1_i_invalidate), .L1_I_READY_I(l1_i_ready),
        .L1_I_DONE_I(l1_i_done), .L1_I_ERROR_I(l1_i_error),
        .L2_MAINT_REQ_O(l2_req), .L2_MAINT_OP_O(l2_op),
        .L2_MAINT_RANGE_BASE_O(l2_range_base), .L2_MAINT_RANGE_LENGTH_O(l2_range_length),
        .L2_MAINT_READY_I(l2_ready), .L2_MAINT_DONE_I(l2_done),
        .L2_MAINT_ERROR_I(l2_error)
    );
    always #5 clk=~clk;

    task wait_l1d;
        begin
            timeout=0;
            while (!(l1_d_flush || l1_d_invalidate) && timeout<80) begin
                @(negedge clk); timeout=timeout+1;
            end
            if (timeout>=80) begin FAILURES_O=FAILURES_O+1; $display("FAIL MAINT: L1 D-cache command timeout"); end
        end
    endtask

    task wait_l2;
        begin
            timeout=0;
            while (!l2_req && timeout<80) begin @(negedge clk); timeout=timeout+1; end
            if (timeout>=80) begin FAILURES_O=FAILURES_O+1; $display("FAIL MAINT: L2 command timeout"); end
        end
    endtask

    task wait_l1i;
        begin
            timeout=0;
            while (!l1_i_invalidate && timeout<80) begin @(negedge clk); timeout=timeout+1; end
            if (timeout>=80) begin FAILURES_O=FAILURES_O+1; $display("FAIL MAINT: L1 I-cache command timeout"); end
        end
    endtask

    task pulse_l1d_response;
        input inject_error;
        begin
            repeat (2) @(negedge clk);
            if (inject_error) l1_d_error=1;
            else l1_d_done=1;
            @(negedge clk); l1_d_error=0; l1_d_done=0;
        end
    endtask

    task pulse_l2_response;
        input inject_error;
        begin
            repeat (2) @(negedge clk);
            if (inject_error) l2_error=1;
            else l2_done=1;
            @(negedge clk); l2_error=0; l2_done=0;
        end
    endtask

    task pulse_l1i_response;
        input inject_error;
        begin
            repeat (2) @(negedge clk);
            if (inject_error) l1_i_error=1;
            else l1_i_done=1;
            @(negedge clk); l1_i_error=0; l1_i_done=0;
        end
    endtask

    task check_final;
        input expected_error;
        input [511:0] label_text;
        begin
            timeout=0;
            while (!done && timeout<100) begin @(negedge clk); timeout=timeout+1; end
            if (timeout>=100 || error !== expected_error) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL MAINT: %0s done=%b error=%b timeout=%0d", label_text,done,error,timeout);
            end
            else $display("PASS MAINT: %0s",label_text);
            @(negedge clk);
        end
    endtask

    task run_command;
        input [2:0] command_value;
        input [63:0] base_value;
        input [63:0] length_value;
        input [1:0] expected_l2_op;
        input [2:0] error_stage; // 0=none, 1=L1D, 2=L2, 3=L1I
        input [511:0] label_text;

        begin
            command_count=command_count+1;
            l1_d_ready=0; l1_i_ready=0; l2_ready=0;
            l1_d_done=0; l1_d_error=0; l1_i_done=0; l1_i_error=0;
            l2_done=0; l2_error=0;
            
            @(negedge clk);
            cmd=command_value; range_base=base_value; range_length=length_value; cmd_valid=1;
            
            @(negedge clk); cmd_valid=0;
            repeat (2) @(negedge clk);
            if (!busy) begin FAILURES_O=FAILURES_O+1; $display("FAIL MAINT: busy not asserted"); end

            // A second command while busy must not overwrite the active one.
            cmd=3'd3; cmd_valid=1;
            @(negedge clk); cmd_valid=0;
            if (!busy) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL MAINT: busy command unexpectedly changed controller state");
            end

            if ((command_value==0) || (command_value==1) || (command_value==2) || (command_value==4)) begin
                l1_d_ready=0;
                repeat (2) @(negedge clk);
                if (l1_d_flush || l1_d_invalidate) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL MAINT: L1 D command ignored READY backpressure");
                end

                l1_d_ready=1;
                wait_l1d();
                if (command_value==4) begin
                    if (l1_d_invalidate !== 1'b1 || l1_d_flush !== 1'b0) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL MAINT: DMA discard did not request L1 invalidate");
                    end
                end
                
                else if (l1_d_flush !== 1'b1 || l1_d_invalidate !== 1'b0) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL MAINT: data clean did not request L1 flush");
                end
                
                if (l1_d_range_valid !== ((command_value==2)||(command_value==4)) || l1_d_range_base !== base_value || l1_d_range_length !== length_value) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL MAINT: L1 range metadata mismatch");
                end
                
                l1_d_ready=0;
                pulse_l1d_response(error_stage==1);
                
                if (error_stage==1) begin
                    check_final(1'b1,label_text);
                end
                
                
                else begin
                    l2_ready=0;
                    repeat (2) @(negedge clk);
                    if (l2_req) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL MAINT: L2 request asserted before READY");
                    end
                    l2_ready=1;
                    wait_l2();
                    if (l2_op !== expected_l2_op || l2_range_base !== base_value || l2_range_length !== length_value) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL MAINT: L2 operation/range mismatch op=%0d expected=%0d",l2_op,expected_l2_op);
                    end

                    l2_ready=0;
                    pulse_l2_response(error_stage==2);
                    
                    if (error_stage==2)
                        check_final(1'b1,label_text);
                    
                    else if ((command_value==0)||(command_value==1)) begin
                        l1_i_ready=1;
                        wait_l1i();
                        l1_i_ready=0;
                        pulse_l1i_response(error_stage==3);
                        check_final(error_stage==3,label_text);
                    end
                    
                    
                    else
                        check_final(1'b0,label_text);
                end
            end
            else if (command_value==3) begin
                l1_i_ready=0;
                repeat (2) @(negedge clk);
                
                if (l1_i_invalidate) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL MAINT: L1 I invalidate ignored READY backpressure");
                
                end
                l1_i_ready=1;
                wait_l1i();
                if (l1_d_flush || l1_d_invalidate || l2_req) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL MAINT: INVALIDATE_I unexpectedly touched data/L2 cache");
                end
                
                l1_i_ready=0;
                pulse_l1i_response(error_stage==3);
                check_final(error_stage==3,label_text);
            end
            
            else begin
                check_final(1'b1,label_text);
            end
        end
    endtask


    initial begin
        clk=0; rst=1; cmd_valid=0; cmd=0; range_base=0; range_length=0;
        l1_d_ready=0; l1_d_done=0; l1_d_error=0;
        l1_i_ready=0; l1_i_done=0; l1_i_error=0;
        l2_ready=0; l2_done=0; l2_error=0;
        DONE_O=0; FAILURES_O=0; command_count=0;
        repeat (3) @(negedge clk); rst=0;

        run_command(3'd0,64'd0,64'd0,2'd0,3'd0,"FENCE.I cleans data/L2 then invalidates I-cache");
        run_command(3'd1,64'd0,64'd0,2'd1,3'd0,"FLUSH_ALL cleans and invalidates all cache levels");
        run_command(3'd2,64'h8000_1000,64'd128,2'd0,3'd0,"CLEAN_FOR_DMA preserves supplied address range");
        run_command(3'd3,64'd0,64'd0,2'd0,3'd0,"INVALIDATE_I touches only instruction cache");
        run_command(3'd4,64'h8000_2000,64'd64,2'd2,3'd0,"INVALIDATE_AFTER_DMA discards selected range");

        // Error propagation from each downstream cache adapter.
        run_command(3'd0,64'd0,64'd0,2'd0,3'd1,"L1 data-cache error propagates");
        run_command(3'd0,64'd0,64'd0,2'd0,3'd2,"L2 maintenance error propagates");
        run_command(3'd3,64'd0,64'd0,2'd0,3'd3,"L1 instruction-cache error propagates");

        // Invalid command and zero-length range must fail immediately.
        @(negedge clk); cmd=3'd2; range_base=64'h8000; range_length=0; cmd_valid=1;
        @(negedge clk); cmd_valid=0;
        check_final(1'b1,"zero-length DMA range is rejected");
        @(negedge clk); cmd=3'd7; cmd_valid=1;
        @(negedge clk); cmd_valid=0;
        check_final(1'b1,"unsupported maintenance opcode is rejected");

        $display("CACHE MAINTENANCE TESTS COMPLETE: %0d commands, %0d failures",command_count,FAILURES_O);
        DONE_O=1;
    end
endmodule



// 16 - WATCHDOG TIMER

module Watchdog_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg clk, rst;
    reg [63:0] wb_addr, wb_wdata;
    wire [63:0] wb_rdata;
    reg [7:0] wb_sel;
    reg wb_cyc, wb_stb, wb_we;
    wire wb_ack, wb_err;
    wire irq, system_reset, timeout_flag;
    wire [63:0] debug_count;
    integer checks;
    integer timeout;

    Watchdog_Timer #(.DEFAULT_TIMEOUT(64'd7), .RESET_PULSE_CYCLES(3)) dut (
        .CLK_I(clk), .RST_I(rst), .WB_ADR_I(wb_addr), .WB_DAT_I(wb_wdata),
        .WB_DAT_O(wb_rdata), .WB_SEL_I(wb_sel), .WB_CYC_I(wb_cyc),
        .WB_STB_I(wb_stb), .WB_WE_I(wb_we), .WB_ACK_O(wb_ack), .WB_ERR_O(wb_err),
        .IRQ_O(irq), .SYSTEM_RESET_O(system_reset), .TIMEOUT_O(timeout_flag),
        .DEBUG_COUNT_O(debug_count)
    );
    always #5 clk=~clk;

    task wb_access;
        input write_enable;
        input [63:0] address;
        input [63:0] value;
        input [7:0] select;
        input expected_error;
        output [63:0] read_value;
    
        begin
            read_value=0;
            @(negedge clk);
            wb_addr=address; wb_wdata=value; wb_sel=select;
            wb_we=write_enable; wb_cyc=1; wb_stb=1;
            timeout=0;
    
            while (!(wb_ack || wb_err) && timeout<40) begin
                @(negedge clk); timeout=timeout+1;
            end
    
            #1;
    
            checks=checks+1;
            if (timeout>=40 || wb_err !== expected_error ||
                (!expected_error && wb_ack !== 1'b1)) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL WATCHDOG: %s addr=%h ack=%b err=%b timeout=%0d", write_enable?"write":"read",address,wb_ack,wb_err,timeout);
            end
            
            else begin
                if (!write_enable && !expected_error) read_value=wb_rdata;
                $display("PASS WATCHDOG: %s addr=%h",write_enable?"write":"read",address);
            end
            
            @(negedge clk); wb_cyc=0; wb_stb=0; wb_we=0;
            @(negedge clk);
        end
    endtask

    task wait_cycles;
        input integer count;
        integer n;
        begin 
            for (n=0;n<count;n=n+1) @(negedge clk); end
    endtask

    reg [63:0] value;
    initial begin
        clk=0; rst=1; wb_addr=0; wb_wdata=0; wb_sel=8'hFF;
        wb_cyc=0; wb_stb=0; wb_we=0;
        DONE_O=0; FAILURES_O=0; checks=0; value=0;
        repeat (3) @(negedge clk); rst=0;

        // Use enough cycles that the bus transactions themselves cannot consume the entire timeout before the first observation.
        wb_access(1,64'h00,64'd16,8'hFF,0,value);
        wb_access(1,64'h08,64'd7,8'hFF,0,value); // enable + IRQ + reset
        wait_cycles(2);
        if (timeout_flag || irq || system_reset) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL WATCHDOG: expired before programmed timeout");
        end
        timeout=0;

        while (!timeout_flag && timeout<24) begin
            @(negedge clk);
            timeout=timeout+1;
        end

        if (!timeout_flag || !irq || !system_reset) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL WATCHDOG: timeout did not assert IRQ/reset outputs");
        end

        else $display("PASS WATCHDOG: timeout asserts sticky flag, IRQ and reset request");
       
        if (debug_count !== 64'd16) begin FAILURES_O=FAILURES_O+1; $display("FAIL WATCHDOG: counter reload value incorrect"); end
       
        wait_cycles(4);
        if (system_reset) begin FAILURES_O=FAILURES_O+1; $display("FAIL WATCHDOG: reset pulse longer than configured"); end

        wb_access(1,64'h20,64'd1,8'h01,0,value);
        if (timeout_flag || irq) begin FAILURES_O=FAILURES_O+1; $display("FAIL WATCHDOG: status write-one-clear failed"); end

        // Feed/reload must prevent expiration when performed in time.
        wb_access(1,64'h00,64'd8,8'hFF,0,value);
        wb_access(1,64'h08,64'd7,8'hFF,0,value); // re-enable after timeout
        wait_cycles(2);
        wb_access(1,64'h18,64'd0,8'hFF,0,value); // timely feed
        wait_cycles(4);

        if (timeout_flag) begin FAILURES_O=FAILURES_O+1; $display("FAIL WATCHDOG: feed did not reload countdown"); end
        wait_cycles(3);

        if (!timeout_flag) begin FAILURES_O=FAILURES_O+1; $display("FAIL WATCHDOG: reloaded timeout never expired"); end

        // Disable reset but leave IRQ disabled; timeout remains status-only.
        wb_access(1,64'h20,64'd1,8'h01,0,value);
        wb_access(1,64'h08,64'd0,8'hFF,0,value);
        wb_access(1,64'h00,64'd4,8'hFF,0,value);
        wb_access(1,64'h08,64'd1,8'hFF,0,value); // enable only
        wait_cycles(3);
        
        if (!timeout_flag || irq || system_reset) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL WATCHDOG: enable-only timeout output mismatch");
        end

        // Byte strobes merge the timeout register, rather than replacing all bytes.
        wb_access(1,64'h00,64'hAA00_0000_0000_0000,8'h80,0,value);
        wb_access(0,64'h00,0,8'hFF,0,value);
        
        if (value !== 64'hAA00_0000_0000_0004) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL WATCHDOG: partial-byte register write got %h",value);
        end

        // Zero timeout, unaligned and unmapped accesses must return ERR.
        wb_access(1,64'h00,64'd0,8'hFF,1,value);
        wb_access(0,64'h04,0,8'hFF,1,value);
        wb_access(0,64'h28,0,8'hFF,1,value);

        $display("WATCHDOG TESTS COMPLETE: %0d bus checks, %0d failures",checks,FAILURES_O);
        DONE_O=1;
    end
endmodule



// 13 - L2 CACHE WITH DELAYED WISHBONE MEMORY MODEL

module L2_Cache_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    reg clk, rst;
    reg [63:0] wb_addr, wb_wdata;
    wire [63:0] wb_rdata;
    reg [7:0] wb_sel;
    reg wb_cyc, wb_stb, wb_we;
    reg [2:0] wb_cti;
    reg [1:0] wb_bte;
    reg wb_cacheable;
    wire wb_ack, wb_err;

    wire [63:0] mem_addr, mem_wdata;
    reg [63:0] mem_rdata;
    wire [7:0] mem_sel;
    wire mem_cyc, mem_stb, mem_we;
    wire [2:0] mem_cti;
    wire [1:0] mem_bte;
    reg mem_ack, mem_err;

    reg maint_req;
    reg [1:0] maint_op;
    reg [63:0] maint_base, maint_length;
    wire maint_ready, maint_done, maint_error;
    wire [31:0] hit_count, miss_count, writeback_count;

    reg [63:0] memory [0:8191];
    reg mem_pending, mem_seen;
    reg [63:0] pending_addr, pending_data, last_mem_addr;
    reg [7:0] pending_sel;
    reg pending_we;
    integer mem_delay;
    integer mem_index;
    integer mem_byte;
    integer init_i;
    integer mem_transactions;
    reg inject_mem_error;
    reg [63:0] inject_error_address;
    integer checks;
    integer timeout;
    reg [63:0] read_value;
    reg [63:0] expected_value;

    L2_Cache #(.ADDR_WIDTH(64), .DATA_WIDTH(64), .CACHE_SIZE(128), .LINE_BYTES(16), .WAYS(2)) dut (
        .CLK_I(clk), .RST_I(rst),
        .WB_ADR_I(wb_addr), .WB_DAT_I(wb_wdata), .WB_DAT_O(wb_rdata),
        .WB_SEL_I(wb_sel), .WB_CYC_I(wb_cyc), .WB_STB_I(wb_stb),
        .WB_WE_I(wb_we), .WB_CTI_I(wb_cti), .WB_BTE_I(wb_bte),
        .WB_CACHEABLE_I(wb_cacheable), .WB_ACK_O(wb_ack), .WB_ERR_O(wb_err),
        .MEM_ADR_O(mem_addr), .MEM_DAT_O(mem_wdata), .MEM_DAT_I(mem_rdata),
        .MEM_SEL_O(mem_sel), .MEM_CYC_O(mem_cyc), .MEM_STB_O(mem_stb),
        .MEM_WE_O(mem_we), .MEM_CTI_O(mem_cti), .MEM_BTE_O(mem_bte),
        .MEM_ACK_I(mem_ack), .MEM_ERR_I(mem_err),
        .MAINT_REQ_I(maint_req), .MAINT_OP_I(maint_op),
        .MAINT_RANGE_BASE_I(maint_base), .MAINT_RANGE_LENGTH_I(maint_length),
        .MAINT_READY_O(maint_ready), .MAINT_DONE_O(maint_done),
        .MAINT_ERROR_O(maint_error), .DEBUG_HIT_COUNT_O(hit_count),
        .DEBUG_MISS_COUNT_O(miss_count), .DEBUG_WRITEBACK_COUNT_O(writeback_count)
    );

    always #5 clk=~clk;

    function [63:0] merge_word;
        input [63:0] old_word;
        input [63:0] new_word;
        input [7:0] select;
        integer b;
        
        begin
            merge_word=old_word;
            for (b=0;b<8;b=b+1)
                if (select[b]) merge_word[b*8 +: 8]=new_word[b*8 +: 8];
        end
    endfunction

    // Memory slave: delayed, one-cycle ACK/ERR responses. The seen-address guard prevents the same held Wishbone beat from being acknowledged twice.
    always @(posedge clk or posedge rst) begin
        
        if (rst) begin
            mem_ack<=0; mem_err<=0; mem_pending<=0; mem_seen<=0;
            pending_addr<=0; pending_data<=0; pending_sel<=0; pending_we<=0;
            last_mem_addr<=0; mem_delay<=0; mem_rdata<=0; mem_transactions<=0;
        end
        
        else begin
            mem_ack<=0; mem_err<=0;
            if (!(mem_cyc && mem_stb)) begin
                mem_pending<=0;
                mem_seen<=0;
            end
        
            else if (mem_ack || mem_err) begin
                mem_seen<=1;
            end
        
            else if (mem_pending) begin
                if (mem_delay>0)
                    mem_delay<=mem_delay-1;
                else begin
        
                    mem_index=(pending_addr >> 3) & 8191;
                    if (inject_mem_error && pending_addr==inject_error_address) begin
                        mem_err<=1;
                    end
        
                    else begin
                        if (pending_we)
                            memory[mem_index] <= merge_word(memory[mem_index],pending_data,pending_sel);
        
                        mem_rdata <= memory[mem_index];
                        mem_ack<=1;
                        mem_transactions<=mem_transactions+1;
                    end
        
                    mem_pending<=0;
                    mem_seen<=1;
                    last_mem_addr<=pending_addr;
                end
            end
        
        
            else if (!mem_seen || (mem_addr != last_mem_addr)) begin
                pending_addr<=mem_addr;
                pending_data<=mem_wdata;
                pending_sel<=mem_sel;
                pending_we<=mem_we;
                mem_delay<=2;
                mem_pending<=1;
            end
        
        end
    
    
    end
    task wb_transfer;
        input write_enable;
        input [63:0] address;
        input [63:0] value;
       
        input [7:0] select;
        input cacheable_value;
        input [1:0] bte_value;
        input expected_error;
        output [63:0] result;
       
        begin
            result=0;
            @(negedge clk);
            wb_addr=address; wb_wdata=value; wb_sel=select;
            wb_we=write_enable; wb_cacheable=cacheable_value;
            wb_bte=bte_value; wb_cti=3'b000; wb_cyc=1; wb_stb=1;
            timeout=0;
       
            while (!(wb_ack || wb_err) && timeout<500) begin
                @(negedge clk); timeout=timeout+1;
            end
       
            #1;
       
            checks=checks+1;
            if (timeout>=500 || wb_err !== expected_error || (!expected_error && wb_ack !== 1'b1)) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL L2: %s addr=%h ack=%b err=%b timeout=%0d", write_enable?"write":"read",address,wb_ack,wb_err,timeout);
            end
            else begin
                result=wb_rdata;
                $display("PASS L2: %s addr=%h",write_enable?"write":"read",address);
            end
            @(negedge clk); wb_cyc=0; wb_stb=0; wb_we=0;
            @(negedge clk);
        end
    endtask

    task maintenance;
        input [1:0] operation;
        input [63:0] base;
        input [63:0] length;
        input expected_error;
        begin
            timeout=0;
            while (!maint_ready && timeout<30) begin @(negedge clk); timeout=timeout+1; end
            
            if (timeout>=30) begin FAILURES_O=FAILURES_O+1; $display("FAIL L2: maintenance never ready"); end
            
            @(negedge clk); maint_op=operation; maint_base=base; maint_length=length; maint_req=1;
            @(negedge clk); maint_req=0;
            
            timeout=0;
            
            while (!(maint_done || maint_error) && timeout<2000) begin
                @(negedge clk); timeout=timeout+1;
            end
            
            checks=checks+1;
            
            if (timeout>=2000 || maint_error !== expected_error || maint_done !== 1'b1) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL L2: maintenance op=%0d done=%b err=%b timeout=%0d", operation,maint_done,maint_error,timeout);
            end
            
            else $display("PASS L2: maintenance op=%0d base=%h length=%h",operation,base,length);
            @(negedge clk);
        end


    endtask

    initial begin
        clk=0; rst=1;
        wb_addr=0; wb_wdata=0; wb_sel=8'hFF; wb_cyc=0; wb_stb=0; wb_we=0;
        wb_cti=0; wb_bte=0; wb_cacheable=1;
        maint_req=0; maint_op=0; maint_base=0; maint_length=0;
        inject_mem_error=0; inject_error_address=0;
        DONE_O=0; FAILURES_O=0; checks=0;
        for (init_i=0;init_i<8192;init_i=init_i+1)
            memory[init_i]=64'h1000_0000_0000_0000 ^ init_i;
        repeat (4) @(negedge clk); rst=0;

        // Cold miss, refill, hit, counters and partial byte writes.
        wb_transfer(0,64'h1000,0,8'hFF,1,2'b00,0,read_value);
        expected_value=64'h1000_0000_0000_0000 ^ (64'h1000 >> 3);
        
        if (read_value !== expected_value) begin FAILURES_O=FAILURES_O+1; $display("FAIL L2: refill data mismatch"); end
        wb_transfer(0,64'h1000,0,8'hFF,1,2'b00,0,read_value);
        
        if (read_value !== expected_value || hit_count < 1 || miss_count < 1) begin
            FAILURES_O=FAILURES_O+1; $display("FAIL L2: cache hit/counter mismatch");
        end
        
        wb_transfer(1,64'h1000,64'hAABB_CCDD_1122_3344,8'h0F,1,2'b00,0,read_value);
        wb_transfer(0,64'h1000,0,8'hFF,1,2'b00,0,read_value);
        
        if (read_value !== 64'h1000_0000_1122_3344) begin
            FAILURES_O=FAILURES_O+1; $display("FAIL L2: byte-select merge got %h",read_value);
        end

        // Two-way set pressure: A/B occupy both ways; C forces dirty A eviction.
        
        wb_transfer(0,64'h1040,0,8'hFF,1,2'b00,0,read_value);
        wb_transfer(0,64'h1080,0,8'hFF,1,2'b00,0,read_value);
        
        #1;
        
        if (memory[64'h1000>>3] !== 64'h1000_0000_1122_3344 || writeback_count==0) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL L2: dirty victim was not written back correctly");
        end
        
        else $display("PASS L2: dirty eviction writes all selected victim data");
        wb_transfer(0,64'h1000,0,8'hFF,1,2'b00,0,read_value);
        
        if (read_value !== 64'h1000_0000_1122_3344) begin FAILURES_O=FAILURES_O+1; $display("FAIL L2: evicted line refill lost updated data"); end

        // Uncacheable bypass must preserve byte enables and avoid cache refill.
        
        wb_transfer(1,64'h2000,64'hFEED_FACE_1234_5678,8'hF0,0,2'b00,0,read_value);
        
        wb_transfer(0,64'h2000,0,8'hFF,0,2'b00,0,read_value);
        
        if (read_value !== merge_word((64'h1000_0000_0000_0000 ^ (64'h2000>>3)), 64'hFEED_FACE_1234_5678,8'hF0)) begin
            FAILURES_O=FAILURES_O+1; $display("FAIL L2: bypass partial write/read mismatch %h",read_value);
        end

        // BTE is not implemented by this cache endpoint and must return ERR.
        wb_transfer(0,64'h3000,0,8'hFF,1,2'b01,1,read_value);

        // Range clean: dirty line must be written back, kept valid and remain a hit.
        wb_transfer(1,64'h1020,64'h0123_4567_89AB_CDEF,8'hFF,1,2'b00,0,read_value);
        wb_transfer(1,64'h1030,64'h0F0E_0D0C_0B0A_0908,8'hFF,1,2'b00,0,read_value);
        
        begin : clean_range_check
            reg [31:0] old_hits;
            reg [63:0] untouched_word;
            old_hits=hit_count;
            untouched_word=64'h1000_0000_0000_0000 ^ (64'h1030 >> 3);
            maintenance(2'd0,64'h1020,64'd1,1'b0);
        
            if (memory[64'h1020>>3] !== 64'h0123_4567_89AB_CDEF) begin
                FAILURES_O=FAILURES_O+1; $display("FAIL L2: range clean did not update selected memory");
            end
        
            if (memory[64'h1030>>3] !== untouched_word) begin
                FAILURES_O=FAILURES_O+1; $display("FAIL L2: range clean wrote back an unrelated dirty line");
            end
        
            wb_transfer(0,64'h1020,0,8'hFF,1,2'b00,0,read_value);
        
            if (hit_count <= old_hits) begin FAILURES_O=FAILURES_O+1; $display("FAIL L2: clean operation invalidated selected line unexpectedly"); end
            wb_transfer(0,64'h1030,0,8'hFF,1,2'b00,0,read_value);
        
            if (read_value !== 64'h0F0E_0D0C_0B0A_0908) begin
                FAILURES_O=FAILURES_O+1; $display("FAIL L2: unrelated dirty line was not preserved in cache");
            end
        
        end

        // Discard must drop dirty cache copy without writing it over new DMA data.
        wb_transfer(1,64'h1010,64'hDEAD_BEEF_CAFE_BABE,8'hFF,1,2'b00,0,read_value);
        memory[64'h1010>>3]=64'h55AA_55AA_1234_9876;
        maintenance(2'd2,64'h1010,64'd8,1'b0);
        wb_transfer(0,64'h1010,0,8'hFF,1,2'b00,0,read_value);
        
        if (read_value !== 64'h55AA_55AA_1234_9876) begin
            FAILURES_O=FAILURES_O+1; $display("FAIL L2: discard wrote stale dirty data over DMA data");
        end
        
        else $display("PASS L2: range discard preserves external DMA update");

        // Clean+invalidate all: dirty lines are written back before invalidation.
        wb_transfer(1,64'h1030,64'h0BAD_F00D_7654_3210,8'hFF,1,2'b00,0,read_value);
        
        begin : invalidate_all_check
            reg [31:0] old_misses;
            old_misses=miss_count;
            maintenance(2'd1,64'd0,64'd0,1'b0);
            wb_transfer(0,64'h1030,0,8'hFF,1,2'b00,0,read_value);
        
            if (miss_count <= old_misses || read_value !== 64'h0BAD_F00D_7654_3210) begin
                FAILURES_O=FAILURES_O+1; $display("FAIL L2: clean+invalidate failed to evict/reload line");
        
            end
        end

        // Discard with zero length must be rejected and must not become global.
        maintenance(2'd2,64'd0,64'd0,1'b1);
        maintenance(2'd3,64'd0,64'd0,1'b1);

        // Refill error and uncacheable memory error propagation.
        inject_mem_error=1; inject_error_address=64'h4000;
        wb_transfer(0,64'h4000,0,8'hFF,1,2'b00,1,read_value);
        inject_error_address=64'h5000;
        wb_transfer(0,64'h5000,0,8'hFF,0,2'b00,1,read_value);
        inject_mem_error=0;

        // Error during maintenance writeback must report both ERROR and DONE.
        wb_transfer(1,64'h1060,64'h9999_AAAA_BBBB_CCCC,8'hFF,1,2'b00,0,read_value);
        inject_mem_error=1; inject_error_address=64'h1060;
        maintenance(2'd0,64'd0,64'd0,1'b1);
        inject_mem_error=0;

        // Asynchronous reset while an external refill is outstanding must cancel the old transaction and leave the cache usable afterwards.
        @(negedge clk);
        wb_addr=64'h6000; wb_wdata=0; wb_sel=8'hFF; wb_we=0;
        wb_cacheable=1; wb_bte=0; wb_cti=0; wb_cyc=1; wb_stb=1;
        timeout=0;
        while (!mem_cyc && timeout<100) begin @(negedge clk); timeout=timeout+1; end
        
        if (timeout>=100) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL L2: did not reach external refill before reset test");
        end
        
        @(negedge clk); rst=1; wb_cyc=0; wb_stb=0;
        repeat (3) @(negedge clk);
        rst=0;
        repeat (3) @(negedge clk);
        
        if (wb_ack || wb_err || mem_cyc) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL L2: stale response remained after reset");
        end
        
        wb_transfer(0,64'h6000,0,8'hFF,1,2'b00,0,read_value);
        expected_value=64'h1000_0000_0000_0000 ^ (64'h6000 >> 3);
        
        if (read_value !== expected_value) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL L2: cache did not recover after reset during refill");
        end
        
        else $display("PASS L2: reset cancels outstanding refill and cache recovers");

        $display("L2 CACHE TESTS COMPLETE: %0d checks, %0d failures",checks,FAILURES_O);
        DONE_O=1;
    end
endmodule

// 13 - WISHBONE TO AXI4 BRIDGE
// AXI slave model includes independent AW/W backpressure, response errors, wrong IDs and malformed RLAST conditions.

module AXI_Bridge_Test(output reg DONE_O, output reg [31:0] FAILURES_O);

    localparam integer ID_WIDTH=6;
    localparam integer BURST_BEATS=8;

    reg clk, rst;
    reg [63:0] wb_addr, wb_wdata;
    wire [63:0] wb_rdata;
    reg [7:0] wb_sel;
    reg wb_cyc, wb_stb, wb_we;
    reg [2:0] wb_cti;
    reg [1:0] wb_bte;
    wire wb_ack, wb_err;

    wire [ID_WIDTH-1:0] awid;
    wire [48:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire awlock, awvalid;
    reg awready;

    wire [63:0] wdata;
    wire [7:0] wstrb;
    wire wlast, wvalid;
    reg wready;

    reg [ID_WIDTH-1:0] bid;
    reg [1:0] bresp;
    reg bvalid;
    wire bready;

    wire [ID_WIDTH-1:0] arid;
    wire [48:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire arlock, arvalid;
    reg arready;

    reg [ID_WIDTH-1:0] rid;
    reg [63:0] rdata;
    reg [1:0] rresp;
    reg rlast, rvalid;
    wire rready;

    reg [63:0] axi_memory [0:8191];
    reg [63:0] write_buffer [0:BURST_BEATS-1];
    reg [7:0] strobe_buffer [0:BURST_BEATS-1];
    reg aw_seen, w_done, read_active;
    reg [48:0] awaddr_hold, araddr_hold;
    reg [7:0] awlen_hold, arlen_hold;
    integer w_count, r_count, b_delay;
    integer cycle_count;
    integer b;
    integer memory_index;
    reg [1:0] inject_bresp, inject_rresp;
    reg [ID_WIDTH-1:0] inject_bid, inject_rid;
    reg force_ar_stall;
    integer inject_rlast_mode; // 0 normal, 1 early at beat 2, 2 late after expected final
    integer checks;
    integer timeout;
    reg [63:0] expected_data;
    integer i;
    reg axi_parameter_error;

    Wishbone_AXI4_Bridge #(
        .WB_ADDR_WIDTH(64), .AXI_ADDR_WIDTH(49), .PHYS_ADDR_WIDTH(40),
        .DATA_WIDTH(64), .MAX_BURST_BEATS(BURST_BEATS), .AXI_ID_WIDTH(ID_WIDTH)
    ) dut (
        .CLK_I(clk), .RST_I(rst),
        .WB_ADR_I(wb_addr), .WB_DAT_I(wb_wdata), .WB_DAT_O(wb_rdata),
        .WB_SEL_I(wb_sel), .WB_CYC_I(wb_cyc), .WB_STB_I(wb_stb),
        .WB_WE_I(wb_we), .WB_CTI_I(wb_cti), .WB_BTE_I(wb_bte),
        .WB_ACK_O(wb_ack), .WB_ERR_O(wb_err),
        .M_AXI_AWID(awid), .M_AXI_AWADDR(awaddr), .M_AXI_AWLEN(awlen),
        .M_AXI_AWSIZE(awsize), .M_AXI_AWBURST(awburst), .M_AXI_AWCACHE(awcache),
        .M_AXI_AWPROT(awprot), .M_AXI_AWLOCK(awlock), .M_AXI_AWVALID(awvalid),
        .M_AXI_AWREADY(awready), .M_AXI_WDATA(wdata), .M_AXI_WSTRB(wstrb),
        .M_AXI_WLAST(wlast), .M_AXI_WVALID(wvalid), .M_AXI_WREADY(wready),
        .M_AXI_BID(bid), .M_AXI_BRESP(bresp), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARID(arid), .M_AXI_ARADDR(araddr), .M_AXI_ARLEN(arlen),
        .M_AXI_ARSIZE(arsize), .M_AXI_ARBURST(arburst), .M_AXI_ARCACHE(arcache),
        .M_AXI_ARPROT(arprot), .M_AXI_ARLOCK(arlock), .M_AXI_ARVALID(arvalid),
        .M_AXI_ARREADY(arready), .M_AXI_RID(rid), .M_AXI_RDATA(rdata),
        .M_AXI_RRESP(rresp), .M_AXI_RLAST(rlast), .M_AXI_RVALID(rvalid),
        .M_AXI_RREADY(rready)
    );

    always #5 clk=~clk;

    function [63:0] merge_word;
        
        input [63:0] old_value;
        input [63:0] new_value;
        input [7:0] select;
        integer lane;

        begin
            merge_word=old_value;
            for (lane=0;lane<8;lane=lane+1)
                if (select[lane]) merge_word[lane*8 +: 8]=new_value[lane*8 +: 8];
        
        end
    
    
    endfunction

    // AXI memory slave model. AW and W are accepted independently; B is delayed until both have completed. RVALID remains asserted until RREADY.
    always @(negedge clk) begin
        
        if (rst) begin
            cycle_count=0;
            awready=0; wready=0; arready=0;
        end
        
        else begin
            cycle_count=cycle_count+1;
            awready=((cycle_count%4)!=0);
            wready=((cycle_count%5)!=1);
            arready=force_ar_stall ? 1'b0 : ((cycle_count%3)!=0);
        end
    
    
    end

    always @(posedge clk or posedge rst) begin
    
        if (rst) begin
            aw_seen<=0; w_done<=0; read_active<=0;
            awaddr_hold<=0; araddr_hold<=0; awlen_hold<=0; arlen_hold<=0;
            w_count<=0; r_count<=0; b_delay<=0;
            bid<=0; bresp<=0; bvalid<=0;
            rid<=0; rdata<=0; rresp<=0; rlast<=0; rvalid<=0;
    
            for (b=0;b<BURST_BEATS;b=b+1) begin
                write_buffer[b]<=0;
                strobe_buffer[b]<=0;
    
            end
        end
    
    
        else begin
            // Independent write address acceptance.
            if (awvalid && awready) begin
                if ((awsize != 3'd3) || (awburst != 2'b01) || (awid != {ID_WIDTH{1'b0}}) || (awcache != 4'b0011) || (awprot != 3'b000) || (awlock != 1'b0) || ((awlen != 8'd0) && (awlen != BURST_BEATS-1)))
                    axi_parameter_error<=1'b1;
                aw_seen<=1;
                awaddr_hold<=awaddr;
                awlen_hold<=awlen;
            end

            // Buffer write beats even when AWREADY is delayed.
            if (wvalid && wready) begin
                if (w_count < BURST_BEATS) begin
                    write_buffer[w_count]<=wdata;
                    strobe_buffer[w_count]<=wstrb;
                end
                w_count<=w_count+1;
                if (wlast) w_done<=1;
            end

            if (aw_seen && w_done && !bvalid) begin
          
                if (w_count != (awlen_hold + 1))
                    axi_parameter_error<=1'b1;
          
                if (b_delay<2)
                    b_delay<=b_delay+1;
          
                else begin
                    for (b=0;b<BURST_BEATS;b=b+1) begin
          
                        if (b<=awlen_hold) begin
                            memory_index=((awaddr_hold>>3)+b) & 8191;
                            axi_memory[memory_index]<=merge_word(
                                axi_memory[memory_index],write_buffer[b],strobe_buffer[b]);
                        end
          
                    end
                    bid<=inject_bid;
                    bresp<=inject_bresp;
                    bvalid<=1;
                end
          
          
            end

            if (bvalid && bready) begin
                bvalid<=0;
                aw_seen<=0;
                w_done<=0;
                w_count<=0;
                b_delay<=0;
            end

            // Read address channel.
            if (arvalid && arready) begin
          
                if ((arsize != 3'd3) || (arburst != 2'b01) ||
                    (arid != {ID_WIDTH{1'b0}}) || (arcache != 4'b0011) ||
                    (arprot != 3'b000) || (arlock != 1'b0) ||
                    ((arlen != 8'd0) && (arlen != BURST_BEATS-1)))
                    axi_parameter_error<=1'b1;
          
                read_active<=1;
                araddr_hold<=araddr;
                arlen_hold<=arlen;
                r_count<=0;
                rvalid<=0;
            end
          
            else if (read_active) begin
          
                if (!rvalid) begin
                    memory_index=((araddr_hold>>3)+r_count) & 8191;
                    rdata<=axi_memory[memory_index];
                    rid<=inject_rid;
                    rresp<=inject_rresp;
          
                    if (inject_rlast_mode==1)
                        rlast<=(r_count==2);
                    else if (inject_rlast_mode==2)
          
                        rlast<=(r_count==arlen_hold+1);
                    else
                        rlast<=(r_count==arlen_hold);
          
                    rvalid<=1;
                end
                else if (rvalid && rready) begin
                    rvalid<=0;
          
                    if (rlast)
                        read_active<=0;
                    else
                        r_count<=r_count+1;
                end
          
            end
        end
    
    
    end


    task wb_single;
    
        input write_enable;
        input [63:0] address;
        input [63:0] value;
        input [7:0] select;
        input [1:0] bte_value;
    
        input [2:0] cti_value;
        input expected_error;
        input [63:0] expected_read;
        integer drain_timeout;
    
        begin
            @(negedge clk);
            wb_addr=address; wb_wdata=value; wb_sel=select;
            wb_we=write_enable; wb_bte=bte_value; wb_cti=cti_value;
            wb_cyc=1; wb_stb=1;
            timeout=0;
    
            while (!(wb_ack || wb_err) && timeout<100) begin
                @(negedge clk); timeout=timeout+1;
            end
    
            #1; checks=checks+1;
    
            if (timeout>=100 || wb_err !== expected_error ||
                (!expected_error && wb_ack !== 1'b1)) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL AXI BRIDGE: single %s addr=%h ack=%b err=%b", write_enable?"write":"read",address,wb_ack,wb_err);
            end
            
            else if (!write_enable && !expected_error && wb_rdata !== expected_read) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL AXI BRIDGE: single read data=%h expected=%h",wb_rdata,expected_read);
            
            end
            
            else $display("PASS AXI BRIDGE: single %s addr=%h",write_enable?"write":"read",address);
            @(negedge clk); wb_cyc=0; wb_stb=0; wb_we=0;
            
            drain_timeout=0;
            
            while (((dut.state != 4'd0) || read_active) && drain_timeout<100) begin
                @(negedge clk);
                drain_timeout=drain_timeout+1;
            end
            
            if (drain_timeout>=100) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL AXI BRIDGE: single-transfer cleanup timed out state=%0d read_active=%b", dut.state,read_active);
            end
            repeat (2) @(negedge clk);
        end
    endtask

    task wb_write_burst;
        input [63:0] base;
        input integer malformed_final;
        input expected_error;
        
        integer beat;
        integer drain_timeout;
        begin
        
            for (beat=0;beat<BURST_BEATS;beat=beat+1) begin
                @(negedge clk);
                wb_addr=base+(beat*8);
        
                wb_wdata=64'hB000_0000_0000_0000+beat;
                wb_sel=8'hFF; wb_we=1; wb_bte=0; wb_cyc=1; wb_stb=1;
        
                if (beat==BURST_BEATS-1)
                    wb_cti=(malformed_final!=0)?3'b010:3'b111;
        
                else
                    wb_cti=3'b010;

                #1;
                if (beat < BURST_BEATS-1) begin
                    
                    if (wb_ack !== 1'b1 || wb_err !== 1'b0) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL AXI BRIDGE: write burst beat %0d was not accepted ack=%b err=%b state=%0d collect=%0d", beat,wb_ack,wb_err,dut.state,dut.collect_index);
                    end
                    
                    @(posedge clk); #1;
                end
                else if (malformed_final!=0) begin
                    
                    timeout=0;
                    while (!(wb_ack || wb_err) && timeout<20) begin @(negedge clk); timeout=timeout+1; end
                    
                    #1;
                    if (wb_err !== 1'b1 || wb_ack !== 1'b0) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL AXI BRIDGE: malformed final beat not rejected");
                    end
                    
                    else $display("PASS AXI BRIDGE: malformed final CTI rejected");
                end
                else begin
                    
                    timeout=0;
                    while (!(wb_ack || wb_err) && timeout<150) begin @(negedge clk); timeout=timeout+1; end
                    #1;
                    
                    if (timeout>=150 || wb_err !== expected_error || wb_ack !== !expected_error) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL AXI BRIDGE: final write burst response ack=%b err=%b",wb_ack,wb_err);
                    end
                    else $display("PASS AXI BRIDGE: full write burst, AW/W backpressure and B response");
                
                end
            
            
            end
            
            @(negedge clk); wb_cyc=0; wb_stb=0; wb_we=0;
            drain_timeout=0;
            
            while ((dut.state != 4'd0) && drain_timeout<100) begin
                @(negedge clk);
                drain_timeout=drain_timeout+1;
            end
            
            if (drain_timeout>=100) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL AXI BRIDGE: write-burst cleanup timed out state=%0d",dut.state);
            end
            
            repeat (2) @(negedge clk);
        
        end
    
    
    endtask

    task wb_read_burst;
        input [63:0] base;
        input integer corrupt_beat;
        input expected_error;
        integer beat;
        integer local_timeout;
    
        integer drain_timeout;
        reg [63:0] beat_expected;
    
    
        begin
    
            for (beat=0;beat<BURST_BEATS;beat=beat+1) begin
                @(negedge clk);
                wb_addr=base+(beat*8);
                if (beat==corrupt_beat) wb_addr=wb_addr+8;
                wb_wdata=0; wb_sel=8'hFF; wb_we=0; wb_bte=0;
    
                wb_cti=(beat==BURST_BEATS-1)?3'b111:3'b010;
                wb_cyc=1; wb_stb=1;
                local_timeout=0;
    
                while (!(wb_ack || wb_err) && local_timeout<100) begin
                    @(negedge clk); local_timeout=local_timeout+1;
                end
                #1;
    
                if (local_timeout>=100) begin
                    FAILURES_O=FAILURES_O+1;
                    $display("FAIL AXI BRIDGE: read burst beat %0d timed out",beat);
                end
    
                else if (wb_err) begin
    
                    if (!expected_error) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL AXI BRIDGE: unexpected read burst error at beat %0d",beat);
    
                    end
                    else $display("PASS AXI BRIDGE: read burst error detected at beat %0d",beat);
                    @(posedge clk); #1;
                    beat=BURST_BEATS;
    
                end
                else begin
    
                    beat_expected=axi_memory[(base>>3)+beat];
                    if (wb_ack !== 1'b1 || wb_rdata !== beat_expected) begin
                        FAILURES_O=FAILURES_O+1;
                        $display("FAIL AXI BRIDGE: read beat %0d got=%h expected=%h",beat,wb_rdata,beat_expected);
                    end
    
                    @(posedge clk); #1;
                end
            end
            @(negedge clk); wb_cyc=0; wb_stb=0;
            // An early/late RLAST or a bad Wishbone beat can put the bridge into R_DRAIN. Do not start another transaction until AXI has delivered the terminating RLAST and the bridge returned idle.
            
            drain_timeout=0;
            while (((dut.state != 4'd0) || read_active) && drain_timeout<100) begin
                @(negedge clk);
                drain_timeout=drain_timeout+1;
            end
            if (drain_timeout>=100) begin
                FAILURES_O=FAILURES_O+1;
                $display("FAIL AXI BRIDGE: read-burst drain timed out state=%0d read_active=%b", dut.state,read_active);
            end
            repeat (2) @(negedge clk);
        end

    endtask

    initial begin
        clk=0; rst=1;
        wb_addr=0; wb_wdata=0; wb_sel=8'hFF; wb_cyc=0; wb_stb=0;
        wb_we=0; wb_cti=0; wb_bte=0;
        awready=0; wready=0; arready=0;
        inject_bresp=0; inject_rresp=0; inject_bid=0; inject_rid=0; inject_rlast_mode=0;
        force_ar_stall=0; axi_parameter_error=0;
        DONE_O=0; FAILURES_O=0; checks=0;
        for (i=0;i<8192;i=i+1) axi_memory[i]=64'h6000_0000_0000_0000 ^ i;
        repeat (4) @(negedge clk); rst=0;

        // Basic single-beat transfers and byte strobes.
        wb_single(1,64'h1000,64'h0123_4567_89AB_CDEF,8'hFF,0,0,0,0);
        wb_single(0,64'h1000,0,8'hFF,0,0,0,64'h0123_4567_89AB_CDEF);
        wb_single(1,64'h1000,64'hDEAD_BEEF_0000_0000,8'hF0,0,0,0,0);
        wb_single(0,64'h1000,0,8'hFF,0,0,0,64'hDEAD_BEEF_89AB_CDEF);

        // AXI read/write error responses and wrong transaction IDs.
        inject_bresp=2'b10;
        wb_single(1,64'h1010,64'h1111,8'hFF,0,0,1,0);
        inject_bresp=0;
        inject_bid=6'd3;
        wb_single(1,64'h1018,64'h2222,8'hFF,0,0,1,0);
        inject_bid=0;

        inject_rresp=2'b10;
        wb_single(0,64'h1000,0,8'hFF,0,0,1,0);
        inject_rresp=0;
        inject_rid=6'd2;
        wb_single(0,64'h1000,0,8'hFF,0,0,1,0);
        inject_rid=0;

        // Single read must reject RLAST=0 and drain the remainder of the AXI burst.
        inject_rlast_mode=2; // with ARLEN=0 the model emits an extra beat before RLAST
        wb_single(0,64'h1000,0,8'hFF,0,0,1,0);
        inject_rlast_mode=0;

        // A full line write burst and matching full line read burst.
        wb_write_burst(64'h2000,0,0);
        wb_read_burst(64'h2000,-1,0);

        // Early and late RLAST are protocol errors; late data is drained.
        inject_rlast_mode=1;
        wb_read_burst(64'h2000,-1,1);
        inject_rlast_mode=2;
        wb_read_burst(64'h2000,-1,1);
        inject_rlast_mode=0;

        // Wishbone master changing beat address incorrectly must be rejected.
        wb_read_burst(64'h2000,2,1);

        // Malformed write final CTI, unsupported BTE/CTI and invalid physical address.
        wb_write_burst(64'h3000,1,1);
        wb_single(0,64'h1000,0,8'hFF,2'b01,3'b000,1,0);
        wb_single(0,64'h1000,0,8'hFF,2'b00,3'b001,1,0);
        wb_single(0,64'h0000_0100_0000_0000,0,8'hFF,2'b00,3'b000,1,0);

        // An aligned burst ending exactly at a 4 KiB boundary is legal.
        wb_write_burst(64'h0000_0000_0000_1FC0,0,0);

        // Misaligned line burst must be rejected before issuing AXI AR.
        wb_addr=64'h1088; wb_wdata=0; wb_sel=8'hFF; wb_we=0;
        wb_bte=0; wb_cti=3'b010; wb_cyc=1; wb_stb=1;
        timeout=0;
        
        while (!(wb_ack || wb_err) && timeout<20) begin @(negedge clk); timeout=timeout+1; end
        
        #1;
        if (wb_err !== 1'b1) begin FAILURES_O=FAILURES_O+1; $display("FAIL AXI BRIDGE: misaligned burst address accepted"); end
        else $display("PASS AXI BRIDGE: misaligned burst address rejected");
        @(negedge clk); wb_cyc=0; wb_stb=0;
        repeat (4) @(negedge clk);

        // Physical address space above 40 bits is rejected for burst aslo.
        wb_addr=64'h0000_0100_0000_0000; wb_wdata=0; wb_sel=8'hFF;
        wb_we=0; wb_bte=0; wb_cti=3'b010; wb_cyc=1; wb_stb=1;
        timeout=0;
        while (!(wb_ack || wb_err) && timeout<20) begin @(negedge clk); timeout=timeout+1; end
        
        #1;
        if (wb_err !== 1'b1) begin FAILURES_O=FAILURES_O+1; $display("FAIL AXI BRIDGE: >40-bit burst address accepted"); end
        else $display("PASS AXI BRIDGE: >40-bit burst address rejected");
        @(negedge clk); wb_cyc=0; wb_stb=0;

        // Reset with an AXI read address stalled. No old VALID/response may
        // leak into the next transaction after reset deassertion.
        @(negedge clk);
        force_ar_stall=1;
        
        wb_addr=64'h2000; wb_wdata=0; wb_sel=8'hFF;
        wb_we=0; wb_bte=0; wb_cti=0; wb_cyc=1; wb_stb=1;
        timeout=0;
        while (!arvalid && timeout<20) begin @(negedge clk); timeout=timeout+1; end
        if (timeout>=20) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL AXI BRIDGE: did not reach stalled AR channel for reset test");
        end
        // Reset at the same negative edge where ARVALID is observed, before
        // any following positive edge can accept the address.
        rst=1; wb_cyc=0; wb_stb=0;
        repeat (3) @(negedge clk);
        rst=0; force_ar_stall=0;
        inject_bresp=0; inject_rresp=0; inject_bid=0; inject_rid=0;
        inject_rlast_mode=0;
        repeat (3) @(negedge clk);
        
        if (wb_ack || wb_err || arvalid || awvalid || wvalid) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL AXI BRIDGE: stale channel state remained after reset");
        end
        
        else $display("PASS AXI BRIDGE: reset clears stalled AXI address transaction");
        wb_single(0,64'h2000,0,8'hFF,0,0,0,64'hB000_0000_0000_0000);
        if (axi_parameter_error) begin
            FAILURES_O=FAILURES_O+1;
            $display("FAIL AXI BRIDGE: AXI size/burst/ID/cache/protection/length fields invalid");
        
        end
        else $display("PASS AXI BRIDGE: AXI control fields and write beat count are valid");

        $display("AXI BRIDGE TESTS COMPLETE: %0d single-transfer checks, %0d failures",checks,FAILURES_O);
        DONE_O=1;
    end
endmodule