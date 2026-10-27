`timescale 1ns/1ps

// GTKWave Ethernet VirtIO Testbench
// Generates a waveform for two screenshots:
// 1. VirtIO setup, queue configuration and TX notification.
// 2. Queue snapshot acknowledgement, RX notification and guest interrupt.
// No text-based test results are printed from this testbench.

module Sim_ethernet;

    reg clk;
    reg rst;

    reg [63:0] wb_adr_i;
    reg [63:0] wb_dat_i;
    reg [7:0] wb_sel_i;
    reg wb_cyc_i;
    reg wb_stb_i;
    reg wb_we_i;
    wire [63:0] wb_dat_o;
    wire wb_ack_o;
    wire wb_err_o;

    reg [31:0] s_axi_awaddr_i;
    reg s_axi_awvalid_i;
    wire s_axi_awready_o;
    reg [31:0] s_axi_wdata_i;
    reg [3:0] s_axi_wstrb_i;
    reg s_axi_wvalid_i;
    wire s_axi_wready_o;
    wire [1:0] s_axi_bresp_o;
    wire s_axi_bvalid_o;
    reg s_axi_bready_i;

    reg [31:0] s_axi_araddr_i;
    reg s_axi_arvalid_i;
    wire s_axi_arready_o;
    wire [31:0] s_axi_rdata_o;
    wire [1:0] s_axi_rresp_o;
    wire s_axi_rvalid_o;
    reg s_axi_rready_i;

    wire cpu_irq_o;
    wire ps_irq_o;

    reg [1:0] scenario;
    reg [3:0] checkpoint;
    reg [31:0] read_value;
    reg [31:0] tx_snapshot;
    reg [31:0] rx_snapshot;

    eth_virtio_net dut (
        .clk(clk),
        .rst(rst),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_sel_i(wb_sel_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_stb_i(wb_stb_i),
        .wb_we_i(wb_we_i),
        .wb_dat_o(wb_dat_o),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),

        .s_axi_awaddr_i(s_axi_awaddr_i),
        .s_axi_awvalid_i(s_axi_awvalid_i),
        .s_axi_awready_o(s_axi_awready_o),
        .s_axi_wdata_i(s_axi_wdata_i),
        .s_axi_wstrb_i(s_axi_wstrb_i),
        .s_axi_wvalid_i(s_axi_wvalid_i),
        .s_axi_wready_o(s_axi_wready_o),
        .s_axi_bresp_o(s_axi_bresp_o),
        .s_axi_bvalid_o(s_axi_bvalid_o),
        .s_axi_bready_i(s_axi_bready_i),
        .s_axi_araddr_i(s_axi_araddr_i),
        .s_axi_arvalid_i(s_axi_arvalid_i),
        .s_axi_arready_o(s_axi_arready_o),
        .s_axi_rdata_o(s_axi_rdata_o),
        .s_axi_rresp_o(s_axi_rresp_o),
        .s_axi_rvalid_o(s_axi_rvalid_o),
        .s_axi_rready_i(s_axi_rready_i),
        .cpu_irq_o(cpu_irq_o),
        .ps_irq_o(ps_irq_o)
    );

    always #5 clk = ~clk;

    
    // Wishbone Access Tasks
    

    task wb_write32;
        input [31:0] address;
        input [31:0] data;
        integer timeout;

        begin
            @(negedge clk);
            wb_adr_i = {32'd0, address};
            if (address[2]) begin
                wb_dat_i = {data, 32'd0};
                wb_sel_i = 8'hF0;
            end else begin
                wb_dat_i = {32'd0, data};
                wb_sel_i = 8'h0F;
            end

            wb_we_i = 1'b1;
            wb_cyc_i = 1'b1;
            wb_stb_i = 1'b1;
            timeout = 0;

            while (wb_ack_o !== 1'b1 && wb_err_o !== 1'b1 && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            @(negedge clk);
            wb_cyc_i = 1'b0;
            wb_stb_i = 1'b0;
            wb_we_i = 1'b0;
            wb_sel_i = 8'd0;
        end
    endtask

    task wb_read32;
        input [31:0] address;
        output [31:0] data;
        integer timeout;

        begin

            @(negedge clk);
            wb_adr_i = {32'd0, address};
            wb_dat_i = 64'd0;
            wb_sel_i = address[2] ? 8'hF0 : 8'h0F;
            wb_we_i = 1'b0;
            wb_cyc_i = 1'b1;
            wb_stb_i = 1'b1;
            timeout = 0;

            while (wb_ack_o !== 1'b1 && wb_err_o !== 1'b1 && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if (address[2])
                data = wb_dat_o[63:32];
            else
                data = wb_dat_o[31:0];
            @(negedge clk);

            wb_cyc_i = 1'b0;
            wb_stb_i = 1'b0;
            wb_sel_i = 8'd0;
        end
    endtask

    
    // AXI4-Lite Access Tasks
    

    task axi_write32;
        input [31:0] address;
        input [31:0] data;
        integer timeout;
        reg aw_done;
        reg w_done;
        begin
            @(negedge clk);
            s_axi_awaddr_i = address;
            s_axi_awvalid_i = 1'b1;
            s_axi_wdata_i = data;
            s_axi_wstrb_i = 4'hF;
            s_axi_wvalid_i = 1'b1;
            s_axi_bready_i = 1'b0;
            aw_done = 1'b0;
            w_done = 1'b0;
            timeout = 0;

            while ((!aw_done || !w_done) && timeout < 20) begin
                @(posedge clk);
                if (s_axi_awvalid_i && s_axi_awready_o)
                    aw_done = 1'b1;
                if (s_axi_wvalid_i && s_axi_wready_o)
                    w_done = 1'b1;
                @(negedge clk);
                if (aw_done)
                    s_axi_awvalid_i = 1'b0;
                if (w_done)
                    s_axi_wvalid_i = 1'b0;
                timeout = timeout + 1;
            end
            timeout = 0;
            while (s_axi_bvalid_o !== 1'b1 && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            @(negedge clk);
            s_axi_bready_i = 1'b1;
            @(negedge clk);
            s_axi_bready_i = 1'b0;
            s_axi_awvalid_i = 1'b0;
            s_axi_wvalid_i = 1'b0;
        end
    endtask

    task axi_write32_split;
        input [31:0] address;
        input [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            s_axi_awaddr_i = address;
            s_axi_awvalid_i = 1'b1;
            s_axi_wdata_i = data;
            s_axi_wstrb_i = 4'hF;
            s_axi_wvalid_i = 1'b0;
            s_axi_bready_i = 1'b0;
            @(posedge clk);
            timeout = s_axi_awready_o;
            @(negedge clk);
            s_axi_awvalid_i = 1'b0;
            repeat (2) @(negedge clk);
            s_axi_wvalid_i = 1'b1;
            timeout = 0;
            while (s_axi_wready_o !== 1'b1 && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            @(negedge clk);
            s_axi_wvalid_i = 1'b0;
            timeout = 0;
            while (s_axi_bvalid_o !== 1'b1 && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            @(negedge clk);
            s_axi_bready_i = 1'b1;
            @(negedge clk);
            s_axi_bready_i = 1'b0;
        end
    endtask

    task axi_read32;
        input [31:0] address;
        output [31:0] data;
        integer timeout;
        reg accepted;
        begin
            @(negedge clk);
            s_axi_araddr_i = address;
            s_axi_arvalid_i = 1'b1;
            s_axi_rready_i = 1'b0;
            accepted = 1'b0;
            timeout = 0;
            while (!accepted && timeout < 20) begin
                @(posedge clk);
                if (s_axi_arvalid_i && s_axi_arready_o)
                    accepted = 1'b1;
                @(negedge clk);
                timeout = timeout + 1;
            end
            s_axi_arvalid_i = 1'b0;
            timeout = 0;
            while (s_axi_rvalid_o !== 1'b1 && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            data = s_axi_rdata_o;
            @(negedge clk);
            s_axi_rready_i = 1'b1;
            @(negedge clk);
            s_axi_rready_i = 1'b0;
        end
        
    endtask

    
    // Main Waveform Sequence
    

    initial begin
        $dumpfile("Sim_ethernet.vcd");
        $dumpvars(0, Sim_ethernet);

        clk = 1'b0;
        rst = 1'b1;
        scenario = 2'd0;
        checkpoint = 4'd0;

        wb_adr_i = 64'd0;
        wb_dat_i = 64'd0;
        wb_sel_i = 8'd0;
        wb_cyc_i = 1'b0;
        wb_stb_i = 1'b0;
        wb_we_i = 1'b0;

        s_axi_awaddr_i = 32'd0;
        s_axi_awvalid_i = 1'b0;
        s_axi_wdata_i = 32'd0;
        s_axi_wstrb_i = 4'd0;
        s_axi_wvalid_i = 1'b0;
        s_axi_bready_i = 1'b0;
        s_axi_araddr_i = 32'd0;
        s_axi_arvalid_i = 1'b0;
        s_axi_rready_i = 1'b0;

        read_value = 32'd0;
        tx_snapshot = 32'd0;
        rx_snapshot = 32'd0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);


        // SCENARIO 1
        // VirtIO identification, feature negotiation, queue setup and TX kick


        scenario = 2'd1;
        checkpoint = 4'd1;
        wb_read32(32'h000, read_value);
        wb_read32(32'h004, read_value);
        wb_read32(32'h008, read_value);
        wb_read32(32'h010, read_value);

        checkpoint = 4'd2;
        wb_write32(32'h070, 32'h00000001);
        wb_write32(32'h070, 32'h00000003);
        wb_write32(32'h024, 32'd0);
        wb_write32(32'h020, 32'h00000020);
        wb_write32(32'h024, 32'd1);
        wb_write32(32'h020, 32'h00000001);
        wb_write32(32'h070, 32'h0000000B);
        wb_write32(32'h070, 32'h0000000F);

        checkpoint = 4'd3;
        wb_write32(32'h030, 32'd0);
        wb_write32(32'h038, 32'd8);
        wb_write32(32'h080, 32'h81001000);
        wb_write32(32'h084, 32'd0);
        wb_write32(32'h090, 32'h81002000);
        wb_write32(32'h094, 32'd0);
        wb_write32(32'h0A0, 32'h81003000);
        wb_write32(32'h0A4, 32'd0);
        wb_write32(32'h044, 32'd1);
        wb_write32(32'h030, 32'd1);
        wb_write32(32'h038, 32'd8);
        wb_write32(32'h080, 32'h81004000);
        wb_write32(32'h084, 32'd0);
        wb_write32(32'h090, 32'h81005000);
        wb_write32(32'h094, 32'd0);
        wb_write32(32'h0A0, 32'h81006000);
        wb_write32(32'h0A4, 32'd0);
        wb_write32(32'h044, 32'd1);

        checkpoint = 4'd4;
        wb_write32(32'h050, 32'd0);
        repeat (3) @(posedge clk);
        axi_read32(32'h020, tx_snapshot);
        axi_read32(32'h008, read_value);
        axi_read32(32'h028, read_value);
        axi_read32(32'h030, read_value);


        // SCENARIO 2
        // Counter snapshot acknowledgement, RX queue and guest interrupt


        scenario = 2'd2;
        checkpoint = 4'd1;
        axi_write32(32'h00C, tx_snapshot);
        repeat (3) @(posedge clk);
        axi_read32(32'h008, read_value);

        checkpoint = 4'd2;
        wb_write32(32'h050, 32'd0);
        repeat (3) @(posedge clk);
        axi_read32(32'h020, tx_snapshot);
        wb_write32(32'h050, 32'd0);
        repeat (3) @(posedge clk);
        axi_write32_split(32'h00C, tx_snapshot);
        repeat (3) @(posedge clk);
        axi_read32(32'h008, read_value);
        axi_read32(32'h020, read_value);
        axi_write32(32'h00C, read_value);
        repeat (3) @(posedge clk);

        checkpoint = 4'd3;
        wb_write32(32'h050, 32'd1);
        repeat (3) @(posedge clk);
        axi_read32(32'h010, read_value);
        axi_read32(32'h024, rx_snapshot);
        axi_write32(32'h014, rx_snapshot);
        repeat (3) @(posedge clk);
        axi_read32(32'h010, read_value);

        checkpoint = 4'd4;
        axi_write32(32'h018, 32'h00000001);
        repeat (3) @(posedge clk);
        wb_read32(32'h060, read_value);
        wb_write32(32'h064, 32'd1);
        repeat (3) @(posedge clk);
        wb_read32(32'h060, read_value);

        checkpoint = 4'd5;
        wb_write32(32'h070, 32'd0);
        repeat (5) @(posedge clk);
        scenario = 2'd0;
        checkpoint = 4'd0;
        repeat (10) @(posedge clk);
        $finish;
        
    end

endmodule