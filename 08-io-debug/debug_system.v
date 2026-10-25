`timescale 1ns/1ps

// Top-level external debug path.
// JTAG DTM -> DMI -> Debug Module -> independent Wishbone system-bus master.
// The Wishbone master must be connected to the SoC bus arbiter as another master.

module debug_system #(
    parameter [31:0] JTAG_IDCODE = 32'h00000001,
    parameter TIMEOUT_CYCLES = 1024
)(
    input wire clk_i,
    input wire rst_i,

    input wire jtag_tck_i,
    input wire jtag_tms_i,
    input wire jtag_tdi_i,
    input wire jtag_trst_n_i,
    output wire jtag_tdo_o,

    input wire core_available_i,
    input wire core_halted_i,
    output wire core_haltreq_o,
    output wire core_resumereq_o,
    output wire core_ndmreset_o,

    output wire core_reg_req_o,
    output wire core_reg_write_o,
    output wire [15:0] core_regno_o,
    output wire [63:0] core_reg_wdata_o,
    input wire core_reg_ready_i,
    input wire core_reg_error_i,
    input wire [63:0] core_reg_rdata_i,

    output wire core_exec_progbuf_o,
    input wire core_progbuf_done_i,
    input wire core_progbuf_exception_i,
    output wire [127:0] core_progbuf_o,

    output wire dbg_wb_cyc_o,
    output wire dbg_wb_stb_o,
    output wire dbg_wb_we_o,
    output wire [63:0] dbg_wb_adr_o,
    output wire [63:0] dbg_wb_dat_o,
    output wire [7:0] dbg_wb_sel_o,
    input wire [63:0] dbg_wb_dat_i,
    input wire dbg_wb_ack_i,
    input wire dbg_wb_err_i,
    output wire dbg_wb_busy_o,
    output wire dbg_wb_done_o,
    output wire dbg_wb_error_o
);

    wire dmi_valid;
    wire [1:0] dmi_op;
    wire [6:0] dmi_addr;
    wire [31:0] dmi_data;
    wire dmi_ready;
    wire [1:0] dmi_resp_op;
    wire [31:0] dmi_resp_data;

    wire bus_req;
    wire bus_write;
    wire [63:0] bus_addr;
    wire [63:0] bus_wdata;
    wire [7:0] bus_sel;
    wire bus_busy;
    wire bus_done;
    wire bus_error;
    wire [63:0] bus_rdata;

    debug_transport #(
        .IDCODE(JTAG_IDCODE),
        .ABITS(7)
    ) transport(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .tck_i(jtag_tck_i),
        .tms_i(jtag_tms_i),
        .tdi_i(jtag_tdi_i),
        .trst_n_i(jtag_trst_n_i),
        .tdo_o(jtag_tdo_o),
        .dmi_valid_o(dmi_valid),
        .dmi_op_o(dmi_op),
        .dmi_addr_o(dmi_addr),
        .dmi_data_o(dmi_data),
        .dmi_ready_i(dmi_ready),
        .dmi_resp_op_i(dmi_resp_op),
        .dmi_resp_data_i(dmi_resp_data)
    );

    debug_module dm(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .dmi_valid_i(dmi_valid),
        .dmi_op_i(dmi_op),
        .dmi_addr_i(dmi_addr),
        .dmi_data_i(dmi_data),
        .dmi_ready_o(dmi_ready),
        .dmi_resp_op_o(dmi_resp_op),
        .dmi_resp_data_o(dmi_resp_data),
        .hart_available_i(core_available_i),
        .hart_halted_i(core_halted_i),
        .hart_haltreq_o(core_haltreq_o),
        .hart_resumereq_o(core_resumereq_o),
        .hart_ndmreset_o(core_ndmreset_o),
        .hart_reg_req_o(core_reg_req_o),
        .hart_reg_write_o(core_reg_write_o),
        .hart_regno_o(core_regno_o),
        .hart_reg_wdata_o(core_reg_wdata_o),
        .hart_reg_ready_i(core_reg_ready_i),
        .hart_reg_error_i(core_reg_error_i),
        .hart_reg_rdata_i(core_reg_rdata_i),
        .hart_exec_progbuf_o(core_exec_progbuf_o),
        .hart_progbuf_done_i(core_progbuf_done_i),
        .hart_progbuf_exception_i(core_progbuf_exception_i),
        .hart_progbuf_o(core_progbuf_o),
        .bus_req_o(bus_req),
        .bus_write_o(bus_write),
        .bus_addr_o(bus_addr),
        .bus_wdata_o(bus_wdata),
        .bus_sel_o(bus_sel),
        .bus_busy_i(bus_busy),
        .bus_done_i(bus_done),
        .bus_error_i(bus_error),
        .bus_rdata_i(bus_rdata)
    );

    debug_bus_access #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) bus_access(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(bus_req),
        .we_i(bus_write),
        .addr_i(bus_addr),
        .wdata_i(bus_wdata),
        .sel_i(bus_sel),
        .busy_o(bus_busy),
        .done_o(bus_done),
        .error_o(bus_error),
        .rdata_o(bus_rdata),
        .wb_cyc_o(dbg_wb_cyc_o),
        .wb_stb_o(dbg_wb_stb_o),
        .wb_we_o(dbg_wb_we_o),
        .wb_adr_o(dbg_wb_adr_o),
        .wb_dat_o(dbg_wb_dat_o),
        .wb_sel_o(dbg_wb_sel_o),
        .wb_dat_i(dbg_wb_dat_i),
        .wb_ack_i(dbg_wb_ack_i),
        .wb_err_i(dbg_wb_err_i)
    );

    assign dbg_wb_busy_o = bus_busy;
    assign dbg_wb_done_o = bus_done;
    assign dbg_wb_error_o = bus_error;

endmodule