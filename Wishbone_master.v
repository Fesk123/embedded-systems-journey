module wishbone_master (
    input CLK_I,
    input RST_I,

    input cpu_start,
    input cpu_write,
    input [3:0] cpu_address,
    input [7:0] cpu_write_data,
    output reg [7:0] cpu_read_data,
    output reg cpu_done,

    // Wishbone interface
    output reg [3:0] ADR_O,
    output reg [7:0] DAT_O,
    input [7:0] DAT_I,

    output reg CYC_O,
    output reg STB_O,
    output reg WE_O,

    input ACK_I
);

    localparam IDLE = 1'b0;
    localparam WAIT = 1'b1;

    reg state;

    always @(posedge CLK_I or posedge RST_I) begin

        if (RST_I) begin

            state <= IDLE;

            ADR_O <= 4'b0;
            DAT_O <= 8'b0;

            CYC_O <= 1'b0;
            STB_O <= 1'b0;
            WE_O <= 1'b0;

            cpu_read_data <= 8'b0;
            cpu_done <= 1'b0;

        end

        else begin

            cpu_done <= 1'b0;

            case (state)

                IDLE: begin

                    CYC_O <= 1'b0;
                    STB_O <= 1'b0;
                    WE_O <= 1'b0;

                    if (cpu_start) begin

                        ADR_O <= cpu_address;

                        DAT_O <= cpu_write_data;

                        // 1 = write
                        // 0 = read
                        WE_O <= cpu_write;

                        // Start Wishbone cycle
                        CYC_O <= 1'b1;
                        STB_O <= 1'b1;

                        state <= WAIT;
                    end

                end


                // Wait for ACK
                WAIT: begin

                    if (ACK_I) begin

                        // Read data
                        if (!WE_O) begin
                            cpu_read_data <= DAT_I;
                        end

                        CYC_O <= 1'b0;
                        STB_O <= 1'b0;
                        WE_O <= 1'b0;

                        cpu_done <= 1'b1;

                        state <= IDLE;
                    end

                end

            endcase

        end

    end

endmodule