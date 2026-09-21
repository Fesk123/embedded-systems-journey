`timescale 1ns/1ps

// The testbench runs a small RISC-V program and checks the pipeline behaviour in GTKWave

module Sim_5SP_MC_RV32IMA;

    reg clk;
    reg rst;
    reg clock_enable;


    // Debug outputs

    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [31:0] debug_result;


    // DUT

    RV32IMA_5SP_CPU dut (
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


    function [31:0] encode_u;

        input [19:0] imm;
        input [4:0] rd;
        input [6:0] opcode;

        begin

            encode_u = {imm, rd, opcode};

        end

    endfunction


    function [31:0] encode_j;

        input [20:0] imm;
        input [4:0] rd;
        input [6:0] opcode;

        begin

            encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};

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
    localparam [6:0] OPCODE_LUI = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC = 7'b0010111;
    localparam [6:0] OPCODE_JAL = 7'b1101111;
    localparam [6:0] OPCODE_JALR = 7'b1100111;
    localparam [6:0] OPCODE_ATOMIC = 7'b0101111;


    // Main testbench

    integer i;

    initial begin

        // Reset

        rst = 1'b1;
        clock_enable = 1'b1;

        #2;

        // Initialize memories used by the testbench.

        for (i = 0; i < 32; i = i + 1)
            dut.instruction_memory[i] = 32'h00000013;

        for (i = 0; i < 16; i = i + 1)
            dut.data_memory[i] = 32'd0;


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
        // SLT
        // SLTU
        // Immediate ALU operations
        // LUI
        // AUIPC
        // LW
        // SW

        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd20, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);

        dut.instruction_memory[3] = encode_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4, OPCODE_OP);

        dut.instruction_memory[4] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd5, OPCODE_OP);

        dut.instruction_memory[5] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd6, OPCODE_OP);

        dut.instruction_memory[6] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd7, OPCODE_OP);

        dut.instruction_memory[7] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd8, OPCODE_OP);

        dut.instruction_memory[8] =  encode_r(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd9, OPCODE_OP);

        dut.instruction_memory[9] = encode_r(7'b0100000, 5'd2, 5'd1, 3'b101, 5'd10, OPCODE_OP);

        dut.instruction_memory[10] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd11, OPCODE_OP);

        dut.instruction_memory[11] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd12, OPCODE_OP);

        dut.instruction_memory[12] = encode_i(12'd5, 5'd1, 3'b000, 5'd13, OPCODE_OP_IMM);

        dut.instruction_memory[13] = encode_i(12'd10, 5'd1, 3'b010, 5'd14, OPCODE_OP_IMM);

        dut.instruction_memory[14] = encode_i(12'd10, 5'd1, 3'b011, 5'd15, OPCODE_OP_IMM);

        dut.instruction_memory[15] = encode_i(12'd3, 5'd1, 3'b100, 5'd16, OPCODE_OP_IMM);

        dut.instruction_memory[16] = encode_i(12'd8, 5'd1, 3'b110, 5'd17, OPCODE_OP_IMM);

        dut.instruction_memory[17] = encode_i(12'd7, 5'd1, 3'b111, 5'd18, OPCODE_OP_IMM);

        dut.instruction_memory[18] = encode_i(12'd2, 5'd1, 3'b001, 5'd19, OPCODE_OP_IMM);

        dut.instruction_memory[19] = encode_i(12'd2, 5'd19, 3'b101, 5'd20, OPCODE_OP_IMM);

        dut.instruction_memory[20] = encode_i(12'hFF8, 5'd0, 3'b000, 5'd21, OPCODE_OP_IMM);

        dut.instruction_memory[21] = encode_i(12'h401, 5'd21, 3'b101, 5'd22, OPCODE_OP_IMM);

        dut.instruction_memory[22] = encode_u(20'h12345, 5'd23, OPCODE_LUI);

        dut.instruction_memory[23] = encode_u(20'h00001, 5'd24, OPCODE_AUIPC);

        dut.instruction_memory[24] = encode_s(12'd0, 5'd3, 5'd0, 3'b010, OPCODE_STORE);

        dut.instruction_memory[25] = encode_i(12'd0, 5'd0, 3'b010, 5'd25, OPCODE_LOAD);

        dut.instruction_memory[26] = 32'h00000013;

        #400;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.
    

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
        // Division by zero
        // Signed overflow case

        dut.instruction_memory[0] = encode_u(20'h00010, 5'd1, OPCODE_LUI);

        dut.instruction_memory[1] = encode_u(20'h00010, 5'd2, OPCODE_LUI);

        dut.instruction_memory[2] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);

        dut.instruction_memory[3] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b001, 5'd4, OPCODE_OP);

        dut.instruction_memory[4] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b010, 5'd5, OPCODE_OP);

        dut.instruction_memory[5] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b011, 5'd6, OPCODE_OP);

        dut.instruction_memory[6] = encode_i(12'hFF9, 5'd0, 3'b000, 5'd7, OPCODE_OP_IMM);

        dut.instruction_memory[7] = encode_i(12'd3, 5'd0, 3'b000, 5'd8, OPCODE_OP_IMM);

        dut.instruction_memory[8] = encode_r(7'b0000001, 5'd8, 5'd7, 3'b100, 5'd9, OPCODE_OP);

        dut.instruction_memory[9] = encode_r(7'b0000001, 5'd8, 5'd7, 3'b101, 5'd10, OPCODE_OP);

        dut.instruction_memory[10] = encode_r(7'b0000001, 5'd8, 5'd7, 3'b110, 5'd11, OPCODE_OP);

        dut.instruction_memory[11] = encode_r(7'b0000001, 5'd8, 5'd7, 3'b111, 5'd12, OPCODE_OP);

        dut.instruction_memory[12] = encode_r(7'b0000001, 5'd0, 5'd8, 3'b100, 5'd13, OPCODE_OP);

        dut.instruction_memory[13] = encode_r(7'b0000001, 5'd0, 5'd8, 3'b110, 5'd14, OPCODE_OP);

        dut.instruction_memory[14] = encode_u(20'h80000, 5'd15, OPCODE_LUI);

        dut.instruction_memory[15] = encode_i(12'hFFF, 5'd0, 3'b000, 5'd16, OPCODE_OP_IMM);

        dut.instruction_memory[16] = encode_r(7'b0000001, 5'd16, 5'd15, 3'b100, 5'd17, OPCODE_OP);

        dut.instruction_memory[17] = encode_r(7'b0000001, 5'd16, 5'd15, 3'b110, 5'd18, OPCODE_OP);

        dut.instruction_memory[18] = 32'h00000013;

        #500;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

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
        dut.data_memory[4] = 32'd50;
        dut.data_memory[5] = 32'd60;
        dut.data_memory[6] = 32'd70;
        dut.data_memory[7] = 32'd80;
        dut.data_memory[8] = 32'd90;

        // x1 = address 0
        // x2 = value 5
        // x3 = address 4
        // x5 = address 8
        // x6 = address 16
        // x7 = address 20
        // x8 = address 24
        // x9 = address 28
        // x10 = address 32
        // x16 = -1

        dut.instruction_memory[0] = encode_i(12'd0, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd5, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_i(12'd4, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[3] = encode_i(12'd8, 5'd0, 3'b000, 5'd5, OPCODE_OP_IMM);

        dut.instruction_memory[4] = encode_i(12'd16, 5'd0, 3'b000, 5'd6, OPCODE_OP_IMM);

        dut.instruction_memory[5] = encode_i(12'd20, 5'd0, 3'b000, 5'd7, OPCODE_OP_IMM);

        dut.instruction_memory[6] = encode_i(12'd24, 5'd0, 3'b000, 5'd8, OPCODE_OP_IMM);

        dut.instruction_memory[7] = encode_i(12'd28, 5'd0, 3'b000, 5'd9, OPCODE_OP_IMM);

        dut.instruction_memory[8] = encode_i(12'd32, 5'd0, 3'b000, 5'd10, OPCODE_OP_IMM);

        dut.instruction_memory[9] = encode_i(12'hFFF, 5'd0, 3'b000, 5'd16, OPCODE_OP_IMM);

        // LR.W x11, (x1)

        dut.instruction_memory[10] = encode_amo(5'b00010, 5'd0, 5'd1, 5'd11);

        // SC.W x12, x2, (x1)

        dut.instruction_memory[11] = encode_amo(5'b00011, 5'd2, 5'd1, 5'd12);

        // SC.W x13, x2, (x1)
        // This should fail because the previous SC.W consumed the reservation.

        dut.instruction_memory[12] = encode_amo(5'b00011, 5'd2, 5'd1, 5'd13);

        // AMOSWAP.W x14, x2, (x3)

        dut.instruction_memory[13] = encode_amo(5'b00001, 5'd2, 5'd3, 5'd14);

        // AMOADD.W x15, x2, (x3)

        dut.instruction_memory[14] = encode_amo(5'b00000, 5'd2, 5'd3, 5'd15);

        // AMOXOR.W x17, x2, (x5)

        dut.instruction_memory[15] = encode_amo(5'b00100, 5'd2, 5'd5, 5'd17);

        // AMOAND.W x18, x2, (x6)

        dut.instruction_memory[16] = encode_amo(5'b01100, 5'd2, 5'd6, 5'd18);

        // AMOOR.W x19, x2, (x7)

        dut.instruction_memory[17] = encode_amo(5'b01000, 5'd2, 5'd7, 5'd19);

        // AMOMIN.W x20, x16, (x8)

        dut.instruction_memory[18] = encode_amo(5'b10000, 5'd16, 5'd8, 5'd20);

        // AMOMAX.W x21, x16, (x8)

        dut.instruction_memory[19] = encode_amo(5'b10100, 5'd16, 5'd8, 5'd21);

        // AMOMINU.W x22, x2, (x9)

        dut.instruction_memory[20] = encode_amo(5'b11000, 5'd2, 5'd9, 5'd22);

        // AMOMAXU.W x23, x16, (x10)

        dut.instruction_memory[21] = encode_amo(5'b11100, 5'd16, 5'd10, 5'd23);

        dut.instruction_memory[22] = 32'h00000013;

        #700;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 4
        // DATA FORWARDING
        //
        // The results of previous ALU instructions are used directly by following instructions.


        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd5, 5'd1, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b000, 5'd3, OPCODE_OP);

        dut.instruction_memory[3] = encode_r(7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4, OPCODE_OP);

        dut.instruction_memory[4] = encode_r(7'b0000000, 5'd2, 5'd4, 3'b111, 5'd5, OPCODE_OP);

        dut.instruction_memory[5] = 32'h00000013;

        // Expected:
        // x1 = 10
        // x2 = 15
        // x3 = 25
        // x4 = 15
        // x5 = 15

        #250;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;

        // TEST 5
        // LOAD USE HAZARD
        //
        // The instruction following LW must wait for the memory result before using the loaded register.

        dut.data_memory[0] = 32'd25;

        // LW x1, 0(x0)

        dut.instruction_memory[0] = encode_i(12'd0, 5'd0, 3'b010, 5'd1, OPCODE_LOAD);

        // ADD x2, x1, x1

        dut.instruction_memory[1] = encode_r(7'b0000000, 5'd1, 5'd1, 3'b000, 5'd2, OPCODE_OP);

        // ADD x3, x2, x1

        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b000, 5'd3, OPCODE_OP);

        dut.instruction_memory[3] = 32'h00000013;

        // Expected:
        // x1 = 25
        // x2 = 50
        // x3 = 75
        // load_use_stall should become active for the LW -> ADD dependency.

        #250;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 6
        // BRANCH HANDLING AND PIPELINE FLUSH
        //
        // BEQ
        // BNE
        // BLT
        // BGE
        // BLTU
        // BGEU
        //
        // Each taken branch skips an instruction that writes x31. If flushing is correct, x31 stays zero.

        dut.instruction_memory[0] = encode_i(12'd5, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd5, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_i(12'hFFB, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[3] = encode_i(12'd10, 5'd0, 3'b000, 5'd4, OPCODE_OP_IMM);

        // BEQ x1, x2, +8

        dut.instruction_memory[4] = encode_b(13'd8, 5'd2, 5'd1, 3'b000, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[5] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // BNE x1, x3, +8

        dut.instruction_memory[6] = encode_b(13'd8, 5'd3, 5'd1, 3'b001, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[7] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // BLT x3, x1, +8

        dut.instruction_memory[8] = encode_b(13'd8, 5'd1, 5'd3, 3'b100, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[9] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // BGE x1, x3, +8

        dut.instruction_memory[10] = encode_b(13'd8, 5'd3, 5'd1, 3'b101, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[11] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // BLTU x1, x4, +8

        dut.instruction_memory[12] = encode_b(13'd8, 5'd4, 5'd1, 3'b110, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[13] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // BGEU x4, x1, +8

        dut.instruction_memory[14] = encode_b(13'd8, 5'd1, 5'd4, 3'b111, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[15] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // Target after all branches

        dut.instruction_memory[16] = encode_i(12'd42, 5'd0, 3'b000, 5'd5, OPCODE_OP_IMM);

        dut.instruction_memory[17] = 32'h00000013;

        // Expected:
        // x5 = 42
        // x31 = 0

        #400;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.
    
        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;

        // TEST 7
        // JAL
        //
        // The wrong path instruction must be flushed and rd must receive PC + 4.
        

        // JAL x5, +8

        dut.instruction_memory[0] = encode_j(21'd8, 5'd5, OPCODE_JAL);

        // Wrong path

        dut.instruction_memory[1] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // Target

        dut.instruction_memory[2] = encode_i(12'd42, 5'd0, 3'b000, 5'd6, OPCODE_OP_IMM);

        dut.instruction_memory[3] = 32'h00000013;

        // Expected:
        // x5 = 4
        // x6 = 42
        // x31 = 0

        #200;

        clock_enable = 1'b0;



        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.
        

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 8
        // JALR
        //
        // The JALR source register depends on the immediately preceding ADDI instruction and therefore also tests forwarding into the jump calculation.


        // ADDI x1, x0, 16

        dut.instruction_memory[0] = encode_i(12'd16, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // JALR x5, 0(x1)

        dut.instruction_memory[1] = encode_i(12'd0, 5'd1, 3'b000, 5'd5, OPCODE_JALR);

        // Wrong path

        dut.instruction_memory[2] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        dut.instruction_memory[3] = encode_i(12'd98, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // Target

        dut.instruction_memory[4] = encode_i(12'd42, 5'd0, 3'b000, 5'd6, OPCODE_OP_IMM);

        dut.instruction_memory[5] = 32'h00000013;

        // Expected:
        // x1 = 16
        // x5 = 8
        // x6 = 42
        // x31 = 0

        #250;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.


        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;

        // TEST 9
        // BRANCH DEPENDENCY
        //
        // The branch uses a value produced by a previous ALU instruction. The value must reach the branch through the forwarding logic.


        // ADDI x1, x0, 10

        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // ADDI x2, x1, 0

        dut.instruction_memory[1] = encode_i(12'd0, 5'd1, 3'b000, 5'd2, OPCODE_OP_IMM);

        // BEQ x1, x2, +8

        dut.instruction_memory[2] = encode_b(13'd8, 5'd2, 5'd1, 3'b000, OPCODE_BRANCH);

        // Wrong path

        dut.instruction_memory[3] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        // Target

        dut.instruction_memory[4] = encode_i(12'd42, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[5] = 32'h00000013;

        // Expected:
        // x1 = 10
        // x2 = 10
        // x3 = 42
        // x31 = 0

        #200;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.
      

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 10
        // RV32IMA MIXED PIPELINE
        //
        // The CPU executes I, M, memory, and A instructions in one program to verify that the complete pipeline can move different instruction types together.


        dut.data_memory[0] = 32'd7;
        dut.data_memory[1] = 32'd10;

        // ADDI x1, x0, 6

        dut.instruction_memory[0] = encode_i(12'd6, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // ADDI x2, x0, 7

        dut.instruction_memory[1] = encode_i(12'd7, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // MUL x3, x1, x2

        dut.instruction_memory[2] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);

        // SW x3, 4(x0)

        dut.instruction_memory[3] = encode_s(12'd4, 5'd3, 5'd0, 3'b010, OPCODE_STORE);

        // LW x4, 4(x0)

        dut.instruction_memory[4] = encode_i(12'd4, 5'd0, 3'b010, 5'd4, OPCODE_LOAD);

        // ADD x5, x4, x3

        dut.instruction_memory[5] = encode_r(7'b0000000, 5'd3, 5'd4, 3'b000, 5'd5, OPCODE_OP);

        // LR.W x6, (x0)

        dut.instruction_memory[6] = encode_amo(5'b00010, 5'd0, 5'd0, 5'd6);

        // AMOADD.W x7, x2, (x0)

        dut.instruction_memory[7] = encode_amo(5'b00000, 5'd2, 5'd0, 5'd7);

        // NOP

        dut.instruction_memory[8] = 32'h00000013;

        // Expected:
        // x3 = 42
        // x4 = 42
        // x5 = 84
        // x6 = 7
        // x7 = 7
        // memory[0] = 14
        // memory[1] = 10
        // memory[1] is overwritten by the SW at address 4 bytes.

        #350;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped at the end of the simulation so the final pipeline state can be inspected in GTKWave.

        #200;


        // End of simulation

        $finish;

    end


    // Waveform dump

    initial begin
        $dumpfile("Sim_5SP_MC_RV32IMA.vcd");
        $dumpvars(0, Sim_5SP_MC_RV32IMA);
        
    end


endmodule
