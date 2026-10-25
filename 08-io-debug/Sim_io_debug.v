`timescale 1ns/1ps

// GTKWave testbench for the I/O + Debug project.

module Sim_io_debug;

    reg clk_i;
    reg rst_i;
    reg [3:0] scenario;
    reg [7:0] checkpoint;

    reg wb_cyc_i;
    reg wb_stb_i;
    reg wb_we_i;
    reg [63:0] wb_adr_i;
    reg [63:0] wb_dat_i;
    reg [7:0] wb_sel_i;
    wire [63:0] wb_dat_o;
    wire wb_ack_o;
    wire wb_err_o;

    reg uart_rx_i;
    wire uart_tx_o;
    wire uart_irq_o;
    reg [31:0] gpio_i;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe_o;
    wire gpio_irq_o;

    reg trace_valid_i;
    reg [63:0] trace_pc_i;
    reg [31:0] trace_instruction_i;
    reg [1:0] trace_privilege_i;
    reg trace_exception_i;
    wire trace_irq_o;
    wire timer_msip_o;
    wire timer_mtip_o;
    wire [2:0] io_irq_o;

    reg jtag_tck_i;
    reg jtag_tms_i;
    reg jtag_tdi_i;
    reg jtag_trst_n_i;
    wire jtag_tdo_o;

    reg core_available_i;
    reg core_halted_i;
    wire core_haltreq_o;
    wire core_resumereq_o;
    wire core_ndmreset_o;
    wire core_reg_req_o;
    wire core_reg_write_o;
    wire [15:0] core_regno_o;
    wire [63:0] core_reg_wdata_o;
    reg core_reg_ready_i;
    reg core_reg_error_i;
    reg [63:0] core_reg_rdata_i;
    wire core_exec_progbuf_o;
    reg core_progbuf_done_i;
    reg core_progbuf_exception_i;
    wire [127:0] core_progbuf_o;

    wire dbg_wb_cyc_o;
    wire dbg_wb_stb_o;
    wire dbg_wb_we_o;
    wire [63:0] dbg_wb_adr_o;
    wire [63:0] dbg_wb_dat_o;
    wire [7:0] dbg_wb_sel_o;
    reg [63:0] dbg_wb_dat_i;
    reg dbg_wb_ack_i;
    reg dbg_wb_err_i;
    wire dbg_wb_busy_o;
    wire dbg_wb_done_o;
    wire dbg_wb_error_o;
    reg dbg_reply_seen;

    integer i;

    debug_io_interconnect #(
        .GPIO_WIDTH(32),
        .TRACE_DEPTH(4)
    ) io_dut(
        .clk_i(clk_i), .rst_i(rst_i),
        .wb_cyc_i(wb_cyc_i), .wb_stb_i(wb_stb_i), .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i), .wb_dat_i(wb_dat_i), .wb_sel_i(wb_sel_i),
        .wb_dat_o(wb_dat_o), .wb_ack_o(wb_ack_o), .wb_err_o(wb_err_o),
        .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o), .uart_irq_o(uart_irq_o),
        .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_oe_o(gpio_oe_o), .gpio_irq_o(gpio_irq_o),
        .trace_valid_i(trace_valid_i), .trace_pc_i(trace_pc_i),
        .trace_instruction_i(trace_instruction_i), .trace_privilege_i(trace_privilege_i),
        .trace_exception_i(trace_exception_i), .trace_irq_o(trace_irq_o),
        .timer_msip_o(timer_msip_o), .timer_mtip_o(timer_mtip_o), .io_irq_o(io_irq_o)
    );

    debug_system #(
        .JTAG_IDCODE(32'h12345679),
        .TIMEOUT_CYCLES(32)
    ) dbg_dut(
        .clk_i(clk_i), .rst_i(rst_i),
        .jtag_tck_i(jtag_tck_i), .jtag_tms_i(jtag_tms_i),
        .jtag_tdi_i(jtag_tdi_i), .jtag_trst_n_i(jtag_trst_n_i), .jtag_tdo_o(jtag_tdo_o),
        .core_available_i(core_available_i), .core_halted_i(core_halted_i),
        .core_haltreq_o(core_haltreq_o), .core_resumereq_o(core_resumereq_o),
        .core_ndmreset_o(core_ndmreset_o),
        .core_reg_req_o(core_reg_req_o), .core_reg_write_o(core_reg_write_o),
        .core_regno_o(core_regno_o), .core_reg_wdata_o(core_reg_wdata_o),
        .core_reg_ready_i(core_reg_ready_i), .core_reg_error_i(core_reg_error_i),
        .core_reg_rdata_i(core_reg_rdata_i),
        .core_exec_progbuf_o(core_exec_progbuf_o),
        .core_progbuf_done_i(core_progbuf_done_i), .core_progbuf_exception_i(core_progbuf_exception_i),
        .core_progbuf_o(core_progbuf_o),
        .dbg_wb_cyc_o(dbg_wb_cyc_o), .dbg_wb_stb_o(dbg_wb_stb_o),
        .dbg_wb_we_o(dbg_wb_we_o), .dbg_wb_adr_o(dbg_wb_adr_o),
        .dbg_wb_dat_o(dbg_wb_dat_o), .dbg_wb_sel_o(dbg_wb_sel_o),
        .dbg_wb_dat_i(dbg_wb_dat_i), .dbg_wb_ack_i(dbg_wb_ack_i), .dbg_wb_err_i(dbg_wb_err_i),
        .dbg_wb_busy_o(dbg_wb_busy_o), .dbg_wb_done_o(dbg_wb_done_o), .dbg_wb_error_o(dbg_wb_error_o)
    );

    always #5 clk_i = ~clk_i;

    // One-cycle response model for debugger System Bus Access.
    always @(posedge clk_i) begin

        if (rst_i) begin
            dbg_wb_ack_i <= 1'b0;
            dbg_wb_err_i <= 1'b0;
            dbg_wb_dat_i <= 64'd0;
            dbg_reply_seen <= 1'b0;
        end else begin

            dbg_wb_ack_i <= 1'b0;
            dbg_wb_err_i <= 1'b0;
            if (!dbg_wb_cyc_o || !dbg_wb_stb_o) begin
                dbg_reply_seen <= 1'b0;

            end else if (!dbg_reply_seen) begin
                dbg_reply_seen <= 1'b1;
                dbg_wb_dat_i <= 64'h1122334455667788;
                dbg_wb_ack_i <= 1'b1;

            end
       
        end
    end

    // Fake core acknowledgement for abstract register and program-buffer commands.
    always @(negedge clk_i) begin
        if (rst_i) begin
            core_reg_ready_i = 1'b0;
            core_reg_error_i = 1'b0;
            core_reg_rdata_i = 64'd0;
            core_progbuf_done_i = 1'b0;
            core_progbuf_exception_i = 1'b0;
        end else begin
            core_reg_ready_i = core_reg_req_o;
            core_reg_error_i = 1'b0;
            core_reg_rdata_i = 64'h1122334455667788;
            core_progbuf_done_i = core_exec_progbuf_o;
            core_progbuf_exception_i = 1'b0;
        end
    end

    task wait_cycles;
        input integer cycles;
        integer cycle_index;
        begin
            for (cycle_index = 0; cycle_index < cycles; cycle_index = cycle_index + 1)
                @(posedge clk_i);
            #1;
        end
    endtask

    task wb_write;
        input [63:0] address_value;
        input [63:0] data_value;
        integer wait_count;
        begin
            @(negedge clk_i);
            wb_adr_i = address_value;
            wb_dat_i = data_value;
            wb_we_i = 1'b1;
            wb_sel_i = 8'hFF;
            wb_cyc_i = 1'b1;
            wb_stb_i = 1'b1;
            wait_count = 0;

            while ((wb_ack_o !== 1'b1) && (wb_err_o !== 1'b1) && (wait_count < 100)) begin
                @(posedge clk_i);
                #1;
                wait_count = wait_count + 1;
            end

            @(negedge clk_i);
            wb_cyc_i = 1'b0;
            wb_stb_i = 1'b0;
            wb_we_i = 1'b0;
            @(posedge clk_i);
            #1;
        end
    endtask

    task pulse_trace;
        input [63:0] pc_value;
        input [31:0] instruction_value;
        input [1:0] privilege_value;
        input exception_value;

        begin
            @(negedge clk_i);
            trace_pc_i = pc_value;
            trace_instruction_i = instruction_value;
            trace_privilege_i = privilege_value;
            trace_exception_i = exception_value;
            trace_valid_i = 1'b1;
            @(negedge clk_i);
            trace_valid_i = 1'b0;
        end
    endtask

    task jtag_cycle;
        input tms_value;
        input tdi_value;
        begin
            jtag_tms_i = tms_value;
            jtag_tdi_i = tdi_value;
            #10;
            jtag_tck_i = 1'b1;
            #10;
            jtag_tck_i = 1'b0;
            #4;
        end
    endtask

    task jtag_reset;
        integer reset_index;
        begin
            for (reset_index = 0; reset_index < 6; reset_index = reset_index + 1)
                jtag_cycle(1'b1, 1'b0);
            jtag_cycle(1'b0, 1'b0);
        end
    endtask

    task jtag_select_ir;
        input [4:0] instruction_value;
        integer bit_index;
        begin
            jtag_cycle(1'b1, 1'b0);
            jtag_cycle(1'b1, 1'b0);
            jtag_cycle(1'b0, 1'b0);
            jtag_cycle(1'b0, 1'b0);

            for (bit_index = 0; bit_index < 5; bit_index = bit_index + 1)
                jtag_cycle(bit_index == 4, instruction_value[bit_index]);
            
            jtag_cycle(1'b1, 1'b0);
            jtag_cycle(1'b0, 1'b0);
        end
    endtask

    task jtag_dmi_write;
        input [6:0] address_value;
        input [31:0] data_value;
        reg [40:0] shift_value;
        integer bit_index;
        begin

            jtag_select_ir(5'h11);
            shift_value = {address_value, data_value, 2'b10};
            jtag_cycle(1'b1, 1'b0);
            jtag_cycle(1'b0, 1'b0);
            jtag_cycle(1'b0, 1'b0);

            for (bit_index = 0; bit_index < 41; bit_index = bit_index + 1)
                jtag_cycle(bit_index == 40, shift_value[bit_index]);
            
            jtag_cycle(1'b1, 1'b0);
            jtag_cycle(1'b0, 1'b0);
            repeat (12) @(posedge clk_i);
            #1;
        end
    endtask

    initial begin
        $dumpfile("Sim_io_debug.vcd");
        $dumpvars(0, Sim_io_debug);

        clk_i = 1'b0;
        rst_i = 1'b1;
        scenario = 0;
        checkpoint = 0;

        wb_cyc_i = 1'b0;
        wb_stb_i = 1'b0;
        wb_we_i = 1'b0;
        wb_adr_i = 64'd0;
        wb_dat_i = 64'd0;
        wb_sel_i = 8'hFF;
        uart_rx_i = 1'b1;
        gpio_i = 32'd0;
        trace_valid_i = 1'b0;
        trace_pc_i = 64'd0;
        trace_instruction_i = 32'd0;
        trace_privilege_i = 2'd3;
        trace_exception_i = 1'b0;

        jtag_tck_i = 1'b0;
        jtag_tms_i = 1'b1;
        jtag_tdi_i = 1'b0;
        jtag_trst_n_i = 1'b0;

        core_available_i = 1'b1;
        core_halted_i = 1'b0;
        core_reg_ready_i = 1'b0;
        core_reg_error_i = 1'b0;
        core_reg_rdata_i = 64'd0;
        core_progbuf_done_i = 1'b0;
        core_progbuf_exception_i = 1'b0;
        dbg_wb_dat_i = 64'd0;
        dbg_wb_ack_i = 1'b0;
        dbg_wb_err_i = 1'b0;
        dbg_reply_seen = 1'b0;

        repeat (6) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        jtag_trst_n_i = 1'b1;
        wait_cycles(3);


        // SCENARIO 1 - UART TX and GPIO register access
        // Suggested screenshot interval: approximately 0 ns - 2.2 us.

        scenario = 1;
        checkpoint = 1;
        wb_write(64'h0000000010010000, 64'h00000000A5A50F0F);
        wb_write(64'h0000000010010010, 64'h00000000FFFFFFFF);
        checkpoint = 2;
        wb_write(64'h0000000010000038, 64'h000000000000005A);
        wb_write(64'h0000000010000000, 64'h00000000000000A5);
        checkpoint = 3;
        repeat (200) @(posedge clk_i);


        // SCENARIO 2 - GPIO interrupt, timer interrupt, and trace overflow
        // Suggested screenshot interval: approximately 2.2 us - 3.3 us.

        scenario = 2;
        checkpoint = 10;
        gpio_i = 32'd0;
        wb_write(64'h0000000010010018, 64'd1);
        gpio_i = 32'd1;
        wait_cycles(8);
        checkpoint = 11;
        wb_write(64'h0000000010030000, 64'd1);
        wb_write(64'h0000000010030000, 64'd0);
        wb_write(64'h0000000010034000, 64'hFFFFFFFFFFFFFFFF);
        wb_write(64'h0000000010034000, 64'd0);
        checkpoint = 12;
        wb_write(64'h0000000010020000, 64'h3);
        for (i = 0; i < 5; i = i + 1)
            pulse_trace(64'h0000000080000000 + (i * 4), 32'h00100093 + i, i[1:0], (i == 3));
        wait_cycles(80);
        checkpoint = 13;


        // SCENARIO 3 - JTAG DMI, CPU halt, program buffer, and SBA
        // Suggested screenshot interval: approximately 3.3 us - 13.5 us.

        scenario = 3;
        checkpoint = 20;
        jtag_reset();
        jtag_dmi_write(7'h10, 32'h00000001);
        checkpoint = 21;
        jtag_dmi_write(7'h10, 32'h80000001);
        core_halted_i = 1'b1;
        checkpoint = 22;
        jtag_dmi_write(7'h20, 32'h00100073);
        jtag_dmi_write(7'h17, 32'h00040000);
        wait_cycles(5);
        checkpoint = 23;
        jtag_dmi_write(7'h38, 32'h00160000);
        jtag_dmi_write(7'h39, 32'h00001000);
        wait_cycles(20);
        checkpoint = 24;
        repeat (30) @(posedge clk_i);

        $finish;
    end

    initial begin
        #200000;
        $finish;
    end

endmodule