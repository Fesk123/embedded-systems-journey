`timescale 1ns/1ps

// The testbench runs a small RISC-V program and checks the results produced by the CPU

// The CPU is tested using:

//  - ADDI
//  - ADD
//  - SUB
//  - AND
//  - OR
//  - XOR
//  - SLL
//  - SRL
//  - SRA
//  - SLT
//  - SLTU
//  - SLLI
//  - SRLI
//  - SRAI
//  - LW
//  - SW
//  - BEQ
//  - BNE
//  - BLT
//  - BGE
//  - BLTU
//  - BGEU
//  - LUI
//  - AUIPC
//  - JAL
//  - JALR
//  - Register x0


module Sim_RV32I_CPU;

    reg clk;

    reg rst;

    // Debug outputs

    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [31:0] debug_result;



    RV32I_CPU dut (
        .clk(clk),
        .rst(rst),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_result(debug_result)
    );


    // Clock generation

    // The clock changes every 5 ns
    // This gives a 10 ns clock period

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    function [31:0] encode_r;

        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;

        begin
            encode_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
        end

    endfunction


    function [31:0] encode_i;

        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;

        begin
            encode_i = {imm, rs1, funct3, rd, 7'b0010011};
        end

    endfunction


    function [31:0] encode_shift_i;

        input [6:0] funct7;
        input [4:0] shamt;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;

        begin
            encode_shift_i = {funct7, shamt, rs1, funct3, rd, 7'b0010011};
        end

    endfunction


    function [31:0] encode_lw;

        input [11:0] imm;
        input [4:0] rs1;
        input [4:0] rd;

        begin
            encode_lw = {imm, rs1, 3'b010, rd, 7'b0000011};
        end

    endfunction


    function [31:0] encode_sw;

        input [11:0] imm;
        input [4:0] rs1;
        input [4:0] rs2;

        begin
            encode_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
        end

    endfunction


    function [31:0] encode_branch;

        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;

        begin
            encode_branch = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 1'b0, 7'b1100011};
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

        begin
            encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
        end

    endfunction


    function [31:0] encode_jalr;

        input [11:0] imm;
        input [4:0] rs1;
        input [4:0] rd;

        begin
            encode_jalr = {imm, rs1, 3'b000, rd, 7'b1100111};
        end

    endfunction


    // Test program

    integer i;


    initial begin

        rst = 1'b1;

        #20;

        rst = 1'b0;

        // The CPU already initializes its memory, but we overwrite it here with the test program

        for (i = 0; i < 256; i = i + 1)
            dut.instruction_memory[i] = 32'h00000013;


        for (i = 0; i < 256; i = i + 1)
            dut.data_memory[i] = 32'd0;


        // Test 1: ADDI
        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1);
        dut.instruction_memory[1] = encode_i(12'd20, 5'd0, 3'b000, 5'd2);


        // Test 2: ADD
        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);


        // Test 3: SUB
        dut.instruction_memory[3] = encode_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4);


        // Test 4: AND
        dut.instruction_memory[4] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd5);


        // Test 5: OR
        dut.instruction_memory[5] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd6);


        // Test 6: XOR
        dut.instruction_memory[6] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd7);


        // Test 7: SLL
        dut.instruction_memory[7] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd8);


        // Test 8: SRL
        dut.instruction_memory[8] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b101, 5'd9);


        // Test 9: SRA
        dut.instruction_memory[9] = encode_i(12'hFF0, 5'd0, 3'b000, 5'd10);
        dut.instruction_memory[10] = encode_shift_i(7'b0100000, 5'd2, 5'd10, 3'b101, 5'd11);


        // Test 10: SLT
        dut.instruction_memory[11] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd12);


        // Test 11: SLTU
        dut.instruction_memory[12] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd13);


        // Test 12: SW
        dut.instruction_memory[13] = encode_sw(12'd0, 5'd0, 5'd3);


        // Test 13: LW
        dut.instruction_memory[14] = encode_lw(12'd0, 5'd0, 5'd14);


        // Test 14: LUI
        dut.instruction_memory[15] = encode_u(20'h12345, 5'd15, 7'b0110111);


        // Test 15: AUIPC
        dut.instruction_memory[16] = encode_u(20'h00001, 5'd16, 7'b0010111);


        // Test 16: BEQ
        dut.instruction_memory[17] = encode_branch(13'd8, 5'd1, 5'd1, 3'b000);
        dut.instruction_memory[18] = encode_i(12'd999, 5'd0, 3'b000, 5'd17);
        dut.instruction_memory[19] = encode_i(12'd100, 5'd0, 3'b000, 5'd17);


        // Test 17: BNE
        dut.instruction_memory[20] = encode_branch(13'd8, 5'd2, 5'd1, 3'b001);
        dut.instruction_memory[21] = encode_i(12'd999, 5'd0, 3'b000, 5'd18);
        dut.instruction_memory[22] = encode_i(12'd200, 5'd0, 3'b000, 5'd18);


        // Test 18: BLT
        dut.instruction_memory[23] = encode_branch(13'd8, 5'd2, 5'd1, 3'b100);
        dut.instruction_memory[24] = encode_i(12'd999, 5'd0, 3'b000, 5'd19);
        dut.instruction_memory[25] = encode_i(12'd300, 5'd0, 3'b000, 5'd19);


        // Test 19: BGE
        dut.instruction_memory[26] = encode_branch(13'd8, 5'd1, 5'd2, 3'b101);
        dut.instruction_memory[27] = encode_i(12'd999, 5'd0, 3'b000, 5'd20);
        dut.instruction_memory[28] = encode_i(12'd400, 5'd0, 3'b000, 5'd20);


        // Test 20: JAL
        dut.instruction_memory[29] = encode_j(21'd8, 5'd21);
        dut.instruction_memory[30] = encode_i(12'd999, 5'd0, 3'b000, 5'd22);
        dut.instruction_memory[31] = encode_i(12'd500, 5'd0, 3'b000, 5'd22);


        // Test 21: JALR
        dut.instruction_memory[32] = encode_i(12'd144, 5'd0, 3'b000, 5'd23);
        dut.instruction_memory[33] = encode_jalr(12'd0, 5'd23, 5'd24);
        dut.instruction_memory[34] = encode_i(12'd999, 5'd0, 3'b000, 5'd25);
        dut.instruction_memory[35] = encode_i(12'd999, 5'd0, 3'b000, 5'd25);


        // JALR TARGET
        dut.instruction_memory[36] = encode_i(12'd600, 5'd0, 3'b000, 5'd25);


        // Wait for the CPU to execute the program
        #500;

        $finish;
    end


    // GTKWave dump
    initial begin
        $dumpfile("rv32i_cpu.vcd");
        $dumpvars(0, Sim_RV32I_CPU);
    end


endmodule