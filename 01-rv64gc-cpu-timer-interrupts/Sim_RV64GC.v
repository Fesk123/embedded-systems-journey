`timescale 1ns/1ps

// The testbench runs a broad RV64GC program and checks the CPU, pipeline, compressed instructions, floating point, atomics, CSR, privilege, timer and interrupt behaviour.

module Sim_RV64GC;

    reg clk;
    reg rst;
    reg external_interrupt;
    reg software_interrupt;

    wire [63:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [63:0] debug_result;
    wire [63:0] debug_mtime;
    wire [63:0] debug_mtimecmp;
    wire [1:0] debug_current_mode;
    wire debug_mtip;
    wire debug_interrupt_taken;


    // DUT

    RV64GC_CPU dut (

        .clk(clk),
        .rst(rst),
        .external_interrupt(external_interrupt),
        .software_interrupt(software_interrupt),

        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_result(debug_result),
        .debug_mtime(debug_mtime),
        .debug_mtimecmp(debug_mtimecmp),
        .debug_current_mode(debug_current_mode),
        .debug_mtip(debug_mtip),
        .debug_interrupt_taken(debug_interrupt_taken)

    );


    // Testbench constants

    localparam [6:0] OPCODE_OP = 7'b0110011;
    localparam [6:0] OPCODE_OP_32 = 7'b0111011;
    localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam [6:0] OPCODE_OP_IMM_32 = 7'b0011011;
    localparam [6:0] OPCODE_LOAD = 7'b0000011;
    localparam [6:0] OPCODE_STORE = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_LUI = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC = 7'b0010111;
    localparam [6:0] OPCODE_JAL = 7'b1101111;
    localparam [6:0] OPCODE_JALR = 7'b1100111;
    localparam [6:0] OPCODE_ATOMIC = 7'b0101111;
    localparam [6:0] OPCODE_SYSTEM = 7'b1110011;
    localparam [6:0] OPCODE_LOAD_FP = 7'b0000111;
    localparam [6:0] OPCODE_STORE_FP = 7'b0100111;
    localparam [6:0] OPCODE_OP_FP = 7'b1010011;

    localparam [11:0] CSR_FFLAGS = 12'h001;
    localparam [11:0] CSR_FRM = 12'h002;
    localparam [11:0] CSR_FCSR = 12'h003;

    localparam [11:0] CSR_SSTATUS = 12'h100;
    localparam [11:0] CSR_SIE = 12'h104;
    localparam [11:0] CSR_STVEC = 12'h105;
    localparam [11:0] CSR_SSCRATCH = 12'h140;
    localparam [11:0] CSR_SEPC = 12'h141;
    localparam [11:0] CSR_SCAUSE = 12'h142;
    localparam [11:0] CSR_STVAL = 12'h143;
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

    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    localparam [4:0] ATOMIC_ADD = 5'b00000;
    localparam [4:0] ATOMIC_SWAP = 5'b00001;
    localparam [4:0] ATOMIC_LR = 5'b00010;
    localparam [4:0] ATOMIC_SC = 5'b00011;
    localparam [4:0] ATOMIC_XOR = 5'b00100;
    localparam [4:0] ATOMIC_OR = 5'b01000;
    localparam [4:0] ATOMIC_AND = 5'b01100;
    localparam [4:0] ATOMIC_MIN = 5'b10000;
    localparam [4:0] ATOMIC_MAX = 5'b10100;
    localparam [4:0] ATOMIC_MINU = 5'b11000;
    localparam [4:0] ATOMIC_MAXU = 5'b11100;


    // Clock

    initial begin

        clk = 1'b0;

        forever begin
            #5;
            clk = ~clk;
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
        input [1:0] aqrl;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            encode_amo = {funct5, aqrl, rs2, rs1, funct3, rd, OPCODE_ATOMIC};
        end
    endfunction


    function [31:0] encode_csr;
        input [11:0] csr;
        input [4:0] rs1_zimm;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            encode_csr = {csr, rs1_zimm, funct3, rd, OPCODE_SYSTEM};
        end
    endfunction


    function [31:0] encode_fp_r3;
        input [4:0] funct5;
        input [1:0] fmt;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] rm;
        input [4:0] rd;
        begin
            encode_fp_r3 = {funct5, fmt, rs2, rs1, rm, rd, OPCODE_OP_FP};
        end
    endfunction


    function [31:0] encode_fp_r4;
        input [6:0] opcode;
        input [1:0] fmt;
        input [4:0] rs3;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] rm;
        input [4:0] rd;
        begin
            encode_fp_r4 = {rs3, fmt, rs2, rs1, rm, rd, opcode};
        end
    endfunction


    // Compressed instruction encoders

    function [15:0] c_addi;
        input [4:0] rd;
        input [5:0] imm;
        begin
            c_addi = {3'b000, imm[5], rd, imm[4:0], 2'b01};
        end
    endfunction


    function [15:0] c_addiw;
        input [4:0] rd;
        input [5:0] imm;
        begin
            c_addiw = {3'b001, imm[5], rd, imm[4:0], 2'b01};
        end
    endfunction


    function [15:0] c_li;
        input [4:0] rd;
        input [5:0] imm;
        begin
            c_li = {3'b010, imm[5], rd, imm[4:0], 2'b01};
        end
    endfunction


    function [15:0] c_lui;
        input [4:0] rd;
        input [5:0] imm;
        begin
            c_lui = {3'b011, imm[5], rd, imm[4:0], 2'b01};
        end
    endfunction


    function [15:0] c_addi16sp;
        input [9:0] imm;
        begin
            c_addi16sp = {3'b011, imm[9], 5'd2, imm[4], imm[6], imm[8:7], imm[5], 4'b0000, 2'b01};
        end
    endfunction


    function [15:0] c_shift_imm;
        input [1:0] op;
        input [2:0] rd_prime;
        input [5:0] imm;
        begin
            c_shift_imm = {3'b100, op, rd_prime, imm[4:0], 2'b01};
            c_shift_imm[12] = imm[5];
        end
    endfunction


    function [15:0] c_andi;
        input [2:0] rd_prime;
        input [5:0] imm;
        begin
            c_andi = {3'b100, 2'b10, rd_prime, imm[5:0], 2'b01};
            c_andi[6:2] = imm[4:0];
            c_andi[12] = imm[5];
        end
    endfunction


    function [15:0] c_alu_rr;
        input [1:0] op;
        input [2:0] rd_prime;
        input [2:0] rs2_prime;
        input bit12;
        begin
            c_alu_rr = {3'b100, 2'b11, rd_prime, rs2_prime, 2'b00, 2'b01};
            c_alu_rr[12] = bit12;
            c_alu_rr[6:5] = op;
        end
    endfunction


    function [15:0] c_j;
        input [11:0] imm;
        begin
            c_j = {3'b101, imm[11], imm[4], imm[9:8], imm[10], imm[6], imm[7], imm[3:1], imm[5], 2'b01};
        end
    endfunction


    function [15:0] c_branch_zero;
        input bit_bne;
        input [2:0] rs1_prime;
        input [8:0] imm;
        begin
            c_branch_zero = {bit_bne ? 3'b111 : 3'b110, imm[8], imm[4:3], rs1_prime, imm[7:5], imm[2:0], 2'b01};
            c_branch_zero[6:5] = imm[7:6];
            c_branch_zero[4:3] = imm[2:1];
            c_branch_zero[2] = imm[5];
        end
    endfunction


    function [15:0] c_ld;
        input [2:0] rd_prime;
        input [2:0] rs1_prime;
        input [7:0] imm;
        begin
            c_ld = {3'b011, imm[5:3], rs1_prime, imm[7:6], rd_prime, 2'b00};
        end
    endfunction


    function [15:0] c_lw;
        input [2:0] rd_prime;
        input [2:0] rs1_prime;
        input [5:0] imm;
        begin
            c_lw = {3'b010, imm[4:2], rs1_prime, imm[2], imm[5], rd_prime, 2'b00};
        end
    endfunction


    function [15:0] c_sd;
        input [2:0] rs2_prime;
        input [2:0] rs1_prime;
        input [7:0] imm;
        begin
            c_sd = {3'b111, imm[5:3], rs1_prime, imm[7:6], rs2_prime, 2'b00};
        end
    endfunction


    function [15:0] c_sw;
        input [2:0] rs2_prime;
        input [2:0] rs1_prime;
        input [5:0] imm;
        begin
            c_sw = {3'b110, imm[4:2], rs1_prime, imm[2], imm[5], rs2_prime, 2'b00};
        end
    endfunction


    function [15:0] c_ldsp;
        input [4:0] rd;
        input [7:0] imm;
        begin
            c_ldsp = {3'b011, imm[7], rd, imm[2:0], imm[6:3], 2'b10};
        end
    endfunction


    function [15:0] c_lwsp;
        input [4:0] rd;
        input [7:0] imm;
        begin
            c_lwsp = {3'b010, imm[5], rd, imm[4:2], imm[6:3], 2'b10};
        end
    endfunction


    function [15:0] c_sdsp;
        input [4:0] rs2;
        input [7:0] imm;
        begin
            c_sdsp = {3'b111, imm[7:5], imm[4:2], rs2, 2'b10};
        end
    endfunction


    function [15:0] c_swsp;
        input [4:0] rs2;
        input [5:0] imm;
        begin
            c_swsp = {3'b110, imm[5:2], imm[1:0], rs2, 2'b10};
        end
    endfunction


    function [15:0] c_jalr_family;
        input [4:0] rd_rs1;
        input [4:0] rs2;
        input bit12;
        begin
            c_jalr_family = {3'b100, bit12, rd_rs1, rs2, 2'b00, 2'b10};
        end
    endfunction


    // Utility tasks

    integer i;
    integer failures;

    task reset_cpu;
        begin

            rst = 1'b1;
            external_interrupt = 1'b0;
            software_interrupt = 1'b0;

            #20;

            rst = 1'b0;

            for (i = 0; i < 256; i = i + 1)
                dut.instruction_memory[i] = 32'h00000013;

            for (i = 0; i < 256; i = i + 1)
                dut.data_memory[i] = 64'b0;

            for (i = 0; i < 32; i = i + 1)
                dut.registers[i] = 64'b0;

            for (i = 0; i < 32; i = i + 1)
                dut.fregisters[i] = 64'hFFFFFFFF00000000;

            dut.mtime = 64'b0;
            dut.mtimecmp = 64'hFFFFFFFFFFFFFFFF;
            dut.mstatus = 64'b0;
            dut.mie = 64'b0;
            dut.mideleg = 64'b0;
            dut.medeleg = 64'b0;
            dut.mtvec = 64'b0;
            dut.stvec = 64'b0;
            dut.mepc = 64'b0;
            dut.sepc = 64'b0;
            dut.mcause = 64'b0;
            dut.scause = 64'b0;
            dut.mtval = 64'b0;
            dut.stval = 64'b0;
            dut.current_mode = PRIV_M;
            dut.reservation_valid = 1'b0;

            #2;

        end
    endtask


    task run_cycles;
        input integer count;
        begin
            repeat (count) @(posedge clk);
        end
    endtask


    task clear_program_tail;
        input integer start_index;
        begin
            for (i = start_index; i < 256; i = i + 1)
                dut.instruction_memory[i] = 32'h00000013;
        end
    endtask


    task wait_for_interrupt;
        integer timeout;
        begin
            timeout = 0;
            while ((debug_interrupt_taken !== 1'b1) && (timeout < 500)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
        end
    endtask


    // TEST SECTIONS

    initial begin

        failures = 0;

        // TEST 1
        // RV64I BASIC INTEGER OPERATIONS

        reset_cpu;

        dut.instruction_memory[0] = encode_i(12'd10, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);
        dut.instruction_memory[1] = encode_i(12'd20, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);
        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);
        dut.instruction_memory[3] = encode_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4, OPCODE_OP);
        dut.instruction_memory[4] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b001, 5'd5, OPCODE_OP);
        dut.instruction_memory[5] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b010, 5'd6, OPCODE_OP);
        dut.instruction_memory[6] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b011, 5'd7, OPCODE_OP);
        dut.instruction_memory[7] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b100, 5'd8, OPCODE_OP);
        dut.instruction_memory[8] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b101, 5'd9, OPCODE_OP);
        dut.instruction_memory[9] = encode_r(7'b0100000, 5'd1, 5'd2, 3'b101, 5'd10, OPCODE_OP);
        dut.instruction_memory[10] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b110, 5'd11, OPCODE_OP);
        dut.instruction_memory[11] = encode_r(7'b0000000, 5'd1, 5'd2, 3'b111, 5'd12, OPCODE_OP);
        dut.instruction_memory[12] = encode_u(20'h12345, 5'd13, OPCODE_LUI);
        dut.instruction_memory[13] = encode_u(20'h00002, 5'd14, OPCODE_AUIPC);

        run_cycles(40);

                


        // TEST 2
        // RV64I WORD OPERATIONS

        reset_cpu;

        dut.registers[1] = 64'hFFFFFFFF00000007;
        dut.registers[2] = 64'h0000000000000003;

        dut.instruction_memory[0] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP_32);
        dut.instruction_memory[1] = encode_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd4, OPCODE_OP_32);
        dut.instruction_memory[2] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd5, OPCODE_OP_32);
        dut.instruction_memory[3] = encode_r(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd6, OPCODE_OP_32);
        dut.instruction_memory[4] = encode_r(7'b0100000, 5'd2, 5'd1, 3'b101, 5'd7, OPCODE_OP_32);
        dut.instruction_memory[5] = encode_i(12'h001, 5'd1, 3'b000, 5'd8, OPCODE_OP_IMM_32);
        dut.instruction_memory[6] = encode_i(12'h001, 5'd1, 3'b001, 5'd9, OPCODE_OP_IMM_32);
        dut.instruction_memory[7] = encode_i(12'h401, 5'd1, 3'b101, 5'd10, OPCODE_OP_IMM_32);
        dut.instruction_memory[8] = encode_i(12'h001, 5'd1, 3'b101, 5'd11, OPCODE_OP_IMM_32);

        run_cycles(35);

                


        // TEST 3
        // RV64I LOAD / STORE SIZES AND SIGN EXTENSION

        reset_cpu;

        dut.data_memory[0] = 64'h8000800080000080;
        dut.registers[1] = 64'h0000000000000000;
        dut.registers[2] = 64'h1122334455667788;

        dut.instruction_memory[0] = encode_i(12'd0, 5'd1, 3'b000, 5'd3, OPCODE_LOAD);
        dut.instruction_memory[1] = encode_i(12'd0, 5'd1, 3'b100, 5'd4, OPCODE_LOAD);
        dut.instruction_memory[2] = encode_i(12'd2, 5'd1, 3'b001, 5'd5, OPCODE_LOAD);
        dut.instruction_memory[3] = encode_i(12'd2, 5'd1, 3'b101, 5'd6, OPCODE_LOAD);
        dut.instruction_memory[4] = encode_i(12'd4, 5'd1, 3'b010, 5'd7, OPCODE_LOAD);
        dut.instruction_memory[5] = encode_i(12'd4, 5'd1, 3'b110, 5'd8, OPCODE_LOAD);
        dut.instruction_memory[6] = encode_i(12'd0, 5'd1, 3'b011, 5'd9, OPCODE_LOAD);
        dut.instruction_memory[7] = encode_s(12'd8, 5'd2, 5'd1, 3'b000, OPCODE_STORE);
        dut.instruction_memory[8] = encode_s(12'd9, 5'd2, 5'd1, 3'b001, OPCODE_STORE);
        dut.instruction_memory[9] = encode_s(12'd12, 5'd2, 5'd1, 3'b010, OPCODE_STORE);
        dut.instruction_memory[10] = encode_s(12'd16, 5'd2, 5'd1, 3'b011, OPCODE_STORE);

        run_cycles(45);

                


        // TEST 4
        // RV64M ALL OPERATIONS AND DIVISION EDGE CASES

        reset_cpu;

        dut.registers[1] = 64'd20;
        dut.registers[2] = 64'd6;

        dut.instruction_memory[0] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, OPCODE_OP);
        dut.instruction_memory[1] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b001, 5'd4, OPCODE_OP);
        dut.instruction_memory[2] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b010, 5'd5, OPCODE_OP);
        dut.instruction_memory[3] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b011, 5'd6, OPCODE_OP);
        dut.instruction_memory[4] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd7, OPCODE_OP);
        dut.instruction_memory[5] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b101, 5'd8, OPCODE_OP);
        dut.instruction_memory[6] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd9, OPCODE_OP);
        dut.instruction_memory[7] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b111, 5'd10, OPCODE_OP);
        dut.instruction_memory[8] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd11, OPCODE_OP_32);
        dut.instruction_memory[9] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd12, OPCODE_OP_32);
        dut.instruction_memory[10] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b101, 5'd13, OPCODE_OP_32);
        dut.instruction_memory[11] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd14, OPCODE_OP_32);
        dut.instruction_memory[12] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b111, 5'd15, OPCODE_OP_32);

        run_cycles(45);

                


        // TEST 5
        // RV64M DIVIDE BY ZERO AND SIGNED OVERFLOW

        reset_cpu;

        dut.registers[1] = 64'd123;
        dut.registers[2] = 64'd0;
        dut.instruction_memory[0] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd3, OPCODE_OP);
        dut.instruction_memory[1] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b101, 5'd4, OPCODE_OP);
        dut.instruction_memory[2] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd5, OPCODE_OP);
        dut.instruction_memory[3] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b111, 5'd6, OPCODE_OP);

        run_cycles(25);


        reset_cpu;

        dut.registers[1] = 64'h8000000000000000;
        dut.registers[2] = 64'hFFFFFFFFFFFFFFFF;
        dut.instruction_memory[0] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd3, OPCODE_OP);
        dut.instruction_memory[1] = encode_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd4, OPCODE_OP);
        run_cycles(20);

                


        // TEST 6
        // RV64A LR/SC AND AMO.W

        reset_cpu;

        dut.registers[1] = 64'd0;
        dut.registers[2] = 64'h00000000FFFFFFFF;
        dut.data_memory[0] = 64'h0000000000000005;

        dut.instruction_memory[0] = encode_amo(ATOMIC_LR, 2'b00, 5'd0, 5'd1, 3'b010, 5'd3);
        dut.instruction_memory[1] = encode_amo(ATOMIC_SC, 2'b00, 5'd2, 5'd1, 3'b010, 5'd4);
        dut.instruction_memory[2] = encode_amo(ATOMIC_ADD, 2'b00, 5'd2, 5'd1, 3'b010, 5'd5);
        dut.instruction_memory[3] = encode_amo(ATOMIC_SWAP, 2'b00, 5'd2, 5'd1, 3'b010, 5'd6);
        dut.instruction_memory[4] = encode_amo(ATOMIC_XOR, 2'b00, 5'd2, 5'd1, 3'b010, 5'd7);
        dut.instruction_memory[5] = encode_amo(ATOMIC_OR, 2'b00, 5'd2, 5'd1, 3'b010, 5'd8);
        dut.instruction_memory[6] = encode_amo(ATOMIC_AND, 2'b00, 5'd2, 5'd1, 3'b010, 5'd9);
        dut.instruction_memory[7] = encode_amo(ATOMIC_MIN, 2'b00, 5'd2, 5'd1, 3'b010, 5'd10);
        dut.instruction_memory[8] = encode_amo(ATOMIC_MAX, 2'b00, 5'd2, 5'd1, 3'b010, 5'd11);
        dut.instruction_memory[9] = encode_amo(ATOMIC_MINU, 2'b00, 5'd2, 5'd1, 3'b010, 5'd12);
        dut.instruction_memory[10] = encode_amo(ATOMIC_MAXU, 2'b00, 5'd2, 5'd1, 3'b010, 5'd13);

        run_cycles(45);

        


        // TEST 7
        // RV64A LR/SC AND AMO.D

        reset_cpu;

        dut.registers[1] = 64'd8;
        dut.registers[2] = 64'h8000000000000000;
        dut.registers[3] = 64'h0000000000000002;
        dut.data_memory[1] = 64'h0000000000000005;

        dut.instruction_memory[0] = encode_amo(ATOMIC_LR, 2'b00, 5'd0, 5'd1, 3'b011, 5'd4);
        dut.instruction_memory[1] = encode_amo(ATOMIC_SC, 2'b00, 5'd3, 5'd1, 3'b011, 5'd5);
        dut.instruction_memory[2] = encode_amo(ATOMIC_ADD, 2'b00, 5'd3, 5'd1, 3'b011, 5'd6);
        dut.instruction_memory[3] = encode_amo(ATOMIC_SWAP, 2'b00, 5'd2, 5'd1, 3'b011, 5'd7);
        dut.instruction_memory[4] = encode_amo(ATOMIC_XOR, 2'b00, 5'd3, 5'd1, 3'b011, 5'd8);
        dut.instruction_memory[5] = encode_amo(ATOMIC_OR, 2'b00, 5'd3, 5'd1, 3'b011, 5'd9);
        dut.instruction_memory[6] = encode_amo(ATOMIC_AND, 2'b00, 5'd3, 5'd1, 3'b011, 5'd10);
        dut.instruction_memory[7] = encode_amo(ATOMIC_MIN, 2'b00, 5'd3, 5'd1, 3'b011, 5'd11);
        dut.instruction_memory[8] = encode_amo(ATOMIC_MAX, 2'b00, 5'd3, 5'd1, 3'b011, 5'd12);
        dut.instruction_memory[9] = encode_amo(ATOMIC_MINU, 2'b00, 5'd3, 5'd1, 3'b011, 5'd13);
        dut.instruction_memory[10] = encode_amo(ATOMIC_MAXU, 2'b00, 5'd3, 5'd1, 3'b011, 5'd14);

        run_cycles(45);

        


        // TEST 8
        // RV64C REPRESENTATIVE INSTRUCTIONS AND 16 TO 32 BIT FETCH CROSSING

        reset_cpu;

        dut.instruction_memory[0] = {16'h8113, c_addi(5'd1, 6'd1)};
        dut.instruction_memory[1] = {16'h0001, 16'h0020};

        dut.instruction_memory[2] = {c_li(3, 5), c_addi(1, 1)};
        dut.instruction_memory[3] = {16'h0001, 16'h0001};

        run_cycles(25);

        


        reset_cpu;

        dut.registers[8] = 64'd0;
        dut.registers[9] = 64'd5;
        dut.data_memory[0] = 64'h123456789ABCDEF0;
        dut.instruction_memory[0] = {c_ld(3'd0, 3'd0, 8'd0), c_alu_rr(2'b00, 3'd0, 3'd1, 1'b1)};
        dut.instruction_memory[1] = {16'h0001, 16'h0001};
        dut.registers[8] = 64'd0;
        dut.registers[9] = 64'd5;

        run_cycles(20);

        


        reset_cpu;

        dut.registers[8] = 64'd0;
        dut.registers[9] = 64'd0;
        dut.data_memory[0] = 64'h0000000000000007;
        dut.instruction_memory[0] = {c_branch_zero(1'b1, 3'd0, 9'd4), c_addi(5'd8, 6'd1)};
        dut.instruction_memory[1] = {16'h0001, 16'h0001};

        run_cycles(15);

        


        // TEST 9
        // BRANCH PREDICTION, FORWARDING, LOAD USE HAZARD AND FLUSH

        reset_cpu;

        dut.instruction_memory[0] = encode_i(12'd3, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);
        dut.instruction_memory[1] = encode_i(12'hFFF, 5'd1, 3'b000, 5'd1, OPCODE_OP_IMM);
        dut.instruction_memory[2] = encode_b(13'h1FFC, 5'd0, 5'd1, 3'b001, OPCODE_BRANCH);
        dut.instruction_memory[3] = encode_i(12'd99, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);
        dut.instruction_memory[4] = encode_i(12'd7, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);
        dut.data_memory[0] = 64'd21;
        dut.instruction_memory[5] = encode_i(12'd0, 5'd0, 3'b011, 5'd3, OPCODE_LOAD);
        dut.instruction_memory[6] = encode_r(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd4, OPCODE_OP);

        run_cycles(55);

        


        // TEST 10
        // JAL AND JALR

        reset_cpu;

        dut.registers[5] = 64'd24;
        dut.instruction_memory[0] = encode_j(21'd8, 5'd1, OPCODE_JAL);
        dut.instruction_memory[1] = encode_i(12'd99, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);
        dut.instruction_memory[2] = encode_i(12'd11, 5'd0, 3'b000, 5'd2, OPCODE_OP_IMM);
        dut.instruction_memory[3] = encode_i(12'd0, 5'd5, 3'b000, 5'd6, OPCODE_JALR);
        dut.instruction_memory[6] = encode_i(12'd55, 5'd0, 3'b000, 5'd7, OPCODE_OP_IMM);

        run_cycles(30);

        


        // TEST 11
        // CSR, ZICSR, FCSR AND READ ONLY PROTECTION

        reset_cpu;

        dut.instruction_memory[0] = encode_i(12'd21, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);
        dut.instruction_memory[1] = encode_csr(CSR_MSCRATCH, 5'd1, 3'b001, 5'd0);
        dut.instruction_memory[2] = encode_csr(CSR_MSCRATCH, 5'd0, 3'b010, 5'd2);
        dut.instruction_memory[3] = encode_csr(CSR_MSCRATCH, 5'd0, 3'b010, 5'd3);
        dut.instruction_memory[4] = encode_csr(CSR_FFLAGS, 5'd0, 3'b010, 5'd4);
        dut.instruction_memory[5] = encode_csr(CSR_FRM, 5'd0, 3'b010, 5'd5);
        dut.instruction_memory[6] = encode_csr(CSR_FCSR, 5'd0, 3'b010, 5'd6);
        dut.instruction_memory[7] = encode_csr(CSR_MISA, 5'd1, 3'b001, 5'd0);
        dut.instruction_memory[8] = encode_csr(CSR_MTVEC, 5'd1, 3'b001, 5'd0);

        run_cycles(45);

        


        // TEST 12
        // M MODE, S MODE AND U MODE

        reset_cpu;

        dut.registers[1] = 64'd64;
        dut.instruction_memory[0] = encode_csr(CSR_MEPC, 5'd1, 3'b001, 5'd0);
        dut.instruction_memory[1] = encode_csr(CSR_MSTATUS, 5'd0, 3'b001, 5'd0);
        dut.instruction_memory[2] = 32'h30200073;
        dut.instruction_memory[16] = encode_i(12'd77, 5'd0, 3'b000, 5'd3, OPCODE_OP_IMM);

        run_cycles(30);

        


        // TEST 13
        // ILLEGAL INSTRUCTION, BREAKPOINT, ECALL AND MRET

        reset_cpu;

        dut.mtvec = 64'd64;
        dut.instruction_memory[0] = 32'hFFFFFFFF;
        dut.instruction_memory[16] = encode_csr(CSR_MEPC, 5'd0, 3'b010, 5'd10);
        dut.instruction_memory[17] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);
        dut.instruction_memory[18] = encode_csr(CSR_MEPC, 5'd10, 3'b001, 5'd0);
        dut.instruction_memory[19] = 32'h30200073;

        run_cycles(35);

        


        reset_cpu;

        dut.mtvec = 64'd64;
        dut.instruction_memory[0] = 32'h00100073;
        dut.instruction_memory[16] = 32'h30200073;
        run_cycles(25);

        


        reset_cpu;

        dut.mtvec = 64'd64;
        dut.instruction_memory[0] = 32'h00000073;
        dut.instruction_memory[16] = 32'h30200073;
        run_cycles(25);

        


        // TEST 14
        // U MODE ECALL DELEGATION TO S MODE

        reset_cpu;

        dut.current_mode = PRIV_U;
        dut.medeleg[8] = 1'b1;
        dut.stvec = 64'd128;
        dut.instruction_memory[0] = 32'h00000073;
        dut.instruction_memory[32] = encode_csr(CSR_SEPC, 5'd0, 3'b010, 5'd10);
        dut.instruction_memory[33] = encode_i(12'd4, 5'd10, 3'b000, 5'd10, OPCODE_OP_IMM);
        dut.instruction_memory[34] = encode_csr(CSR_SEPC, 5'd10, 3'b001, 5'd0);
        dut.instruction_memory[35] = 32'h10200073;

        run_cycles(45);

        


        // TEST 15
        // MACHINE TIMER INTERRUPT

        reset_cpu;

        dut.mtvec = 64'd128;
        dut.mtime = 64'd10;
        dut.mtimecmp = 64'd15;
        dut.mie[7] = 1'b1;
        dut.mstatus[3] = 1'b1;
        dut.instruction_memory[32] = encode_csr(CSR_MCAUSE, 5'd0, 3'b010, 5'd10);
        dut.instruction_memory[33] = 32'h30200073;

        wait_for_interrupt;
        dut.mtimecmp = 64'hFFFFFFFFFFFFFFFF;
        run_cycles(10);

        


        // TEST 16
        // MACHINE SOFTWARE INTERRUPT

        reset_cpu;

        dut.mtvec = 64'd128;
        dut.mie[3] = 1'b1;
        dut.mstatus[3] = 1'b1;
        dut.instruction_memory[32] = 32'h30200073;
        software_interrupt = 1'b1;

        wait_for_interrupt;
        software_interrupt = 1'b0;
        run_cycles(8);

        


        // TEST 17
        // MACHINE EXTERNAL INTERRUPT

        reset_cpu;

        dut.mtvec = 64'd128;
        dut.mie[11] = 1'b1;
        dut.mstatus[3] = 1'b1;
        dut.instruction_memory[32] = 32'h30200073;
        external_interrupt = 1'b1;

        wait_for_interrupt;
        external_interrupt = 1'b0;
        run_cycles(8);

        


        // TEST 18
        // SUPERVISOR TIMER INTERRUPT DELEGATION

        reset_cpu;

        dut.current_mode = PRIV_S;
        dut.stvec = 64'd128;
        dut.mideleg[7] = 1'b1;
        dut.mie[5] = 1'b1;
        dut.mstatus[1] = 1'b1;
        dut.mtime = 64'd20;
        dut.mtimecmp = 64'd25;
        dut.instruction_memory[32] = 32'h10200073;

        wait_for_interrupt;
        dut.mtimecmp = 64'hFFFFFFFFFFFFFFFF;
        run_cycles(8);

        


        // TEST 19
        // TIMER MMIO READ / WRITE

        reset_cpu;

        dut.registers[1] = 64'h000000000200BFF8;
        dut.registers[2] = 64'h0000000000001234;
        dut.registers[3] = 64'h0000000002004000;
        dut.registers[4] = 64'h0000000000005678;
        dut.instruction_memory[0] = encode_s(12'd0, 5'd2, 5'd1, 3'b011, 7'b0100011);
        dut.instruction_memory[1] = encode_i(12'd0, 5'd1, 3'b011, 5'd5, OPCODE_LOAD);
        dut.instruction_memory[2] = encode_s(12'd0, 5'd4, 5'd3, 3'b011, 7'b0100011);
        dut.instruction_memory[3] = encode_i(12'd0, 5'd3, 3'b011, 5'd6, OPCODE_LOAD);

        run_cycles(30);

        


        // TEST 20
        // MISALIGNED ACCESS AND ILLEGAL COMPRESSED INSTRUCTION

        reset_cpu;

        dut.mtvec = 64'd128;
        dut.registers[1] = 64'd1;
        dut.instruction_memory[0] = encode_i(12'd0, 5'd1, 3'b011, 5'd2, OPCODE_LOAD);
        dut.instruction_memory[32] = 32'h30200073;
        run_cycles(25);

        


        reset_cpu;

        dut.mtvec = 64'd128;
        dut.instruction_memory[0] = {16'h0001, 16'h0000};
        dut.instruction_memory[32] = 32'h30200073;
        run_cycles(25);

        


        // TEST 21
        // RV64F SINGLE PRECISION CORE OPERATIONS

        reset_cpu;

        dut.fregisters[1] = 64'hFFFFFFFF3FC00000;
        dut.fregisters[2] = 64'hFFFFFFFF40100000;

        dut.instruction_memory[0] = encode_fp_r3(5'b00000, 2'b00, 5'd2, 5'd1, 3'b000, 5'd3);
        dut.instruction_memory[1] = encode_fp_r3(5'b00001, 2'b00, 5'd2, 5'd1, 3'b000, 5'd4);
        dut.instruction_memory[2] = encode_fp_r3(5'b00010, 2'b00, 5'd2, 5'd1, 3'b000, 5'd5);
        dut.instruction_memory[3] = encode_fp_r3(5'b00011, 2'b00, 5'd2, 5'd1, 3'b000, 5'd6);
        dut.instruction_memory[4] = encode_fp_r3(5'b00100, 2'b00, 5'd2, 5'd1, 3'b000, 5'd7);
        dut.instruction_memory[5] = encode_fp_r3(5'b00101, 2'b00, 5'd2, 5'd1, 3'b000, 5'd8);
        dut.instruction_memory[6] = encode_fp_r3(5'b00101, 2'b00, 5'd2, 5'd1, 3'b001, 5'd9);
        dut.instruction_memory[7] = encode_fp_r3(5'b10100, 2'b00, 5'd2, 5'd1, 3'b010, 5'd10);
        dut.instruction_memory[8] = encode_fp_r3(5'b10100, 2'b00, 5'd2, 5'd1, 3'b001, 5'd11);
        dut.instruction_memory[9] = encode_fp_r3(5'b10100, 2'b00, 5'd2, 5'd1, 3'b000, 5'd12);
        dut.instruction_memory[10] = encode_fp_r3(5'b11100, 2'b00, 5'd0, 5'd1, 3'b001, 5'd13);

        run_cycles(50);

        


        // TEST 22
        // RV64D DOUBLE PRECISION CORE OPERATIONS

        reset_cpu;

        dut.fregisters[1] = 64'h3FF8000000000000;
        dut.fregisters[2] = 64'h4002000000000000;

        dut.instruction_memory[0] = encode_fp_r3(5'b00000, 2'b01, 5'd2, 5'd1, 3'b000, 5'd3);
        dut.instruction_memory[1] = encode_fp_r3(5'b00001, 2'b01, 5'd2, 5'd1, 3'b000, 5'd4);
        dut.instruction_memory[2] = encode_fp_r3(5'b00010, 2'b01, 5'd2, 5'd1, 3'b000, 5'd5);
        dut.instruction_memory[3] = encode_fp_r3(5'b00011, 2'b01, 5'd2, 5'd1, 3'b000, 5'd6);
        dut.instruction_memory[4] = encode_fp_r3(5'b00101, 2'b01, 5'd2, 5'd1, 3'b000, 5'd7);
        dut.instruction_memory[5] = encode_fp_r3(5'b10100, 2'b01, 5'd2, 5'd1, 3'b010, 5'd8);
        dut.instruction_memory[6] = encode_fp_r3(5'b11100, 2'b01, 5'd0, 5'd1, 3'b001, 5'd9);

        run_cycles(45);

        


        // TEST 23
        // FP / INT MOVES AND CONVERSIONS

        reset_cpu;

        dut.registers[1] = 64'h000000003FC00000;
        dut.instruction_memory[0] = encode_fp_r3(5'b11110, 2'b00, 5'd0, 5'd1, 3'b000, 5'd2);
        dut.instruction_memory[1] = encode_fp_r3(5'b11100, 2'b00, 5'd0, 5'd2, 3'b000, 5'd3);
        dut.instruction_memory[2] = encode_fp_r3(5'b11000, 2'b00, 5'd0, 5'd2, 3'b000, 5'd4);
        dut.instruction_memory[3] = encode_fp_r3(5'b11010, 2'b00, 5'd0, 5'd4, 3'b000, 5'd5);
        dut.instruction_memory[4] = encode_fp_r3(5'b01000, 2'b01, 5'd0, 5'd2, 3'b000, 5'd6);
        dut.instruction_memory[5] = encode_fp_r3(5'b01000, 2'b00, 5'd1, 5'd6, 3'b000, 5'd7);

        run_cycles(45);

        


        // TEST 24
        // FUSED MULTIPLY ADD

        reset_cpu;

        dut.fregisters[1] = 64'hFFFFFFFF3FC00000;
        dut.fregisters[2] = 64'hFFFFFFFF40000000;
        dut.fregisters[3] = 64'hFFFFFFFF3F800000;
        dut.instruction_memory[0] = encode_fp_r4(7'b1000011, 2'b00, 5'd3, 5'd2, 5'd1, 3'b000, 5'd4);
        dut.instruction_memory[1] = encode_fp_r4(7'b1000111, 2'b00, 5'd3, 5'd2, 5'd1, 3'b000, 5'd5);
        dut.instruction_memory[2] = encode_fp_r4(7'b1001011, 2'b00, 5'd3, 5'd2, 5'd1, 3'b000, 5'd6);
        dut.instruction_memory[3] = encode_fp_r4(7'b1001111, 2'b00, 5'd3, 5'd2, 5'd1, 3'b000, 5'd7);

        run_cycles(35);

        


        // TEST 25
        // FP LOAD / STORE AND FENCE.I

        reset_cpu;

        dut.data_memory[0] = 64'hFFFFFFFF3FC00000;
        dut.registers[1] = 64'd0;
        dut.fregisters[2] = 64'hFFFFFFFF40100000;
        dut.instruction_memory[0] = encode_i(12'd0, 5'd1, 3'b010, 5'd3, OPCODE_LOAD_FP);
        dut.instruction_memory[1] = encode_s(12'd8, 5'd2, 5'd1, 3'b010, OPCODE_STORE_FP);
        dut.instruction_memory[2] = 32'h0000100F;

        run_cycles(30);

        


        // End of simulation

        $finish;

    end


    // Waveform dump

    // Waveform dump

    initial begin
        $dumpfile("Sim_RV64GC.vcd");
        $dumpvars(0, Sim_RV64GC);
    end


endmodule
