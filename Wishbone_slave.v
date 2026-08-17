module wishbone_ram (
    input CLK_I,
    input RST_I,

    // Wishbone interface
    input [3:0] ADR_I,
    input [7:0] DAT_I,
    output reg [7:0] DAT_O,

    input CYC_I,
    input STB_I,
    input WE_I,

    output ACK_O
);

    // 16 addresses × 8 bits
    reg [7:0] memory [0:15];

    integer i;

    // Initialize memory
    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            memory[i] = 8'b0;
        end
    end


    // Registered read data and synchronous write
    always @(posedge CLK_I or posedge RST_I) begin
        
        if (RST_I) begin
            DAT_O <= 8'b0;

        end else begin
        
            // Write on posedge when valid
            if (CYC_I && STB_I && WE_I) begin
                memory[ADR_I] <= DAT_I;
            end

            // Read: update output register when a valid read occurs
            if (CYC_I && STB_I && !WE_I) begin
                DAT_O <= memory[ADR_I];
        
            end
        end
    end

    // ACK is combinational when CYC and STB are asserted
    assign ACK_O = CYC_I & STB_I;

endmodule