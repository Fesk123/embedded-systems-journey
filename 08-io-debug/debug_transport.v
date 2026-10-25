`timescale 1ns/1ps

// RISC-V JTAG Debug Transport Module (DTM), compatible with the JTAG-DTM register layout in the RISC-V Debug Specification 1.0.
// A toggle handshake crosses DMI requests and responses between TCK and clk_i.

module debug_transport #(

    parameter [31:0] IDCODE = 32'h00000001,
    parameter ABITS = 7
)(
    input wire clk_i,
    input wire rst_i,

    input wire tck_i,
    input wire tms_i,
    input wire tdi_i,
    input wire trst_n_i,
    output reg tdo_o,

    output reg dmi_valid_o,
    output reg [1:0] dmi_op_o,
    output reg [ABITS-1:0] dmi_addr_o,
    output reg [31:0] dmi_data_o,
    input wire dmi_ready_i,
    input wire [1:0] dmi_resp_op_i,
    input wire [31:0] dmi_resp_data_i
);

    localparam DMI_WIDTH = ABITS + 34;

    localparam TEST_LOGIC_RESET = 4'd0;
    localparam RUN_TEST_IDLE = 4'd1;
    localparam SELECT_DR_SCAN = 4'd2;
    localparam CAPTURE_DR = 4'd3;
    localparam SHIFT_DR = 4'd4;
    localparam EXIT1_DR = 4'd5;
    localparam PAUSE_DR = 4'd6;
    localparam EXIT2_DR = 4'd7;
    localparam UPDATE_DR = 4'd8;
    localparam SELECT_IR_SCAN = 4'd9;
    localparam CAPTURE_IR = 4'd10;
    localparam SHIFT_IR = 4'd11;
    localparam EXIT1_IR = 4'd12;
    localparam PAUSE_IR = 4'd13;
    localparam EXIT2_IR = 4'd14;
    localparam UPDATE_IR = 4'd15;

    localparam IR_IDCODE = 5'h01;
    localparam IR_DTMCS = 5'h10;
    localparam IR_DMI = 5'h11;
    localparam IR_BYPASS = 5'h1F;

    wire dtm_reset_n = trst_n_i && !rst_i;

    reg [3:0] tap_state;
    reg [3:0] tap_next_state;
    reg [4:0] ir_reg;
    reg [4:0] ir_shift;
    reg [DMI_WIDTH-1:0] dr_shift;
    reg [31:0] dtmcs_capture;

    reg [1:0] dmi_status_tck;
    reg dmi_busy_tck;
    reg [ABITS-1:0] dmi_request_addr_tck;
    reg [31:0] dmi_request_data_tck;
    reg [1:0] dmi_request_op_tck;
    reg [31:0] dmi_response_data_tck;
    reg [ABITS-1:0] dmi_response_addr_tck;

    reg dmi_req_toggle_tck;
    reg [1:0] dmi_ack_sync_tck;
    reg dmi_ack_seen_tck;
    reg [31:0] dmi_resp_data_meta_tck;
    reg [31:0] dmi_resp_data_sync_tck;
    reg [1:0] dmi_resp_op_meta_tck;
    reg [1:0] dmi_resp_op_sync_tck;

    reg [1:0] dmi_req_sync_sys;
    reg dmi_req_seen_sys;
    reg dmi_ack_toggle_sys;
    reg [31:0] dmi_resp_data_sys;
    reg [1:0] dmi_resp_op_sys;

    reg response_ignored_tck;
    reg [DMI_WIDTH-1:0] dmi_capture_value;

    always @* begin
        tap_next_state = tap_state;

        case (tap_state)

            TEST_LOGIC_RESET: tap_next_state = tms_i ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE: tap_next_state = tms_i ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            SELECT_DR_SCAN: tap_next_state = tms_i ? SELECT_IR_SCAN : CAPTURE_DR;
            CAPTURE_DR: tap_next_state = tms_i ? EXIT1_DR : SHIFT_DR;
            SHIFT_DR: tap_next_state = tms_i ? EXIT1_DR : SHIFT_DR;

            EXIT1_DR: tap_next_state = tms_i ? UPDATE_DR : PAUSE_DR;
            PAUSE_DR: tap_next_state = tms_i ? EXIT2_DR : PAUSE_DR;
            EXIT2_DR: tap_next_state = tms_i ? UPDATE_DR : SHIFT_DR;
            UPDATE_DR: tap_next_state = tms_i ? SELECT_DR_SCAN : RUN_TEST_IDLE;

            SELECT_IR_SCAN: tap_next_state = tms_i ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR: tap_next_state = tms_i ? EXIT1_IR : SHIFT_IR;
            SHIFT_IR: tap_next_state = tms_i ? EXIT1_IR : SHIFT_IR;
            EXIT1_IR: tap_next_state = tms_i ? UPDATE_IR : PAUSE_IR;
            PAUSE_IR: tap_next_state = tms_i ? EXIT2_IR : PAUSE_IR;
            EXIT2_IR: tap_next_state = tms_i ? UPDATE_IR : SHIFT_IR;
            UPDATE_IR: tap_next_state = tms_i ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            default: tap_next_state = TEST_LOGIC_RESET;
        endcase
    end

    always @* begin

        dtmcs_capture = 32'd0;
        dtmcs_capture[3:0] = 4'd1; // RISC-V Debug Specification 1.0 DTM.
        dtmcs_capture[9:4] = ABITS[5:0];
        dtmcs_capture[11:10] = dmi_busy_tck ? 2'b11 : dmi_status_tck;
        dtmcs_capture[14:12] = 3'd1; // One Run-Test/Idle cycle is recommended.
        dtmcs_capture[20:18] = 3'd0; // Optional errinfo is not implemented.

        dmi_capture_value = {dmi_response_addr_tck, dmi_response_data_tck, (dmi_busy_tck ? 2'b11 : dmi_status_tck)};
    end

    // TAP and TCK-side DMI registers.
    always @(posedge tck_i or negedge dtm_reset_n) begin

        if (!dtm_reset_n) begin
            tap_state <= TEST_LOGIC_RESET;
            ir_reg <= IR_IDCODE;
            ir_shift <= 5'b00001;
            dr_shift <= 0;
            dmi_status_tck <= 0;
            dmi_busy_tck <= 1'b0;
            dmi_request_addr_tck <= 0;
            dmi_request_data_tck <= 0;
            dmi_request_op_tck <= 0;

            dmi_response_data_tck <= 0;
            dmi_response_addr_tck <= 0;
            dmi_req_toggle_tck <= 1'b0;
            dmi_ack_sync_tck <= 0;
            dmi_ack_seen_tck <= 1'b0;
            dmi_resp_data_meta_tck <= 0;
            dmi_resp_data_sync_tck <= 0;
            dmi_resp_op_meta_tck <= 0;
            dmi_resp_op_sync_tck <= 0;
            response_ignored_tck <= 1'b0;

        end else begin
            tap_state <= tap_next_state;
            dmi_ack_sync_tck <= {dmi_ack_sync_tck[0], dmi_ack_toggle_sys};
            dmi_resp_data_meta_tck <= dmi_resp_data_sys;
            dmi_resp_data_sync_tck <= dmi_resp_data_meta_tck;
            dmi_resp_op_meta_tck <= dmi_resp_op_sys;
            dmi_resp_op_sync_tck <= dmi_resp_op_meta_tck;

            if (dmi_ack_sync_tck[1] != dmi_ack_seen_tck) begin
                dmi_ack_seen_tck <= dmi_ack_sync_tck[1];
                if (response_ignored_tck) begin
                    response_ignored_tck <= 1'b0;
                    dmi_busy_tck <= 1'b0;
                    dmi_status_tck <= 2'b00;

                end else begin
                    dmi_response_data_tck <= dmi_resp_data_sync_tck;
                    dmi_response_addr_tck <= dmi_request_addr_tck;
                    dmi_busy_tck <= 1'b0;
                    if (dmi_status_tck == 2'b00)
                        dmi_status_tck <= dmi_resp_op_sync_tck;
                end
            end

            case (tap_state)
                TEST_LOGIC_RESET: begin
                    ir_reg <= IR_IDCODE;
                    ir_shift <= 5'b00001;
                end

                CAPTURE_IR: ir_shift <= 5'b00001;
                SHIFT_IR: ir_shift <= {tdi_i, ir_shift[4:1]};
                UPDATE_IR: ir_reg <= ir_shift;

                CAPTURE_DR: begin

                    case (ir_reg)
                        IR_IDCODE: dr_shift <= {{(DMI_WIDTH-32){1'b0}}, IDCODE};
                        IR_DTMCS: dr_shift <= {{(DMI_WIDTH-32){1'b0}}, dtmcs_capture};
                        IR_DMI: dr_shift <= dmi_capture_value;

                        default: dr_shift <= {{(DMI_WIDTH-1){1'b0}}, 1'b0};
                    endcase

                end

                SHIFT_DR: dr_shift <= {tdi_i, dr_shift[DMI_WIDTH-1:1]};

                UPDATE_DR: begin

                    if (ir_reg == IR_DTMCS) begin
                        if (dr_shift[16])
                            dmi_status_tck <= 2'b00; // dmireset clears sticky DMI status.

                        if (dr_shift[17]) begin
                            dmi_status_tck <= 2'b00;

                            if (dmi_busy_tck) begin
                                response_ignored_tck <= 1'b1;
                            end else begin
                                dmi_busy_tck <= 1'b0;
                            end

                        end
                    end else if (ir_reg == IR_DMI) begin

                        if (dr_shift[1:0] == 2'b01 || dr_shift[1:0] == 2'b10) begin

                            if (dmi_status_tck != 2'b00) begin
                                dmi_status_tck <= dmi_status_tck;

                            end else if (dmi_busy_tck) begin
                                dmi_status_tck <= 2'b11;

                            end else begin
                                dmi_request_op_tck <= dr_shift[1:0];
                                dmi_request_data_tck <= dr_shift[33:2];
                                dmi_request_addr_tck <= dr_shift[DMI_WIDTH-1:34];
                                dmi_req_toggle_tck <= ~dmi_req_toggle_tck;
                                dmi_busy_tck <= 1'b1;
                            end

                        end else if (dr_shift[1:0] == 2'b11) begin
                            dmi_status_tck <= 2'b10;
                        end
                    end

                end

                default: begin end

            endcase
    
        end
    
    end


    // IEEE 1149.1 samples TDO on rising TCK; update it on falling TCK.
    always @(negedge tck_i or negedge dtm_reset_n) begin

        if (!dtm_reset_n) begin
            tdo_o <= 1'b0;

        end else begin
            if (tap_state == SHIFT_IR)
                tdo_o <= ir_shift[0];
            else if (tap_state == SHIFT_DR)
                tdo_o <= dr_shift[0];
            else
                tdo_o <= 1'b0;
        end
    end

    // System-clock side of the asynchronous DMI request/response handshake.

    always @(posedge clk_i or negedge dtm_reset_n) begin

        if (!dtm_reset_n) begin
            dmi_req_sync_sys <= 0;
            dmi_req_seen_sys <= 1'b0;
            dmi_ack_toggle_sys <= 1'b0;
            dmi_valid_o <= 1'b0;
            dmi_op_o <= 0;
            dmi_addr_o <= 0;
            dmi_data_o <= 0;
            dmi_resp_data_sys <= 0;
            dmi_resp_op_sys <= 0;
        end else begin

            dmi_req_sync_sys <= {dmi_req_sync_sys[0], dmi_req_toggle_tck};

            if (!dmi_valid_o && dmi_req_sync_sys[1] != dmi_req_seen_sys) begin
                dmi_req_seen_sys <= dmi_req_sync_sys[1];
                dmi_valid_o <= 1'b1;
                dmi_op_o <= dmi_request_op_tck;
                dmi_addr_o <= dmi_request_addr_tck;
                dmi_data_o <= dmi_request_data_tck;
                
            end else if (dmi_valid_o && dmi_ready_i) begin
                dmi_resp_data_sys <= dmi_resp_data_i;
                dmi_resp_op_sys <= dmi_resp_op_i;
                dmi_ack_toggle_sys <= ~dmi_ack_toggle_sys;
                dmi_valid_o <= 1'b0;
            end

        end


    end

endmodule