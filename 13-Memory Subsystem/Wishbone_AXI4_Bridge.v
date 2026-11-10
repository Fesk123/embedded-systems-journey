`timescale 1ns/1ps

// WISHBONE TO AXI4 BRIDGE
// 64-bit AXI4 master for the KV260 PS DDR access path.

module Wishbone_AXI4_Bridge #(
    parameter integer WB_ADDR_WIDTH = 64,
    parameter integer AXI_ADDR_WIDTH = 49,
    parameter integer PHYS_ADDR_WIDTH = 40,
    parameter integer DATA_WIDTH = 64,
    parameter integer MAX_BURST_BEATS = 8,
    parameter integer AXI_ID_WIDTH = 6
)(
    input wire CLK_I,
    input wire RST_I,

    // Wishbone slave.
    input wire [WB_ADDR_WIDTH-1:0] WB_ADR_I,
    input wire [DATA_WIDTH-1:0] WB_DAT_I,
    output wire [DATA_WIDTH-1:0] WB_DAT_O,
    input wire [DATA_WIDTH/8-1:0] WB_SEL_I,
    input wire WB_CYC_I,
    input wire WB_STB_I,
    input wire WB_WE_I,
    input wire [2:0] WB_CTI_I,
    input wire [1:0] WB_BTE_I,
    output wire WB_ACK_O,
    output wire WB_ERR_O,

    // AXI4 write address channel. This bridge permits one outstanding transaction and uses AXI ID zero.

    output wire [AXI_ID_WIDTH-1:0] M_AXI_AWID,
    output wire [AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire [3:0] M_AXI_AWCACHE,
    output wire [2:0] M_AXI_AWPROT,
    output wire M_AXI_AWLOCK,
    output wire M_AXI_AWVALID,
    input wire M_AXI_AWREADY,

    // AXI4 write data channel.
    output wire [DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output wire M_AXI_WLAST,
    output wire M_AXI_WVALID,
    input wire M_AXI_WREADY,

    // AXI4 write response channel.
    input wire [AXI_ID_WIDTH-1:0] M_AXI_BID,
    input wire [1:0] M_AXI_BRESP,
    input wire M_AXI_BVALID,
    output wire M_AXI_BREADY,

    // AXI4 read address channel.
    output wire [AXI_ID_WIDTH-1:0] M_AXI_ARID,
    output wire [AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [7:0] M_AXI_ARLEN,
    output wire [2:0] M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    output wire [3:0] M_AXI_ARCACHE,
    output wire [2:0] M_AXI_ARPROT,
    output wire M_AXI_ARLOCK,
    output wire M_AXI_ARVALID,
    input wire M_AXI_ARREADY,

    // AXI4 read data channel.
    input wire [AXI_ID_WIDTH-1:0] M_AXI_RID,
    input wire [DATA_WIDTH-1:0] M_AXI_RDATA,
    input wire [1:0] M_AXI_RRESP,
    input wire M_AXI_RLAST,
    input wire M_AXI_RVALID,
    output wire M_AXI_RREADY
);

    localparam [3:0] B_IDLE = 4'd0;
    localparam [3:0] B_W_SINGLE = 4'd1;
    localparam [3:0] B_W_COLLECT = 4'd2;
    localparam [3:0] B_W_BURST = 4'd3;
    localparam [3:0] B_W_WAIT = 4'd4;
    localparam [3:0] B_R_SINGLE_ADDR = 4'd5;
    localparam [3:0] B_R_SINGLE_DATA = 4'd6;
    localparam [3:0] B_R_BURST_ADDR = 4'd7;
    localparam [3:0] B_R_BURST_DATA = 4'd8;
    localparam [3:0] B_R_DRAIN = 4'd9;
    localparam [3:0] B_ERROR = 4'd10;
    localparam [3:0] B_RELEASE = 4'd11;

    localparam [2:0] CTI_CLASSIC = 3'b000;
    localparam [2:0] CTI_INCREMENT = 3'b010;
    localparam [2:0] CTI_END = 3'b111;

    reg [3:0] state;
    reg [WB_ADDR_WIDTH-1:0] request_address;
    reg [DATA_WIDTH-1:0] single_write_data;
    reg [DATA_WIDTH/8-1:0] single_write_select;
    reg [DATA_WIDTH-1:0] read_data_register;
    reg aw_sent;
    reg w_sent;
    reg [4:0] write_index;
    reg [4:0] collect_index;
    reg [4:0] read_index;
    reg [WB_ADDR_WIDTH-1:0] burst_address;
    reg [DATA_WIDTH-1:0] burst_data [0:MAX_BURST_BEATS-1];
    reg [DATA_WIDTH/8-1:0] burst_select [0:MAX_BURST_BEATS-1];
    integer reset_index;

    wire [WB_ADDR_WIDTH:0] transfer_last_address;
    wire [WB_ADDR_WIDTH:0] burst_last_address;

    assign transfer_last_address = {1'b0, WB_ADR_I} + (DATA_WIDTH/8 - 1);
    assign burst_last_address = {1'b0, WB_ADR_I} + (MAX_BURST_BEATS*(DATA_WIDTH/8) - 1);

    // A line burst must be aligned and must remain within one 4 KiB AXI boundary and the implemented 40-bit physical address space.
    // The current L1/L2 default uses 64-byte aligned lines.

    wire burst_address_valid;
    assign burst_address_valid = (WB_ADR_I[5:0] == 6'b000000) && (WB_ADR_I[11:0] <= (4096 - MAX_BURST_BEATS*(DATA_WIDTH/8))) && ((burst_last_address >> PHYS_ADDR_WIDTH) == 0) && ((burst_last_address >> AXI_ADDR_WIDTH) == 0) && (WB_BTE_I == 2'b00);
    assign WB_DAT_O = (state == B_R_SINGLE_DATA) ? M_AXI_RDATA : (state == B_R_BURST_DATA) ? M_AXI_RDATA : read_data_register;

    // Single WB requests are acknowledged after the AXI response.
    // Write-burst beats are buffered and acknowledged as they are accepted;
    // the final beat is acknowledged only after the AXI B response.

    assign WB_ACK_O =
        ((state == B_W_COLLECT) && WB_CYC_I && WB_STB_I && (collect_index < MAX_BURST_BEATS-1) &&
         (WB_ADR_I == burst_address + collect_index*(DATA_WIDTH/8)) &&
         WB_WE_I && (WB_BTE_I == 2'b00) && (WB_CTI_I == CTI_INCREMENT)) ||
        ((state == B_IDLE) && WB_CYC_I && WB_STB_I && WB_WE_I &&
         (WB_CTI_I == CTI_INCREMENT) && burst_address_valid) ||
        ((state == B_W_WAIT) && WB_CYC_I && WB_STB_I && WB_WE_I &&
         (WB_BTE_I == 2'b00) &&
         (WB_ADR_I == burst_address + (MAX_BURST_BEATS-1)*(DATA_WIDTH/8)) &&
         (WB_CTI_I == CTI_END) &&
         (WB_DAT_I == burst_data[MAX_BURST_BEATS-1]) &&
         (WB_SEL_I == burst_select[MAX_BURST_BEATS-1]) &&
         M_AXI_BVALID && M_AXI_BREADY &&
         (M_AXI_BID == {AXI_ID_WIDTH{1'b0}}) && (M_AXI_BRESP == 2'b00)) ||
        ((state == B_W_SINGLE) && WB_CYC_I && WB_STB_I && WB_WE_I &&
         (WB_ADR_I == request_address) && (WB_BTE_I == 2'b00) &&
         (WB_CTI_I == CTI_CLASSIC) &&
         (WB_DAT_I == single_write_data) && (WB_SEL_I == single_write_select) &&
         M_AXI_BVALID && M_AXI_BREADY &&
         (M_AXI_BID == {AXI_ID_WIDTH{1'b0}}) && (M_AXI_BRESP == 2'b00)) ||
        ((state == B_R_SINGLE_DATA) && WB_CYC_I && WB_STB_I && !WB_WE_I &&
         (WB_ADR_I == request_address) && (WB_BTE_I == 2'b00) &&
         (WB_CTI_I == CTI_CLASSIC) && M_AXI_RVALID && M_AXI_RREADY &&
         (M_AXI_RID == {AXI_ID_WIDTH{1'b0}}) && (M_AXI_RRESP == 2'b00) && M_AXI_RLAST) ||
        ((state == B_R_BURST_DATA) && WB_CYC_I && WB_STB_I &&
         !WB_WE_I && (WB_BTE_I == 2'b00) &&
         (WB_ADR_I == burst_address + read_index*(DATA_WIDTH/8)) &&
         (WB_CTI_I == ((read_index == MAX_BURST_BEATS-1) ? CTI_END : CTI_INCREMENT)) &&
         M_AXI_RVALID && M_AXI_RREADY &&
         (M_AXI_RID == {AXI_ID_WIDTH{1'b0}}) && (M_AXI_RRESP == 2'b00) &&
         (M_AXI_RLAST == (read_index == MAX_BURST_BEATS-1)));

    assign WB_ERR_O =
        ((state == B_ERROR) ||
         ((state == B_W_WAIT || state == B_W_SINGLE) && M_AXI_BVALID && M_AXI_BREADY &&
          ((M_AXI_BRESP != 2'b00) || (M_AXI_BID != {AXI_ID_WIDTH{1'b0}}))) ||
         ((state == B_W_WAIT) && M_AXI_BVALID && M_AXI_BREADY && WB_CYC_I && WB_STB_I &&
          (!WB_WE_I || (WB_BTE_I != 2'b00) ||
           (WB_ADR_I != burst_address + (MAX_BURST_BEATS-1)*(DATA_WIDTH/8)) ||
           (WB_CTI_I != CTI_END) ||
           (WB_DAT_I != burst_data[MAX_BURST_BEATS-1]) ||
           (WB_SEL_I != burst_select[MAX_BURST_BEATS-1]))) ||
         ((state == B_W_SINGLE) && M_AXI_BVALID && M_AXI_BREADY && WB_CYC_I && WB_STB_I &&
          (!WB_WE_I || (WB_ADR_I != request_address) || (WB_BTE_I != 2'b00) ||
           (WB_CTI_I != CTI_CLASSIC) || (WB_DAT_I != single_write_data) ||
           (WB_SEL_I != single_write_select))) ||
         ((state == B_R_SINGLE_DATA || state == B_R_BURST_DATA) &&
          M_AXI_RVALID && M_AXI_RREADY &&
          ((M_AXI_RRESP != 2'b00) || (M_AXI_RID != {AXI_ID_WIDTH{1'b0}}))) ||
         ((state == B_R_SINGLE_DATA) && WB_CYC_I && WB_STB_I && M_AXI_RVALID && M_AXI_RREADY &&
          (!M_AXI_RLAST || WB_WE_I || (WB_ADR_I != request_address) ||
           (WB_BTE_I != 2'b00) || (WB_CTI_I != CTI_CLASSIC))) ||
         ((state == B_R_BURST_DATA) && M_AXI_RVALID && M_AXI_RREADY &&
          ((M_AXI_RLAST != (read_index == MAX_BURST_BEATS-1)) ||
           (WB_CYC_I && WB_STB_I &&
            (WB_WE_I || (WB_BTE_I != 2'b00) ||
             (WB_ADR_I != burst_address + read_index*(DATA_WIDTH/8)) ||
             (WB_CTI_I != ((read_index == MAX_BURST_BEATS-1) ? CTI_END : CTI_INCREMENT)))))));

    assign M_AXI_AWID = {AXI_ID_WIDTH{1'b0}};
    assign M_AXI_AWADDR = request_address[AXI_ADDR_WIDTH-1:0];
    assign M_AXI_AWLEN = (state == B_W_BURST) ? MAX_BURST_BEATS-1 : 8'd0;
    assign M_AXI_AWSIZE = $clog2(DATA_WIDTH/8);
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWCACHE = 4'b0011;
    assign M_AXI_AWPROT = 3'b000;
    assign M_AXI_AWLOCK = 1'b0;
    assign M_AXI_AWVALID = ((state == B_W_SINGLE) && !aw_sent) || ((state == B_W_BURST) && !aw_sent);

    assign M_AXI_WDATA = (state == B_W_BURST) ? burst_data[write_index] : single_write_data;
    assign M_AXI_WSTRB = (state == B_W_BURST) ? burst_select[write_index] : single_write_select;
    assign M_AXI_WLAST = (state == B_W_BURST) ? (write_index == MAX_BURST_BEATS-1) : 1'b1;
    assign M_AXI_WVALID = ((state == B_W_SINGLE) && !w_sent) || ((state == B_W_BURST) && !w_sent);
    assign M_AXI_BREADY = ((state == B_W_SINGLE) || (state == B_W_WAIT)) && aw_sent && w_sent;

    assign M_AXI_ARID = {AXI_ID_WIDTH{1'b0}};
    assign M_AXI_ARADDR = request_address[AXI_ADDR_WIDTH-1:0];
    assign M_AXI_ARLEN = (state == B_R_BURST_ADDR || state == B_R_BURST_DATA) ? MAX_BURST_BEATS-1 : 8'd0;
    assign M_AXI_ARSIZE = $clog2(DATA_WIDTH/8);
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARCACHE = 4'b0011;
    assign M_AXI_ARPROT = 3'b000;
    assign M_AXI_ARLOCK = 1'b0;
    assign M_AXI_ARVALID = (state == B_R_SINGLE_ADDR) || (state == B_R_BURST_ADDR);
    assign M_AXI_RREADY = (state == B_R_SINGLE_DATA) || (state == B_R_BURST_DATA) || (state == B_R_DRAIN);

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin
            state <= B_IDLE;
            request_address <= {WB_ADDR_WIDTH{1'b0}};
            single_write_data <= {DATA_WIDTH{1'b0}};
            single_write_select <= {DATA_WIDTH/8{1'b0}};
            read_data_register <= {DATA_WIDTH{1'b0}};
            aw_sent <= 1'b0;
            w_sent <= 1'b0;

            write_index <= 5'd0;
            collect_index <= 5'd0;
            read_index <= 5'd0;
            burst_address <= {WB_ADDR_WIDTH{1'b0}};
            
            for (reset_index = 0; reset_index < MAX_BURST_BEATS; reset_index = reset_index + 1) begin
                burst_data[reset_index] <= {DATA_WIDTH{1'b0}};
                burst_select[reset_index] <= {DATA_WIDTH/8{1'b0}};
            end
        end
        
        else begin
            case (state)
                B_IDLE: begin
                    aw_sent <= 1'b0;
                    w_sent <= 1'b0;
                    write_index <= 5'd0;
                    collect_index <= 5'd0;
                    read_index <= 5'd0;

                    if (WB_CYC_I && WB_STB_I) begin
                        // The PS-PL port has a 49-bit AXI address bus, while the Zynq UltraScale+ physical address map is limited to 40 bits. Reject wider physical addresses.
                        if (((transfer_last_address >> PHYS_ADDR_WIDTH) != 0) || ((transfer_last_address >> AXI_ADDR_WIDTH) != 0)) begin
                            state <= B_ERROR;
                        end
                        else if ((WB_BTE_I != 2'b00) || ((WB_CTI_I != CTI_CLASSIC) && (WB_CTI_I != CTI_INCREMENT))) begin
                            state <= B_ERROR;
                        end
                        else if (WB_WE_I && (WB_CTI_I == CTI_INCREMENT)) begin
                            if (burst_address_valid) begin
                                burst_address <= WB_ADR_I;
                                request_address <= WB_ADR_I;
                                burst_data[0] <= WB_DAT_I;
                                burst_select[0] <= WB_SEL_I;
                                collect_index <= 5'd1;
                                state <= B_W_COLLECT;
                            end
                            else
                                state <= B_ERROR;
                        end

                        else begin
                            request_address <= WB_ADR_I;
                            if (WB_WE_I) begin
                                single_write_data <= WB_DAT_I;
                                single_write_select <= WB_SEL_I;
                                state <= B_W_SINGLE;
                            end
                            else if (WB_CTI_I == CTI_INCREMENT) begin
                                if (burst_address_valid) begin
                                    burst_address <= WB_ADR_I;
                                    state <= B_R_BURST_ADDR;
                                end
                                else
                                    state <= B_ERROR;
                            end
                            else begin
                                state <= B_R_SINGLE_ADDR;
                            end
                        end

                    end


                end

                B_W_COLLECT: begin
                    if (!WB_CYC_I) begin
                        state <= B_IDLE;
                        collect_index <= 5'd0;
                    end
                    else if (WB_STB_I) begin
                        if ((WB_ADR_I != burst_address + collect_index*(DATA_WIDTH/8)) || !WB_WE_I || (WB_BTE_I != 2'b00) || (WB_CTI_I != ((collect_index == MAX_BURST_BEATS-1) ? CTI_END : CTI_INCREMENT))) begin
                            state <= B_ERROR;
                        end
                        else if (collect_index < MAX_BURST_BEATS) begin
                            burst_data[collect_index] <= WB_DAT_I;
                            burst_select[collect_index] <= WB_SEL_I;

                            if (collect_index == MAX_BURST_BEATS-1) begin
                                request_address <= burst_address;
                                aw_sent <= 1'b0;
                                w_sent <= 1'b0;
                                write_index <= 5'd0;
                                state <= B_W_BURST;
                            end

                            else
                                collect_index <= collect_index + 1'b1;
                        end
                        else
                            state <= B_ERROR;
                    end
                end


                B_W_SINGLE: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY)
                        aw_sent <= 1'b1;
                    if (M_AXI_WVALID && M_AXI_WREADY)
                        w_sent <= 1'b1;
                    if (M_AXI_BVALID && M_AXI_BREADY)
                        state <= B_RELEASE;
                end

                B_W_BURST: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY)
                        aw_sent <= 1'b1;
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        if (write_index == MAX_BURST_BEATS-1)
                            w_sent <= 1'b1;
                        else
                            write_index <= write_index + 1'b1;
                    end
                    if (aw_sent && w_sent)
                        state <= B_W_WAIT;
                end

                B_W_WAIT: begin
                    if (M_AXI_BVALID && M_AXI_BREADY)
                        state <= B_RELEASE;
                end

                B_R_SINGLE_ADDR: begin
                    if (M_AXI_ARREADY)
                        state <= B_R_SINGLE_DATA;
                end

                B_R_SINGLE_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        read_data_register <= M_AXI_RDATA;
                        if (M_AXI_RLAST)
                            state <= B_RELEASE;
                        else
                            state <= B_R_DRAIN;
                    end
                end

                B_R_BURST_ADDR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        read_index <= 5'd0;
                        state <= B_R_BURST_DATA;
                    end
                end

                B_R_BURST_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        if ((M_AXI_RRESP != 2'b00) || (M_AXI_RID != {AXI_ID_WIDTH{1'b0}}) || (M_AXI_RLAST != (read_index == MAX_BURST_BEATS-1)) || (WB_CYC_I && WB_STB_I && ((WB_ADR_I != burst_address + read_index*(DATA_WIDTH/8)) || (WB_CTI_I != ((read_index == MAX_BURST_BEATS-1) ? CTI_END : CTI_INCREMENT))))) begin
                            state <= M_AXI_RLAST ? B_RELEASE : B_R_DRAIN;
                        end
                        else if (M_AXI_RLAST) begin
                            state <= B_RELEASE;
                        end
                        else begin
                            read_index <= read_index + 1'b1;
                        end
                    end

                end


                B_R_DRAIN: begin
                    if (M_AXI_RVALID && M_AXI_RREADY && M_AXI_RLAST)
                        state <= B_RELEASE;
                end

                B_ERROR: begin
                    // Keep WB_ERR asserted for a complete response cycle,
                    // then wait for the master to retire the rejected beat.
                    state <= B_RELEASE;
                end

                B_RELEASE: begin
                    // Do not reinterpret the still-asserted final WB beat as a new transaction after ACK/ERR. A burst master drops STB/CYC at its CTI=END boundary before the next request.
                    if (!WB_CYC_I || !WB_STB_I)
                        state <= B_IDLE;
                end

                default: state <= B_IDLE;
            endcase


        end

    end
endmodule