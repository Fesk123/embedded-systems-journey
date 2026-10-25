`timescale 1ns/1ps

// Register storage for the RISC-V Debug Module.
// The DMI address map follows the RISC-V Debug Specification 1.0.

module debug_registers(
    input wire clk_i,
    input wire rst_i,
    input wire dmclear_i,

    input wire wr_en_i,
    input wire [6:0] wr_addr_i,
    input wire [31:0] wr_data_i,
    input wire [6:0] rd_addr_i,
    output reg [31:0] rd_data_o,

    input wire [31:0] dmstatus_i,
    input wire [31:0] abstractcs_i,
    input wire [31:0] sbcs_i,

    input wire abstract_data_update_i,
    input wire [63:0] abstract_data_update_data_i,
    input wire sbdata_update_i,
    input wire [63:0] sbdata_update_data_i,
    input wire sbaddress_update_i,
    input wire [63:0] sbaddress_update_data_i,

    output wire [31:0] dmcontrol_o,
    output wire [31:0] data0_o,
    output wire [31:0] data1_o,
    output wire [31:0] command_o,
    output wire [31:0] abstractauto_o,
    output wire [127:0] progbuf_o,
    output wire [31:0] sbcs_control_o,
    output wire [63:0] sbaddress_o,
    output wire [63:0] sbdata_o
);

    reg [31:0] dmcontrol_reg;
    reg [31:0] data0_reg;
    reg [31:0] data1_reg;
    reg [31:0] command_reg;
    reg [31:0] abstractauto_reg;
    reg [31:0] progbuf0_reg;
    reg [31:0] progbuf1_reg;
    reg [31:0] progbuf2_reg;
    reg [31:0] progbuf3_reg;
    reg [31:0] sbcs_control_reg;
    reg [31:0] sbaddress0_reg;
    reg [31:0] sbaddress1_reg;
    reg [31:0] sbdata0_reg;
    reg [31:0] sbdata1_reg;

    assign dmcontrol_o = dmcontrol_reg;
    assign data0_o = data0_reg;
    assign data1_o = data1_reg;
    assign command_o = command_reg;
    assign abstractauto_o = abstractauto_reg;
    assign progbuf_o = {progbuf3_reg, progbuf2_reg, progbuf1_reg, progbuf0_reg};
    assign sbcs_control_o = sbcs_control_reg;
    assign sbaddress_o = {sbaddress1_reg, sbaddress0_reg};
    assign sbdata_o = {sbdata1_reg, sbdata0_reg};

    always @(posedge clk_i) begin

        if (rst_i || dmclear_i) begin
            dmcontrol_reg <= 0;
            data0_reg <= 0;
            data1_reg <= 0;
            command_reg <= 0;
            abstractauto_reg <= 0;
            progbuf0_reg <= 0;
            progbuf1_reg <= 0;
            progbuf2_reg <= 0;
            progbuf3_reg <= 0;
            sbcs_control_reg <= 32'h00040000; // Default sbaccess = 2 (32-bit).
            sbaddress0_reg <= 0;
            sbaddress1_reg <= 0;
            sbdata0_reg <= 0;
            sbdata1_reg <= 0;

        end else begin

            if (abstract_data_update_i) begin
                data0_reg <= abstract_data_update_data_i[31:0];
                data1_reg <= abstract_data_update_data_i[63:32];

            end else if (wr_en_i && wr_addr_i == 7'h04) begin
                data0_reg <= wr_data_i;

            end else if (wr_en_i && wr_addr_i == 7'h05) begin
                data1_reg <= wr_data_i;
            end

            if (sbdata_update_i) begin
                sbdata0_reg <= sbdata_update_data_i[31:0];
                sbdata1_reg <= sbdata_update_data_i[63:32];

            end else begin

                if (wr_en_i && wr_addr_i == 7'h3C)
                    sbdata0_reg <= wr_data_i;

                if (wr_en_i && wr_addr_i == 7'h3D)
                    sbdata1_reg <= wr_data_i;

            end

            if (sbaddress_update_i) begin
                sbaddress0_reg <= sbaddress_update_data_i[31:0];
                sbaddress1_reg <= sbaddress_update_data_i[63:32];
            end else begin

                if (wr_en_i && wr_addr_i == 7'h39)
                    sbaddress0_reg <= wr_data_i;
                if (wr_en_i && wr_addr_i == 7'h3A)
                    sbaddress1_reg <= wr_data_i;

            end

            if (wr_en_i) begin

                case (wr_addr_i)
                    7'h10: begin
                        if (wr_data_i[0])
                            dmcontrol_reg <= {wr_data_i[31], 1'b0, 2'b00, 24'd0, 2'b00, wr_data_i[1:0]};
                        else
                            dmcontrol_reg <= 32'd0;
                        // Single-hart implementation: hartsel, hasel, and hartreset are not implemented.
                    end
                    7'h17: command_reg <= wr_data_i;
                    7'h18: abstractauto_reg <= 32'd0; // Auto-execution is not implemented.
                    7'h20: progbuf0_reg <= wr_data_i;
                    7'h21: progbuf1_reg <= wr_data_i;
                    7'h22: progbuf2_reg <= wr_data_i;
                    7'h23: progbuf3_reg <= wr_data_i;
                    7'h38: sbcs_control_reg <= wr_data_i & 32'h001F8000;
                    default: begin end
                endcase

            end

        end


    end

    always @* begin
        rd_data_o = 32'd0;
        case (rd_addr_i)
            7'h04: rd_data_o = data0_reg;
            7'h05: rd_data_o = data1_reg;
            7'h10: rd_data_o = {dmcontrol_reg[31], 1'b0, 2'b00, 24'd0, 2'b00, dmcontrol_reg[1:0]};
            7'h11: rd_data_o = dmstatus_i;
            7'h12: rd_data_o = 32'd0;
            7'h16: rd_data_o = abstractcs_i;
            7'h17: rd_data_o = command_reg;
            7'h18: rd_data_o = 32'd0;
            7'h20: rd_data_o = progbuf0_reg;
            7'h21: rd_data_o = progbuf1_reg;
            7'h22: rd_data_o = progbuf2_reg;
            7'h23: rd_data_o = progbuf3_reg;
            7'h38: rd_data_o = sbcs_i;
            7'h39: rd_data_o = sbaddress0_reg;
            7'h3A: rd_data_o = sbaddress1_reg;
            7'h3C: rd_data_o = sbdata0_reg;
            7'h3D: rd_data_o = sbdata1_reg;
            default: rd_data_o = 32'd0;
        endcase
    end
endmodule