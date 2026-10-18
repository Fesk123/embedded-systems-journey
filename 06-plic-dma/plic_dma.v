`timescale 1ns/1ps

module plic_dma (

    input CLK_I,
    input RST_I,

    // CPU WISHBONE INTERFACE

    input [63:0] ADR_I,
    input [63:0] DAT_I,
    output [63:0] DAT_O,
    input [7:0] SEL_I,

    input CYC_I,
    input STB_I,
    input WE_I,
    output ACK_O,
    output ERR_O,

    // SHARED WISHBONE INTERFACE TO MEMORY / PERIPHERALS

    output [63:0] WB_ADR_O,
    output [63:0] WB_DAT_O,
    input [63:0] WB_DAT_I,
    output [7:0] WB_SEL_O,
    output WB_CYC_O,
    output WB_STB_O,
    output WB_WE_O,
    input WB_ACK_I,
    input WB_ERR_I,

    // INTERRUPT INTERFACE

    input [31:0] IRQ_SOURCES_I,
    output PLIC_IRQ_O,
    output [3:0] DMA_IRQ_O

);
    // MEMORY MAP

    // PLIC registers: 0x0C000000 - 0x0FFFFFFF
    // DMA control registers: 0x10000000 - 0x100000FF
    // Other addresses are passed to the shared Wishbone bus.

    localparam [63:0] PLIC_BASE = 64'h0000_0000_0C00_0000;
    localparam [63:0] DMA_BASE = 64'h0000_0000_1000_0000;

    wire plic_select = (ADR_I >= PLIC_BASE) && (ADR_I < 64'h0000_0000_1000_0000);
    wire dma_select = (ADR_I >= DMA_BASE) && (ADR_I < 64'h0000_0000_1000_0100);

    // PLIC WIRES

    wire [63:0] plic_dat_o;
    wire plic_ack_o;
    wire plic_err_o;
    wire [31:0] plic_irq_sources;

    // DMA interrupts use PLIC sources 1 through 4.
    // External interrupt sources are connected to source IDs 5 through 31.

    assign plic_irq_sources = {IRQ_SOURCES_I[31:5], DMA_IRQ_O, 1'b0};

    plic plic_unit (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(ADR_I - PLIC_BASE),
        .DAT_I(DAT_I),

        .DAT_O(plic_dat_o),
        .SEL_I(SEL_I),
        .CYC_I(CYC_I && plic_select),
        .STB_I(STB_I && plic_select),
        .WE_I(WE_I),
        .ACK_O(plic_ack_o),
        .ERR_O(plic_err_o),
        .IRQ_I(plic_irq_sources),
        .IRQ_O(PLIC_IRQ_O)
    );


    // DMA CONTROLLER WIRES


    wire [63:0] dma_ctrl_dat_o;
    wire dma_ctrl_ack_o;
    wire dma_ctrl_err_o;

    wire engine_start;
    wire [63:0] engine_src;
    wire [63:0] engine_dst;
    wire [63:0] engine_length;
    wire engine_busy;
    wire engine_done;
    wire engine_error;

    wire descriptor_start;
    wire [63:0] descriptor_address;
    wire descriptor_busy;
    wire descriptor_valid;
    wire descriptor_error;
    wire [63:0] descriptor_src;
    wire [63:0] descriptor_dst;
    wire [63:0] descriptor_length;
    wire [63:0] descriptor_control;
    wire [63:0] descriptor_next;

    dma_controller dma_controller_unit (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .ADR_I(ADR_I - DMA_BASE),
        .DAT_I(DAT_I),
        .DAT_O(dma_ctrl_dat_o),
        .SEL_I(SEL_I),
        .CYC_I(CYC_I && dma_select),
        .STB_I(STB_I && dma_select),
        .WE_I(WE_I),
        .ACK_O(dma_ctrl_ack_o),
        .ERR_O(dma_ctrl_err_o),
        .ENGINE_START_O(engine_start),
        .ENGINE_SRC_O(engine_src),
        .ENGINE_DST_O(engine_dst),
        .ENGINE_LENGTH_O(engine_length),
        .ENGINE_BUSY_I(engine_busy),
        .ENGINE_DONE_I(engine_done),
        .ENGINE_ERROR_I(engine_error),

        .DESCRIPTOR_START_O(descriptor_start),
        .DESCRIPTOR_ADDRESS_O(descriptor_address),
        .DESCRIPTOR_BUSY_I(descriptor_busy),
        .DESCRIPTOR_VALID_I(descriptor_valid),
        .DESCRIPTOR_ERROR_I(descriptor_error),
        .DESCRIPTOR_SRC_I(descriptor_src),
        .DESCRIPTOR_DST_I(descriptor_dst),
        .DESCRIPTOR_LENGTH_I(descriptor_length),
        .DESCRIPTOR_CONTROL_I(descriptor_control),
        .DESCRIPTOR_NEXT_I(descriptor_next),
        .IRQ_O(DMA_IRQ_O)

    );


    // DMA ENGINE WIRES
    wire [63:0] engine_wb_adr;
    wire [63:0] engine_wb_dat_o;
    wire [63:0] engine_wb_dat_i;
    wire [7:0] engine_wb_sel;

    wire engine_wb_cyc;
    wire engine_wb_stb;
    wire engine_wb_we;
    wire engine_wb_ack;
    wire engine_wb_err;

    dma_engine dma_engine_unit (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .START_I(engine_start),
        .SRC_I(engine_src),
        .DST_I(engine_dst),
        .LENGTH_I(engine_length),
        .BUSY_O(engine_busy),
        .DONE_O(engine_done),
        .ERROR_O(engine_error),
        .ERROR_CODE_O(),
        .WB_ADR_O(engine_wb_adr),
        .WB_DAT_O(engine_wb_dat_o),
        .WB_DAT_I(engine_wb_dat_i),
        .WB_SEL_O(engine_wb_sel),
        .WB_CYC_O(engine_wb_cyc),
        .WB_STB_O(engine_wb_stb),
        .WB_WE_O(engine_wb_we),
        .WB_ACK_I(engine_wb_ack),
        .WB_ERR_I(engine_wb_err)
    );


    // DMA DESCRIPTOR WIRES


    wire [63:0] desc_wb_adr;
    wire [63:0] desc_wb_dat_o;
    wire [63:0] desc_wb_dat_i;
    wire [7:0] desc_wb_sel;

    wire desc_wb_cyc;
    wire desc_wb_stb;
    wire desc_wb_we;
    wire desc_wb_ack;
    wire desc_wb_err;

    dma_descriptor dma_descriptor_unit (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .START_I(descriptor_start),
        .DESCRIPTOR_ADDRESS_I(descriptor_address),
        .BUSY_O(descriptor_busy),
        .VALID_O(descriptor_valid),
        .ERROR_O(descriptor_error),
        .SRC_O(descriptor_src),
        .DST_O(descriptor_dst),
        .LENGTH_O(descriptor_length),
        .CONTROL_O(descriptor_control),
        .NEXT_O(descriptor_next),
        .WB_ADR_O(desc_wb_adr),
        .WB_DAT_O(desc_wb_dat_o),
        .WB_DAT_I(desc_wb_dat_i),
        .WB_SEL_O(desc_wb_sel),
        .WB_CYC_O(desc_wb_cyc),
        .WB_STB_O(desc_wb_stb),
        .WB_WE_O(desc_wb_we),
        .WB_ACK_I(desc_wb_ack),
        .WB_ERR_I(desc_wb_err)
    );


    // DMA ENGINE / DESCRIPTOR ARBITER


    wire [63:0] dma_bus_adr;
    wire [63:0] dma_bus_dat_o;
    wire [63:0] dma_bus_dat_i;
    wire [7:0] dma_bus_sel;

    wire dma_bus_cyc;
    wire dma_bus_stb;
    wire dma_bus_we;
    wire dma_bus_ack;
    wire dma_bus_err;

    dma_arbiter dma_arbiter_unit (
        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .M0_ADR_I(engine_wb_adr),
        .M0_DAT_I(engine_wb_dat_o),
        .M0_DAT_O(engine_wb_dat_i),
        .M0_SEL_I(engine_wb_sel),
        .M0_CYC_I(engine_wb_cyc),
        .M0_STB_I(engine_wb_stb),

        .M0_WE_I(engine_wb_we),
        .M0_ACK_O(engine_wb_ack),
        .M0_ERR_O(engine_wb_err),
        .M1_ADR_I(desc_wb_adr),
        .M1_DAT_I(desc_wb_dat_o),
        .M1_DAT_O(desc_wb_dat_i),
        .M1_SEL_I(desc_wb_sel),
        .M1_CYC_I(desc_wb_cyc),

        .M1_STB_I(desc_wb_stb),

        .M1_WE_I(desc_wb_we),
        .M1_ACK_O(desc_wb_ack),
        .M1_ERR_O(desc_wb_err),
        .WB_ADR_O(dma_bus_adr),
        .WB_DAT_O(dma_bus_dat_o),
        .WB_DAT_I(dma_bus_dat_i),
        .WB_SEL_O(dma_bus_sel),
        .WB_CYC_O(dma_bus_cyc),
        .WB_STB_O(dma_bus_stb),
        .WB_WE_O(dma_bus_we),
        .WB_ACK_I(dma_bus_ack),
        .WB_ERR_I(dma_bus_err)
    );


    // CPU / DMA SHARED BUS ARBITER


    wire [63:0] cpu_bus_dat_i;
    wire cpu_bus_ack;
    wire cpu_bus_err;

    wire [63:0] dma_shared_dat_i;
    wire dma_shared_ack;
    wire dma_shared_err;

    wb_arbiter wb_arbiter_unit (
        

        .CLK_I(CLK_I),
        .RST_I(RST_I),
        .CPU_ADR_I(ADR_I),
        .CPU_DAT_I(DAT_I),
        .CPU_DAT_O(cpu_bus_dat_i),

        .CPU_SEL_I(SEL_I),
        .CPU_CYC_I(CYC_I && !plic_select && !dma_select),
        .CPU_STB_I(STB_I && !plic_select && !dma_select),
        .CPU_WE_I(WE_I),
        .CPU_ACK_O(cpu_bus_ack),
        .CPU_ERR_O(cpu_bus_err),
        .DMA_ADR_I(dma_bus_adr),

        .DMA_DAT_I(dma_bus_dat_o),
        .DMA_DAT_O(dma_shared_dat_i),
        .DMA_SEL_I(dma_bus_sel),
        .DMA_CYC_I(dma_bus_cyc),
        .DMA_STB_I(dma_bus_stb),
        .DMA_WE_I(dma_bus_we),
        .DMA_ACK_O(dma_shared_ack),
        .DMA_ERR_O(dma_shared_err),
        .WB_ADR_O(WB_ADR_O),
        .WB_DAT_O(WB_DAT_O),
        .WB_DAT_I(WB_DAT_I),
        .WB_SEL_O(WB_SEL_O),
        .WB_CYC_O(WB_CYC_O),
        .WB_STB_O(WB_STB_O),
        .WB_WE_O(WB_WE_O),
        .WB_ACK_I(WB_ACK_I),
        .WB_ERR_I(WB_ERR_I)
    );

    assign dma_bus_dat_i = dma_shared_dat_i;
    assign dma_bus_ack = dma_shared_ack;
    assign dma_bus_err = dma_shared_err;


    // CPU RESPONSE MULTIPLEXER


    assign DAT_O = plic_select ? plic_dat_o : dma_select  ? dma_ctrl_dat_o : cpu_bus_dat_i;

    assign ACK_O = plic_select ? plic_ack_o : dma_select  ? dma_ctrl_ack_o : cpu_bus_ack;
    assign ERR_O = plic_select ? plic_err_o : dma_select  ? dma_ctrl_err_o : cpu_bus_err;


endmodule