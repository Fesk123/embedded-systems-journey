`timescale 1ns/1ps

// SD/eMMC request bridge for the KV260 platform.
//
// The Wishbone and AXI4-Lite interfaces use the same clk_i clock. 
// Connect the PS AXI interconnect clock and the RV64 Wishbone clock to the same PL clock, or add a proper clock-domain crossing bridge outside this module.
//
// Request operations:
// 0 = READ (SD -> shared DDR buffer)
// 1 = WRITE (shared DDR buffer -> SD)
// 2 = FLUSH (block_count must be zero; buffer address is ignored)
//
// Request descriptors and completions are queued to avoid making every block transfer a synchronous CPU register-polling operation.
// This is the hardware mailbox/queue portion; the PS driver is still required for real SD access.

module sd_emmc #(
    parameter integer QUEUE_DEPTH = 16,
    parameter integer MAX_BLOCKS_PER_REQ = 128
)(
    input wire clk_i,
    input wire rst_i,

    // 64-bit classic Wishbone slave interface from the RV64GC SoC.
    input wire wb_cyc_i,
    input wire wb_stb_i,
    input wire wb_we_i,
    input wire [7:0] wb_sel_i,
    input wire [63:0] wb_adr_i,
    input wire [63:0] wb_dat_i,
    output reg wb_ack_o,
    output reg wb_err_o,
    output reg [63:0] wb_dat_o,

    // AXI4-Lite slave interface from the Zynq PS (via HPM -> PL).
    input wire [31:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input  wire s_axi_bready,

    input wire [31:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input  wire s_axi_rready,

    // Interrupts to the RV64GC and the PS interrupt controller.
    output wire cpu_irq_o,
    output wire ps_irq_o,
    output wire ps_online_o
);

    localparam integer COUNT_WIDTH = $clog2(QUEUE_DEPTH + 1);
    localparam integer REQ_WIDTH = 226;
    localparam integer COMP_WIDTH = 96;

    localparam [1:0] OP_READ = 2'd0;
    localparam [1:0] OP_WRITE = 2'd1;
    localparam [1:0] OP_FLUSH = 2'd2;

    localparam [31:0] PS_ALIVE_MAGIC = 32'h5344454D; // "SDEM"

    localparam [31:0] ERR_NONE = 32'd0;
    localparam [31:0] ERR_BAD_REQUEST = 32'd1;
    localparam [31:0] ERR_REQ_QUEUE_FULL= 32'd2;
    localparam [31:0] ERR_COMP_QUEUE_FULL=32'd3;
    localparam [31:0] ERR_REQ_QUEUE_EMPTY=32'd4;
    localparam [31:0] ERR_BAD_PS_WRITE = 32'd5;
    localparam [31:0] ERR_COMP_QUEUE_EMPTY = 32'd6;

    // RV64 Wishbone register map (byte offsets).
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

    // PS-facing AXI4-Lite register map (local byte offsets).
    localparam [11:0] AXI_CAPS = 12'h000;
    localparam [11:0] AXI_STATUS = 12'h004;
    localparam [11:0] AXI_REQ_COUNT = 12'h008;
    localparam [11:0] AXI_COMP_COUNT = 12'h00C;
    localparam [11:0] AXI_PS_ALIVE = 12'h010;
    localparam [11:0] AXI_PS_IRQ_EN = 12'h014;
    localparam [11:0] AXI_CLEAR_ERROR = 12'h018;

    localparam [11:0] AXI_REQ_VALID = 12'h100;
    localparam [11:0] AXI_REQ_TAG = 12'h104;
    localparam [11:0] AXI_REQ_OP = 12'h108;
    localparam [11:0] AXI_REQ_LBA_LO = 12'h10C;
    localparam [11:0] AXI_REQ_LBA_HI = 12'h110;
    localparam [11:0] AXI_REQ_BLOCKS = 12'h114;
    localparam [11:0] AXI_REQ_BUF_LO = 12'h118;
    localparam [11:0] AXI_REQ_BUF_HI = 12'h11C;
    localparam [11:0] AXI_REQ_FLAGS = 12'h120;
    localparam [11:0] AXI_REQ_POP = 12'h124;

    localparam [11:0] AXI_RESP_TAG = 12'h140;
    localparam [11:0] AXI_RESP_STATUS = 12'h144;
    localparam [11:0] AXI_RESP_ERROR = 12'h148;
    localparam [11:0] AXI_RESP_PUSH = 12'h14C;

    reg [1:0] req_op_stage;
    reg [63:0] req_lba_stage;
    reg [31:0] req_block_count_stage;
    reg [63:0] req_buffer_addr_stage;
    reg [31:0] req_tag_stage;
    reg [31:0] req_flags_stage;

    reg [31:0] response_tag_stage;
    reg [31:0] response_status_stage;
    reg [31:0] response_error_stage;

    reg [31:0] last_error_code;
    reg sticky_error;
    reg [1:0] irq_enable;
    reg ps_irq_enable;
    reg ps_online;

    reg wb_seen;

    reg [31:0] axi_awaddr_reg;
    reg axi_aw_pending;
    reg [31:0] axi_wdata_reg;
    reg [3:0] axi_wstrb_reg;
    reg axi_w_pending;

    wire [REQ_WIDTH-1:0] req_fifo_data_i;
    wire [REQ_WIDTH-1:0] req_fifo_data_o;
    wire [COMP_WIDTH-1:0] comp_fifo_data_i;
    wire [COMP_WIDTH-1:0] comp_fifo_data_o;

    wire [COUNT_WIDTH-1:0] req_count;
    wire [COUNT_WIDTH-1:0] comp_count;
    wire req_full;
    wire req_empty;
    wire comp_full;
    wire comp_empty;

    wire [31:0] req_head_tag;
    wire [1:0] req_head_op;
    wire [63:0] req_head_lba;
    wire [31:0] req_head_blocks;
    wire [63:0] req_head_buffer_addr;
    wire [31:0] req_head_flags;

    wire [31:0] comp_head_tag;
    wire [31:0] comp_head_status;
    wire [31:0] comp_head_error;

    wire wb_access;
    wire wb_submit_attempt;
    wire wb_request_valid;
    wire wb_req_push;
    wire wb_comp_pop;

    wire axi_write_execute;
    wire axi_req_pop_attempt;
    wire axi_req_pop;
    wire axi_comp_push_attempt;
    wire axi_comp_push;

    wire [11:0] wb_addr;
    wire [11:0] axi_write_addr;
    wire [11:0] axi_read_addr;
    reg [63:0] wb_read_data;
    reg [31:0] axi_read_data;
    reg [1:0] axi_read_resp;

    integer i;

    assign wb_addr = wb_adr_i[11:0];
    assign axi_write_addr = axi_awaddr_reg[11:0];
    assign axi_read_addr = s_axi_araddr[11:0];

    assign wb_access = wb_cyc_i && wb_stb_i && !wb_seen;
    assign wb_submit_attempt = wb_access && wb_we_i && (wb_addr == WB_CTRL) && wb_dat_i[0] && wb_sel_i[0];

    assign wb_request_valid = ((req_op_stage == OP_READ) || (req_op_stage == OP_WRITE)) ? ((req_block_count_stage != 0) && (req_block_count_stage <= MAX_BLOCKS_PER_REQ) && (req_buffer_addr_stage[2:0] == 3'b000)) : ((req_op_stage == OP_FLUSH) && (req_block_count_stage == 0));

    assign wb_req_push = wb_submit_attempt && wb_request_valid && !req_full;
    assign wb_comp_pop = wb_access && wb_we_i && (wb_addr == WB_COMP_POP) && wb_dat_i[0] && wb_sel_i[0] && !comp_empty;

    assign axi_write_execute = axi_aw_pending && axi_w_pending && !s_axi_bvalid;
    assign axi_req_pop_attempt = axi_write_execute && (axi_write_addr == AXI_REQ_POP) && axi_wdata_reg[0] && axi_wstrb_reg[0];
    assign axi_req_pop = axi_req_pop_attempt && !req_empty;

    assign axi_comp_push_attempt = axi_write_execute && (axi_write_addr == AXI_RESP_PUSH) && axi_wdata_reg[0] && axi_wstrb_reg[0];
    assign axi_comp_push = axi_comp_push_attempt && !comp_full;

    assign req_fifo_data_i = {req_flags_stage, req_buffer_addr_stage, req_block_count_stage, req_lba_stage, req_op_stage, req_tag_stage};

    assign req_head_flags = req_fifo_data_o[225:194];
    assign req_head_buffer_addr = req_fifo_data_o[193:130];
    assign req_head_blocks = req_fifo_data_o[129:98];
    assign req_head_lba = req_fifo_data_o[97:34];
    assign req_head_op = req_fifo_data_o[33:32];
    assign req_head_tag = req_fifo_data_o[31:0];

    assign comp_fifo_data_i = {response_tag_stage,  response_status_stage,  response_error_stage};

    assign comp_head_tag = comp_fifo_data_o[95:64];
    assign comp_head_status = comp_fifo_data_o[63:32];
    assign comp_head_error = comp_fifo_data_o[31:0];

    assign s_axi_awready = !axi_aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !axi_w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    assign ps_online_o = ps_online;
    assign ps_irq_o = ps_irq_enable && !req_empty;
    assign cpu_irq_o = (irq_enable[0] && !comp_empty) || (irq_enable[1] && sticky_error);

    sd_emmc_fifo #(
        .DATA_WIDTH(REQ_WIDTH),
        .DEPTH(QUEUE_DEPTH)
    ) request_queue (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .push_i(wb_req_push),
        .data_i(req_fifo_data_i),
        .pop_i(axi_req_pop),
        .data_o(req_fifo_data_o),
        .count_o(req_count),
        .full_o(req_full),
        .empty_o(req_empty)
    );

    sd_emmc_fifo #(
        .DATA_WIDTH(COMP_WIDTH),
        .DEPTH(QUEUE_DEPTH)
    ) completion_queue (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .push_i(axi_comp_push),
        .data_i(comp_fifo_data_i),
        .pop_i(wb_comp_pop),
        .data_o(comp_fifo_data_o),
        .count_o(comp_count),
        .full_o(comp_full),
        .empty_o(comp_empty)
    );

    function [63:0] merge64;
        input [63:0] old_value;
        input [63:0] new_value;
        input [7:0] select_bits;
        integer b;
        begin
            merge64 = old_value;
            for (b = 0; b < 8; b = b + 1) begin
                if (select_bits[b]) begin
                    merge64[b*8 +: 8] = new_value[b*8 +: 8];
                end
            end
        end
    endfunction

    function [31:0] merge32;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] select_bits;
        integer b;
        begin
            merge32 = old_value;
            for (b = 0; b < 4; b = b + 1) begin
                if (select_bits[b]) begin
                    merge32[b*8 +: 8] = new_value[b*8 +: 8];
                end
            end
        end
    endfunction

    // CPU-visible Wishbone register read mux.
    always @* begin
        wb_read_data = 64'd0;

        case (wb_addr)
            WB_CTRL: wb_read_data = 64'd0;
            WB_STATUS: begin
                wb_read_data[0] = req_full;
                wb_read_data[1] = req_empty;
                wb_read_data[2] = comp_full;
                wb_read_data[3] = comp_empty;
                wb_read_data[4] = ps_online;
                wb_read_data[5] = sticky_error;
                wb_read_data[15:8] = req_count;
                wb_read_data[23:16] = comp_count;
            end
            WB_OP: wb_read_data = {62'd0, req_op_stage};
            WB_LBA: wb_read_data = req_lba_stage;
            WB_BLOCK_COUNT: wb_read_data = {32'd0, req_block_count_stage};
            WB_BUFFER_ADDR: wb_read_data = req_buffer_addr_stage;
            WB_TAG: wb_read_data = {32'd0, req_tag_stage};
            WB_FLAGS: wb_read_data = {32'd0, req_flags_stage};
            WB_LAST_ERROR: wb_read_data = {32'd0, last_error_code};
            WB_IRQ_ENABLE: wb_read_data = {62'd0, irq_enable};
            WB_IRQ_STATUS: begin
                wb_read_data[0] = !comp_empty;
                wb_read_data[1] = sticky_error;
            end
            WB_COMP_VALID: begin
                wb_read_data[0] = !comp_empty;
                wb_read_data[15:8] = comp_count;
            end
            WB_COMP_TAG: wb_read_data = {32'd0, (comp_empty ? 32'd0 : comp_head_tag)};
            WB_COMP_STATUS: wb_read_data = {32'd0, (comp_empty ? 32'd0 : comp_head_status)};
            WB_COMP_ERROR: wb_read_data = {32'd0, (comp_empty ? 32'd0 : comp_head_error)};
            WB_COMP_POP: wb_read_data = 64'd0;
            WB_CAPS: begin
                wb_read_data[31:0] = 32'h5344454D; // "SDEM"
                wb_read_data[39:32] = QUEUE_DEPTH;
                wb_read_data[63:40] = MAX_BLOCKS_PER_REQ;
            end
            default: wb_read_data = 64'd0;
        endcase
    end

    // PS-visible AXI4-Lite register read mux.
    always @* begin
        axi_read_data = 32'd0;
        axi_read_resp = 2'b00;

        case (axi_read_addr)
            AXI_CAPS: axi_read_data = 32'h5344454D;
            AXI_STATUS: begin
                axi_read_data[0] = ps_online;
                axi_read_data[1] = !req_empty;
                axi_read_data[2] = req_full;
                axi_read_data[3] = comp_full;
                axi_read_data[4] = sticky_error;
            end
            AXI_REQ_COUNT: axi_read_data = req_count;
            AXI_COMP_COUNT: axi_read_data = comp_count;
            AXI_PS_ALIVE: axi_read_data = ps_online ? PS_ALIVE_MAGIC : 32'd0;
            AXI_PS_IRQ_EN: axi_read_data = {31'd0, ps_irq_enable};
            AXI_CLEAR_ERROR: axi_read_data = last_error_code;

            AXI_REQ_VALID: axi_read_data = {31'd0, !req_empty};
            AXI_REQ_TAG: axi_read_data = req_empty ? 32'd0 : req_head_tag;
            AXI_REQ_OP: axi_read_data = req_empty ? 32'd0 : {30'd0, req_head_op};
            AXI_REQ_LBA_LO: axi_read_data = req_empty ? 32'd0 : req_head_lba[31:0];
            AXI_REQ_LBA_HI: axi_read_data = req_empty ? 32'd0 : req_head_lba[63:32];
            AXI_REQ_BLOCKS: axi_read_data = req_empty ? 32'd0 : req_head_blocks;
            AXI_REQ_BUF_LO: axi_read_data = req_empty ? 32'd0 : req_head_buffer_addr[31:0];
            AXI_REQ_BUF_HI: axi_read_data = req_empty ? 32'd0 : req_head_buffer_addr[63:32];
            AXI_REQ_FLAGS: axi_read_data = req_empty ? 32'd0 : req_head_flags;

            AXI_RESP_TAG: axi_read_data = response_tag_stage;
            AXI_RESP_STATUS: axi_read_data = response_status_stage;
            AXI_RESP_ERROR: axi_read_data = response_error_stage;
            default: begin
                axi_read_data = 32'd0;
                axi_read_resp = 2'b11;
            end
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            req_op_stage <= OP_READ;
            req_lba_stage <= 64'd0;
            req_block_count_stage <= 32'd0;
            req_buffer_addr_stage <= 64'd0;
            req_tag_stage <= 32'd0;
            req_flags_stage <= 32'd0;

            response_tag_stage <= 32'd0;
            response_status_stage <= 32'd0;
            response_error_stage <= 32'd0;

            last_error_code <= ERR_NONE;
            sticky_error <= 1'b0;
            irq_enable <= 2'b00;
            ps_irq_enable <= 1'b0;
            ps_online <= 1'b0;

            wb_seen <= 1'b0;
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            wb_dat_o <= 64'd0;

            axi_awaddr_reg <= 32'd0;
            axi_aw_pending <= 1'b0;
            axi_wdata_reg <= 32'd0;
            axi_wstrb_reg <= 4'd0;
            axi_w_pending <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;


            if (!wb_cyc_i || !wb_stb_i) begin
                wb_seen <= 1'b0;
            end else if (wb_access) begin
                wb_seen <= 1'b1;
                wb_ack_o <= 1'b1;
                wb_dat_o <= wb_read_data;

                if (wb_we_i) begin
                    case (wb_addr)
                        WB_CTRL: begin
                            if (wb_dat_i[0] && wb_sel_i[0]) begin
                                if (!wb_request_valid) begin
                                    wb_err_o <= 1'b1;
                                    sticky_error <= 1'b1;
                                    last_error_code <= ERR_BAD_REQUEST;
                                end else if (req_full) begin
                                    wb_err_o <= 1'b1;
                                    sticky_error <= 1'b1;
                                    last_error_code <= ERR_REQ_QUEUE_FULL;
                                end

                            end


                        end
                        
                        WB_OP: req_op_stage <= merge64({62'd0, req_op_stage}, wb_dat_i, wb_sel_i);
                        WB_LBA: req_lba_stage <= merge64(req_lba_stage, wb_dat_i, wb_sel_i);
                        WB_BLOCK_COUNT: req_block_count_stage <= merge64({32'd0, req_block_count_stage}, wb_dat_i, wb_sel_i);
                        WB_BUFFER_ADDR: req_buffer_addr_stage <= merge64(req_buffer_addr_stage, wb_dat_i, wb_sel_i);
                        WB_TAG: req_tag_stage <= merge64({32'd0, req_tag_stage}, wb_dat_i, wb_sel_i);
                        WB_FLAGS: req_flags_stage <= merge64({32'd0, req_flags_stage}, wb_dat_i, wb_sel_i);
                        WB_IRQ_ENABLE: irq_enable <= merge64({62'd0, irq_enable}, wb_dat_i, wb_sel_i);
                        WB_IRQ_STATUS: begin


                            if (wb_sel_i[0] && wb_dat_i[1]) begin
                                sticky_error <= 1'b0;
                                last_error_code <= ERR_NONE;
                            end
                        end
                        WB_COMP_POP: begin
                            if (wb_dat_i[0] && wb_sel_i[0] && comp_empty) begin
                                wb_err_o <= 1'b1;
                                sticky_error <= 1'b1;
                                last_error_code <= ERR_COMP_QUEUE_EMPTY;
                            end

                        end
                        default: begin
                            wb_err_o <= 1'b1;
                            sticky_error <= 1'b1;
                            last_error_code <= ERR_BAD_PS_WRITE;
                        end
                    endcase
                    
                end
            end

            // Capture AXI-Lite write address and write data independently.
            if (s_axi_awvalid && s_axi_awready) begin
                axi_awaddr_reg <= s_axi_awaddr;
                axi_aw_pending <= 1'b1;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                axi_wdata_reg <= s_axi_wdata;
                axi_wstrb_reg <= s_axi_wstrb;
                axi_w_pending <= 1'b1;
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (axi_write_execute) begin
                axi_aw_pending <= 1'b0;
                axi_w_pending <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;

                case (axi_write_addr)
                    AXI_PS_ALIVE: begin
                        if (axi_wstrb_reg[0]) begin
                            if (axi_wdata_reg == PS_ALIVE_MAGIC) begin
                                ps_online <= 1'b1;
                            end else if (axi_wdata_reg == 32'd0) begin
                                ps_online <= 1'b0;
                            end else begin
                                s_axi_bresp <= 2'b10;
                                sticky_error <= 1'b1;
                                last_error_code <= ERR_BAD_PS_WRITE;
                            end
                        end
                    end
                    AXI_PS_IRQ_EN: begin
                        if (axi_wstrb_reg[0]) begin
                            ps_irq_enable <= axi_wdata_reg[0];
                        end
                    end
                    AXI_CLEAR_ERROR: begin
                        if (axi_wstrb_reg[0] && axi_wdata_reg[0]) begin
                            sticky_error <= 1'b0;
                            last_error_code <= ERR_NONE;
                        end
                    end
                    AXI_REQ_POP: begin
                        if (axi_wstrb_reg[0] && axi_wdata_reg[0] && req_empty) begin
                            s_axi_bresp <= 2'b10;
                            sticky_error <= 1'b1;
                            last_error_code <= ERR_REQ_QUEUE_EMPTY;
                        end
                    end

                    AXI_RESP_TAG: response_tag_stage <= merge32(response_tag_stage,axi_wdata_reg,axi_wstrb_reg);
                    AXI_RESP_STATUS: response_status_stage <= merge32(response_status_stage, axi_wdata_reg, axi_wstrb_reg);
                    AXI_RESP_ERROR: response_error_stage <= merge32(response_error_stage, axi_wdata_reg, axi_wstrb_reg);
                    AXI_RESP_PUSH: begin

                        if (axi_wstrb_reg[0] && axi_wdata_reg[0] && comp_full) begin
                            s_axi_bresp <= 2'b10;
                            sticky_error <= 1'b1;
                            last_error_code <= ERR_COMP_QUEUE_FULL;
                        end

                    end
                    default: begin
                        s_axi_bresp <= 2'b11;
                    end
                endcase
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rdata <= axi_read_data;
                s_axi_rresp <= axi_read_resp;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

        end


    end

endmodule