`timescale 1ns/1ps




module Sim_RV32IMA;

    reg clk;
    reg rst;
    reg clock_enable;


    // Debug outputs

    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [31:0] debug_result;


    // DUT

    RV32IMA_CPU dut(
        .clk(clk),
        .rst(rst),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_result(debug_result)
    );


    // Clock

    initial begin

        clk = 1'b0;
        clock_enable = 1'b1;

        forever begin

            #5;

            if (clock_enable)
                clk = ~clk;
            else
                clk = 1'b0;

        end

    end


    // Instruction encoders

    function [31:0] encode_r;

        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;

        begin
            encode_r = {funct7, rs2, rs1, funct3, rd, opcode};
        end

    endfunction


    function [31:0] encode_i;

        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;

        begin
            encode_i = {imm, rs1, funct3, rd, opcode};
        end

    endfunction


    function [31:0] encode_s;

        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;

        begin
            encode_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
        end

    endfunction


    function [31:0] encode_b;

        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;

        begin
            encode_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
        end

    endfunction


    function [31:0] encode_amo;

        input [4:0] funct5;
        input [4:0] rs2;
        input [4:0] rs1;
        input [4:0] rd;

        begin
            // aq = 0, rl = 0, funct3 = 010, opcode = 0101111
            encode_amo = {funct5, 2'b00, rs2, rs1, 3'b010, rd, 7'b0101111};
        end

    endfunction


    // Testbench constants

    localparam [6:0] OPCODE_OP = 7'b0110011;
    localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam [6:0] OPCODE_LOAD = 7'b0000011;
    localparam [6:0] OPCODE_STORE = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_ATOMIC = 7'b0101111;

    


    // Main testbench

    initial begin

        // Reset

        rst = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 1
        // RV32I
        //
        // ADDI
        // ADD
        // SUB
        // AND
        // OR
        // XOR
        // SLL
        // SRL
        // SRA
        // LW
        // SW
        // BEQ

        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] =encode_i(12'd20, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);
 
        dut.instruction_memory[3] = encode_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4, OPCODE_OP);

        dut.instruction_memory[4] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd5, OPCODE_OP);

        dut.instruction_memory[5] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd6, OPCODE_OP);

        dut.instruction_memory[6] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd7, OPCODE_OP);

        dut.instruction_memory[7] = encode_i(12'd1, 5'd1, 3'b001, 5'd8, OPCODE_OP_IMM);

        dut.instruction_memory[8] = encode_i(12'd1, 5'd2, 3'b101, 5'd9, OPCODE_OP_IMM);

        dut.instruction_memory[9] = encode_i(12'h401, 5'd2, 3'b101, 5'd10, OPCODE_OP_IMM);

        dut.instruction_memory[10] = encode_s(12'd0, 5'd3, 5'd0, 3'b010, OPCODE_STORE);

        dut.instruction_memory[11] = encode_i(12'd0, 5'd0, 3'b010, 5'd11, OPCODE_LOAD);

        dut.instruction_memory[12] = encode_b(13'd8, 5'd11, 5'd3, 3'b000, OPCODE_BRANCH);

        dut.instruction_memory[13] = encode_i(12'd1, 5'd0, 3'b000, 5'd12, OPCODE_OP_IMM);

        dut.instruction_memory[14] = 32'h00000013;

        // Wait for the I test to complete.

        #160;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The CPU is allowed to run through NOP instructions
        // before the next extension is tested.
    

        dut.instruction_memory[15] = 32'h00000013;
        dut.instruction_memory[16] = 32'h00000013;
        dut.instruction_memory[17] = 32'h00000013;
        dut.instruction_memory[18] = 32'h00000013;
        dut.instruction_memory[19] = 32'h00000013;
        dut.instruction_memory[20] = 32'h00000013;

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;
        #20;
        rst = 1'b0;

        // TEST 2
        // RV32M
        //
        // MUL
        // MULH
        // MULHSU
        // MULHU
        // DIV
        // DIVU
        // REM
        // REMU
    

        dut.instruction_memory[0] = encode_i(12'd12, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd3, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);

        dut.instruction_memory[3] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b001, 5'd4, OPCODE_OP);

        dut.instruction_memory[4] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b010, 5'd5, OPCODE_OP);

        dut.instruction_memory[5] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b011, 5'd6, OPCODE_OP);

        dut.instruction_memory[6] = encode_r(7'b0000001, 5'd1, 5'd1, 3'b100, 5'd7, OPCODE_OP);

        dut.instruction_memory[7] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b101, 5'd8, OPCODE_OP);

        dut.instruction_memory[8] = encode_r(7'b0000001, 5'd1, 5'd1, 3'b110, 5'd9, OPCODE_OP);

        dut.instruction_memory[9] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b111, 5'd10, OPCODE_OP);

        dut.instruction_memory[10] = 32'h00000013;

        #120;

        clock_enable = 1'b0;

        // EMPTY SPACE
        //
        // The CPU is allowed to run through NOP instructions
        // before the A extension is tested.
        
        dut.instruction_memory[11] = 32'h00000013;
        dut.instruction_memory[12] = 32'h00000013;
        dut.instruction_memory[13] = 32'h00000013;
        dut.instruction_memory[14] = 32'h00000013;
        dut.instruction_memory[15] = 32'h00000013;
        dut.instruction_memory[16] = 32'h00000013;

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;
        #20;
        rst = 1'b0;



        // TEST 3
        // RV32A
        //
        // LR.W
        // SC.W
        // AMOSWAP.W
        // AMOADD.W
        // AMOXOR.W
        // AMOAND.W
        // AMOOR.W
        // AMOMIN.W
        // AMOMAX.W
        // AMOMINU.W
        // AMOMAXU.W

        dut.data_memory[0] = 32'd10;
        dut.data_memory[1] = 32'd20;
        dut.data_memory[2] = 32'd30;
        dut.data_memory[3] = 32'd40;
        dut.data_memory[4] = 32'd50;
        dut.data_memory[5] = 32'd60;
        dut.data_memory[6] = 32'd70;
        dut.data_memory[7] = 32'd80;
        dut.data_memory[8] = 32'd90;

        // x1 = address 0
        // x2 = value 5
        // x3 = address 4
        // x16 = -1

        dut.instruction_memory[0] = encode_i(12'd0, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd5, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_i(12'd4, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[3] = encode_i(12'hFFF, 5'd0, 3'b000, 5'd16, OPCODE_OP_IMM);

        // LR.W x4, (x1)

        dut.instruction_memory[4] = encode_amo(5'b00010, 5'd0, 5'd1, 5'd4);

        // SC.W x5, x2, (x1)

        dut.instruction_memory[5] = encode_amo(5'b00011, 5'd2, 5'd1, 5'd5);

        // SC.W x15, x2, (x1)
        // This should fail because the previous SC.W consumed the reservation.

        dut.instruction_memory[6] = encode_amo(5'b00011, 5'd2, 5'd1, 5'd15);

        // AMOSWAP.W x6, x2, (x3)

        dut.instruction_memory[7] = encode_amo(5'b00001, 5'd2, 5'd3, 5'd6);

        // AMOADD.W x7, x2, (x3)

        dut.instruction_memory[8] = encode_amo(5'b00000, 5'd2, 5'd3, 5'd7);

        // AMOXOR.W x8, x2, (x3)

        dut.instruction_memory[9] = encode_amo(5'b00100, 5'd2, 5'd3, 5'd8);

        // AMOAND.W x9, x2, (x3)

        dut.instruction_memory[10] = encode_amo(5'b01100, 5'd2, 5'd3, 5'd9);

        // AMOOR.W x10, x2, (x3)

        dut.instruction_memory[11] = encode_amo(5'b01000, 5'd2, 5'd3, 5'd10);

        // AMOMIN.W x11, x16, (x3)

        dut.instruction_memory[12] = encode_amo(5'b10000, 5'd16, 5'd3, 5'd11);

        // AMOMAX.W x12, x16, (x3)

        dut.instruction_memory[13] = encode_amo(5'b10100, 5'd16, 5'd3, 5'd12);

        // AMOMINU.W x13, x2, (x3)

        dut.instruction_memory[14] = encode_amo(5'b11000, 5'd2, 5'd3, 5'd13);

        // AMOMAXU.W x14, x16, (x3)

        dut.instruction_memory[15] = encode_amo(5'b11100, 5'd16, 5'd3, 5'd14);

        dut.instruction_memory[16] = 32'h00000013;

        #180;


        // End of simulation

        #50;

        $finish;

    end


    // Optional waveform dump

    initial begin

        $dumpfile("Sim_RV32IMA.vcd");
        $dumpvars(0, Sim_RV32IMA);

    end


endmodule