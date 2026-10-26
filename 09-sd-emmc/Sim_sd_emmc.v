`timescale 1ns/1ps

// This tests the PL request bridge only. The PS SD driver and physical card are represented by an AXI4-Lite testbench master.

module Sim_sd_emmc;

    reg clk_i;
    reg rst_i;

    reg wb_cyc_i;
    reg wb_stb_i;
    reg wb_we_i;
    reg [7:0] wb_sel_i;
    reg [63:0] wb_adr_i;
    reg [63:0] wb_dat_i;
    wire wb_ack_o;
    wire wb_err_o;
    wire [63:0] wb_dat_o;

    reg [31:0] s_axi_awaddr;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;

    reg [31:0] s_axi_araddr;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    wire cpu_irq_o;
    wire ps_irq_o;
    wire ps_online_o;

    reg [63:0] read64;
    reg [31:0] read32;
    reg [1:0] axi_resp;
    integer i;

    // GTKWave markers: select scenario then checkpoint to locate key events.
    reg [1:0] scenario;
    reg [7:0] checkpoint;

    // Internal signals included explicitly to make queue/error behavior visible.
    wire [4:0] debug_request_count;
    wire [4:0] debug_completion_count;
    wire [31:0] debug_last_error;
    wire debug_sticky_error;
    wire [1:0] debug_staged_operation;
    wire [63:0] debug_staged_lba;
    wire [31:0] debug_staged_blocks;
    wire [63:0] debug_staged_buffer;

    assign debug_request_count = dut.req_count;
    assign debug_completion_count = dut.comp_count;
    assign debug_last_error = dut.last_error_code;
    assign debug_sticky_error = dut.sticky_error;
    assign debug_staged_operation = dut.req_op_stage;
    assign debug_staged_lba = dut.req_lba_stage;
    assign debug_staged_blocks = dut.req_block_count_stage;
    assign debug_staged_buffer = dut.req_buffer_addr_stage;

    localparam [11:0] WB_CTRL = 12'h000;
    localparam [11:0] WB_STATUS = 12'h008;
    localparam [11:0] WB_OP = 12'h010;
    localparam [11:0] WB_LBA = 12'h018;
    localparam [11:0] WB_BLOCK_COUNT = 12'h020;
    localparam [11:0] WB_BUFFER_ADDR = 12'h028;
    localparam [11:0] WB_TAG = 12'h030;
    localparam [11:0] WB_FLAGS = 12'h038;
    localparam [11:0] WB_LAST_ERROR = 12'h040;
    localparam [11:0] WB_IRQ_ENABLE = 12'h048;
    localparam [11:0] WB_IRQ_STATUS = 12'h050;
    localparam [11:0] WB_COMP_VALID = 12'h060;
    localparam [11:0] WB_COMP_TAG = 12'h068;
    localparam [11:0] WB_COMP_STATUS = 12'h070;
    localparam [11:0] WB_COMP_ERROR = 12'h078;
    localparam [11:0] WB_COMP_POP = 12'h080;
    localparam [11:0] WB_CAPS = 12'h088;

    localparam [31:0] AXI_CAPS = 32'h000;
    localparam [31:0] AXI_STATUS = 32'h004;
    localparam [31:0] AXI_REQ_COUNT = 32'h008;
    localparam [31:0] AXI_COMP_COUNT = 32'h00C;
    localparam [31:0] AXI_PS_ALIVE = 32'h010;
    localparam [31:0] AXI_PS_IRQ_EN = 32'h014;
    localparam [31:0] AXI_CLEAR_ERROR = 32'h018;
    localparam [31:0] AXI_REQ_VALID = 32'h100;
    localparam [31:0] AXI_REQ_TAG = 32'h104;
    localparam [31:0] AXI_REQ_OP = 32'h108;
    localparam [31:0] AXI_REQ_LBA_LO = 32'h10C;
    localparam [31:0] AXI_REQ_LBA_HI = 32'h110;
    localparam [31:0] AXI_REQ_BLOCKS = 32'h114;
    localparam [31:0] AXI_REQ_BUF_LO = 32'h118;
    localparam [31:0] AXI_REQ_BUF_HI = 32'h11C;
    localparam [31:0] AXI_REQ_FLAGS = 32'h120;
    localparam [31:0] AXI_REQ_POP = 32'h124;
    localparam [31:0] AXI_RESP_TAG = 32'h140;
    localparam [31:0] AXI_RESP_STATUS = 32'h144;
    localparam [31:0] AXI_RESP_ERROR = 32'h148;
    localparam [31:0] AXI_RESP_PUSH = 32'h14C;

    always #5 clk_i = ~clk_i;

    sd_emmc #(
        .QUEUE_DEPTH(16),
        .MAX_BLOCKS_PER_REQ(128)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_stb_i(wb_stb_i),
        .wb_we_i(wb_we_i),
        .wb_sel_i(wb_sel_i),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),
        .wb_dat_o(wb_dat_o),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .cpu_irq_o(cpu_irq_o),
        .ps_irq_o(ps_irq_o),
        .ps_online_o(ps_online_o)
    );

    task wb_write;
        input [63:0] address;
        input [63:0] data;
        input [7:0] select_bits;
        input expected_error;
        integer timeout_count;
        begin
            @(negedge clk_i);
            wb_adr_i = address;
            wb_dat_i = data;
            wb_sel_i = select_bits;
            wb_we_i = 1'b1;
            wb_cyc_i = 1'b1;
            wb_stb_i = 1'b1;

            timeout_count = 0;
            while ((wb_ack_o !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk_i);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (wb_ack_o !== 1'b1) begin
                $fatal(1, "FAIL: Wishbone write timeout at address %h", address);
            end

            if (wb_err_o !== expected_error) begin
                $fatal(1, "FAIL: Wishbone write address %h expected ERR=%b, got %b", address, expected_error, wb_err_o);
            end

            @(negedge clk_i);
            wb_cyc_i = 1'b0;
            wb_stb_i = 1'b0;
            wb_we_i = 1'b0;
            @(posedge clk_i);
            #1;
        end
    endtask

    task wb_read;
        input [63:0] address;
        output [63:0] data;
        integer timeout_count;
        begin
            @(negedge clk_i);
            wb_adr_i = address;
            wb_dat_i = 64'd0;
            wb_sel_i = 8'hFF;
            wb_we_i = 1'b0;
            wb_cyc_i = 1'b1;
            wb_stb_i = 1'b1;

            timeout_count = 0;
            while ((wb_ack_o !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk_i);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (wb_ack_o !== 1'b1) begin
                $fatal(1, "FAIL: Wishbone read timeout at address %h", address);
            end
            if (wb_err_o !== 1'b0) begin
                $fatal(1, "FAIL: unexpected Wishbone ERR on read at %h", address);
            end
            data = wb_dat_o;

            @(negedge clk_i);
            wb_cyc_i = 1'b0;
            wb_stb_i = 1'b0;
            @(posedge clk_i);
            #1;
        end
    endtask

    task axi_write;
        input [31:0] address;
        input [31:0] data;
        input [3:0] strobe;
        input [1:0] expected_response;
        integer timeout_count;
        begin
            @(negedge clk_i);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            s_axi_wdata = data;
            s_axi_wstrb = strobe;
            s_axi_wvalid = 1'b1;

            timeout_count = 0;
            while (!((s_axi_awready === 1'b1) && (s_axi_wready === 1'b1)) &&
                   (timeout_count < 20)) begin
                @(posedge clk_i);
                #1;
                timeout_count = timeout_count + 1;
            end
            if (!((s_axi_awready === 1'b1) && (s_axi_wready === 1'b1))) begin
                $fatal(1, "FAIL: AXI write address/data channel timeout at %h", address);
            end

            @(posedge clk_i);
            #1;
            @(negedge clk_i);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;

            timeout_count = 0;
            while ((s_axi_bvalid !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk_i);
                #1;
                timeout_count = timeout_count + 1;
            end
            if (s_axi_bvalid !== 1'b1) begin
                $fatal(1, "FAIL: AXI write response timeout at %h", address);
            end
            if (s_axi_bresp !== expected_response) begin
                $fatal(1, "FAIL: AXI write %h expected BRESP=%b, got %b", address, expected_response, s_axi_bresp);
            end

            @(negedge clk_i);
            s_axi_bready = 1'b1;
            @(posedge clk_i);
            #1;
            @(negedge clk_i);
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_read;
        input [31:0] address;
        output [31:0] data;
        input [1:0] expected_response;
        integer timeout_count;
        begin
            @(negedge clk_i);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;

            timeout_count = 0;
            while ((s_axi_arready !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk_i);
                #1;
                timeout_count = timeout_count + 1;
            end
            if (s_axi_arready !== 1'b1) begin
                $fatal(1, "FAIL: AXI read address timeout at %h", address);
            end

            @(posedge clk_i);
            #1;
            if (s_axi_rvalid !== 1'b1) begin
                $fatal(1, "FAIL: AXI read response timeout at %h", address);
            end
            if (s_axi_rresp !== expected_response) begin
                $fatal(1, "FAIL: AXI read %h expected RRESP=%b, got %b", address, expected_response, s_axi_rresp);
            end
            data = s_axi_rdata;

            @(negedge clk_i);
            s_axi_arvalid = 1'b0;
            s_axi_rready = 1'b1;
            @(posedge clk_i);
            #1;
            @(negedge clk_i);
            s_axi_rready = 1'b0;
        end
    endtask

    task submit_request;
        input [1:0] operation;
        input [63:0] lba;
        input [31:0] blocks;
        input [63:0] buffer_address;
        input [31:0] tag;
        input [31:0] flags;
        input expected_error;
        begin
            wb_write({52'd0, WB_OP}, {62'd0, operation}, 8'hFF, 1'b0);
            wb_write({52'd0, WB_LBA}, lba, 8'hFF, 1'b0);
            wb_write({52'd0, WB_BLOCK_COUNT}, {32'd0, blocks}, 8'hFF, 1'b0);
            wb_write({52'd0, WB_BUFFER_ADDR}, buffer_address, 8'hFF, 1'b0);
            wb_write({52'd0, WB_TAG}, {32'd0, tag}, 8'hFF, 1'b0);
            wb_write({52'd0, WB_FLAGS}, {32'd0, flags}, 8'hFF, 1'b0);
            wb_write({52'd0, WB_CTRL}, 64'd1, 8'hFF, expected_error);
        end
    endtask

    initial begin
        $dumpfile("Sim_sd_emmc.vcd");
        $dumpvars(0, Sim_sd_emmc);

        clk_i = 1'b0;
        rst_i = 1'b1;
        scenario = 2'd0;
        checkpoint = 8'd0;

        wb_cyc_i = 1'b0;
        wb_stb_i = 1'b0;
        wb_we_i = 1'b0;
        wb_sel_i = 8'hFF;
        wb_adr_i = 64'd0;
        wb_dat_i = 64'd0;

        s_axi_awaddr = 32'd0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata = 32'd0;
        s_axi_wstrb = 4'd0;
        s_axi_wvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_araddr = 32'd0;
        s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;

        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (2) @(posedge clk_i);

        // Scenario 1: submit a READ request and let PS inspect the descriptor.
        scenario = 2'd1;
        checkpoint = 8'd1;
        wb_read({52'd0, WB_CAPS}, read64);
        axi_write(AXI_PS_ALIVE, 32'h5344454D, 4'hF, 2'b00);
        axi_write(AXI_PS_IRQ_EN, 32'd1, 4'hF, 2'b00);
        wb_write({52'd0, WB_IRQ_ENABLE}, 64'd1, 8'hFF, 1'b0);
        checkpoint = 8'd2;
        submit_request(2'd0, 64'h00000012_9ABCDEF0, 32'd4, 64'h00000000_40001000, 32'hCAFE1234, 32'h00000003, 1'b0);
        checkpoint = 8'd3;
        axi_read(AXI_REQ_VALID, read32, 2'b00);
        axi_read(AXI_REQ_TAG, read32, 2'b00);
        axi_read(AXI_REQ_OP, read32, 2'b00);
        axi_read(AXI_REQ_LBA_LO, read32, 2'b00);
        axi_read(AXI_REQ_LBA_HI, read32, 2'b00);
        axi_read(AXI_REQ_BLOCKS, read32, 2'b00);
        axi_read(AXI_REQ_BUF_LO, read32, 2'b00);
        axi_read(AXI_REQ_BUF_HI, read32, 2'b00);
        axi_read(AXI_REQ_FLAGS, read32, 2'b00);
        checkpoint = 8'd4;
        axi_write(AXI_REQ_POP, 32'd1, 4'hF, 2'b00);
        repeat (3) @(posedge clk_i);

        // Scenario 2: PS returns completion; CPU sees interrupt then pops it.
        scenario = 2'd2;
        checkpoint = 8'd1;
        axi_write(AXI_RESP_TAG, 32'hCAFE1234, 4'hF, 2'b00);
        axi_write(AXI_RESP_STATUS, 32'd0, 4'hF, 2'b00);
        axi_write(AXI_RESP_ERROR, 32'd0, 4'hF, 2'b00);
        checkpoint = 8'd2;
        axi_write(AXI_RESP_PUSH, 32'd1, 4'hF, 2'b00);
        checkpoint = 8'd3;
        wb_read({52'd0, WB_COMP_VALID}, read64);
        wb_read({52'd0, WB_COMP_TAG}, read64);
        wb_read({52'd0, WB_COMP_STATUS}, read64);
        wb_read({52'd0, WB_COMP_ERROR}, read64);
        checkpoint = 8'd4;
        wb_write({52'd0, WB_COMP_POP}, 64'd1, 8'hFF, 1'b0);
        repeat (3) @(posedge clk_i);

        // Scenario 3: malformed request, then fill the request queue and show overflow.
        scenario = 2'd3;
        checkpoint = 8'd1;
        submit_request(2'd0, 64'd0, 32'd0, 64'h00000000_40002000, 32'hBAD00001, 32'd0, 1'b1);
        checkpoint = 8'd2;
        wb_read({52'd0, WB_LAST_ERROR}, read64);
        wb_write({52'd0, WB_IRQ_STATUS}, 64'd2, 8'hFF, 1'b0);
        checkpoint = 8'd3;
        for (i = 0; i < 16; i = i + 1) begin
            submit_request(2'd0, i, 32'd1, 64'h00000000_40010000 + (i * 512), 32'h00001000 + i, 32'd0, 1'b0);
        end
        checkpoint = 8'd4;
        wb_read({52'd0, WB_STATUS}, read64);
        submit_request(2'd0, 64'd99, 32'd1, 64'h00000000_40020000, 32'h0000FFFF, 32'd0, 1'b1);
        checkpoint = 8'd5;
        wb_read({52'd0, WB_LAST_ERROR}, read64);
        wb_write({52'd0, WB_IRQ_STATUS}, 64'd2, 8'hFF, 1'b0);
        for (i = 0; i < 16; i = i + 1) begin
            axi_write(AXI_REQ_POP, 32'd1, 4'hF, 2'b00);
        end
        checkpoint = 8'd6;
        repeat (10) @(posedge clk_i);
        $finish;
    end

endmodule