`timescale 1ns/1ps

// The testbench runs a small RISC-V program and checks the CPU, pipeline, CSR, privilege, exception and trap behaviour in GTKWave

module Sim_v1_RV32IMA;

    reg clk;
    reg rst;
    reg clock_enable;


    // Debug outputs

    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [31:0] debug_result;



    v1_RV32IMA_CPU dut (
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


    function [31:0] encode_csr;

        input [11:0] csr;
        input [4:0] rs1_zimm;
        input [2:0] funct3;
        input [4:0] rd;

        begin

            encode_csr = {csr, rs1_zimm, funct3, rd, 7'b1110011};

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
    localparam [6:0] OPCODE_SYSTEM = 7'b1110011;


    // CSR addresses

    localparam [11:0] CSR_SSTATUS = 12'h100;
    localparam [11:0] CSR_SIE = 12'h104;
    localparam [11:0] CSR_STVEC = 12'h105;
    localparam [11:0] CSR_SSCRATCH = 12'h140;
    localparam [11:0] CSR_SEPC = 12'h141;
    localparam [11:0] CSR_SCAUSE = 12'h142;
    localparam [11:0] CSR_STVAL = 12'h143;
    localparam [11:0] CSR_SIP = 12'h144;
    localparam [11:0] CSR_SATP = 12'h180;

    localparam [11:0] CSR_MSTATUS = 12'h300;
    localparam [11:0] CSR_MISA = 12'h301;
    localparam [11:0] CSR_MEDELEG = 12'h302;
    localparam [11:0] CSR_MIDELEG = 12'h303;
    localparam [11:0] CSR_MIE = 12'h304;
    localparam [11:0] CSR_MTVEC = 12'h305;
    localparam [11:0] CSR_MSCRATCH = 12'h340;
    localparam [11:0] CSR_MEPC = 12'h341;
    localparam [11:0] CSR_MCAUSE = 12'h342;
    localparam [11:0] CSR_MTVAL = 12'h343;
    localparam [11:0] CSR_MIP = 12'h344;
    localparam [11:0] CSR_MHARTID = 12'hF14;


    // Main testbench

    integer i;

    initial begin

        // Reset

        rst = 1'b1;
        clock_enable = 1'b1;

        #2;

        // Initialize memories used by the testbench.

        for (i = 0; i < 64; i = i + 1)
            dut.instruction_memory[i] = 32'h00000013;

        for (i = 0; i < 32; i = i + 1)
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

        dut.instruction_memory[8] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd9, OPCODE_OP);

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

        dut.instruction_memory[0] = encode_i(12'd12, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd3, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

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

        // AMOMAXU.W x23, x16, x10

        dut.instruction_memory[21] = encode_amo(5'b11100, 5'd16, 5'd10, 5'd23);

        dut.instruction_memory[22] = 32'h00000013;

        #800;

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

        #300;

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

        #300;

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

        // Target

        dut.instruction_memory[16] = encode_i(12'd42, 5'd0, 3'b000, 5'd5, OPCODE_OP_IMM);

        dut.instruction_memory[17] = 32'h00000013;

        // Expected:
        // x5 = 42
        // x31 = 0

        #450;

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

        dut.instruction_memory[0] = encode_j(21'd8, 5'd5, OPCODE_JAL);

        dut.instruction_memory[1] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_i(12'd42, 5'd0, 3'b000, 5'd6, OPCODE_OP_IMM);

        dut.instruction_memory[3] = 32'h00000013;

        // Expected:
        // x5 = 4
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


        // TEST 8
        // JALR
        //
        // The JALR source register depends on the immediately preceding ADDI instruction and therefore also tests forwarding into the jump calculation.

        dut.instruction_memory[0] = encode_i(12'd16, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd0, 5'd1, 3'b000, 5'd5, OPCODE_JALR);

        dut.instruction_memory[2] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        dut.instruction_memory[3] = encode_i(12'd98, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        dut.instruction_memory[4] = encode_i(12'd42, 5'd0, 3'b000, 5'd6, OPCODE_OP_IMM);

        dut.instruction_memory[5] = 32'h00000013;

        // Expected:
        // x1 = 16
        // x5 = 8
        // x6 = 42
        // x31 = 0

        #300;

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

        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd0, 5'd1, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_b(13'd8, 5'd2, 5'd1, 3'b000, OPCODE_BRANCH);

        dut.instruction_memory[3] = encode_i(12'd99, 5'd0, 3'b000, 5'd31, OPCODE_OP_IMM);

        dut.instruction_memory[4] = encode_i(12'd42, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[5] = 32'h00000013;

        // Expected:
        // x1 = 10
        // x2 = 10
        // x3 = 42
        // x31 = 0

        #300;

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

        dut.instruction_memory[0] = encode_i(12'd6, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        dut.instruction_memory[1] = encode_i(12'd7, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[2] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);

        dut.instruction_memory[3] = encode_s(12'd4, 5'd3, 5'd0, 3'b010, OPCODE_STORE);

        dut.instruction_memory[4] = encode_i(12'd4, 5'd0, 3'b010, 5'd4, OPCODE_LOAD);

        dut.instruction_memory[5] = encode_r(7'b0000000, 5'd3, 5'd4, 3'b000, 5'd5, OPCODE_OP);

        dut.instruction_memory[6] = encode_amo(5'b00010, 5'd0, 5'd0, 5'd6);

        dut.instruction_memory[7] = encode_amo(5'b00000, 5'd2, 5'd0, 5'd7);

        dut.instruction_memory[8] = 32'h00000013;

        // Expected:
        // x3 = 42
        // x4 = 42
        // x5 = 84
        // x6 = 7
        // x7 = 7
        // memory[0] = 14
        // memory[1] = 42

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


        // TEST 11
        // CSR READ / WRITE
        //
        // CSRRW
        // CSRRS
        // CSRRC
        // CSRRWI
        // CSRRSI
        // CSRRCI
        //
        // The test uses mscratch so the CSR values are easy to follow in GTKWave.

        // ADDI x1, x0, 10

        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x2, mscratch, x1

        dut.instruction_memory[1] = encode_csr(CSR_MSCRATCH, 5'd1, 3'b001, 5'd2);

        // CSRRS x3, mscratch, x1

        dut.instruction_memory[2] = encode_csr(CSR_MSCRATCH, 5'd1, 3'b010, 5'd3);

        // CSRRC x4, mscratch, x1

        dut.instruction_memory[3] = encode_csr(CSR_MSCRATCH, 5'd1, 3'b011, 5'd4);

        // CSRRWI x5, mscratch, 5

        dut.instruction_memory[4] = encode_csr(CSR_MSCRATCH, 5'd5, 3'b101, 5'd5);

        // CSRRSI x6, mscratch, 3

        dut.instruction_memory[5] = encode_csr(CSR_MSCRATCH, 5'd3, 3'b110, 5'd6);

        // CSRRCI x7, mscratch, 1

        dut.instruction_memory[6] = encode_csr(CSR_MSCRATCH, 5'd1, 3'b111, 5'd7);

        // CSRR x8, mhartid

        dut.instruction_memory[7] = encode_csr(CSR_MHARTID, 5'd0, 3'b010, 5'd8);

        // CSRR x9, misa

        dut.instruction_memory[8] = encode_csr(CSR_MISA, 5'd0, 3'b010, 5'd9);

        dut.instruction_memory[9] = 32'h00000013;

        // Expected:
        // x2 = 0
        // x3 = 10
        // x4 = 10
        // x5 = 0
        // x6 = 5
        // x7 = 7
        // x8 = 0
        // x9 = 40001101
        // mscratch = 6

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


        // TEST 12
        // CSR SERIALIZATION
        //
        // A CSR write is immediately followed by a CSR read.
        // The second instruction must see the value written by the first instruction.

        // ADDI x1, x0, 21

        dut.instruction_memory[0] = encode_i(12'd21, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mscratch, x1

        dut.instruction_memory[1] = encode_csr(CSR_MSCRATCH, 5'd1, 3'b001, 5'd0);

        // CSRR x2, mscratch

        dut.instruction_memory[2] = encode_csr(CSR_MSCRATCH, 5'd0, 3'b010, 5'd2);

        // ADDI x3, x2, 1

        dut.instruction_memory[3] = encode_i(12'd1, 5'd2, 3'b000, 5'd3, OPCODE_OP_IMM);

        // CSRR x4, mscratch

        dut.instruction_memory[4] = encode_csr(CSR_MSCRATCH, 5'd0, 3'b010, 5'd4);

        dut.instruction_memory[5] = 32'h00000013;

        // Expected:
        // x2 = 21
        // x3 = 22
        // x4 = 21
        // mscratch = 21

        #350;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 13
        // M MODE TO U MODE
        //
        // MRET changes privilege mode according to mstatus.MPP.
        //

        // ADDI x1, x0, 64

        dut.instruction_memory[0] = encode_i(12'd64, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x1

        dut.instruction_memory[1] = encode_csr(CSR_MEPC, 5'd1, 3'b001, 5'd0);

        // CSRRW x0, mstatus, x0
        // MPP = U

        dut.instruction_memory[2] = encode_csr(CSR_MSTATUS, 5'd0, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[3] = 32'h30200073;

        // U-mode target

        dut.instruction_memory[16] = encode_i(12'd42, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[17] = 32'h00000013;

        // Expected:
        // current_mode = U
        // x2 = 42
        // PC reaches 64

        #350;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 14
        // M MODE TO S MODE
        //
        // mstatus.MPP is set to S before MRET.
        //

        // ADDI x1, x0, 1

        dut.instruction_memory[0] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // SLLI x1, x1, 11

        dut.instruction_memory[1] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mstatus, x1
        // MPP = S

        dut.instruction_memory[2] = encode_csr(CSR_MSTATUS, 5'd1, 3'b001, 5'd0);

        // ADDI x2, x0, 64

        dut.instruction_memory[3] = encode_i(12'd64, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x2

        dut.instruction_memory[4] = encode_csr(CSR_MEPC, 5'd2, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[5] = 32'h30200073;

        // S-mode target

        dut.instruction_memory[16] = encode_i(12'd43, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[17] = 32'h00000013;

        // Expected:
        // current_mode = S
        // x3 = 43
        // PC reaches 64

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


        // TEST 15
        // ILLEGAL INSTRUCTION EXCEPTION AND MRET
        //
        // The illegal instruction must not execute normally.
        // The trap handler adjusts mepc before returning.

        // ADDI x1, x0, 128

        dut.instruction_memory[0] = encode_i(12'd128, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mtvec, x1

        dut.instruction_memory[1] = encode_csr(CSR_MTVEC, 5'd1, 3'b001, 5'd0);

        // NOP

        dut.instruction_memory[2] = 32'h00000013;

        // NOP

        dut.instruction_memory[3] = 32'h00000013;

        // Illegal instruction

        dut.instruction_memory[4] = 32'hFFFFFFFF;

        // Instruction after trap return

        dut.instruction_memory[5] = encode_i(12'd55, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        dut.instruction_memory[6] = 32'h00000013;

        // Trap handler at address 128

        // CSRR x10, mepc

        dut.instruction_memory[32] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);

        // ADDI x10, x10, 4

        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x10

        dut.instruction_memory[34] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[35] = 32'h30200073;

        // Expected:
        // current_mode = M
        // mcause = 2
        // mepc = 20 after the handler update
        // mtval = FFFFFFFF
        // x2 = 55

        #600;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 16
        // BREAKPOINT EXCEPTION AND MRET
        //
        // EBREAK creates a breakpoint exception.

        // ADDI x1, x0, 128

        dut.instruction_memory[0] = encode_i(12'd128, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mtvec, x1

        dut.instruction_memory[1] = encode_csr(CSR_MTVEC, 5'd1, 3'b001, 5'd0);

        // EBREAK

        dut.instruction_memory[4] = 32'h00100073;

        // Instruction after trap return

        dut.instruction_memory[5] = encode_i(12'd66, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // Trap handler at address 128

        // CSRR x10, mepc

        dut.instruction_memory[32] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);

        // ADDI x10, x10, 4

        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x10

        dut.instruction_memory[34] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[35] = 32'h30200073;

        // Expected:
        // mcause = 3
        // mtval = 0
        // x2 = 66

        #600;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 17
        // ECALL FROM M MODE
        //
        // ECALL causes a synchronous exception in M-mode.
        //

        // ADDI x1, x0, 128

        dut.instruction_memory[0] = encode_i(12'd128, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mtvec, x1

        dut.instruction_memory[1] = encode_csr(CSR_MTVEC, 5'd1, 3'b001, 5'd0);

        // ECALL

        dut.instruction_memory[4] = 32'h00000073;

        // Instruction after trap return

        dut.instruction_memory[5] = encode_i(12'd77, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // Trap handler at address 128

        // CSRR x10, mepc

        dut.instruction_memory[32] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);

        // ADDI x10, x10, 4

        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x10

        dut.instruction_memory[34] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[35] = 32'h30200073;

        // Expected:
        // mcause = 11
        // x2 = 77

        #600;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 18
        // U MODE PRIVILEGE EXCEPTION
        //
        // A U-mode program attempts to read mstatus.
        // The access must create an illegal instruction exception and trap to M-mode.

        // ADDI x1, x0, 64

        dut.instruction_memory[0] = encode_i(12'd64, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x1

        dut.instruction_memory[1] = encode_csr(CSR_MEPC, 5'd1, 3'b001, 5'd0);

        // CSRRW x0, mstatus, x0
        // MPP = U

        dut.instruction_memory[2] = encode_csr(CSR_MSTATUS, 5'd0, 3'b001, 5'd0);

        // ADDI x4, x0, 128

        dut.instruction_memory[3] = encode_i(12'd128, 5'd0, 3'b000, 5'd4, OPCODE_OP_IMM);

        // CSRRW x0, mtvec, x4

        dut.instruction_memory[4] = encode_csr(CSR_MTVEC, 5'd4, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[5] = 32'h30200073;

        // U-mode illegal CSR access

        dut.instruction_memory[16] = encode_csr(CSR_MSTATUS, 5'd0, 3'b010, 5'd2);

        // Instruction after trap return

        dut.instruction_memory[17] = encode_i(12'd88, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        dut.instruction_memory[18] = 32'h00000013;

        // Trap handler at address 128

        dut.instruction_memory[32] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);

        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);

        dut.instruction_memory[34] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);

        dut.instruction_memory[35] = 32'h30200073;

        // Expected:
        // current_mode = U after MRET
        // mcause = 2
        // x3 = 88

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


        // TEST 19
        // S MODE ECALL
        //
        // M-mode enters S-mode and ECALL creates a trap to M-mode.
        // MRET must return to S-mode.

        // ADDI x1, x0, 1

        dut.instruction_memory[0] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // SLLI x1, x1, 11
        // MPP = S

        dut.instruction_memory[1] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, mstatus, x1

        dut.instruction_memory[2] = encode_csr(CSR_MSTATUS, 5'd1, 3'b001, 5'd0);

        // ADDI x2, x0, 64

        dut.instruction_memory[3] = encode_i(12'd64, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x2

        dut.instruction_memory[4] = encode_csr(CSR_MEPC, 5'd2, 3'b001, 5'd0);

        // ADDI x4, x0, 128

        dut.instruction_memory[5] = encode_i(12'd128, 5'd0, 3'b000, 5'd4, OPCODE_OP_IMM);

        // CSRRW x0, mtvec, x4

        dut.instruction_memory[6] = encode_csr(CSR_MTVEC, 5'd4, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[7] = 32'h30200073;

        // S-mode ECALL

        dut.instruction_memory[16] = 32'h00000073;

        // Instruction after trap return

        dut.instruction_memory[17] = encode_i(12'd89, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        // Trap handler at address 128

        dut.instruction_memory[32] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);

        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);

        dut.instruction_memory[34] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);

        dut.instruction_memory[35] = 32'h30200073;

        // Expected:
        // current_mode = S after MRET
        // mcause = 9
        // x3 = 89

        #800;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 20
        // U MODE ECALL WITH DELEGATION
        //
        // ECALL from U-mode is delegated to S-mode.
        // S-mode handles the trap and returns with SRET.

        // ADDI x1, x0, 128

        dut.instruction_memory[0] = encode_i(12'd128, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // CSRRW x0, stvec, x1

        dut.instruction_memory[1] = encode_csr(CSR_STVEC, 5'd1, 3'b001, 5'd0);

        // ADDI x2, x0, 256

        dut.instruction_memory[2] = encode_i(12'd256, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // CSRRW x0, medeleg, x2
        // Delegate ECALL from U-mode, cause 8.

        dut.instruction_memory[3] = encode_csr(CSR_MEDELEG, 5'd2, 3'b001, 5'd0);

        // CSRR x5, medeleg
        // Read back medeleg to verify that cause 8 was written.

        dut.instruction_memory[4] = encode_csr(CSR_MEDELEG, 5'd0, 3'b010, 5'd5);

        // CSRR x6, stvec
        // Read back stvec to verify the S-mode trap vector.

        dut.instruction_memory[5] = encode_csr(CSR_STVEC, 5'd0, 3'b010, 5'd6);

        // ADDI x3, x0, 64

        dut.instruction_memory[6] = encode_i(12'd64, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x3

        dut.instruction_memory[7] = encode_csr(CSR_MEPC, 5'd3, 3'b001, 5'd0);

        // CSRRW x0, mstatus, x0
        // MPP = U

        dut.instruction_memory[8] = encode_csr(CSR_MSTATUS, 5'd0, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[9] = 32'h30200073;

        // U-mode ECALL

        dut.instruction_memory[16] = 32'h00000073;

        // Instruction after trap return

        dut.instruction_memory[17] = encode_i(12'd90, 5'd0, 3'b000, 5'd4, OPCODE_OP_IMM);

        // S-mode trap handler at address 128

        // CSRR x11, scause

        dut.instruction_memory[32] = encode_csr(CSR_SCAUSE, 5'd0, 3'b010, 5'd11);

        // CSRR x12, sepc

        dut.instruction_memory[33] = encode_csr(CSR_SEPC, 5'd0, 3'b010, 5'd12);

        // ADDI x12, x12, 4

        dut.instruction_memory[34] = encode_i(12'd4, 5'd12, 3'b000, 5'd12, OPCODE_OP_IMM);

        // CSRRW x0, sepc, x12

        dut.instruction_memory[35] = encode_csr(CSR_SEPC, 5'd12, 3'b001, 5'd0);

        // SRET

        dut.instruction_memory[36] = 32'h10200073;

        // Expected:
        // medeleg = 00000100
        // x5 = 256
        // x6 = 128
        // current_mode = U after SRET
        // scause = 8
        // x11 = 8
        // sepc is advanced by 4
        // x4 = 90

        #800;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to create a clear separation between the tests in GTKWave.

        #100;

        rst = 1'b1;
        clock_enable = 1'b1;

        #20;

        rst = 1'b0;


        // TEST 21
        // READ-ONLY CSR EXCEPTION
        //
        // A write to misa is not allowed.
        // The instruction must create an illegal instruction exception.

        // ADDI x1, x0, 1

        dut.instruction_memory[0] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);

        // ADDI x2, x0, 128

        dut.instruction_memory[1] = encode_i(12'd128, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);

        // CSRRW x0, mtvec, x2

        dut.instruction_memory[2] = encode_csr(CSR_MTVEC, 5'd2, 3'b001, 5'd0);

        // CSRRW x0, misa, x1
        // This must trap because misa is read-only in this implementation.

        dut.instruction_memory[3] = encode_csr(CSR_MISA, 5'd1, 3'b001, 5'd0);

        // Instruction after trap return

        dut.instruction_memory[4] = encode_i(12'd91, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        // Trap handler at address 128

        // CSRR x10, mepc

        dut.instruction_memory[32] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);

        // ADDI x10, x10, 4

        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);

        // CSRRW x0, mepc, x10

        dut.instruction_memory[34] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);

        // MRET

        dut.instruction_memory[35] = 32'h30200073;

        // Expected:
        // mcause = 2
        // mtval = the CSRRW instruction
        // x3 = 91
        // misa remains unchanged

        #700;

        clock_enable = 1'b0;


        // EMPTY SPACE
        //
        // The clock is stopped to keep the final state visible in GTKWave.

        #200;


        // End of simulation

        $finish;

    end


    // Waveform dump

    initial begin

        $dumpfile("Sim_v1_RV32IMA.vcd");
        $dumpvars(0, Sim_v1_RV32IMA);

    end


endmodule
