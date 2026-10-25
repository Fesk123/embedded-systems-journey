`timescale 1ns/1ps

// Single-hart RISC-V Debug Module with DMI registers, abstract register access, a four-word program buffer, and 64-bit System Bus Access.
// The core must implement the debug sideband interface exposed by this module.

module debug_module #(
    parameter HART_COUNT = 1
)(
    input wire clk_i,
    input wire rst_i,

    input wire dmi_valid_i,
    input wire [1:0] dmi_op_i,
    input wire [6:0] dmi_addr_i,
    input wire [31:0] dmi_data_i,
    output wire dmi_ready_o,
    output reg [1:0] dmi_resp_op_o,
    output wire [31:0] dmi_resp_data_o,

    input wire hart_available_i,
    input wire hart_halted_i,
    output wire hart_haltreq_o,
    output reg hart_resumereq_o,
    output wire hart_ndmreset_o,

    output reg hart_reg_req_o,
    output reg hart_reg_write_o,
    output reg [15:0] hart_regno_o,
    output reg [63:0] hart_reg_wdata_o,
    input wire hart_reg_ready_i,
    input wire hart_reg_error_i,
    input wire [63:0] hart_reg_rdata_i,

    output reg hart_exec_progbuf_o,
    input wire hart_progbuf_done_i,
    input wire hart_progbuf_exception_i,
    output wire [127:0] hart_progbuf_o,

    output reg bus_req_o,
    output reg bus_write_o,
    output reg [63:0] bus_addr_o,
    output reg [63:0] bus_wdata_o,
    output reg [7:0] bus_sel_o,
    input wire bus_busy_i,
    input wire bus_done_i,
    input wire bus_error_i,
    input wire [63:0] bus_rdata_i
);

    localparam ABS_IDLE = 2'd0;
    localparam ABS_REG_WAIT = 2'd1;
    localparam ABS_PROGBUF_WAIT = 2'd2;

    localparam SBA_IDLE = 1'b0;
    localparam SBA_WAIT = 1'b1;

    wire [31:0] dmcontrol;
    wire [31:0] data0;
    wire [31:0] data1;
    wire [31:0] command_reg;
    wire [31:0] abstractauto;
    wire [127:0] progbuf;
    wire [31:0] sbcs_control;
    wire [63:0] sbaddress;
    wire [63:0] sbdata;

    wire reg_wr_en;
    wire dmclear = dmi_write && dmi_addr_i == 7'h10 && !dmi_data_i[0];
    wire [31:0] reg_rd_data;
    reg [31:0] dmstatus_value;
    reg [31:0] abstractcs_value;
    reg [31:0] sbcs_value;

    reg [1:0] abstract_state;
    reg abstract_busy;
    reg [2:0] abstract_cmderr;
    reg [31:0] command_latched;
    reg resume_pending;
    reg resume_ack;
    reg [63:0] abstract_update_data;
    reg abstract_data_update;

    reg [2:0] sb_error;
    reg sb_busy_error;
    reg sba_state;
    reg sba_read_latched;
    reg [63:0] sba_addr_latched;
    reg [2:0] sba_access_latched;
    reg sba_autoincrement_latched;

    reg [63:0] sba_start_address;
    reg [63:0] sba_start_data;
    reg sba_start_write;
    reg sba_start_request;

    wire sbaddress_update = (sba_state == SBA_WAIT) && bus_done_i && !bus_error_i && sba_autoincrement_latched;
    wire [63:0] sbaddress_update_data = sba_addr_latched + (64'd1 << sba_access_latched);
    wire sbdata_update = (sba_state == SBA_WAIT) && bus_done_i && !bus_error_i && sba_read_latched;
    wire [63:0] sbdata_update_data = bus_rdata_i >> (sba_addr_latched[2:0] * 8);

    wire dmi_fire = dmi_valid_i && dmi_ready_o;
    wire dmi_write = dmi_fire && dmi_op_i == 2'b10;
    wire dmi_read = dmi_fire && dmi_op_i == 2'b01;
    wire dmactive = dmcontrol[0];
    wire sba_busy = (sba_state == SBA_WAIT) || bus_busy_i;
    wire [2:0] sbaccess = sbcs_control[19:17];

    assign dmi_ready_o = 1'b1;
    assign dmi_resp_data_o = reg_rd_data;
    assign hart_haltreq_o = dmactive && dmcontrol[31];
    assign hart_ndmreset_o = dmactive && dmcontrol[1];
    assign hart_progbuf_o = progbuf;

    assign reg_wr_en = dmi_write && (dmactive || dmi_addr_i == 7'h10) && !((sba_busy) && ((dmi_addr_i == 7'h39) || (dmi_addr_i == 7'h3A) || (dmi_addr_i == 7'h3C) || (dmi_addr_i == 7'h3D)));

    // Dynamic status fields visible through standard DMI addresses.

    always @* begin
        dmstatus_value = 32'd0;
        dmstatus_value[3:0] = 4'd3; // RISC-V Debug Specification 1.0.
        dmstatus_value[7] = 1'b1; // authenticated
        dmstatus_value[8] = hart_available_i && hart_halted_i;
        dmstatus_value[9] = hart_available_i && hart_halted_i;
        dmstatus_value[10] = hart_available_i && !hart_halted_i;
        dmstatus_value[11] = hart_available_i && !hart_halted_i;
        dmstatus_value[12] = !hart_available_i;
        dmstatus_value[13] = !hart_available_i;
        dmstatus_value[14] = 1'b0;
        dmstatus_value[15] = 1'b0;
        dmstatus_value[16] = resume_ack;
        dmstatus_value[17] = resume_ack;
        dmstatus_value[18] = 1'b0;
        dmstatus_value[19] = 1'b0;
    end

    always @* begin
        abstractcs_value = 32'd0;
        abstractcs_value[3:0] = 4'd2; // data0 and data1 are implemented.
        abstractcs_value[10:8] = abstract_cmderr;
        abstractcs_value[12] = abstract_busy;
        abstractcs_value[28:24] = 5'd4; // Four 32-bit progbuf words.
    end

    always @* begin
        sbcs_value = 32'd0;
        sbcs_value[31:29] = 3'b001; // System Bus Access version 1.0.
        sbcs_value[22] = sb_busy_error;
        sbcs_value[21] = sba_busy;
        sbcs_value[20] = sbcs_control[20];
        sbcs_value[19:17] = sbcs_control[19:17];
        sbcs_value[16] = sbcs_control[16];
        sbcs_value[15] = sbcs_control[15];
        sbcs_value[14:12] = sb_error;
        sbcs_value[11:5] = 7'd64; // Physical address width.
        sbcs_value[4:0] = 5'b01111; // 64/32/16/8-bit access sizes.
    end

    debug_registers register_file(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .dmclear_i(dmclear),
        .wr_en_i(reg_wr_en),
        .wr_addr_i(dmi_addr_i),
        .wr_data_i(dmi_data_i),
        .rd_addr_i(dmi_addr_i),
        .rd_data_o(reg_rd_data),
        .dmstatus_i(dmstatus_value),
        .abstractcs_i(abstractcs_value),
        .sbcs_i(sbcs_value),
        .abstract_data_update_i(abstract_data_update),
        .abstract_data_update_data_i(abstract_update_data),
        .sbdata_update_i(sbdata_update),
        .sbdata_update_data_i(sbdata_update_data),
        .sbaddress_update_i(sbaddress_update),
        .sbaddress_update_data_i(sbaddress_update_data),
        .dmcontrol_o(dmcontrol),
        .data0_o(data0),
        .data1_o(data1),
        .command_o(command_reg),
        .abstractauto_o(abstractauto),
        .progbuf_o(progbuf),
        .sbcs_control_o(sbcs_control),
        .sbaddress_o(sbaddress),
        .sbdata_o(sbdata)
    );

    // Abstract commands and the processor-side debug interface.
    always @(posedge clk_i) begin

        if (rst_i) begin
            abstract_state <= ABS_IDLE;
            abstract_busy <= 1'b0;
            abstract_cmderr <= 0;
            command_latched <= 0;
            resume_pending <= 1'b0;
            resume_ack <= 1'b0;
            hart_reg_req_o <= 1'b0;
            hart_reg_write_o <= 1'b0;
            hart_regno_o <= 0;
            hart_reg_wdata_o <= 0;
            hart_exec_progbuf_o <= 1'b0;
            hart_resumereq_o <= 1'b0;
            abstract_data_update <= 1'b0;
            abstract_update_data <= 0;

        end else begin
            hart_resumereq_o <= 1'b0;
            hart_exec_progbuf_o <= 1'b0;
            abstract_data_update <= 1'b0;

            if (dmi_write && dmi_addr_i == 7'h10 && dmi_data_i[30] && dmactive && !dmcontrol[31]) begin
                hart_resumereq_o <= 1'b1;
                resume_pending <= 1'b1;
                resume_ack <= 1'b0;
            end

            if (hart_halted_i)
                resume_ack <= 1'b0;

            if (resume_pending && hart_available_i && !hart_halted_i) begin
                resume_pending <= 1'b0;
                resume_ack <= 1'b1;
            end

            if (dmi_write && dmi_addr_i == 7'h16 && |dmi_data_i[10:8])
                abstract_cmderr <= 0;

            case (abstract_state)
                ABS_IDLE: begin
                    hart_reg_req_o <= 1'b0;
                    abstract_busy <= 1'b0;

                    if (dmi_write && dmi_addr_i == 7'h17 && dmactive) begin
                        command_latched <= dmi_data_i;

                        if (abstract_cmderr != 0) begin
                            abstract_busy <= 1'b0;

                        end else if (abstract_busy) begin
                            if (abstract_cmderr == 0)
                                abstract_cmderr <= 3'd1;

                        end else if (dmi_data_i[31:24] != 8'd0) begin
                            abstract_cmderr <= 3'd2;

                        end else if (dmi_data_i[19]) begin
                            abstract_cmderr <= 3'd2;

                        end else if (dmi_data_i[17]) begin
                            if (!hart_available_i || !hart_halted_i) begin
                                abstract_cmderr <= 3'd4;

                            end else if (dmi_data_i[22:20] != 3'd2 && dmi_data_i[22:20] != 3'd3) begin
                                abstract_cmderr <= 3'd2;

                            end else begin
                                hart_reg_req_o <= 1'b1;
                                hart_reg_write_o <= dmi_data_i[16];
                                hart_regno_o <= dmi_data_i[15:0];
                                hart_reg_wdata_o <= (dmi_data_i[22:20] == 3'd2) ? {32'd0, data0} : {data1, data0};
                                abstract_busy <= 1'b1;
                                abstract_state <= ABS_REG_WAIT;
                            end

                        end else if (dmi_data_i[18]) begin
                            if (!hart_available_i || !hart_halted_i) begin
                                abstract_cmderr <= 3'd4;

                            end else begin
                                hart_exec_progbuf_o <= 1'b1;
                                abstract_busy <= 1'b1;
                                abstract_state <= ABS_PROGBUF_WAIT;
                            end
                        end

                    end
                end

                ABS_REG_WAIT: begin
                    if (dmi_write && dmi_addr_i == 7'h17 && abstract_cmderr == 0)
                        abstract_cmderr <= 3'd1;

                    if (hart_reg_ready_i && hart_reg_req_o) begin
                        hart_reg_req_o <= 1'b0;

                        if (hart_reg_error_i) begin
                            if (abstract_cmderr == 0)
                                abstract_cmderr <= 3'd3;
                            abstract_busy <= 1'b0;
                            abstract_state <= ABS_IDLE;

                        end else begin
                            if (!command_latched[16]) begin
                                if (command_latched[22:20] == 3'd2)
                                    abstract_update_data <= {32'd0, hart_reg_rdata_i[31:0]};
                                else
                                    abstract_update_data <= hart_reg_rdata_i;
                                abstract_data_update <= 1'b1;
                            end

                            if (command_latched[18]) begin
                                hart_exec_progbuf_o <= 1'b1;
                                abstract_state <= ABS_PROGBUF_WAIT;
                            end else begin
                                abstract_busy <= 1'b0;
                                abstract_state <= ABS_IDLE;
                            end
                        end

                    end

                end

                ABS_PROGBUF_WAIT: begin
                    if (dmi_write && dmi_addr_i == 7'h17 && abstract_cmderr == 0)
                        abstract_cmderr <= 3'd1;

                    if (hart_progbuf_done_i) begin
                        if (hart_progbuf_exception_i && abstract_cmderr == 0)
                            abstract_cmderr <= 3'd3;
                        abstract_busy <= 1'b0;
                        abstract_state <= ABS_IDLE;
                    end
                end

                default: begin
                    abstract_state <= ABS_IDLE;
                    abstract_busy <= 1'b0;
                    hart_reg_req_o <= 1'b0;
                end
            endcase

            if (dmclear) begin
                abstract_state <= ABS_IDLE;
                abstract_busy <= 1'b0;
                abstract_cmderr <= 0;
                hart_reg_req_o <= 1'b0;
                hart_exec_progbuf_o <= 1'b0;
                resume_pending <= 1'b0;
                resume_ack <= 1'b0;
            end
        end
    end

    // System Bus Access engine. Requests are serialized here, not in the CPU datapath.
    always @(posedge clk_i) begin
        if (rst_i) begin
            sba_state <= SBA_IDLE;
            sb_error <= 0;
            sb_busy_error <= 1'b0;
            bus_req_o <= 1'b0;
            bus_write_o <= 1'b0;
            bus_addr_o <= 0;
            bus_wdata_o <= 0;
            bus_sel_o <= 0;
            sba_read_latched <= 1'b0;
            sba_addr_latched <= 0;
            sba_access_latched <= 0;
            sba_autoincrement_latched <= 1'b0;
            sba_start_address <= 0;
            sba_start_data <= 0;
            sba_start_write <= 1'b0;
            sba_start_request <= 1'b0;
        end else begin
            bus_req_o <= 1'b0;

            if (dmi_write && dmi_addr_i == 7'h38 && !sba_busy) begin
                if (dmi_data_i[22])
                    sb_busy_error <= 1'b0;
                if (|dmi_data_i[14:12])
                    sb_error <= 0;
            end

            // A new address/data operation while busy sets the standard sticky busy error.
            if (sba_busy && dmi_fire &&
                ((dmi_op_i == 2'b10 && (dmi_addr_i == 7'h39 || dmi_addr_i == 7'h3A || dmi_addr_i == 7'h3C)) || (dmi_op_i == 2'b01 && dmi_addr_i == 7'h3C))) begin
                sb_busy_error <= 1'b1;
            end

            if (sba_state == SBA_IDLE && !sba_busy) begin
                sba_start_request <= 1'b0;

                if (sb_error == 0 && !sb_busy_error) begin
                    if (dmi_write && dmi_addr_i == 7'h39 && sbcs_control[20]) begin
                        sba_start_address <= {sbaddress[63:32], dmi_data_i};
                        sba_start_data <= sbdata;
                        sba_start_write <= 1'b0;
                        sba_start_request <= 1'b1;

                    end else if (dmi_write && dmi_addr_i == 7'h3C) begin
                        sba_start_address <= sbaddress;
                        sba_start_data <= {sbdata[63:32], dmi_data_i};
                        sba_start_write <= 1'b1;
                        sba_start_request <= 1'b1;

                    end else if (dmi_read && dmi_addr_i == 7'h3C && sbcs_control[15]) begin
                        sba_start_address <= sbaddress;
                        sba_start_data <= sbdata;
                        sba_start_write <= 1'b0;
                        sba_start_request <= 1'b1;

                    end
                end


                if (sba_start_request) begin
                    if (sbaccess > 3'd3) begin
                        sb_error <= 3'd4;
                        sba_start_request <= 1'b0;

                    end else if ((sba_start_address & ((64'd1 << sbaccess) - 1'b1)) != 0) begin
                        sb_error <= 3'd3;
                        sba_start_request <= 1'b0;

                    end else begin
                        sba_state <= SBA_WAIT;
                        sba_read_latched <= !sba_start_write;
                        sba_addr_latched <= sba_start_address;
                        sba_access_latched <= sbaccess;
                        sba_autoincrement_latched <= sbcs_control[16];
                        bus_req_o <= 1'b1;
                        bus_write_o <= sba_start_write;
                        bus_addr_o <= {sba_start_address[63:3], 3'b000};
                        bus_wdata_o <= sba_start_data << (sba_start_address[2:0] * 8);

                        case (sbaccess)
                            3'd0: bus_sel_o <= 8'h01 << sba_start_address[2:0];
                            3'd1: bus_sel_o <= 8'h03 << sba_start_address[2:0];
                            3'd2: bus_sel_o <= 8'h0F << sba_start_address[2:0];
                            3'd3: bus_sel_o <= 8'hFF;
                            default: bus_sel_o <= 8'h00;
                        
                        endcase
                        
                        sba_start_request <= 1'b0;

                    end
                end
            end else if (sba_state == SBA_WAIT && bus_done_i) begin
                sba_state <= SBA_IDLE;

                if (bus_error_i) begin
                    sb_error <= 3'd7; // Report generic bus faults as the standard 'other' error.
                end
            end

        end
        
    end

    // DMI is a one-cycle register bus. An invalid operation is reported as failed.
    always @* begin
        dmi_resp_op_o = 2'b00;
        if (dmi_op_i == 2'b11)
            dmi_resp_op_o = 2'b10;
    end

endmodule