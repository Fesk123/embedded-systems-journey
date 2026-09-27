`timescale 1ns/1ps

// A simple parameterized pipelined RISC-V processor based on the RV64GC ISA.

// The architecture is inspired by the Bitspinner RV32I
// Link: https://www.bit-spinner.com/rv32i/rv32i-data-memory

// Multi-cycle design inspired by Bitspinner
// Link: https://www.bit-spinner.com/rv32i-multi-cycle/rv32i-multi-cycle-introduction

// Pipelined design uses the same datapath as the previous multi-cycle design and is divided into five pipeline stages.


// The CPU contains:
//  - Program Counter (PC)
//  - Register File (32 x XLEN-bit)
//  - Immediate Generator
//  - ALU
//  - Branch / Jump Logic
//  - Instruction Memory
//  - Data Memory
//  - Instruction Decoder
//  - Write Back logic
//  - Multiply / Divide instructions
//  - Atomic Memory instructions
//  - Compressed instructions
//  - Hazard Detection
//  - Forwarding logic
//  - Branch Predictor
//  - Pipeline registers
//  - CSR registers
//  - Privileged Architecture
//  - Exception and Trap handling
//  - Machine Timer
//  - Interrupt support


module RV64GC_CPU #(

    // Parameters

    // XLEN controls the register, ALU, PC, address, and data width

    // Number of words in instruction/data memory
    // 256 words = 2048 bytes for XLEN = 64

    parameter XLEN = 64,
    parameter IMEM_SIZE = 256,
    parameter DMEM_SIZE = 256

)(

    input wire clk,
    input wire rst,

    // External interrupt input used by the future interrupt controller
    input wire external_interrupt,

    // Machine software interrupt input
    input wire software_interrupt,

    // Debug outputs
    output wire [XLEN-1:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire [XLEN-1:0] debug_result,
    output wire [XLEN-1:0] debug_mtime,
    output wire [XLEN-1:0] debug_mtimecmp,
    output wire [1:0] debug_current_mode,
    output wire debug_mtip,
    output wire debug_interrupt_taken

);

    localparam SHIFT_WIDTH = (XLEN <= 32) ? 5 : 6;
    localparam IMEM_ADDR_WIDTH = (IMEM_SIZE <= 1) ? 1 : $clog2(IMEM_SIZE);
    localparam DMEM_ADDR_WIDTH = (DMEM_SIZE <= 1) ? 1 : $clog2(DMEM_SIZE);


    // OPCODES

    localparam [6:0] OPCODE_OP = 7'b0110011;       // R-type
    localparam [6:0] OPCODE_OP_32 = 7'b0111011;    // R-type word
    localparam [6:0] OPCODE_OP_IMM = 7'b0010011;   // I-type ALU
    localparam [6:0] OPCODE_OP_IMM_32 = 7'b0011011;// I-type ALU word
    localparam [6:0] OPCODE_LOAD = 7'b0000011;     // Load
    localparam [6:0] OPCODE_STORE = 7'b0100011;    // Store
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;   // Branch
    localparam [6:0] OPCODE_LUI = 7'b0110111;      // LUI
    localparam [6:0] OPCODE_AUIPC = 7'b0010111;    // AUIPC
    localparam [6:0] OPCODE_JAL = 7'b1101111;      // JAL
    localparam [6:0] OPCODE_JALR = 7'b1100111;     // JALR
    localparam [6:0] OPCODE_ATOMIC = 7'b0101111;   // Atomic memory operations
    localparam [6:0] OPCODE_SYSTEM = 7'b1110011;   // System and CSR instructions
    localparam [6:0] OPCODE_FENCE = 7'b0001111;    // Fence instructions
    localparam [6:0] OPCODE_LOAD_FP = 7'b0000111;  // Floating point load
    localparam [6:0] OPCODE_STORE_FP = 7'b0100111; // Floating point store
    localparam [6:0] OPCODE_OP_FP = 7'b1010011;    // Floating point operation

    // ALU operations

    localparam [4:0] ALU_ADD = 5'd0;
    localparam [4:0] ALU_SUB = 5'd1;
    localparam [4:0] ALU_SLL = 5'd2;
    localparam [4:0] ALU_SLT = 5'd3;
    localparam [4:0] ALU_SLTU = 5'd4;
    localparam [4:0] ALU_XOR = 5'd5;
    localparam [4:0] ALU_SRL = 5'd6;
    localparam [4:0] ALU_SRA = 5'd7;
    localparam [4:0] ALU_OR = 5'd8;
    localparam [4:0] ALU_AND = 5'd9;
    localparam [4:0] ALU_ADDW = 5'd10;
    localparam [4:0] ALU_SUBW = 5'd11;
    localparam [4:0] ALU_SLLW = 5'd12;
    localparam [4:0] ALU_SRLW = 5'd13;
    localparam [4:0] ALU_SRAW = 5'd14;

    // Load/store sizes

    localparam [1:0] MEM_BYTE = 2'b00;
    localparam [1:0] MEM_HALF = 2'b01;
    localparam [1:0] MEM_WORD = 2'b10;
    localparam [1:0] MEM_DOUBLE = 2'b11;

    // Atomic operations

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

    // Privileged architecture

    localparam [1:0] PRIV_U = 2'b00; // User-mode
    localparam [1:0] PRIV_S = 2'b01; // Supervisor-mode
    localparam [1:0] PRIV_M = 2'b11; // Machine-mode

    // CSR addresses

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

    // mstatus bit positions

    localparam MSTATUS_SIE = 1;
    localparam MSTATUS_MIE = 3;
    localparam MSTATUS_SPIE = 5;
    localparam MSTATUS_MPIE = 7;
    localparam MSTATUS_SPP = 8;
    localparam MSTATUS_MPP_LOW = 11;
    localparam MSTATUS_MPP_HIGH = 12;

    // Interrupt causes

    localparam [4:0] INTERRUPT_S_SOFTWARE = 5'd1;
    localparam [4:0] INTERRUPT_M_SOFTWARE = 5'd3;
    localparam [4:0] INTERRUPT_S_TIMER = 5'd5;
    localparam [4:0] INTERRUPT_M_TIMER = 5'd7;
    localparam [4:0] INTERRUPT_S_EXTERNAL = 5'd9;
    localparam [4:0] INTERRUPT_M_EXTERNAL = 5'd11;

    // Interrupt bits in mip and mie

    localparam MIP_SSIP = 1;
    localparam MIP_MSIP = 3;
    localparam MIP_STIP = 5;
    localparam MIP_MTIP = 7;
    localparam MIP_SEIP = 9;
    localparam MIP_MEIP = 11;

    // Exception causes

    localparam [4:0] CAUSE_INST_ADDR_MISALIGNED = 5'd0;
    localparam [4:0] CAUSE_ILLEGAL_INSTRUCTION = 5'd2;
    localparam [4:0] CAUSE_BREAKPOINT = 5'd3;
    localparam [4:0] CAUSE_LOAD_ADDR_MISALIGNED = 5'd4;
    localparam [4:0] CAUSE_STORE_ADDR_MISALIGNED = 5'd6;
    localparam [4:0] CAUSE_ECALL_U = 5'd8;
    localparam [4:0] CAUSE_ECALL_S = 5'd9;
    localparam [4:0] CAUSE_ECALL_M = 5'd11;

    // Machine timer addresses

    localparam [XLEN-1:0] MTIME_ADDR = 64'h000000000200BFF8;
    localparam [XLEN-1:0] MTIMECMP_ADDR = 64'h0000000002004000;

    // Machine software interrupt address

    localparam [XLEN-1:0] MSIP_ADDR = 64'h0000000002000000;


    // PIPELINE STAGES

    // The pipeline is divided into five stages.

    // IF  = Instruction Fetch
    // ID  = Instruction Decode
    // EX  = Execute
    // MEM = Memory Access
    // WB  = Write Back


    // REGISTERS AND MEMORIES

    // Program Counter

    reg [XLEN-1:0] pc;

    // 32 general purpose registers
    // x0 is hardwired to zero according to the RISC-V specification

    reg [XLEN-1:0] registers [0:31];

    // 32 floating point registers
    // FPRs are always stored as 64-bit values. Single precision values use NaN-boxing.

    reg [63:0] fregisters [0:31];

    // Floating point control and status registers

    reg [4:0] fflags;
    reg [2:0] frm;

    // Instruction memory
    // Each address contains one 32-bit instruction word

    reg [31:0] instruction_memory [0:IMEM_SIZE-1];

    // Data memory
    // Each address contains one 64-bit data word

    reg [XLEN-1:0] data_memory [0:DMEM_SIZE-1];

    // Reservation used by LR.W / SC.W / LR.D / SC.D
    // This implementation models one reservation at a time

    reg reservation_valid;
    reg [XLEN-1:0] reservation_address;


    // CSR REGISTERS

    // The CSR file stores control and status information used by the privileged architecture.

    reg [XLEN-1:0] mstatus;
    reg [XLEN-1:0] misa;
    reg [XLEN-1:0] medeleg;
    reg [XLEN-1:0] mideleg;
    reg [XLEN-1:0] mie;
    reg [XLEN-1:0] mtvec;
    reg [XLEN-1:0] mscratch;
    reg [XLEN-1:0] mepc;
    reg [XLEN-1:0] mcause;
    reg [XLEN-1:0] mtval;

    reg [XLEN-1:0] stvec;
    reg [XLEN-1:0] sscratch;
    reg [XLEN-1:0] sepc;
    reg [XLEN-1:0] scause;
    reg [XLEN-1:0] stval;
    reg [XLEN-1:0] satp;

    // Current privilege mode

    reg [1:0] current_mode;


    // MACHINE TIMER

    // mtime and mtimecmp are 64-bit registers on RV32 and RV64 systems.

    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    wire timer_interrupt;

    assign timer_interrupt = (mtime >= mtimecmp);

    // The current interrupt state exposed through mip.

    reg [XLEN-1:0] mip_value_reg;
    wire [XLEN-1:0] mip_value;

    always @(*) begin

        mip_value_reg = {XLEN{1'b0}};

        // Machine-level interrupt pending bits

        mip_value_reg[MIP_MSIP] = software_interrupt;
        mip_value_reg[MIP_MTIP] = timer_interrupt;
        mip_value_reg[MIP_MEIP] = external_interrupt;

        // Supervisor-level interrupt pending bits reflect delegated machine interrupts

        mip_value_reg[MIP_SSIP] = software_interrupt && mideleg[MIP_MSIP];
        mip_value_reg[MIP_STIP] = timer_interrupt && mideleg[MIP_MTIP];
        mip_value_reg[MIP_SEIP] = external_interrupt && mideleg[MIP_MEIP];

    end

    assign mip_value = mip_value_reg;

    wire [XLEN-1:0] mip;

    assign mip = mip_value;


    // INSTRUCTION FETCH

    // Compressed instructions use 16-bit alignment, so a 32-bit instruction can start at either half of an instruction memory word.

    wire [31:0] instruction_memory_word;
    wire [31:0] instruction_memory_next_word;
    wire [15:0] compressed_instruction;
    wire [31:0] fetched_instruction_word;
    wire [31:0] fetched_instruction;
    wire fetched_instruction_compressed;
    wire [2:0] fetched_instruction_length;

    assign instruction_memory_word = instruction_memory[pc[IMEM_ADDR_WIDTH+1:2]];
    assign instruction_memory_next_word = instruction_memory[pc[IMEM_ADDR_WIDTH+1:2] + 1'b1];

    assign compressed_instruction = (pc[1] == 1'b0) ? instruction_memory_word[15:0] : instruction_memory_word[31:16];

    assign fetched_instruction_word = (pc[1] == 1'b0) ? instruction_memory_word : {instruction_memory_next_word[15:0], instruction_memory_word[31:16]};

    assign fetched_instruction_compressed = (compressed_instruction[1:0] != 2'b11);
    assign fetched_instruction_length = fetched_instruction_compressed ? 3'd2 : 3'd4;

    // A compressed instruction with an unsupported encoding must raise an illegal-instruction exception.
    // Keep the explicit zero C.ADDI4SPN encoding check here as well so the fetch stage does not depend on
    // the timing of the compressed decoder result.

    wire fetched_compressed_illegal;

    assign fetched_compressed_illegal = fetched_instruction_compressed && ((!compressed_instruction_supported) || (compressed_instruction == 16'h0000));


    // INSTRUCTION ENCODERS

    // These functions are used to expand compressed instructions into normal 32-bit instructions.

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


    // COMPRESSED INSTRUCTION DECODER

    // Compressed instructions are expanded into normal 32-bit instructions before entering the pipeline.

    reg [31:0] compressed_decoded_instruction;
    reg compressed_instruction_supported;

    wire [9:0] c_addi4spn_imm;
    wire [6:0] c_lw_imm;
    wire [7:0] c_ld_imm;
    wire [5:0] c_imm6;
    wire [9:0] c_addi16sp_imm;
    wire [19:0] c_lui_imm20;
    wire [20:0] c_j_imm21;
    wire [12:0] c_b_imm13;
    wire [7:0] c_lwsp_imm;
    wire [8:0] c_ldsp_imm;
    wire [7:0] c_swsp_imm;
    wire [8:0] c_sdsp_imm;

    assign c_addi4spn_imm = {compressed_instruction[10:7], compressed_instruction[12:11], compressed_instruction[5], compressed_instruction[6], 2'b00};
    assign c_lw_imm = {compressed_instruction[5], compressed_instruction[12:10], compressed_instruction[6], 2'b00};
    assign c_ld_imm = {compressed_instruction[6:5], compressed_instruction[12:10], 3'b000};
    assign c_imm6 = {compressed_instruction[12], compressed_instruction[6:2]};
    assign c_addi16sp_imm = {compressed_instruction[12], compressed_instruction[6], compressed_instruction[5], compressed_instruction[4:3], compressed_instruction[2], 4'b0000};
    assign c_lui_imm20 = {{14{compressed_instruction[12]}}, compressed_instruction[12], compressed_instruction[6:2]};
    assign c_j_imm21 = {{10{compressed_instruction[12]}}, compressed_instruction[12], compressed_instruction[8], compressed_instruction[10:9], compressed_instruction[6], compressed_instruction[7], compressed_instruction[5:3], compressed_instruction[2], 1'b0};
    assign c_b_imm13 = {{4{compressed_instruction[12]}}, compressed_instruction[12], compressed_instruction[6:5], compressed_instruction[2], compressed_instruction[11:10], compressed_instruction[4:3], 1'b0};
    assign c_lwsp_imm = {compressed_instruction[12], compressed_instruction[6:4], compressed_instruction[3:2], 2'b00};
    assign c_ldsp_imm = {compressed_instruction[12], compressed_instruction[4:2], compressed_instruction[6:5], 3'b000};
    assign c_swsp_imm = {compressed_instruction[8:7], compressed_instruction[12:9], 2'b00};
    assign c_sdsp_imm = {compressed_instruction[12:10], compressed_instruction[9:7], 3'b000};

    always @(*) begin

        compressed_decoded_instruction = 32'h00000013;
        compressed_instruction_supported = 1'b1;

        case (compressed_instruction[1:0])

            // QUADRANT 0

            2'b00: begin

                case (compressed_instruction[15:13])

                    // C.ADDI4SPN

                    3'b000: begin
                        if (c_addi4spn_imm == 10'b0)
                            compressed_instruction_supported = 1'b0;
                        else
                            compressed_decoded_instruction = encode_i({2'b00, c_addi4spn_imm}, 5'd2, 3'b000, 5'd8 + {2'b00, compressed_instruction[4:2]}, OPCODE_OP_IMM);
                    end

                    // C.FLD

                    3'b001: begin
                        compressed_decoded_instruction = encode_i({5'b00000, c_ld_imm}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b011, 5'd8 + {2'b00, compressed_instruction[4:2]}, OPCODE_LOAD_FP);
                    end

                    // C.LW

                    3'b010: begin
                        compressed_decoded_instruction = encode_i({5'b00000, c_lw_imm}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b010, 5'd8 + {2'b00, compressed_instruction[4:2]}, OPCODE_LOAD);
                    end

                    // C.LD

                    3'b011: begin
                        compressed_decoded_instruction = encode_i({4'b0000, c_ld_imm}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b011, 5'd8 + {2'b00, compressed_instruction[4:2]}, OPCODE_LOAD);
                    end

                    // Reserved / floating point store variants

                    3'b100: begin
                        compressed_instruction_supported = 1'b0;
                    end

                    // C.FSD

                    3'b101: begin
                        compressed_decoded_instruction = encode_s({4'b0000, c_ld_imm}, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b011, OPCODE_STORE_FP);
                    end

                    // C.SW

                    3'b110: begin
                        compressed_decoded_instruction = encode_s({5'b00000, c_lw_imm}, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b010, OPCODE_STORE);
                    end

                    // C.SD

                    3'b111: begin
                        compressed_decoded_instruction = encode_s({4'b0000, c_ld_imm}, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b011, OPCODE_STORE);
                    end

                    default: begin
                        compressed_instruction_supported = 1'b0;
                    end

                endcase

            end


            // QUADRANT 1

            2'b01: begin

                case (compressed_instruction[15:13])

                    // C.ADDI

                    3'b000: begin
                        compressed_decoded_instruction = encode_i({{6{c_imm6[5]}}, c_imm6}, compressed_instruction[11:7], 3'b000, compressed_instruction[11:7], OPCODE_OP_IMM);
                    end

                    // C.ADDIW

                    3'b001: begin
                        if (compressed_instruction[11:7] == 5'd0)
                            compressed_instruction_supported = 1'b0;
                        else
                            compressed_decoded_instruction = encode_i({{6{c_imm6[5]}}, c_imm6}, compressed_instruction[11:7], 3'b000, compressed_instruction[11:7], OPCODE_OP_IMM_32);
                    end

                    // C.LI

                    3'b010: begin
                        compressed_decoded_instruction = encode_i({{6{c_imm6[5]}}, c_imm6}, 5'd0, 3'b000, compressed_instruction[11:7], OPCODE_OP_IMM);
                    end

                    // C.LUI / C.ADDI16SP

                    3'b011: begin

                        if (compressed_instruction[11:7] == 5'd2) begin
                            if (c_addi16sp_imm == 10'b0)
                                compressed_instruction_supported = 1'b0;
                            else
                                compressed_decoded_instruction = encode_i({{2{c_addi16sp_imm[9]}}, c_addi16sp_imm}, 5'd2, 3'b000, 5'd2, OPCODE_OP_IMM);
                        end

                        else if (compressed_instruction[11:7] != 5'd0) begin
                            if (c_lui_imm20 == 20'b0)
                                compressed_instruction_supported = 1'b0;
                            else
                                compressed_decoded_instruction = encode_u(c_lui_imm20, compressed_instruction[11:7], OPCODE_LUI);
                        end

                        else begin
                            compressed_instruction_supported = 1'b0;
                        end

                    end

                    // C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND / C.SUBW / C.ADDW

                    3'b100: begin

                        case (compressed_instruction[11:10])

                            2'b00: begin
                                compressed_decoded_instruction = encode_i({6'b000000, c_imm6}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b101, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP_IMM);
                            end

                            2'b01: begin
                                compressed_decoded_instruction = encode_i({6'b010000, c_imm6}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b101, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP_IMM);
                            end

                            2'b10: begin
                                compressed_decoded_instruction = encode_i({{6{c_imm6[5]}}, c_imm6}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b111, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP_IMM);
                            
                            end

                            2'b11: begin

                                if (compressed_instruction[12] == 1'b0) begin

                                    case (compressed_instruction[6:5])
                                        2'b00: compressed_decoded_instruction = encode_r(7'b0100000, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b000, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP);
                                        2'b01: compressed_decoded_instruction = encode_r(7'b0000000, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b100, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP);
                                        2'b10: compressed_decoded_instruction = encode_r(7'b0000000, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b110, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP);
                                        2'b11: compressed_decoded_instruction = encode_r(7'b0000000, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b111, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP);
                                        default: compressed_instruction_supported = 1'b0;
                                    endcase


                                end

                                else begin

                                    case (compressed_instruction[6:5])
                                        2'b00: compressed_decoded_instruction = encode_r(7'b0100000, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b000, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP_32);
                                        2'b01: compressed_decoded_instruction = encode_r(7'b0000000, 5'd8 + {2'b00, compressed_instruction[4:2]}, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b000, 5'd8 + {2'b00, compressed_instruction[9:7]}, OPCODE_OP_32);
                                        default: compressed_instruction_supported = 1'b0;
                                    endcase

                                end

                            end

                            default: compressed_instruction_supported = 1'b0;

                        endcase

                    end


                    // C.J

                    3'b101: begin
                        compressed_decoded_instruction = encode_j(c_j_imm21, 5'd0, OPCODE_JAL);
                    end

                    // C.BEQZ

                    3'b110: begin
                        compressed_decoded_instruction = encode_b(c_b_imm13, 5'd0, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b000, OPCODE_BRANCH);
                    end

                    // C.BNEZ

                    3'b111: begin
                        compressed_decoded_instruction = encode_b(c_b_imm13, 5'd0, 5'd8 + {2'b00, compressed_instruction[9:7]}, 3'b001, OPCODE_BRANCH);
                    end

                    default: begin
                        compressed_instruction_supported = 1'b0;
                    end


                endcase

            end


            // QUADRANT 2

            2'b10: begin

                case (compressed_instruction[15:13])


                    // C.SLLI

                    3'b000: begin
                        if (compressed_instruction[11:7] == 5'd0)
                            compressed_instruction_supported = 1'b0;
                        else
                            compressed_decoded_instruction = encode_i({6'b000000, c_imm6}, compressed_instruction[11:7], 3'b001, compressed_instruction[11:7], OPCODE_OP_IMM);
                    end

                    // C.FLDSP

                    3'b001: begin
                        if (compressed_instruction[11:7] == 5'd0)
                            compressed_instruction_supported = 1'b0;

                        else
                            compressed_decoded_instruction = encode_i({3'b000, c_ldsp_imm}, 5'd2, 3'b011, compressed_instruction[11:7], OPCODE_LOAD_FP);
                    end

                    // C.LWSP

                    3'b010: begin
                        if (compressed_instruction[11:7] == 5'd0)
                            compressed_instruction_supported = 1'b0;
                        else
                            compressed_decoded_instruction = encode_i({4'b0000, c_lwsp_imm}, 5'd2, 3'b010, compressed_instruction[11:7], OPCODE_LOAD);
                    end

                    // C.LDSP

                    3'b011: begin
                        if (compressed_instruction[11:7] == 5'd0)
                            compressed_instruction_supported = 1'b0;

                        else
                            compressed_decoded_instruction = encode_i({3'b000, c_ldsp_imm}, 5'd2, 3'b011, compressed_instruction[11:7], OPCODE_LOAD);
                    end

                    // J[AL]R / MV / ADD

                    3'b100: begin

                        if (compressed_instruction[12] == 1'b0) begin

                            if (compressed_instruction[6:2] == 5'd0)
                                compressed_decoded_instruction = encode_i(12'b0, compressed_instruction[11:7], 3'b000, 5'd0, OPCODE_JALR);
                            else
                                compressed_decoded_instruction = encode_r(7'b0000000, compressed_instruction[6:2], 5'd0, 3'b000, compressed_instruction[11:7], OPCODE_OP);

                        end

                        else begin

                            if ((compressed_instruction[11:7] == 5'd0) && (compressed_instruction[6:2] == 5'd0))
                                compressed_decoded_instruction = 32'h00100073;
                            else if (compressed_instruction[6:2] == 5'd0)
                                compressed_decoded_instruction = encode_i(12'b0, compressed_instruction[11:7], 3'b000, 5'd1, OPCODE_JALR);
                            else
                                compressed_decoded_instruction = encode_r(7'b0000000, compressed_instruction[6:2], compressed_instruction[11:7], 3'b000, compressed_instruction[11:7], OPCODE_OP);

                        end

                    end

                    // C.FSDSP

                    3'b101: begin
                        compressed_decoded_instruction = encode_s({3'b000, c_sdsp_imm}, compressed_instruction[6:2], 5'd2, 3'b011, OPCODE_STORE_FP);
                    end

                    // C.SWSP

                    3'b110: begin
                        compressed_decoded_instruction = encode_s({4'b0000, c_swsp_imm}, compressed_instruction[6:2], 5'd2, 3'b010, OPCODE_STORE);
                    end

                    // C.SDSP

                    3'b111: begin
                        compressed_decoded_instruction = encode_s({3'b000, c_sdsp_imm}, compressed_instruction[9:7], 5'd2, 3'b011, OPCODE_STORE);
                    end

                    default: begin
                        compressed_instruction_supported = 1'b0;
                    end

                endcase

            end

            default: begin
                compressed_instruction_supported = 1'b0;
            end

        endcase

    end

    assign fetched_instruction = fetched_instruction_compressed ?
        ((compressed_instruction == 16'h0000) ? 32'hFFFFFFFF :
         (fetched_compressed_illegal ? 32'hFFFFFFFF : compressed_decoded_instruction)) :
        fetched_instruction_word;


    // IF / ID PIPELINE REGISTER

    // Holds the fetched instruction and its PC before the decode stage.

    reg IF_ID_valid;
    reg [XLEN-1:0] IF_ID_pc;
    reg [31:0] IF_ID_instruction;
    reg [2:0] IF_ID_instruction_length;
    reg IF_ID_compressed_illegal;
    reg [15:0] IF_ID_compressed_instruction;
    reg [XLEN-1:0] IF_ID_predicted_next_pc;

    // Debug aliases for the current pipeline values

    wire [XLEN-1:0] instruction_pc;
    wire [31:0] instruction_register;

    assign instruction_pc = IF_ID_pc;
    assign instruction_register = IF_ID_instruction;


    // INSTRUCTION FIELDS

    // These fields are present in different instruction formats and are extracted directly from the instruction

    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rs3;
    wire [6:0] funct7;

    assign opcode = IF_ID_instruction[6:0];
    assign rd = IF_ID_instruction[11:7];
    assign funct3 = IF_ID_instruction[14:12];
    assign rs1 = IF_ID_instruction[19:15];
    assign rs2 = IF_ID_instruction[24:20];
    assign rs3 = IF_ID_instruction[31:27];
    assign funct7 = IF_ID_instruction[31:25];


    // REGISTER FILE READ

    // The register file has two asynchronous read ports
    // Reading x0 always returns zero

    wire [XLEN-1:0] rs1_data;
    wire [XLEN-1:0] rs2_data;
    wire [63:0] fp_rs1_data;
    wire [63:0] fp_rs2_data;
    wire [63:0] fp_rs3_data;

    assign rs1_data = (rs1 == 5'd0) ? {XLEN{1'b0}} : registers[rs1];
    assign rs2_data = (rs2 == 5'd0) ? {XLEN{1'b0}} : registers[rs2];

    assign fp_rs1_data = fregisters[rs1];
    assign fp_rs2_data = fregisters[rs2];
    assign fp_rs3_data = fregisters[rs3];


    // CSR

    // CSR fields used by the SYSTEM instruction encoding

    wire [11:0] csr_address;
    wire [4:0] csr_zimm;
    wire csr_instruction;

    assign csr_address = IF_ID_instruction[31:20];
    assign csr_zimm = IF_ID_instruction[19:15];
    assign csr_instruction = (opcode == OPCODE_SYSTEM) && (funct3 != 3'b000);

    reg [XLEN-1:0] csr_read_data;
    reg csr_supported;
    reg csr_write_intent;
    reg csr_illegal_access;

    // Returns the value of the selected CSR

    always @(*) begin

        csr_supported = 1'b1;
        csr_read_data = {XLEN{1'b0}};

        if (ID_EX_csr_write && (ID_EX_csr_address == csr_address)) begin
            csr_read_data = csr_write_data_ex;
        end

        else if (EX_MEM_valid && EX_MEM_csr_write && (EX_MEM_csr_address == csr_address)) begin
            csr_read_data = EX_MEM_csr_write_data;
        end

        else if (MEM_WB_valid && MEM_WB_csr_write && (MEM_WB_csr_address == csr_address)) begin
            csr_read_data = MEM_WB_csr_write_data;
        end

        else begin

            case (csr_address)

                CSR_FFLAGS: csr_read_data = {{(XLEN-5){1'b0}}, fflags};
                CSR_FRM: csr_read_data = {{(XLEN-3){1'b0}}, frm};
                CSR_FCSR: csr_read_data = {{(XLEN-8){1'b0}}, frm, fflags};

                CSR_SSTATUS: begin
                    csr_read_data = {XLEN{1'b0}};
                    csr_read_data[MSTATUS_SIE] = mstatus[MSTATUS_SIE];
                    csr_read_data[MSTATUS_SPIE] = mstatus[MSTATUS_SPIE];
                    csr_read_data[MSTATUS_SPP] = mstatus[MSTATUS_SPP];
                end

                CSR_SIE: begin
                    csr_read_data = {XLEN{1'b0}};
                    csr_read_data[MIP_SSIP] = mie[MIP_SSIP];
                    csr_read_data[MIP_STIP] = mie[MIP_STIP];
                    csr_read_data[MIP_SEIP] = mie[MIP_SEIP];
                end
                CSR_STVEC: csr_read_data = stvec;
                CSR_SSCRATCH: csr_read_data = sscratch;
                CSR_SEPC: csr_read_data = sepc;
                CSR_SCAUSE: csr_read_data = scause;
                CSR_STVAL: csr_read_data = stval;
                CSR_SIP: begin
                    csr_read_data = {XLEN{1'b0}};
                    csr_read_data[MIP_SSIP] = mip_value[MIP_SSIP];
                    csr_read_data[MIP_STIP] = mip_value[MIP_STIP];
                    csr_read_data[MIP_SEIP] = mip_value[MIP_SEIP];
                end
                CSR_SATP: csr_read_data = satp;

                CSR_MSTATUS: csr_read_data = mstatus;
                CSR_MISA: csr_read_data = misa;
                CSR_MEDELEG: csr_read_data = medeleg;
                CSR_MIDELEG: csr_read_data = mideleg;
                CSR_MIE: csr_read_data = mie;
                CSR_MTVEC: csr_read_data = mtvec;
                CSR_MSCRATCH: csr_read_data = mscratch;
                CSR_MEPC: csr_read_data = mepc;
                CSR_MCAUSE: csr_read_data = mcause;
                CSR_MTVAL: csr_read_data = mtval;
                CSR_MIP: csr_read_data = mip_value;
                CSR_MHARTID: csr_read_data = {XLEN{1'b0}};

                default: begin
                    csr_read_data = {XLEN{1'b0}};
                    csr_supported = 1'b0;
                end

            endcase

        end

    end


    // Determine whether the CSR operation attempts to modify the selected CSR

    always @(*) begin

        csr_write_intent = 1'b0;

        if (csr_instruction) begin

            case (funct3)

                3'b001, 3'b101: csr_write_intent = 1'b1;
                3'b010, 3'b011: csr_write_intent = (rs1 != 5'd0);
                3'b110, 3'b111: csr_write_intent = (csr_zimm != 5'd0);

                default: csr_write_intent = 1'b0;

            endcase

        end

    end


    // Check CSR privilege and write permissions

    always @(*) begin

        csr_illegal_access = 1'b0;

        if (csr_instruction) begin

            if (!csr_supported)
                csr_illegal_access = 1'b1;

            if (csr_address[9:8] == 2'b10)
                csr_illegal_access = 1'b1;

            if ((current_mode == PRIV_U) && (csr_address[9:8] != 2'b00))
                csr_illegal_access = 1'b1;

            if ((current_mode == PRIV_S) && (csr_address[9:8] == 2'b11))
                csr_illegal_access = 1'b1;

            if (csr_write_intent && (csr_address[11:10] == 2'b11))
                csr_illegal_access = 1'b1;

            if (csr_write_intent && (csr_address == CSR_MISA))
                csr_illegal_access = 1'b1;

            if (csr_write_intent && (csr_address == CSR_MHARTID))
                csr_illegal_access = 1'b1;

            if (csr_write_intent && (csr_address == CSR_SCAUSE))
                csr_illegal_access = 1'b1;

            if (csr_write_intent && (csr_address == CSR_SIP))
                csr_illegal_access = 1'b1;

            if (csr_write_intent && (csr_address == CSR_MIP))
                csr_illegal_access = 1'b1;

        end

    end


    // IMMEDIATE GENERATOR

    // RISC-V's immediate formats:
    // I-type
    // S-type
    // B-type
    // U-type
    // J-type

    // The immediate is selected based on the opcode

    reg [XLEN-1:0] immediate;

    always @(*) begin

        immediate = {XLEN{1'b0}};

        case (opcode)

            // I-TYPE

            // Used by:
            // ADDI
            // SLTI
            // SLTIU
            // XORI
            // ORI
            // ANDI
            // SLLI
            // SRLI
            // SRAI
            // ADDIW
            // SLLIW
            // SRLIW
            // SRAIW
            // JALR

            OPCODE_OP_IMM, OPCODE_OP_IMM_32, OPCODE_LOAD, OPCODE_JALR: immediate = {{(XLEN-12){IF_ID_instruction[31]}}, IF_ID_instruction[31:20]};

            // S-TYPE

            // Used by:
            // SB
            // SH
            // SW
            // SD

            OPCODE_STORE: immediate = {{(XLEN-12){IF_ID_instruction[31]}}, IF_ID_instruction[31:25], IF_ID_instruction[11:7]};

            // B-TYPE

            // Used by:
            // BEQ
            // BNE
            // BLT
            // BGE
            // BLTU
            // BGEU

            // The lowest bit is always zero because branches are aligned to 16 bits with the C extension.

            OPCODE_BRANCH: immediate = {{(XLEN-13){IF_ID_instruction[31]}}, IF_ID_instruction[31], IF_ID_instruction[7], IF_ID_instruction[30:25], IF_ID_instruction[11:8], 1'b0};

            // U-TYPE

            // Used by:
            // LUI
            // AUIPC

            OPCODE_LUI, OPCODE_AUIPC: immediate = {{(XLEN-32){IF_ID_instruction[31]}}, IF_ID_instruction[31:12], 12'b0};

            // J-TYPE

            // Used by:
            // JAL

            OPCODE_JAL: immediate = {{(XLEN-21){IF_ID_instruction[31]}}, IF_ID_instruction[31], IF_ID_instruction[19:12], IF_ID_instruction[20], IF_ID_instruction[30:21], 1'b0};

            default: immediate = {XLEN{1'b0}};

        endcase

    end


    // Floating point operations

    localparam [4:0] FP_ADD = 5'd0;
    localparam [4:0] FP_SUB = 5'd1;
    localparam [4:0] FP_MUL = 5'd2;
    localparam [4:0] FP_DIV = 5'd3;
    localparam [4:0] FP_SQRT = 5'd4;
    localparam [4:0] FP_SGNJ = 5'd5;
    localparam [4:0] FP_SGNJN = 5'd6;
    localparam [4:0] FP_SGNJX = 5'd7;
    localparam [4:0] FP_MIN = 5'd8;
    localparam [4:0] FP_MAX = 5'd9;
    localparam [4:0] FP_FEQ = 5'd10;
    localparam [4:0] FP_FLT = 5'd11;
    localparam [4:0] FP_FLE = 5'd12;
    localparam [4:0] FP_FCLASS = 5'd13;
    localparam [4:0] FP_CVT_W = 5'd14;
    localparam [4:0] FP_CVT_WU = 5'd15;
    localparam [4:0] FP_CVT_L = 5'd16;
    localparam [4:0] FP_CVT_LU = 5'd17;
    localparam [4:0] FP_CVT_FROM_W = 5'd18;
    localparam [4:0] FP_CVT_FROM_WU = 5'd19;
    localparam [4:0] FP_CVT_FROM_L = 5'd20;
    localparam [4:0] FP_CVT_FROM_LU = 5'd21;
    localparam [4:0] FP_MV_X_W = 5'd22;
    localparam [4:0] FP_MV_W_X = 5'd23;
    localparam [4:0] FP_CVT_S_D = 5'd24;
    localparam [4:0] FP_CVT_D_S = 5'd25;
    localparam [4:0] FP_MV_X_D = 5'd26;
    localparam [4:0] FP_MV_D_X = 5'd27;
    localparam [4:0] FP_FMADD = 5'd28;
    localparam [4:0] FP_FMSUB = 5'd29;
    localparam [4:0] FP_FNMSUB = 5'd30;
    localparam [4:0] FP_FNMADD = 5'd31;


    // CONTROL SIGNALS

    reg reg_write;
    reg mem_write;
    reg mem_read;

    reg alu_src_immediate;

    reg branch;
    reg jump;
    reg jump_register;

    reg [4:0] alu_control;

    reg is_m_instruction;
    reg is_atomic_instruction;
    reg is_lr;
    reg is_sc;
    reg atomic_write;
    reg [4:0] atomic_operation;
    reg atomic_word;

    reg csr_instruction_control;
    reg csr_write;
    reg [2:0] csr_op;
    reg [11:0] csr_addr_control;
    reg [4:0] csr_zimm_control;

    reg mret;
    reg sret;

    reg exception;
    reg [XLEN-1:0] exception_cause;
    reg [XLEN-1:0] exception_tval;

    reg use_rs1;
    reg use_rs2;

    reg [1:0] mem_size;
    reg mem_unsigned;

    reg fence_instruction;
    reg fence_i_instruction;

    reg fp_instruction;
    reg fp_reg_write;
    reg fp_to_int;
    reg fp_mem_read;
    reg fp_mem_write;
    reg fp_use_rs1;
    reg fp_use_rs2;
    reg fp_use_rs3;
    reg fp_format_d;
    reg [4:0] fp_operation;
    reg [2:0] fp_rounding_mode;

    // Selects what is written back into the register file.

    // 00 = ALU result
    // 01 = Memory result
    // 10 = PC + instruction length
    // 11 = PC + immediate

    reg [1:0] result_select;


    // DECODER

    // The decoder looks at the opcode and funct fields and generates the control signals used by the datapath.

    always @(*) begin

        // Default values

        reg_write = 1'b0;
        mem_write = 1'b0;
        mem_read = 1'b0;

        alu_src_immediate = 1'b0;

        branch = 1'b0;
        jump = 1'b0;
        jump_register = 1'b0;

        alu_control = ALU_ADD;

        is_m_instruction = 1'b0;
        is_atomic_instruction = 1'b0;
        is_lr = 1'b0;
        is_sc = 1'b0;
        atomic_write = 1'b0;
        atomic_operation = ATOMIC_ADD;
        atomic_word = 1'b0;

        csr_instruction_control = 1'b0;
        csr_write = 1'b0;
        csr_op = 3'b000;
        csr_addr_control = 12'b0;
        csr_zimm_control = 5'b0;

        mret = 1'b0;
        sret = 1'b0;

        exception = 1'b0;
        exception_cause = {XLEN{1'b0}};
        exception_tval = {XLEN{1'b0}};

        use_rs1 = 1'b0;
        use_rs2 = 1'b0;

        mem_size = MEM_DOUBLE;
        mem_unsigned = 1'b0;

        fence_instruction = 1'b0;
        fence_i_instruction = 1'b0;

        fp_instruction = 1'b0;
        fp_reg_write = 1'b0;
        fp_to_int = 1'b0;
        fp_mem_read = 1'b0;
        fp_mem_write = 1'b0;
        fp_use_rs1 = 1'b0;
        fp_use_rs2 = 1'b0;
        fp_use_rs3 = 1'b0;
        fp_format_d = 1'b0;
        fp_operation = FP_ADD;
        fp_rounding_mode = funct3;

        result_select = 2'b00;


        if (IF_ID_valid) begin

            case (opcode)

                // R-TYPE

                OPCODE_OP: begin

                    reg_write = 1'b1;
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;

                    // The M extension uses funct7 = 0000001.

                    if (funct7 == 7'b0000001) begin
                        is_m_instruction = 1'b1;
                    end

                    else begin

                        case (funct3)

                            3'b000: begin
                                if (funct7 == 7'b0100000)
                                    alu_control = ALU_SUB;
                                else
                                    alu_control = ALU_ADD;
                            end

                            3'b001: alu_control = ALU_SLL;
                            3'b010: alu_control = ALU_SLT;
                            3'b011: alu_control = ALU_SLTU;
                            3'b100: alu_control = ALU_XOR;

                            3'b101: begin
                                if (funct7 == 7'b0100000)
                                    alu_control = ALU_SRA;
                                else
                                    alu_control = ALU_SRL;
                            end

                            3'b110: alu_control = ALU_OR;
                            3'b111: alu_control = ALU_AND;

                            default: alu_control = ALU_ADD;

                        endcase

                    end

                end


                // R-TYPE WORD

                // Used by:
                // ADDW
                // SUBW
                // SLLW
                // SRLW
                // SRAW
                // MULW
                // DIVW
                // DIVUW
                // REMW
                // REMUW

                OPCODE_OP_32: begin

                    reg_write = 1'b1;
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;

                    if (funct7 == 7'b0000001)
                        is_m_instruction = 1'b1;
                    else begin

                        case (funct3)
                            3'b000: alu_control = (funct7 == 7'b0100000) ? ALU_SUBW : ALU_ADDW;
                            3'b001: alu_control = ALU_SLLW;
                            3'b101: alu_control = (funct7 == 7'b0100000) ? ALU_SRAW : ALU_SRLW;
                            default: begin
                                alu_control = ALU_ADDW;
                                exception = 1'b1;
                                exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                exception_tval = IF_ID_instruction;
                            end
                        endcase

                    end

                end


                // I-TYPE ALU

                OPCODE_OP_IMM: begin

                    reg_write = 1'b1;
                    alu_src_immediate = 1'b1;
                    use_rs1 = 1'b1;

                    case (funct3)
                        3'b000: alu_control = ALU_ADD;
                        3'b010: alu_control = ALU_SLT;
                        3'b011: alu_control = ALU_SLTU;
                        3'b100: alu_control = ALU_XOR;
                        3'b110: alu_control = ALU_OR;
                        3'b111: alu_control = ALU_AND;
                        3'b001: alu_control = ALU_SLL;
                        3'b101: alu_control = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                        default: begin
                            alu_control = ALU_ADD;
                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;
                        end
                    endcase

                end


                // I-TYPE ALU WORD

                OPCODE_OP_IMM_32: begin

                    reg_write = 1'b1;
                    alu_src_immediate = 1'b1;
                    use_rs1 = 1'b1;

                    case (funct3)
                        3'b000: alu_control = ALU_ADDW;
                        3'b001: alu_control = ALU_SLLW;
                        3'b101: alu_control = (funct7 == 7'b0100000) ? ALU_SRAW : ALU_SRLW;
                        default: begin
                            alu_control = ALU_ADDW;
                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;
                        end
                    endcase

                end


                // LOAD

                // Supports LB, LH, LW, LD, LBU, LHU, LWU.

                OPCODE_LOAD: begin

                    reg_write = 1'b1;
                    mem_read = 1'b1;
                    alu_src_immediate = 1'b1;
                    use_rs1 = 1'b1;
                    alu_control = ALU_ADD;
                    result_select = 2'b01;

                    case (funct3)
                        3'b000: begin mem_size = MEM_BYTE; mem_unsigned = 1'b0; end
                        3'b001: begin mem_size = MEM_HALF; mem_unsigned = 1'b0; end
                        3'b010: begin mem_size = MEM_WORD; mem_unsigned = 1'b0; end
                        3'b011: begin mem_size = MEM_DOUBLE; mem_unsigned = 1'b0; end
                        3'b100: begin mem_size = MEM_BYTE; mem_unsigned = 1'b1; end
                        3'b101: begin mem_size = MEM_HALF; mem_unsigned = 1'b1; end
                        3'b110: begin mem_size = MEM_WORD; mem_unsigned = 1'b1; end
                        default: begin
                            mem_size = MEM_DOUBLE;
                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;
                        end
                    endcase

                end


                // STORE

                // Supports SB, SH, SW, SD.

                OPCODE_STORE: begin

                    mem_write = 1'b1;
                    alu_src_immediate = 1'b1;
                    alu_control = ALU_ADD;
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;

                    case (funct3)
                        3'b000: mem_size = MEM_BYTE;
                        3'b001: mem_size = MEM_HALF;
                        3'b010: mem_size = MEM_WORD;
                        3'b011: mem_size = MEM_DOUBLE;
                        default: begin
                            mem_size = MEM_DOUBLE;
                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;
                        end
                    endcase

                end


                // BRANCH

                // Used by:
                // BEQ
                // BNE
                // BLT
                // BGE
                // BLTU
                // BGEU

                OPCODE_BRANCH: begin
                    branch = 1'b1;
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;
                end


                // LUI

                OPCODE_LUI: begin
                    reg_write = 1'b1;
                    result_select = 2'b11;
                end


                // AUIPC

                OPCODE_AUIPC: begin
                    reg_write = 1'b1;
                    result_select = 2'b11;
                end


                // JAL

                OPCODE_JAL: begin
                    reg_write = 1'b1;
                    jump = 1'b1;
                    result_select = 2'b10;
                end


                // JALR

                OPCODE_JALR: begin
                    reg_write = 1'b1;
                    jump_register = 1'b1;
                    alu_src_immediate = 1'b1;
                    use_rs1 = 1'b1;
                    result_select = 2'b10;
                end


                // SYSTEM

                OPCODE_SYSTEM: begin

                    if (funct3 == 3'b000) begin

                        if (IF_ID_instruction == 32'h00000073) begin

                            exception = 1'b1;

                            if (current_mode == PRIV_U)
                                exception_cause = CAUSE_ECALL_U;
                            else if (current_mode == PRIV_S)
                                exception_cause = CAUSE_ECALL_S;
                            else
                                exception_cause = CAUSE_ECALL_M;

                            exception_tval = {XLEN{1'b0}};

                        end

                        else if (IF_ID_instruction == 32'h00100073) begin

                            exception = 1'b1;
                            exception_cause = CAUSE_BREAKPOINT;
                            exception_tval = {XLEN{1'b0}};

                        end

                        else if (IF_ID_instruction == 32'h30200073) begin

                            if (current_mode == PRIV_M)
                                mret = 1'b1;
                            else begin
                                exception = 1'b1;
                                exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                exception_tval = IF_ID_instruction;
                            end

                        end

                        else if (IF_ID_instruction == 32'h10200073) begin

                            if (current_mode == PRIV_S)
                                sret = 1'b1;
                            else begin
                                exception = 1'b1;
                                exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                exception_tval = IF_ID_instruction;
                            end

                        end

                        else begin

                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;

                        end

                    end

                    else begin

                        csr_instruction_control = 1'b1;
                        csr_addr_control = csr_address;
                        csr_zimm_control = csr_zimm;
                        csr_op = funct3;

                        if (csr_illegal_access) begin

                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;

                        end

                        else begin

                            reg_write = 1'b1;

                            use_rs1 =
                                (funct3 == 3'b001) ||
                                (funct3 == 3'b010) ||
                                (funct3 == 3'b011);

                            csr_write = csr_write_intent;

                        end

                    end

                end


                // FENCE

                OPCODE_FENCE: begin

                    if (funct3 == 3'b000)
                        fence_instruction = 1'b1;
                    else if (funct3 == 3'b001)
                        fence_i_instruction = 1'b1;
                    else begin
                        exception = 1'b1;
                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                        exception_tval = IF_ID_instruction;
                    end

                end


                // ATOMIC

                // Supports LR.W, SC.W, LR.D, SC.D, and the AMO operations.

                OPCODE_ATOMIC: begin

                    if ((funct3 == 3'b010) || (funct3 == 3'b011)) begin

                        is_atomic_instruction = 1'b1;
                        reg_write = 1'b1;
                        use_rs1 = 1'b1;
                        atomic_word = (funct3 == 3'b010);

                        case (funct7[6:2])

                            ATOMIC_LR: begin
                                is_lr = 1'b1;

                            end

                            ATOMIC_SC: begin
                                is_sc = 1'b1;
                                use_rs2 = 1'b1;

                            end

                            default: begin
                                atomic_write = 1'b1;
                                atomic_operation = funct7[6:2];
                                use_rs2 = 1'b1;
                            end

                        endcase

                    end

                    else begin
                        exception = 1'b1;
                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                        exception_tval = IF_ID_instruction;
                    end

                end


                // FUSED MULTIPLY-ADD INSTRUCTIONS

                // FMADD.S/D, FMSUB.S/D, FNMSUB.S/D, and FNMADD.S/D use three floating point source registers.

                7'b1000011,
                7'b1000111,
                7'b1001011,
                7'b1001111: begin

                    fp_instruction = 1'b1;
                    fp_reg_write = 1'b1;
                    fp_use_rs1 = 1'b1;
                    fp_use_rs2 = 1'b1;
                    fp_use_rs3 = 1'b1;
                    fp_format_d = (IF_ID_instruction[26:25] == 2'b01);
                    fp_rounding_mode = funct3;

                    if ((IF_ID_instruction[26:25] != 2'b00) && (IF_ID_instruction[26:25] != 2'b01)) begin
                        exception = 1'b1;
                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                        exception_tval = IF_ID_instruction;
                    end
                    else begin
                        case (opcode)
                            7'b1000011: fp_operation = FP_FMADD;
                            7'b1000111: fp_operation = FP_FMSUB;
                            7'b1001011: fp_operation = FP_FNMSUB;
                            7'b1001111: fp_operation = FP_FNMADD;
                            default: fp_operation = FP_FMADD;
                        endcase
                    end



                end


                // FLOATING POINT LOAD / STORE

                // Supports FLW, FLD, FSW, and FSD.

                OPCODE_LOAD_FP: begin

                    fp_instruction = 1'b1;
                    fp_mem_read = 1'b1;
                    fp_reg_write = 1'b1;
                    fp_format_d = (funct3 == 3'b011);
                    use_rs1 = 1'b1;
                    alu_src_immediate = 1'b1;
                    alu_control = ALU_ADD;

                    case (funct3)
                        3'b010: mem_size = MEM_WORD;
                        3'b011: mem_size = MEM_DOUBLE;
                        default: begin
                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;
                        end
                    endcase

                end


                OPCODE_STORE_FP: begin

                    fp_instruction = 1'b1;
                    fp_mem_write = 1'b1;
                    fp_format_d = (funct3 == 3'b011);
                    fp_use_rs2 = 1'b1;
                    use_rs1 = 1'b1;
                    alu_src_immediate = 1'b1;
                    alu_control = ALU_ADD;

                    case (funct3)
                        3'b010: mem_size = MEM_WORD;
                        3'b011: mem_size = MEM_DOUBLE;
                        default: begin
                            exception = 1'b1;
                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                            exception_tval = IF_ID_instruction;
                        end
                    endcase
                end


                // FLOATING POINT OPERATIONS

                // The F and D extensions use the same floating point execution unit with S or D selected by the format field.

                OPCODE_OP_FP: begin

                    fp_instruction = 1'b1;
                    fp_format_d = (funct7[1:0] == 2'b01);
                    fp_rounding_mode = funct3;

                    if ((funct7[1:0] != 2'b00) && (funct7[1:0] != 2'b01)) begin
                        exception = 1'b1;
                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                        exception_tval = IF_ID_instruction;
                    end

                    else begin

                        case (funct7[6:2])

                            5'b00000: begin
                                fp_operation = FP_ADD;
                                fp_reg_write = 1'b1;
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                            end

                            5'b00001: begin
                                fp_operation = FP_SUB;
                                fp_reg_write = 1'b1;
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                            end

                            5'b00010: begin
                                fp_operation = FP_MUL;
                                fp_reg_write = 1'b1;
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                            end

                            5'b00011: begin
                                fp_operation = FP_DIV;
                                fp_reg_write = 1'b1;
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                            end

                            5'b01011: begin
                                if (rs2 != 5'd0) begin
                                    exception = 1'b1;
                                    exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                    exception_tval = IF_ID_instruction;
                                end
                                else begin
                                    fp_operation = FP_SQRT;
                                    fp_reg_write = 1'b1;
                                    fp_use_rs1 = 1'b1;
                                end
                            end

                            5'b00100: begin
                                fp_reg_write = 1'b1;
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                                case (funct3)
                                    3'b000: fp_operation = FP_SGNJ;
                                    3'b001: fp_operation = FP_SGNJN;
                                    3'b010: fp_operation = FP_SGNJX;
                                    default: begin
                                        exception = 1'b1;
                                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                        exception_tval = IF_ID_instruction;
                                    end
                                endcase
                            end

                            5'b00101: begin
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                                case (funct3)
                                    3'b000: begin fp_operation = FP_MIN; fp_reg_write = 1'b1; end
                                    3'b001: begin fp_operation = FP_MAX; fp_reg_write = 1'b1; end
                                    default: begin
                                        exception = 1'b1;
                                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                        exception_tval = IF_ID_instruction;
                                    end
                                endcase
                            end

                            5'b10100: begin
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b1;
                                case (funct3)

                                    3'b010: begin fp_operation = FP_FEQ; fp_to_int = 1'b1; reg_write = 1'b1; end
                                    3'b001: begin fp_operation = FP_FLT; fp_to_int = 1'b1; reg_write = 1'b1; end
                                    3'b000: begin fp_operation = FP_FLE; fp_to_int = 1'b1; reg_write = 1'b1; end
                                    
                                    
                                    default: begin
                                        exception = 1'b1;
                                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                        exception_tval = IF_ID_instruction;
                                    end
                                endcase
                            end

                            5'b11100: begin
                                fp_use_rs1 = 1'b1;
                                case (funct3)
                                    3'b000: begin
                                        if (rs2 == 5'd0) begin
                                            fp_operation = fp_format_d ? FP_MV_X_D : FP_MV_X_W;
                                            fp_to_int = 1'b1;
                                            reg_write = 1'b1;
                                        end
                                        else begin
                                            exception = 1'b1;
                                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                            exception_tval = IF_ID_instruction;
                                        end
                                    end
                                    3'b001: begin
                                        if (rs2 == 5'd0) begin fp_operation = FP_FCLASS; fp_to_int = 1'b1; reg_write = 1'b1; end
                                        else begin
                                            exception = 1'b1;
                                            exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                            exception_tval = IF_ID_instruction;
                                        end
                                    end
                                    default: begin
                                        exception = 1'b1;
                                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                        exception_tval = IF_ID_instruction;
                                    end
                                endcase
                            end

                            5'b11000: begin
                                fp_use_rs1 = 1'b1;
                                fp_to_int = 1'b1;
                                reg_write = 1'b1;
                                case (rs2)
                                    5'b00000: fp_operation = FP_CVT_W;
                                    5'b00001: fp_operation = FP_CVT_WU;
                                    5'b00010: fp_operation = FP_CVT_L;
                                    5'b00011: fp_operation = FP_CVT_LU;
                                    default: begin
                                        exception = 1'b1;
                                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                        exception_tval = IF_ID_instruction;
                                    end
                                endcase
                            end

                            5'b11010: begin
                                fp_reg_write = 1'b1;
                                use_rs1 = 1'b1;
                                case (rs2)

                                    5'b00000: fp_operation = FP_CVT_FROM_W;
                                    5'b00001: fp_operation = FP_CVT_FROM_WU;
                                    5'b00010: fp_operation = FP_CVT_FROM_L;
                                    5'b00011: fp_operation = FP_CVT_FROM_LU;
                                    default: begin
                                        exception = 1'b1;
                                        exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                        exception_tval = IF_ID_instruction;
                                    end
                                endcase
                            end

                            5'b11110: begin
                                use_rs1 = 1'b1;
                                if ((funct3 == 3'b000) && (rs2 == 5'd0)) begin
                                    fp_reg_write = 1'b1;
                                    fp_operation = FP_MV_W_X;
                                    if (fp_format_d)
                                        fp_operation = FP_MV_D_X;
                                end
                                else begin
                                    exception = 1'b1;
                                    exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                    exception_tval = IF_ID_instruction;
                                end
                            end

                            5'b01000: begin
                                fp_use_rs1 = 1'b1;
                                fp_use_rs2 = 1'b0;
                                if (fp_format_d) begin
                                    fp_operation = FP_CVT_D_S;
                                    fp_reg_write = 1'b1;
                                end
                                else begin
                                    fp_operation = FP_CVT_S_D;
                                    fp_reg_write = 1'b1;
                                end
                            end

                            default: begin
                                exception = 1'b1;
                                exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                                exception_tval = IF_ID_instruction;
                            end

                        endcase

                    end

                end


                default: begin
                    exception = 1'b1;
                    exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                    exception_tval = IF_ID_instruction;
                end

            endcase

        end

    end


    // ID / EX PIPELINE REGISTER

    // Holds decoded register values and control signals before the execute stage.

    reg ID_EX_valid;
    reg [XLEN-1:0] ID_EX_pc;
    reg [XLEN-1:0] ID_EX_rs1_data;
    reg [XLEN-1:0] ID_EX_rs2_data;
    reg [XLEN-1:0] ID_EX_immediate;
    reg [2:0] ID_EX_instruction_length;
    reg [XLEN-1:0] ID_EX_predicted_next_pc;

    reg [4:0] ID_EX_rs1;
    reg [4:0] ID_EX_rs2;
    reg [4:0] ID_EX_rd;
    reg [2:0] ID_EX_funct3;
    reg [6:0] ID_EX_funct7;
    reg [6:0] ID_EX_opcode;

    reg ID_EX_reg_write;
    reg ID_EX_mem_write;
    reg ID_EX_mem_read;
    reg ID_EX_alu_src_immediate;
    reg ID_EX_branch;
    reg ID_EX_jump;
    reg ID_EX_jump_register;
    reg [4:0] ID_EX_alu_control;

    reg ID_EX_is_m_instruction;
    reg ID_EX_is_atomic_instruction;
    reg ID_EX_is_lr;
    reg ID_EX_is_sc;
    reg ID_EX_atomic_write;
    reg [4:0] ID_EX_atomic_operation;
    reg ID_EX_atomic_word;

    reg ID_EX_csr_instruction;
    reg ID_EX_csr_write;
    reg [2:0] ID_EX_csr_op;
    reg [11:0] ID_EX_csr_address;
    reg [4:0] ID_EX_csr_zimm;
    reg [XLEN-1:0] ID_EX_csr_old_data;

    reg ID_EX_mret;
    reg ID_EX_sret;

    reg ID_EX_exception;
    reg [XLEN-1:0] ID_EX_exception_cause;
    reg [XLEN-1:0] ID_EX_exception_tval;

    reg [1:0] ID_EX_mem_size;
    reg ID_EX_mem_unsigned;
    reg ID_EX_fence_instruction;
    reg ID_EX_fence_i_instruction;

    reg [1:0] ID_EX_result_select;

    reg ID_EX_fp_instruction;
    reg ID_EX_fp_reg_write;
    reg ID_EX_fp_to_int;
    reg ID_EX_fp_mem_read;
    reg ID_EX_fp_mem_write;
    reg ID_EX_fp_use_rs1;
    reg ID_EX_fp_use_rs2;
    reg ID_EX_fp_use_rs3;
    reg ID_EX_fp_format_d;
    reg [4:0] ID_EX_fp_operation;
    reg [2:0] ID_EX_fp_rounding_mode;
    reg [63:0] ID_EX_fp_rs1_data;
    reg [63:0] ID_EX_fp_rs2_data;
    reg [63:0] ID_EX_fp_rs3_data;
    reg [63:0] ID_EX_fp_store_data;
    reg [4:0] ID_EX_fp_rd;


    // FORWARDING

    // Forwarding allows an ALU result to be used before it reaches the register file.

    reg [XLEN-1:0] forwarded_rs1_data;
    reg [XLEN-1:0] forwarded_rs2_data;

    always @(*) begin

        forwarded_rs1_data = ID_EX_rs1_data;
        forwarded_rs2_data = ID_EX_rs2_data;

        // EX/MEM forwarding

        if (EX_MEM_valid && EX_MEM_reg_write && (EX_MEM_rd != 5'd0) && !EX_MEM_mem_read && !EX_MEM_is_atomic_instruction) begin

            if (EX_MEM_rd == ID_EX_rs1)
                forwarded_rs1_data = EX_MEM_result;

            if (EX_MEM_rd == ID_EX_rs2)
                forwarded_rs2_data = EX_MEM_result;

        end

        // MEM/WB forwarding

        if (MEM_WB_valid && MEM_WB_reg_write && (MEM_WB_rd != 5'd0)) begin

            if ((MEM_WB_rd == ID_EX_rs1) && !(EX_MEM_valid && EX_MEM_reg_write && (EX_MEM_rd == ID_EX_rs1) && !EX_MEM_mem_read && !EX_MEM_is_atomic_instruction))
                forwarded_rs1_data = MEM_WB_write_data;

            if ((MEM_WB_rd == ID_EX_rs2) && !(EX_MEM_valid && EX_MEM_reg_write && (EX_MEM_rd == ID_EX_rs2) && !EX_MEM_mem_read && !EX_MEM_is_atomic_instruction))
                forwarded_rs2_data = MEM_WB_write_data;

        end

    end


    // CSR EXECUTE

    // Calculates the value written to the selected CSR.

    reg [XLEN-1:0] csr_write_data_ex;

    always @(*) begin

        csr_write_data_ex = ID_EX_csr_old_data;

        case (ID_EX_csr_op)

            // CSRRW
            3'b001: csr_write_data_ex = forwarded_rs1_data;

            // CSRRS
            3'b010: csr_write_data_ex = ID_EX_csr_old_data | forwarded_rs1_data;

            // CSRRC
            3'b011: csr_write_data_ex = ID_EX_csr_old_data & ~forwarded_rs1_data;

            // CSRRWI
            3'b101: csr_write_data_ex = {{(XLEN-5){1'b0}}, ID_EX_csr_zimm};

            // CSRRSI
            3'b110: csr_write_data_ex = ID_EX_csr_old_data | {{(XLEN-5){1'b0}}, ID_EX_csr_zimm};

            // CSRRCI
            3'b111: csr_write_data_ex = ID_EX_csr_old_data & ~{{(XLEN-5){1'b0}}, ID_EX_csr_zimm};

            default: csr_write_data_ex = ID_EX_csr_old_data;

        endcase

    end


    // FLOATING POINT EXECUTION

    // The floating point unit implements the F and D arithmetic and conversion instructions.

    wire [63:0] fp_execute_result;
    wire [XLEN-1:0] fp_integer_result;
    wire [4:0] fp_exception_flags;

    RV64GC_FP_UNIT fp_unit (
        .operation(ID_EX_fp_operation),
        .format_d(ID_EX_fp_format_d),
        .rounding_mode(ID_EX_fp_rounding_mode),
        .rs1_data(ID_EX_fp_rs1_data),
        .rs2_data(ID_EX_fp_rs2_data),
        .rs3_data(ID_EX_fp_rs3_data),
        .integer_data(forwarded_rs1_data),
        .fp_result(fp_execute_result),
        .integer_result(fp_integer_result),
        .exception_flags(fp_exception_flags)
    );


    // ALU INPUTS

    wire [XLEN-1:0] alu_input_a;
    wire [XLEN-1:0] alu_input_b;

    assign alu_input_a = forwarded_rs1_data;
    assign alu_input_b =
        ID_EX_is_atomic_instruction ? {XLEN{1'b0}} :
        ID_EX_alu_src_immediate ? ID_EX_immediate :
        forwarded_rs2_data;


    // ALU

    reg [XLEN-1:0] alu_result;
    reg [31:0] alu_word_result;

    always @(*) begin

        alu_result = {XLEN{1'b0}};
        alu_word_result = 32'b0;

        case (ID_EX_alu_control)

            ALU_ADD: alu_result = alu_input_a + alu_input_b;

            ALU_SUB: alu_result = alu_input_a - alu_input_b;

            ALU_SLL: alu_result = alu_input_a << alu_input_b[SHIFT_WIDTH-1:0];

            ALU_SLT: alu_result = ($signed(alu_input_a) < $signed(alu_input_b)) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};

            ALU_SLTU: alu_result = (alu_input_a < alu_input_b) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};

            ALU_XOR: alu_result = alu_input_a ^ alu_input_b;

            ALU_SRL: alu_result = alu_input_a >> alu_input_b[SHIFT_WIDTH-1:0];

            ALU_SRA: alu_result = $signed(alu_input_a) >>> alu_input_b[SHIFT_WIDTH-1:0];

            ALU_OR: alu_result = alu_input_a | alu_input_b;

            ALU_AND: alu_result = alu_input_a & alu_input_b;

            ALU_ADDW: begin
                alu_word_result = alu_input_a[31:0] + alu_input_b[31:0];
                alu_result = {{32{alu_word_result[31]}}, alu_word_result};
            end

            ALU_SUBW: begin
                alu_word_result = alu_input_a[31:0] - alu_input_b[31:0];
                alu_result = {{32{alu_word_result[31]}}, alu_word_result};
            end

            ALU_SLLW: begin
                alu_word_result = alu_input_a[31:0] << alu_input_b[4:0];
                alu_result = {{32{alu_word_result[31]}}, alu_word_result};
            end

            ALU_SRLW: begin
                alu_word_result = alu_input_a[31:0] >> alu_input_b[4:0];
                alu_result = {{32{alu_word_result[31]}}, alu_word_result};
            end

            ALU_SRAW: begin
                alu_word_result = $signed(alu_input_a[31:0]) >>> alu_input_b[4:0];
                alu_result = {{32{alu_word_result[31]}}, alu_word_result};
            end

            default: alu_result = {XLEN{1'b0}};

        endcase

    end


    // M EXTENSION

    // Implements the RISC-V M multiply and divide instructions.

    reg [XLEN-1:0] m_result;
    reg signed [(2*XLEN)-1:0] signed_multiply;
    reg signed [(2*XLEN)-1:0] signed_multiply_hsu;
    reg [(2*XLEN)-1:0] unsigned_multiply;
    reg [31:0] m_word_result;

    always @(*) begin

        signed_multiply =
            $signed({{XLEN{forwarded_rs1_data[XLEN-1]}}, forwarded_rs1_data}) *
            $signed({{XLEN{forwarded_rs2_data[XLEN-1]}}, forwarded_rs2_data});

        signed_multiply_hsu =
            $signed({{XLEN{forwarded_rs1_data[XLEN-1]}}, forwarded_rs1_data}) *
            $signed({{XLEN{1'b0}}, forwarded_rs2_data});

        unsigned_multiply =
            {{XLEN{1'b0}}, forwarded_rs1_data} *
            {{XLEN{1'b0}}, forwarded_rs2_data};

        m_result = {XLEN{1'b0}};
        m_word_result = 32'b0;

        if (ID_EX_opcode == OPCODE_OP_32) begin

            case (ID_EX_funct3)

                // MULW
                3'b000: m_word_result = $signed(forwarded_rs1_data[31:0]) * $signed(forwarded_rs2_data[31:0]);

                // DIVW
                3'b100: begin
                    if (forwarded_rs2_data[31:0] == 32'b0)
                        m_word_result = 32'hFFFFFFFF;
                    else if ((forwarded_rs1_data[31:0] == 32'h80000000) && (forwarded_rs2_data[31:0] == 32'hFFFFFFFF))
                        m_word_result = 32'h80000000;
                    else
                        m_word_result = $signed(forwarded_rs1_data[31:0]) / $signed(forwarded_rs2_data[31:0]);
                end

                // DIVUW
                3'b101: begin
                    if (forwarded_rs2_data[31:0] == 32'b0)
                        m_word_result = 32'hFFFFFFFF;
                    else
                        m_word_result = forwarded_rs1_data[31:0] / forwarded_rs2_data[31:0];
                end

                // REMW
                3'b110: begin
                    if (forwarded_rs2_data[31:0] == 32'b0)
                        m_word_result = forwarded_rs1_data[31:0];
                    else if ((forwarded_rs1_data[31:0] == 32'h80000000) && (forwarded_rs2_data[31:0] == 32'hFFFFFFFF))
                        m_word_result = 32'b0;
                    else
                        m_word_result = $signed(forwarded_rs1_data[31:0]) % $signed(forwarded_rs2_data[31:0]);
                end

                // REMUW
                3'b111: begin
                    if (forwarded_rs2_data[31:0] == 32'b0)
                        m_word_result = forwarded_rs1_data[31:0];
                    else
                        m_word_result = forwarded_rs1_data[31:0] % forwarded_rs2_data[31:0];
                end

                default: m_word_result = 32'b0;

            endcase

            m_result = {{32{m_word_result[31]}}, m_word_result};

        end

        else begin

            case (ID_EX_funct3)

                // MUL
                3'b000: m_result = signed_multiply[XLEN-1:0];

                // MULH
                3'b001: m_result = signed_multiply[(2*XLEN)-1:XLEN];

                // MULHSU
                3'b010: m_result = signed_multiply_hsu[(2*XLEN)-1:XLEN];

                // MULHU
                3'b011: m_result = unsigned_multiply[(2*XLEN)-1:XLEN];

                // DIV
                3'b100: begin
                    if (forwarded_rs2_data == {XLEN{1'b0}})
                        m_result = {XLEN{1'b1}};
                    else if ((forwarded_rs1_data == {1'b1, {(XLEN-1){1'b0}}}) && (forwarded_rs2_data == {XLEN{1'b1}}))
                        m_result = {1'b1, {(XLEN-1){1'b0}}};
                    else
                        m_result = $signed(forwarded_rs1_data) / $signed(forwarded_rs2_data);
                end

                // DIVU
                3'b101: begin
                    if (forwarded_rs2_data == {XLEN{1'b0}})
                        m_result = {XLEN{1'b1}};
                    else
                        m_result = forwarded_rs1_data / forwarded_rs2_data;
                end

                // REM
                3'b110: begin
                    if (forwarded_rs2_data == {XLEN{1'b0}})
                        m_result = forwarded_rs1_data;
                    else if ((forwarded_rs1_data == {1'b1, {(XLEN-1){1'b0}}}) && (forwarded_rs2_data == {XLEN{1'b1}}))
                        m_result = {XLEN{1'b0}};
                    else
                        m_result = $signed(forwarded_rs1_data) % $signed(forwarded_rs2_data);
                end

                // REMU
                3'b111: begin
                    if (forwarded_rs2_data == {XLEN{1'b0}})
                        m_result = forwarded_rs1_data;
                    else
                        m_result = forwarded_rs1_data % forwarded_rs2_data;
                end

                default: m_result = {XLEN{1'b0}};

            endcase

        end

    end


    // ATOMIC MEMORY OPERATION

    // The atomic instructions read a memory word, calculate a new value, and write the new value back as one atomic operation in this CPU.

    // Atomic rs2 data is taken from the current architectural register value with
    // the same forwarding priority used by normal integer operations.  Reading
    // the register file here avoids carrying a stale decode copy through a long
    // sequence of AMO instructions.

    wire [XLEN-1:0] atomic_rs2_execute_data;

    assign atomic_rs2_execute_data =
        (EX_MEM_valid && EX_MEM_reg_write && (EX_MEM_rd != 5'd0) &&
         !EX_MEM_mem_read && !EX_MEM_is_atomic_instruction && (EX_MEM_rd == ID_EX_rs2)) ? EX_MEM_result :
        (MEM_WB_valid && MEM_WB_reg_write && (MEM_WB_rd != 5'd0) &&
         (MEM_WB_rd == ID_EX_rs2)) ? MEM_WB_write_data :
        ((ID_EX_rs2 == 5'd0) ? {XLEN{1'b0}} : registers[ID_EX_rs2]);

    wire [XLEN-1:0] atomic_address;
    wire [XLEN-1:0] atomic_memory_data;
    reg [XLEN-1:0] atomic_result;
    reg [XLEN-1:0] atomic_old_value;
    reg atomic_sc_success;
    reg [31:0] atomic_word_old;
    reg [31:0] atomic_word_new;
    reg [XLEN-1:0] atomic_full_new_value;

    assign atomic_address = EX_MEM_atomic_address;
    assign atomic_memory_data = data_memory[atomic_address[DMEM_ADDR_WIDTH+2:3]];

    always @(*) begin

        atomic_old_value = atomic_memory_data;
        atomic_result = atomic_memory_data;
        atomic_sc_success = 1'b0;
        atomic_word_old = atomic_address[2] ? atomic_memory_data[63:32] : atomic_memory_data[31:0];
        atomic_word_new = atomic_word_old;
        atomic_full_new_value = atomic_memory_data;

        if (EX_MEM_is_sc) begin

            if (reservation_valid && (reservation_address == atomic_address))
                atomic_sc_success = 1'b1;

            atomic_result = atomic_sc_success ? {{(XLEN-1){1'b0}}, 1'b0} : {{(XLEN-1){1'b0}}, 1'b1};

        end

        else if (EX_MEM_is_lr) begin

            if (EX_MEM_atomic_word)
                atomic_old_value = {{32{atomic_word_old[31]}}, atomic_word_old};
            else
                atomic_old_value = atomic_memory_data;

            atomic_result = atomic_old_value;

        end

        else begin

            if (EX_MEM_atomic_word) begin

                case (EX_MEM_atomic_operation)
                    ATOMIC_ADD: atomic_word_new = atomic_word_old + EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_SWAP: atomic_word_new = EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_XOR: atomic_word_new = atomic_word_old ^ EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_OR: atomic_word_new = atomic_word_old | EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_AND: atomic_word_new = atomic_word_old & EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_MIN: atomic_word_new = ($signed(atomic_word_old) < $signed(EX_MEM_atomic_rs2_data[31:0])) ? atomic_word_old : EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_MAX: atomic_word_new = ($signed(atomic_word_old) > $signed(EX_MEM_atomic_rs2_data[31:0])) ? atomic_word_old : EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_MINU: atomic_word_new = (atomic_word_old < EX_MEM_atomic_rs2_data[31:0]) ? atomic_word_old : EX_MEM_atomic_rs2_data[31:0];
                    ATOMIC_MAXU: atomic_word_new = (atomic_word_old > EX_MEM_atomic_rs2_data[31:0]) ? atomic_word_old : EX_MEM_atomic_rs2_data[31:0];
                    default: atomic_word_new = atomic_word_old;
                endcase

                if (atomic_address[2])
                    atomic_full_new_value = {atomic_word_new, atomic_memory_data[31:0]};
                else
                    atomic_full_new_value = {atomic_memory_data[63:32], atomic_word_new};

                atomic_old_value = {{32{atomic_word_old[31]}}, atomic_word_old};
                atomic_result = atomic_full_new_value;

            end

            else begin

                // AMO.D returns the old memory value while writing the calculated new value.

                atomic_old_value = atomic_memory_data;

                case (EX_MEM_atomic_operation)
                    ATOMIC_ADD: begin
                        atomic_full_new_value = atomic_memory_data + EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_SWAP: begin
                        atomic_full_new_value = EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_XOR: begin
                        atomic_full_new_value = atomic_memory_data ^ EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_OR: begin
                        atomic_full_new_value = atomic_memory_data | EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_AND: begin
                        atomic_full_new_value = atomic_memory_data & EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_MIN: begin
                        atomic_full_new_value = ($signed(atomic_memory_data) < $signed(EX_MEM_atomic_rs2_data)) ? atomic_memory_data : EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_MAX: begin
                        atomic_full_new_value = ($signed(atomic_memory_data) > $signed(EX_MEM_atomic_rs2_data)) ? atomic_memory_data : EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_MINU: begin
                        atomic_full_new_value = (atomic_memory_data < EX_MEM_atomic_rs2_data) ? atomic_memory_data : EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    ATOMIC_MAXU: begin
                        atomic_full_new_value = (atomic_memory_data > EX_MEM_atomic_rs2_data) ? atomic_memory_data : EX_MEM_atomic_rs2_data;
                        atomic_result = atomic_memory_data;
                    end

                    default: begin
                        atomic_full_new_value = atomic_memory_data;
                        atomic_result = atomic_memory_data;
                    end
                endcase

            end

        end

    end


    // BRANCH COMPARISON

    // Checks if the branch condition is true.

    // Branches read the most recent committed register value directly, with the same execute-stage forwarding priority used by the normal ALU path.
    // This prevents a branch from using a stale ID/EX copy after a short loop has reached write back.

    wire [XLEN-1:0] branch_rs1_data;
    wire [XLEN-1:0] branch_rs2_data;
    reg branch_taken;

    // The branch hazard unit already stalls a branch until all older register writers have left the pipeline.  Read the committed register file here instead of applying a second forwarding network to the branch compare.
    // This prevents the branch from comparing against a stale or wrong-path forwarded value while a short loop is being resolved.

    assign branch_rs1_data = forwarded_rs1_data;
    assign branch_rs2_data = forwarded_rs2_data;

    always @(*) begin

        branch_taken = 1'b0;

        if (ID_EX_branch) begin

            case (ID_EX_funct3)

                // BEQ
                3'b000: branch_taken = (branch_rs1_data == branch_rs2_data);

                // BNE
                3'b001: branch_taken = (branch_rs1_data != branch_rs2_data);

                // BLT
                3'b100: branch_taken = ($signed(branch_rs1_data) < $signed(branch_rs2_data));

                // BGE
                3'b101: branch_taken = ($signed(branch_rs1_data) >= $signed(branch_rs2_data));

                // BLTU
                3'b110: branch_taken = (branch_rs1_data < branch_rs2_data);

                // BGEU
                3'b111: branch_taken = (branch_rs1_data >= branch_rs2_data);

                default: branch_taken = 1'b0;

            endcase

        end

    end


    // NEXT PROGRAM COUNTER

    // Normally the PC increases by the current instruction length.

    // For a branch or jump the PC changes to the target address instead.

    reg [XLEN-1:0] sequential_next_pc;
    reg [XLEN-1:0] actual_next_pc;

    always @(*) begin

        sequential_next_pc = ID_EX_pc + {{(XLEN-3){1'b0}}, ID_EX_instruction_length};
        actual_next_pc = sequential_next_pc;

        if (ID_EX_branch && branch_taken)
            actual_next_pc = ID_EX_pc + ID_EX_immediate;

        if (ID_EX_jump)
            actual_next_pc = ID_EX_pc + ID_EX_immediate;

        if (ID_EX_jump_register)
            actual_next_pc = (forwarded_rs1_data + ID_EX_immediate) & {{(XLEN-1){1'b1}}, 1'b0};

        if (ID_EX_mret)
            actual_next_pc = mepc;

        if (ID_EX_sret)
            actual_next_pc = sepc;

    end


    // MEMORY ALIGNMENT CHECK

    // Checks the effective address in the execute stage before a memory operation reaches the memory stage.

    wire execute_misaligned_exception;
    wire [XLEN-1:0] execute_exception_cause;
    wire [XLEN-1:0] execute_exception_tval;

    assign execute_misaligned_exception =
        ID_EX_valid &&
        (
            ((ID_EX_mem_read || ID_EX_mem_write || ID_EX_fp_mem_read || ID_EX_fp_mem_write) &&
             (((ID_EX_mem_size == MEM_HALF) && alu_result[0]) ||
              ((ID_EX_mem_size == MEM_WORD) && (|alu_result[1:0])) ||
              ((ID_EX_mem_size == MEM_DOUBLE) && (|alu_result[2:0])))) ||
            (ID_EX_is_atomic_instruction &&
             ((ID_EX_atomic_word && (|alu_result[1:0])) ||
              (!ID_EX_atomic_word && (|alu_result[2:0]))) )
        );

    assign execute_exception_cause = execute_misaligned_exception ?
        ((ID_EX_mem_write || ID_EX_fp_mem_write || ID_EX_is_sc) ? CAUSE_STORE_ADDR_MISALIGNED : CAUSE_LOAD_ADDR_MISALIGNED) :
        ID_EX_exception_cause;

    assign execute_exception_tval = execute_misaligned_exception ? alu_result : ID_EX_exception_tval;


    // BRANCH PREDICTOR

    // A small 16-entry branch target buffer with 2-bit saturating counters is used to predict conditional branches.

    reg btb_valid [0:15];
    reg [XLEN-1:0] btb_pc [0:15];
    reg [XLEN-1:0] btb_target [0:15];
    reg [1:0] btb_counter [0:15];

    wire [3:0] btb_index_fetch;
    wire btb_hit_fetch;
    wire btb_predict_taken_fetch;
    reg [XLEN-1:0] fetch_sequential_pc;
    reg [XLEN-1:0] fetch_predict_next_pc;
    reg [XLEN-1:0] fetch_branch_target;

    assign btb_index_fetch = pc[5:2];
    assign btb_hit_fetch = btb_valid[btb_index_fetch] && (btb_pc[btb_index_fetch] == pc);
    assign btb_predict_taken_fetch = btb_hit_fetch && (btb_counter[btb_index_fetch] == 2'b11) &&
                                     (btb_target[btb_index_fetch] != pc);

    always @(*) begin

        fetch_sequential_pc = pc + {{(XLEN-3){1'b0}}, fetched_instruction_length};
        fetch_branch_target = pc + {{(XLEN-13){fetched_instruction[31]}}, fetched_instruction[31], fetched_instruction[7], fetched_instruction[30:25], fetched_instruction[11:8], 1'b0};
        fetch_predict_next_pc = fetch_sequential_pc;

        if (fetched_instruction[6:0] == OPCODE_JAL) begin
            fetch_predict_next_pc = pc + {{(XLEN-21){fetched_instruction[31]}}, fetched_instruction[31], fetched_instruction[19:12], fetched_instruction[20], fetched_instruction[30:21], 1'b0};
        end

        else if (fetched_instruction[6:0] == OPCODE_BRANCH) begin

            if (btb_predict_taken_fetch)
                fetch_predict_next_pc = btb_target[btb_index_fetch];

        end

    end

    wire branch_mispredict;
    wire forced_illegal_instruction;
    wire direct_fetch_compressed_illegal;
    wire [XLEN-1:0] current_exception_cause;
    wire [XLEN-1:0] current_exception_tval;
    wire [XLEN-1:0] current_exception_pc;

    assign branch_mispredict = ID_EX_branch && (ID_EX_predicted_next_pc != actual_next_pc);

    // 0x0000 is an illegal compressed instruction.  It is converted to
    // 0xFFFFFFFF during fetch, which gives an otherwise unused major opcode.
    // Treat that opcode as an illegal instruction directly in execute as a
    // second safety net so the trap does not depend on compressed decoder timing.
    assign forced_illegal_instruction = ID_EX_valid && (ID_EX_opcode == 7'b1111111);

    // When the pipeline is empty, a compressed illegal instruction can be
    // trapped directly from the fetch stage.  This handles the first illegal
    // instruction after reset without depending on a later pipeline stage.
    assign direct_fetch_compressed_illegal =
        fetched_compressed_illegal &&
        !IF_ID_valid &&
        !ID_EX_valid &&
        !EX_MEM_valid &&
        !MEM_WB_valid;

    assign current_exception_cause = direct_fetch_compressed_illegal ?
        {{(XLEN-5){1'b0}}, CAUSE_ILLEGAL_INSTRUCTION} : execute_exception_cause;

    assign current_exception_tval = direct_fetch_compressed_illegal ?
        {{(XLEN-16){1'b0}}, compressed_instruction} : execute_exception_tval;

    assign current_exception_pc = direct_fetch_compressed_illegal ?
        pc : ID_EX_pc;


    // EXECUTE RESULT

    // Selects the result that will continue to the memory and write back stages.

    reg [XLEN-1:0] execute_result;

    always @(*) begin

        if (ID_EX_exception) begin
            execute_result = {XLEN{1'b0}};
        end

        else if (ID_EX_fp_instruction) begin

            if (ID_EX_fp_to_int)
                execute_result = fp_integer_result;
            else
                execute_result = fp_execute_result;

        end

        else if (ID_EX_csr_instruction) begin
            execute_result = ID_EX_csr_old_data;
        end

        else if (ID_EX_is_m_instruction) begin
            execute_result = m_result;
        end

        else begin

            case (ID_EX_result_select)

                // ALU result
                2'b00: execute_result = alu_result;

                // Memory address
                2'b01: execute_result = alu_result;

                // PC + instruction length
                2'b10: execute_result = sequential_next_pc;

                // PC + immediate
                2'b11: begin
                    if (ID_EX_opcode == OPCODE_LUI)
                        execute_result = ID_EX_immediate;
                    else
                        execute_result = ID_EX_pc + ID_EX_immediate;
                end

                default: execute_result = alu_result;

            endcase

        end

    end


    // EX / MEM PIPELINE REGISTER

    // Holds the execution result and memory control signals before the memory stage.

    reg EX_MEM_valid;
    reg [XLEN-1:0] EX_MEM_result;
    reg [XLEN-1:0] EX_MEM_store_data;
    reg [4:0] EX_MEM_rd;

    reg EX_MEM_reg_write;
    reg EX_MEM_mem_write;
    reg EX_MEM_mem_read;
    reg [1:0] EX_MEM_mem_size;
    reg EX_MEM_mem_unsigned;

    reg EX_MEM_is_m_instruction;
    reg EX_MEM_is_atomic_instruction;
    reg EX_MEM_is_lr;
    reg EX_MEM_is_sc;
    reg EX_MEM_atomic_write;
    reg [4:0] EX_MEM_atomic_operation;
    reg EX_MEM_atomic_word;
    reg [XLEN-1:0] EX_MEM_atomic_address;
    reg [XLEN-1:0] EX_MEM_atomic_rs2_data;

    reg EX_MEM_csr_instruction;
    reg EX_MEM_csr_write;
    reg [11:0] EX_MEM_csr_address;
    reg [XLEN-1:0] EX_MEM_csr_write_data;

    reg EX_MEM_fp_instruction;
    reg EX_MEM_fp_reg_write;
    reg EX_MEM_fp_to_int;
    reg EX_MEM_fp_mem_read;
    reg EX_MEM_fp_mem_write;
    reg EX_MEM_fp_format_d;
    reg [63:0] EX_MEM_fp_store_data;
    reg [4:0] EX_MEM_fp_rd;
    reg [4:0] EX_MEM_fp_exception_flags;

    // Debug aliases for the current pipeline values

    wire [XLEN-1:0] alu_result_register;
    wire [XLEN-1:0] memory_address_register;

    assign alu_result_register = EX_MEM_result;
    assign memory_address_register = EX_MEM_result;


    // DATA MEMORY

    // The ALU calculates the address used to access the data memory.

    wire data_memory_mmio_mtime;
    wire data_memory_mmio_mtimecmp;
    wire data_memory_mmio_msip;

    assign data_memory_mmio_mtime = (EX_MEM_result == MTIME_ADDR);
    assign data_memory_mmio_mtimecmp = (EX_MEM_result == MTIMECMP_ADDR);
    assign data_memory_mmio_msip = (EX_MEM_result == MSIP_ADDR);

    // Read data from memory

    reg [XLEN-1:0] memory_read_data;

    always @(*) begin

        memory_read_data = {XLEN{1'b0}};

        if (data_memory_mmio_mtime) begin
            memory_read_data = {{(XLEN-64){1'b0}}, mtime};
        end

        else if (data_memory_mmio_mtimecmp) begin
            memory_read_data = {{(XLEN-64){1'b0}}, mtimecmp};
        end

        else if (data_memory_mmio_msip) begin
            memory_read_data = {{(XLEN-1){1'b0}}, software_interrupt};
        end

        else begin

            case (EX_MEM_mem_size)

                MEM_BYTE: begin
                    if (EX_MEM_mem_unsigned)
                        memory_read_data = {{(XLEN-8){1'b0}}, data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:0]*8) +: 8]};
                    else
                        memory_read_data = {{(XLEN-8){data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:0]*8)+7]}}, data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:0]*8) +: 8]};
                end

                MEM_HALF: begin
                    if (EX_MEM_mem_unsigned)
                        memory_read_data = {{(XLEN-16){1'b0}}, data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:1]*16) +: 16]};
                    else
                        memory_read_data = {{(XLEN-16){data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:1]*16)+15]}}, data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:1]*16) +: 16]};
                end

                MEM_WORD: begin
                    if (EX_MEM_mem_unsigned)
                        memory_read_data = {{(XLEN-32){1'b0}}, data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2]*32) +: 32]};
                    else
                        memory_read_data = {{(XLEN-32){data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2]*32)+31]}}, data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2]*32) +: 32]};
                end

                MEM_DOUBLE: begin
                    memory_read_data = data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]];
                end

                default: memory_read_data = {XLEN{1'b0}};

            endcase

        end

    end


    // MEMORY DATA REGISTER

    // Holds memory data before the write back cycle

    reg [XLEN-1:0] memory_data_register;


    // MEM / WB PIPELINE REGISTER

    // Holds the final result before it is written to the register file.

    reg MEM_WB_valid;
    reg [XLEN-1:0] MEM_WB_write_data;
    reg [4:0] MEM_WB_rd;
    reg MEM_WB_reg_write;

    reg MEM_WB_csr_write;
    reg [11:0] MEM_WB_csr_address;
    reg [XLEN-1:0] MEM_WB_csr_write_data;

    reg MEM_WB_fp_reg_write;
    reg MEM_WB_fp_to_int;
    reg [63:0] MEM_WB_fp_write_data;
    reg [4:0] MEM_WB_fp_rd;
    reg [4:0] MEM_WB_fp_exception_flags;
    reg MEM_WB_fp_format_d;


    // WRITE BACK FORWARDING

    // Allows an instruction entering the decode stage to see a value written back on the same clock edge.

    wire [XLEN-1:0] decode_rs1_data;
    wire [XLEN-1:0] decode_rs2_data;
    wire [63:0] decode_fp_rs1_data;
    wire [63:0] decode_fp_rs2_data;
    wire [63:0] decode_fp_rs3_data;

    assign decode_rs1_data =
        (MEM_WB_valid && MEM_WB_reg_write && (MEM_WB_rd != 5'd0) && (MEM_WB_rd == rs1)) ? MEM_WB_write_data :
        rs1_data;

    assign decode_rs2_data =
        (MEM_WB_valid && MEM_WB_reg_write && (MEM_WB_rd != 5'd0) && (MEM_WB_rd == rs2)) ? MEM_WB_write_data :
        rs2_data;

    assign decode_fp_rs1_data =
        (MEM_WB_valid && MEM_WB_fp_reg_write && (MEM_WB_fp_rd == rs1)) ? MEM_WB_fp_write_data :
        fp_rs1_data;

    assign decode_fp_rs2_data =
        (MEM_WB_valid && MEM_WB_fp_reg_write && (MEM_WB_fp_rd == rs2)) ? MEM_WB_fp_write_data :
        fp_rs2_data;

    assign decode_fp_rs3_data =
        (MEM_WB_valid && MEM_WB_fp_reg_write && (MEM_WB_fp_rd == rs3)) ? MEM_WB_fp_write_data :
        fp_rs3_data;


    // HAZARD DETECTION

    // Detects when an instruction in the decode stage needs a result that is not yet available.

    reg load_use_stall;

    always @(*) begin

        load_use_stall = 1'b0;

        if (IF_ID_valid && ID_EX_valid && ID_EX_reg_write && (ID_EX_rd != 5'd0)) begin

            if (ID_EX_mem_read || ID_EX_is_atomic_instruction) begin

                if (use_rs1 && (ID_EX_rd == rs1))
                    load_use_stall = 1'b1;

                if (use_rs2 && (ID_EX_rd == rs2))
                    load_use_stall = 1'b1;

            end

        end

    end


    // BRANCH DATA HAZARD DETECTION

    // Conditional branches are resolved in the execute stage.
    // Stall a branch while an older instruction is still carrying a value for one of its source registers.
    // This is conservative, but it guarantees that branch comparisons cannot use a stale register value.

    reg branch_data_hazard_stall;

    always @(*) begin

        branch_data_hazard_stall = 1'b0;

        if (IF_ID_valid && (opcode == OPCODE_BRANCH)) begin

            // ALU results are forwarded into the execute stage, so a branch only
            // needs an explicit stall when the older instruction is a load or
            // atomic operation whose result is not available in EX.

            if (ID_EX_valid && ID_EX_reg_write && (ID_EX_rd != 5'd0) &&
                (ID_EX_mem_read || ID_EX_is_atomic_instruction)) begin

                if ((ID_EX_rd == rs1) || (ID_EX_rd == rs2))
                    branch_data_hazard_stall = 1'b1;

            end

        end

    end


    // FLOATING POINT HAZARD DETECTION

    // Floating point instructions are stalled until earlier floating point results reach write back.

    reg fp_hazard_stall;

    always @(*) begin

        fp_hazard_stall = 1'b0;

        if (IF_ID_valid && (fp_instruction || fp_mem_read || fp_mem_write)) begin

            if (fp_use_rs1) begin
                if (ID_EX_valid && ID_EX_fp_reg_write && (ID_EX_fp_rd != 5'd0) && (ID_EX_fp_rd == rs1))
                    fp_hazard_stall = 1'b1;
                if (EX_MEM_valid && EX_MEM_fp_reg_write && (EX_MEM_fp_rd != 5'd0) && (EX_MEM_fp_rd == rs1))
                    fp_hazard_stall = 1'b1;
                if (MEM_WB_valid && MEM_WB_fp_reg_write && (MEM_WB_fp_rd != 5'd0) && (MEM_WB_fp_rd == rs1))
                    fp_hazard_stall = 1'b1;
            end

            if (fp_use_rs2) begin
                if (ID_EX_valid && ID_EX_fp_reg_write && (ID_EX_fp_rd != 5'd0) && (ID_EX_fp_rd == rs2))
                    fp_hazard_stall = 1'b1;
                if (EX_MEM_valid && EX_MEM_fp_reg_write && (EX_MEM_fp_rd != 5'd0) && (EX_MEM_fp_rd == rs2))
                    fp_hazard_stall = 1'b1;
                if (MEM_WB_valid && MEM_WB_fp_reg_write && (MEM_WB_fp_rd != 5'd0) && (MEM_WB_fp_rd == rs2))
                    fp_hazard_stall = 1'b1;
            end

            if (fp_use_rs3) begin
                if (ID_EX_valid && ID_EX_fp_reg_write && (ID_EX_fp_rd != 5'd0) && (ID_EX_fp_rd == rs3))
                    fp_hazard_stall = 1'b1;
                if (EX_MEM_valid && EX_MEM_fp_reg_write && (EX_MEM_fp_rd != 5'd0) && (EX_MEM_fp_rd == rs3))
                    fp_hazard_stall = 1'b1;
                if (MEM_WB_valid && MEM_WB_fp_reg_write && (MEM_WB_fp_rd != 5'd0) && (MEM_WB_fp_rd == rs3))
                    fp_hazard_stall = 1'b1;
            end

        end

    end


    // CSR SERIALIZATION

    // CSR operations are serialized so that privileged state changes are visible before a following system instruction.

    reg csr_serialization_stall;

    always @(*) begin

        csr_serialization_stall = 1'b0;

        if (IF_ID_valid && (opcode == OPCODE_SYSTEM)) begin

            if (ID_EX_csr_instruction)
                csr_serialization_stall = 1'b1;

            if (EX_MEM_csr_instruction)
                csr_serialization_stall = 1'b1;

            if (MEM_WB_csr_write)
                csr_serialization_stall = 1'b1;

        end

    end


    // TIMER AND INTERRUPT LOGIC

    wire [XLEN-1:0] interrupt_machine_pending;
    wire [XLEN-1:0] interrupt_supervisor_pending;
    wire interrupt_machine_enabled;
    wire interrupt_supervisor_enabled;
    wire interrupt_pending;
    wire interrupt_to_supervisor;
    wire [4:0] interrupt_cause;
    reg interrupt_draining;
    reg debug_interrupt_taken_reg;

    assign interrupt_machine_pending =
        ((mip_value[MIP_MEIP] && mie[MIP_MEIP] && !mideleg[MIP_MEIP]) ? (64'd1 << INTERRUPT_M_EXTERNAL) : {XLEN{1'b0}}) |
        ((mip_value[MIP_MTIP] && mie[MIP_MTIP] && !mideleg[MIP_MTIP]) ? (64'd1 << INTERRUPT_M_TIMER) : {XLEN{1'b0}}) |
        ((mip_value[MIP_MSIP] && mie[MIP_MSIP] && !mideleg[MIP_MSIP]) ? (64'd1 << INTERRUPT_M_SOFTWARE) : {XLEN{1'b0}});

    assign interrupt_supervisor_pending =
        ((mip_value[MIP_SEIP] && mie[MIP_SEIP]) ? (64'd1 << INTERRUPT_S_EXTERNAL) : {XLEN{1'b0}}) |
        ((mip_value[MIP_STIP] && mie[MIP_STIP]) ? (64'd1 << INTERRUPT_S_TIMER) : {XLEN{1'b0}}) |
        ((mip_value[MIP_SSIP] && mie[MIP_SSIP]) ? (64'd1 << INTERRUPT_S_SOFTWARE) : {XLEN{1'b0}});

    assign interrupt_machine_enabled = (current_mode == PRIV_M) ? mstatus[MSTATUS_MIE] : 1'b1;
    assign interrupt_supervisor_enabled = (current_mode == PRIV_S) ? mstatus[MSTATUS_SIE] : 1'b1;

    assign interrupt_to_supervisor =
        (current_mode != PRIV_M) &&
        interrupt_supervisor_enabled &&
        (interrupt_supervisor_pending != {XLEN{1'b0}}) &&
        ((interrupt_machine_pending == {XLEN{1'b0}}) || !interrupt_machine_enabled);

    assign interrupt_pending =
        (interrupt_machine_enabled && (interrupt_machine_pending != {XLEN{1'b0}})) ||
        ((current_mode != PRIV_M) && interrupt_supervisor_enabled && (interrupt_supervisor_pending != {XLEN{1'b0}}));

    assign interrupt_cause =
        interrupt_to_supervisor ?
            (interrupt_supervisor_pending[INTERRUPT_S_EXTERNAL] ? INTERRUPT_S_EXTERNAL :
             interrupt_supervisor_pending[INTERRUPT_S_SOFTWARE] ? INTERRUPT_S_SOFTWARE :
             INTERRUPT_S_TIMER) :
            (interrupt_machine_pending[INTERRUPT_M_EXTERNAL] ? INTERRUPT_M_EXTERNAL :
             interrupt_machine_pending[INTERRUPT_M_SOFTWARE] ? INTERRUPT_M_SOFTWARE :
             INTERRUPT_M_TIMER);


    // CPU SEQUENTIAL LOGIC

    // The PC, register file, CSR file, timer, and pipeline registers are updated on the rising edge of the clock

    integer i;
    integer j;
    integer k;

    always @(posedge clk) begin

        if (rst) begin

            // Reset the PC

            pc <= {XLEN{1'b0}};

            // Reset the pipeline registers

            IF_ID_valid <= 1'b0;
            IF_ID_pc <= {XLEN{1'b0}};
            IF_ID_instruction <= 32'h00000013;
            IF_ID_instruction_length <= 3'd4;
            IF_ID_compressed_illegal <= 1'b0;
            IF_ID_compressed_instruction <= 16'b0;
            IF_ID_predicted_next_pc <= {XLEN{1'b0}};

            ID_EX_valid <= 1'b0;
            ID_EX_pc <= {XLEN{1'b0}};
            ID_EX_rs1_data <= {XLEN{1'b0}};
            ID_EX_rs2_data <= {XLEN{1'b0}};
            ID_EX_immediate <= {XLEN{1'b0}};
            ID_EX_instruction_length <= 3'd4;
            ID_EX_predicted_next_pc <= {XLEN{1'b0}};
            ID_EX_rs1 <= 5'd0;
            ID_EX_rs2 <= 5'd0;
            ID_EX_rd <= 5'd0;
            ID_EX_funct3 <= 3'b000;
            ID_EX_funct7 <= 7'b0000000;
            ID_EX_opcode <= OPCODE_OP_IMM;

            ID_EX_reg_write <= 1'b0;
            ID_EX_mem_write <= 1'b0;
            ID_EX_mem_read <= 1'b0;
            ID_EX_alu_src_immediate <= 1'b0;
            ID_EX_branch <= 1'b0;
            ID_EX_jump <= 1'b0;
            ID_EX_jump_register <= 1'b0;
            ID_EX_alu_control <= ALU_ADD;
            ID_EX_is_m_instruction <= 1'b0;
            ID_EX_is_atomic_instruction <= 1'b0;
            ID_EX_is_lr <= 1'b0;
            ID_EX_is_sc <= 1'b0;
            ID_EX_atomic_write <= 1'b0;
            ID_EX_atomic_operation <= ATOMIC_ADD;
            ID_EX_atomic_word <= 1'b0;

            ID_EX_csr_instruction <= 1'b0;
            ID_EX_csr_write <= 1'b0;
            ID_EX_csr_op <= 3'b000;
            ID_EX_csr_address <= 12'b0;
            ID_EX_csr_zimm <= 5'b0;
            ID_EX_csr_old_data <= {XLEN{1'b0}};

            ID_EX_mret <= 1'b0;
            ID_EX_sret <= 1'b0;

            ID_EX_exception <= 1'b0;
            ID_EX_exception_cause <= {XLEN{1'b0}};
            ID_EX_exception_tval <= {XLEN{1'b0}};

            ID_EX_mem_size <= MEM_DOUBLE;
            ID_EX_mem_unsigned <= 1'b0;
            ID_EX_fence_instruction <= 1'b0;
            ID_EX_fence_i_instruction <= 1'b0;
            ID_EX_result_select <= 2'b00;

            ID_EX_fp_instruction <= 1'b0;
            ID_EX_fp_reg_write <= 1'b0;
            ID_EX_fp_to_int <= 1'b0;
            ID_EX_fp_mem_read <= 1'b0;
            ID_EX_fp_mem_write <= 1'b0;
            ID_EX_fp_use_rs1 <= 1'b0;
            ID_EX_fp_use_rs2 <= 1'b0;
            ID_EX_fp_use_rs3 <= 1'b0;
            ID_EX_fp_format_d <= 1'b0;
            ID_EX_fp_operation <= FP_ADD;
            ID_EX_fp_rounding_mode <= 3'b000;
            ID_EX_fp_rs1_data <= 64'hFFFFFFFF7FC00000;
            ID_EX_fp_rs2_data <= 64'hFFFFFFFF7FC00000;
            ID_EX_fp_rs3_data <= 64'hFFFFFFFF7FC00000;
            ID_EX_fp_store_data <= 64'b0;
            ID_EX_fp_rd <= 5'd0;

            EX_MEM_valid <= 1'b0;
            EX_MEM_result <= {XLEN{1'b0}};
            EX_MEM_store_data <= {XLEN{1'b0}};
            EX_MEM_rd <= 5'd0;
            EX_MEM_reg_write <= 1'b0;
            EX_MEM_mem_write <= 1'b0;
            EX_MEM_mem_read <= 1'b0;
            EX_MEM_mem_size <= MEM_DOUBLE;
            EX_MEM_mem_unsigned <= 1'b0;

            EX_MEM_is_m_instruction <= 1'b0;
            EX_MEM_is_atomic_instruction <= 1'b0;
            EX_MEM_is_lr <= 1'b0;
            EX_MEM_is_sc <= 1'b0;
            EX_MEM_atomic_write <= 1'b0;
            EX_MEM_atomic_operation <= ATOMIC_ADD;
            EX_MEM_atomic_word <= 1'b0;
            EX_MEM_atomic_address <= {XLEN{1'b0}};
            EX_MEM_atomic_rs2_data <= {XLEN{1'b0}};

            EX_MEM_csr_instruction <= 1'b0;
            EX_MEM_csr_write <= 1'b0;
            EX_MEM_csr_address <= 12'b0;
            EX_MEM_csr_write_data <= {XLEN{1'b0}};

            EX_MEM_fp_instruction <= 1'b0;
            EX_MEM_fp_reg_write <= 1'b0;
            EX_MEM_fp_to_int <= 1'b0;
            EX_MEM_fp_mem_read <= 1'b0;
            EX_MEM_fp_mem_write <= 1'b0;
            EX_MEM_fp_format_d <= 1'b0;
            EX_MEM_fp_store_data <= 64'b0;
            EX_MEM_fp_rd <= 5'd0;
            EX_MEM_fp_exception_flags <= 5'b0;

            memory_data_register <= {XLEN{1'b0}};

            MEM_WB_valid <= 1'b0;
            MEM_WB_write_data <= {XLEN{1'b0}};
            MEM_WB_rd <= 5'd0;
            MEM_WB_reg_write <= 1'b0;

            MEM_WB_csr_write <= 1'b0;
            MEM_WB_csr_address <= 12'b0;
            MEM_WB_csr_write_data <= {XLEN{1'b0}};

            MEM_WB_fp_reg_write <= 1'b0;
            MEM_WB_fp_to_int <= 1'b0;
            MEM_WB_fp_write_data <= 64'b0;
            MEM_WB_fp_rd <= 5'd0;
            MEM_WB_fp_exception_flags <= 5'b0;
            MEM_WB_fp_format_d <= 1'b0;

            // Reset all registers

            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= {XLEN{1'b0}};
                fregisters[i] <= 64'hFFFFFFFF00000000;
            end

            // Reset floating point status

            fflags <= 5'b0;
            frm <= 3'b000;

            // Reset the atomic reservation

            reservation_valid <= 1'b0;
            reservation_address <= {XLEN{1'b0}};

            // Reset branch predictor

            for (j = 0; j < 16; j = j + 1) begin
                btb_valid[j] <= 1'b0;
                btb_pc[j] <= {XLEN{1'b0}};
                btb_target[j] <= {XLEN{1'b0}};
                btb_counter[j] <= 2'b01;
            end

            // Reset machine timer

            mtime <= 64'b0;
            mtimecmp <= 64'hFFFFFFFFFFFFFFFF;

            interrupt_draining <= 1'b0;
            debug_interrupt_taken_reg <= 1'b0;

            // Reset privileged architecture

            current_mode <= PRIV_M;

            mstatus <= {XLEN{1'b0}};
            misa <= 64'h800000000000112D;
            medeleg <= {XLEN{1'b0}};
            mideleg <= {XLEN{1'b0}};
            mie <= {XLEN{1'b0}};
            mtvec <= {XLEN{1'b0}};
            mscratch <= {XLEN{1'b0}};
            mepc <= {XLEN{1'b0}};
            mcause <= {XLEN{1'b0}};
            mtval <= {XLEN{1'b0}};

            stvec <= {XLEN{1'b0}};
            sscratch <= {XLEN{1'b0}};
            sepc <= {XLEN{1'b0}};
            scause <= {XLEN{1'b0}};
            stval <= {XLEN{1'b0}};
            satp <= {XLEN{1'b0}};

        end

        else begin

            // MACHINE TIMER

            // mtime advances every clock cycle.

            mtime <= mtime + 64'd1;

            // WRITE BACK

            // Write the selected CSR after the instruction reaches the write back stage.

            if (MEM_WB_valid && MEM_WB_csr_write) begin

                case (MEM_WB_csr_address)

                    CSR_FFLAGS: fflags <= MEM_WB_csr_write_data[4:0];
                    CSR_FRM: frm <= MEM_WB_csr_write_data[2:0];
                    CSR_FCSR: begin
                        fflags <= MEM_WB_csr_write_data[4:0];
                        frm <= MEM_WB_csr_write_data[7:5];
                    end

                    CSR_SSTATUS: begin
                        mstatus[MSTATUS_SIE] <= MEM_WB_csr_write_data[MSTATUS_SIE];
                        mstatus[MSTATUS_SPIE] <= MEM_WB_csr_write_data[MSTATUS_SPIE];
                        mstatus[MSTATUS_SPP] <= MEM_WB_csr_write_data[MSTATUS_SPP];
                    end

                    CSR_SIE: begin
                        mie[MIP_SSIP] <= MEM_WB_csr_write_data[MIP_SSIP];
                        mie[MIP_STIP] <= MEM_WB_csr_write_data[MIP_STIP];
                        mie[MIP_SEIP] <= MEM_WB_csr_write_data[MIP_SEIP];
                    end
                    CSR_STVEC: stvec <= {MEM_WB_csr_write_data[XLEN-1:2], MEM_WB_csr_write_data[1:0]};
                    CSR_SSCRATCH: sscratch <= MEM_WB_csr_write_data;
                    CSR_SEPC: sepc <= MEM_WB_csr_write_data;
                    CSR_STVAL: stval <= MEM_WB_csr_write_data;
                    CSR_SATP: satp <= MEM_WB_csr_write_data;

                    CSR_MSTATUS: mstatus <= MEM_WB_csr_write_data;
                    CSR_MEDELEG: medeleg <= MEM_WB_csr_write_data;
                    CSR_MIDELEG: mideleg <= MEM_WB_csr_write_data;
                    CSR_MIE: mie <= MEM_WB_csr_write_data;
                    CSR_MTVEC: mtvec <= {MEM_WB_csr_write_data[XLEN-1:2], MEM_WB_csr_write_data[1:0]};
                    CSR_MSCRATCH: mscratch <= MEM_WB_csr_write_data;
                    CSR_MEPC: mepc <= MEM_WB_csr_write_data;
                    CSR_MCAUSE: mcause <= MEM_WB_csr_write_data;
                    CSR_MTVAL: mtval <= MEM_WB_csr_write_data;

                    default: begin
                    end

                endcase

            end

            // x0 cannot be written because it must always contain zero

            if (MEM_WB_valid && MEM_WB_reg_write && (MEM_WB_rd != 5'd0))
                registers[MEM_WB_rd] <= MEM_WB_write_data;

            // Write floating point results back into the floating point register file.

            if (MEM_WB_valid && MEM_WB_fp_reg_write)
                fregisters[MEM_WB_fp_rd] <= MEM_WB_fp_write_data;

            // Floating point exception flags are sticky.

            if (MEM_WB_valid && (MEM_WB_fp_exception_flags != 5'b0))
                fflags <= fflags | MEM_WB_fp_exception_flags;

            // TIMER MMIO WRITEBACK

            if (EX_MEM_valid && EX_MEM_mem_write && (EX_MEM_result == MTIME_ADDR))
                mtime <= EX_MEM_store_data[63:0];

            if (EX_MEM_valid && EX_MEM_mem_write && (EX_MEM_result == MTIMECMP_ADDR))
                mtimecmp <= EX_MEM_store_data[63:0];

            // MEMORY

            // Move the current memory result into the write back pipeline register.

            MEM_WB_valid <= EX_MEM_valid;
            MEM_WB_rd <= EX_MEM_rd;
            MEM_WB_reg_write <= EX_MEM_reg_write;

            MEM_WB_csr_write <= EX_MEM_csr_write;
            MEM_WB_csr_address <= EX_MEM_csr_address;
            MEM_WB_csr_write_data <= EX_MEM_csr_write_data;

            MEM_WB_fp_reg_write <= EX_MEM_fp_reg_write;
            MEM_WB_fp_to_int <= EX_MEM_fp_to_int;
            MEM_WB_fp_rd <= EX_MEM_fp_rd;
            MEM_WB_fp_exception_flags <= EX_MEM_fp_exception_flags;
            MEM_WB_fp_format_d <= EX_MEM_fp_format_d;

            if (EX_MEM_valid && EX_MEM_fp_mem_read) begin

                memory_data_register <= memory_read_data;

                if (EX_MEM_fp_format_d)
                    MEM_WB_fp_write_data <= memory_read_data;
                else
                    MEM_WB_fp_write_data <= {32'hFFFFFFFF, memory_read_data[31:0]};

            end

            else if (EX_MEM_valid && EX_MEM_mem_read) begin

                memory_data_register <= memory_read_data;
                MEM_WB_write_data <= memory_read_data;

            end

            else if (EX_MEM_valid && EX_MEM_fp_reg_write && !EX_MEM_fp_mem_read) begin

                MEM_WB_fp_write_data <= EX_MEM_result[63:0];

            end

            else if (EX_MEM_valid && EX_MEM_csr_instruction) begin

                MEM_WB_write_data <= EX_MEM_result;

            end

            else if (EX_MEM_valid && EX_MEM_is_atomic_instruction) begin

                // LR.W and LR.D read a memory word and create a reservation

                if (EX_MEM_is_lr) begin

                    memory_data_register <= atomic_old_value;
                    MEM_WB_write_data <= atomic_old_value;

                    reservation_valid <= 1'b1;
                    reservation_address <= EX_MEM_atomic_address;

                end

                // SC.W and SC.D store the data only when the reservation is still valid

                else if (EX_MEM_is_sc) begin

                    if (reservation_valid && (reservation_address == EX_MEM_atomic_address)) begin

                        if (EX_MEM_atomic_word) begin
                            if (EX_MEM_atomic_address[2])
                                data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+2:3]][63:32] <= EX_MEM_atomic_rs2_data[31:0];
                            else
                                data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+2:3]][31:0] <= EX_MEM_atomic_rs2_data[31:0];
                        end

                        else begin
                            data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+2:3]] <= EX_MEM_atomic_rs2_data;
                        end

                        MEM_WB_write_data <= {{(XLEN-1){1'b0}}, 1'b0};

                    end

                    else begin

                        MEM_WB_write_data <= {{(XLEN-1){1'b0}}, 1'b1};

                    end

                    reservation_valid <= 1'b0;

                end

                // AMO instructions always read and write the selected memory word

                else if (EX_MEM_atomic_write) begin

                    MEM_WB_write_data <= atomic_old_value;
                    data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+2:3]] <= atomic_full_new_value;
                    reservation_valid <= 1'b0;

                end

                else begin

                    MEM_WB_write_data <= {XLEN{1'b0}};

                end

            end

            else begin

                MEM_WB_write_data <= EX_MEM_result;

            end


            // Store data into memory

            if (EX_MEM_valid && EX_MEM_fp_mem_write) begin

                if (EX_MEM_mem_size == MEM_WORD)
                    data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2]*32) +: 32] <= EX_MEM_fp_store_data[31:0];
                else
                    data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]] <= EX_MEM_fp_store_data;

            end

            if (EX_MEM_valid && EX_MEM_mem_write && !data_memory_mmio_mtime && !data_memory_mmio_mtimecmp && !data_memory_mmio_msip) begin

                case (EX_MEM_mem_size)

                    MEM_BYTE: data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:0]*8) +: 8] <= EX_MEM_store_data[7:0];
                    MEM_HALF: data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2:1]*16) +: 16] <= EX_MEM_store_data[15:0];
                    MEM_WORD: data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]][(EX_MEM_result[2]*32) +: 32] <= EX_MEM_store_data[31:0];
                    MEM_DOUBLE: data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]] <= EX_MEM_store_data;
                    default: data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+2:3]] <= EX_MEM_store_data;

                endcase

            end

            // A normal store removes the reservation in this single-CPU implementation

            if (EX_MEM_valid && EX_MEM_mem_write)
                reservation_valid <= 1'b0;


            // EX / MEM

            EX_MEM_valid <= ID_EX_valid;
            EX_MEM_result <= execute_result;
            EX_MEM_store_data <= forwarded_rs2_data;
            EX_MEM_rd <= ID_EX_rd;

            EX_MEM_reg_write <= ID_EX_reg_write;
            EX_MEM_mem_write <= ID_EX_mem_write;
            EX_MEM_mem_read <= ID_EX_mem_read;
            EX_MEM_mem_size <= ID_EX_mem_size;
            EX_MEM_mem_unsigned <= ID_EX_mem_unsigned;

            EX_MEM_is_m_instruction <= ID_EX_is_m_instruction;
            EX_MEM_is_atomic_instruction <= ID_EX_is_atomic_instruction;
            EX_MEM_is_lr <= ID_EX_is_lr;
            EX_MEM_is_sc <= ID_EX_is_sc;
            EX_MEM_atomic_write <= ID_EX_atomic_write;
            EX_MEM_atomic_operation <= ID_EX_atomic_operation;
            EX_MEM_atomic_word <= ID_EX_atomic_word;
            EX_MEM_atomic_address <= alu_result;
            EX_MEM_atomic_rs2_data <= atomic_rs2_execute_data;

            EX_MEM_csr_instruction <= ID_EX_csr_instruction;
            EX_MEM_csr_write <= ID_EX_csr_write;
            EX_MEM_csr_address <= ID_EX_csr_address;
            EX_MEM_csr_write_data <= csr_write_data_ex;

            EX_MEM_fp_instruction <= ID_EX_fp_instruction;
            EX_MEM_fp_reg_write <= ID_EX_fp_reg_write;
            EX_MEM_fp_to_int <= ID_EX_fp_to_int;
            EX_MEM_fp_mem_read <= ID_EX_fp_mem_read;
            EX_MEM_fp_mem_write <= ID_EX_fp_mem_write;
            EX_MEM_fp_format_d <= ID_EX_fp_format_d;
            EX_MEM_fp_store_data <= ID_EX_fp_store_data;
            EX_MEM_fp_rd <= ID_EX_rd;
            EX_MEM_fp_exception_flags <= fp_exception_flags;


            // BRANCH PREDICTOR UPDATE

            if (ID_EX_valid && ID_EX_branch) begin

                btb_valid[ID_EX_pc[5:2]] <= 1'b1;
                btb_pc[ID_EX_pc[5:2]] <= ID_EX_pc;
                btb_target[ID_EX_pc[5:2]] <= ID_EX_pc + ID_EX_immediate;

                if (branch_taken) begin
                    if (btb_counter[ID_EX_pc[5:2]] != 2'b11)
                        btb_counter[ID_EX_pc[5:2]] <= btb_counter[ID_EX_pc[5:2]] + 1'b1;
                end

                else begin
                    if (btb_counter[ID_EX_pc[5:2]] != 2'b00)
                        btb_counter[ID_EX_pc[5:2]] <= btb_counter[ID_EX_pc[5:2]] - 1'b1;
                end

            end


            // CONTROL HAZARDS AND TRAPS

            debug_interrupt_taken_reg <= 1'b0;

            if (direct_fetch_compressed_illegal || ID_EX_exception || execute_misaligned_exception || forced_illegal_instruction) begin

                // Trap to the appropriate privileged mode and flush younger instructions.

                interrupt_draining <= 1'b0;

                EX_MEM_valid <= 1'b0;
                EX_MEM_reg_write <= 1'b0;
                EX_MEM_mem_write <= 1'b0;
                EX_MEM_mem_read <= 1'b0;
                EX_MEM_is_m_instruction <= 1'b0;
                EX_MEM_is_atomic_instruction <= 1'b0;
                EX_MEM_is_lr <= 1'b0;
                EX_MEM_is_sc <= 1'b0;
                EX_MEM_atomic_write <= 1'b0;
                EX_MEM_csr_instruction <= 1'b0;
                EX_MEM_csr_write <= 1'b0;

                IF_ID_valid <= 1'b0;
                IF_ID_pc <= {XLEN{1'b0}};
                IF_ID_instruction <= 32'h00000013;
                IF_ID_instruction_length <= 3'd4;
                IF_ID_compressed_illegal <= 1'b0;
                IF_ID_compressed_instruction <= 16'b0;
                IF_ID_predicted_next_pc <= {XLEN{1'b0}};

                ID_EX_valid <= 1'b0;
                ID_EX_reg_write <= 1'b0;
                ID_EX_mem_write <= 1'b0;
                ID_EX_mem_read <= 1'b0;
                ID_EX_branch <= 1'b0;
                ID_EX_jump <= 1'b0;
                ID_EX_jump_register <= 1'b0;
                ID_EX_is_m_instruction <= 1'b0;
                ID_EX_is_atomic_instruction <= 1'b0;
                ID_EX_is_lr <= 1'b0;
                ID_EX_is_sc <= 1'b0;
                ID_EX_atomic_write <= 1'b0;
                ID_EX_csr_instruction <= 1'b0;
                ID_EX_csr_write <= 1'b0;
                ID_EX_mret <= 1'b0;
                ID_EX_sret <= 1'b0;
                ID_EX_exception <= 1'b0;
                ID_EX_fp_instruction <= 1'b0;
                ID_EX_fp_reg_write <= 1'b0;
                ID_EX_fp_to_int <= 1'b0;
                ID_EX_fp_mem_read <= 1'b0;
                ID_EX_fp_mem_write <= 1'b0;
                ID_EX_fence_instruction <= 1'b0;
                ID_EX_fence_i_instruction <= 1'b0;

                if ((current_mode != PRIV_M) && medeleg[current_exception_cause[4:0]]) begin

                    sepc <= current_exception_pc;
                    scause <= current_exception_cause;
                    stval <= current_exception_tval;

                    mstatus[MSTATUS_SPIE] <= mstatus[MSTATUS_SIE];
                    mstatus[MSTATUS_SIE] <= 1'b0;
                    mstatus[MSTATUS_SPP] <= (current_mode == PRIV_S);

                    current_mode <= PRIV_S;
                    if (stvec[1:0] == 2'b01 && current_exception_cause[XLEN-1])
                        pc <= {stvec[XLEN-1:2], 2'b00} + ({{(XLEN-5){1'b0}}, current_exception_cause[4:0]} << 2);
                    else
                        pc <= {stvec[XLEN-1:2], 2'b00};

                end

                else begin

                    mepc <= current_exception_pc;
                    mcause <= current_exception_cause;
                    mtval <= current_exception_tval;

                    mstatus[MSTATUS_MPIE] <= mstatus[MSTATUS_MIE];
                    mstatus[MSTATUS_MIE] <= 1'b0;
                    mstatus[MSTATUS_MPP_HIGH:MSTATUS_MPP_LOW] <= current_mode;

                    current_mode <= PRIV_M;
                    if (mtvec[1:0] == 2'b01 && current_exception_cause[XLEN-1])
                        pc <= {mtvec[XLEN-1:2], 2'b00} + ({{(XLEN-5){1'b0}}, current_exception_cause[4:0]} << 2);
                    else
                        pc <= {mtvec[XLEN-1:2], 2'b00};

                end

            end

            else if (branch_mispredict || ID_EX_jump_register || ID_EX_mret || ID_EX_sret || ID_EX_fence_i_instruction) begin

                // Flush the instructions that were fetched after a wrong branch or control transfer.

                interrupt_draining <= 1'b0;
                pc <= actual_next_pc;

                if (branch_mispredict) begin
                    EX_MEM_valid <= 1'b0;
                    EX_MEM_reg_write <= 1'b0;
                    EX_MEM_mem_write <= 1'b0;
                    EX_MEM_mem_read <= 1'b0;
                    EX_MEM_is_m_instruction <= 1'b0;
                    EX_MEM_is_atomic_instruction <= 1'b0;
                    EX_MEM_is_lr <= 1'b0;
                    EX_MEM_is_sc <= 1'b0;
                    EX_MEM_atomic_write <= 1'b0;
                    EX_MEM_csr_instruction <= 1'b0;
                    EX_MEM_csr_write <= 1'b0;
                    EX_MEM_fp_instruction <= 1'b0;
                    EX_MEM_fp_reg_write <= 1'b0;
                    EX_MEM_fp_mem_read <= 1'b0;
                    EX_MEM_fp_mem_write <= 1'b0;
                end

                IF_ID_valid <= 1'b0;
                IF_ID_pc <= {XLEN{1'b0}};
                IF_ID_instruction <= 32'h00000013;
                IF_ID_instruction_length <= 3'd4;
                IF_ID_compressed_illegal <= 1'b0;
                IF_ID_compressed_instruction <= 16'b0;
                IF_ID_predicted_next_pc <= {XLEN{1'b0}};

                ID_EX_valid <= 1'b0;
                ID_EX_reg_write <= 1'b0;
                ID_EX_mem_write <= 1'b0;
                ID_EX_mem_read <= 1'b0;
                ID_EX_branch <= 1'b0;
                ID_EX_jump <= 1'b0;
                ID_EX_jump_register <= 1'b0;
                ID_EX_is_m_instruction <= 1'b0;
                ID_EX_is_atomic_instruction <= 1'b0;
                ID_EX_is_lr <= 1'b0;
                ID_EX_is_sc <= 1'b0;
                ID_EX_atomic_write <= 1'b0;
                ID_EX_csr_instruction <= 1'b0;
                ID_EX_csr_write <= 1'b0;
                ID_EX_mret <= 1'b0;
                ID_EX_sret <= 1'b0;
                ID_EX_exception <= 1'b0;
                ID_EX_fence_instruction <= 1'b0;
                ID_EX_fence_i_instruction <= 1'b0;

                // MRET

                if (ID_EX_mret) begin
                    current_mode <= mstatus[MSTATUS_MPP_HIGH:MSTATUS_MPP_LOW];
                    mstatus[MSTATUS_MIE] <= mstatus[MSTATUS_MPIE];
                    mstatus[MSTATUS_MPIE] <= 1'b1;
                    mstatus[MSTATUS_MPP_HIGH:MSTATUS_MPP_LOW] <= PRIV_U;
                end

                // SRET

                if (ID_EX_sret) begin
                    current_mode <= mstatus[MSTATUS_SPP] ? PRIV_S : PRIV_U;
                    mstatus[MSTATUS_SIE] <= mstatus[MSTATUS_SPIE];
                    mstatus[MSTATUS_SPIE] <= 1'b1;
                    mstatus[MSTATUS_SPP] <= 1'b0;
                end

            end

            else if (interrupt_draining) begin

                // Drain the pipeline before entering the interrupt handler.

                IF_ID_valid <= 1'b0;
                IF_ID_pc <= {XLEN{1'b0}};
                IF_ID_instruction <= 32'h00000013;
                IF_ID_instruction_length <= 3'd4;
                IF_ID_compressed_illegal <= 1'b0;
                IF_ID_compressed_instruction <= 16'b0;
                IF_ID_predicted_next_pc <= pc;

                if (!ID_EX_valid && !EX_MEM_valid && !MEM_WB_valid) begin

                    interrupt_draining <= 1'b0;
                    debug_interrupt_taken_reg <= 1'b1;
                    if (interrupt_to_supervisor) begin
                        if (stvec[1:0] == 2'b01)
                            pc <= {stvec[XLEN-1:2], 2'b00} + ({{(XLEN-5){1'b0}}, interrupt_cause} << 2);
                        else
                            pc <= {stvec[XLEN-1:2], 2'b00};
                    end
                    else begin
                        if (mtvec[1:0] == 2'b01)
                            pc <= {mtvec[XLEN-1:2], 2'b00} + ({{(XLEN-5){1'b0}}, interrupt_cause} << 2);
                        else
                            pc <= {mtvec[XLEN-1:2], 2'b00};
                    end

                    if (interrupt_to_supervisor) begin

                        sepc <= pc;
                        scause <= {1'b1, {(XLEN-1-5){1'b0}}, interrupt_cause};
                        stval <= {XLEN{1'b0}};

                        mstatus[MSTATUS_SPIE] <= mstatus[MSTATUS_SIE];
                        mstatus[MSTATUS_SIE] <= 1'b0;
                        mstatus[MSTATUS_SPP] <= (current_mode == PRIV_S);

                        current_mode <= PRIV_S;

                    end

                    else begin

                        mepc <= pc;
                        mcause <= {1'b1, {(XLEN-1-5){1'b0}}, interrupt_cause};
                        mtval <= {XLEN{1'b0}};

                        mstatus[MSTATUS_MPIE] <= mstatus[MSTATUS_MIE];
                        mstatus[MSTATUS_MIE] <= 1'b0;
                        mstatus[MSTATUS_MPP_HIGH:MSTATUS_MPP_LOW] <= current_mode;

                        current_mode <= PRIV_M;

                    end

                end

                else begin

                    ID_EX_valid <= 1'b0;
                    ID_EX_reg_write <= 1'b0;
                    ID_EX_mem_write <= 1'b0;
                    ID_EX_mem_read <= 1'b0;
                    ID_EX_branch <= 1'b0;
                    ID_EX_jump <= 1'b0;
                    ID_EX_jump_register <= 1'b0;
                    ID_EX_is_m_instruction <= 1'b0;
                    ID_EX_is_atomic_instruction <= 1'b0;
                    ID_EX_is_lr <= 1'b0;
                    ID_EX_is_sc <= 1'b0;
                    ID_EX_atomic_write <= 1'b0;
                    ID_EX_csr_instruction <= 1'b0;
                    ID_EX_csr_write <= 1'b0;
                    ID_EX_mret <= 1'b0;
                    ID_EX_sret <= 1'b0;
                    ID_EX_exception <= 1'b0;

                end

            end

            else if (interrupt_pending) begin

                // Stop fetching new instructions and drain the older pipeline stages before taking an interrupt.

                interrupt_draining <= 1'b1;
                IF_ID_valid <= 1'b0;
                IF_ID_pc <= {XLEN{1'b0}};
                IF_ID_instruction <= 32'h00000013;
                IF_ID_instruction_length <= 3'd4;
                IF_ID_compressed_illegal <= 1'b0;
                IF_ID_compressed_instruction <= 16'b0;
                IF_ID_predicted_next_pc <= pc;

            end

            else if (csr_serialization_stall) begin

                // Hold the system instruction in the decode stage until the previous CSR operation reaches write back.

                pc <= pc;

                IF_ID_valid <= IF_ID_valid;
                IF_ID_pc <= IF_ID_pc;
                IF_ID_instruction <= IF_ID_instruction;
                IF_ID_instruction_length <= IF_ID_instruction_length;
                IF_ID_compressed_illegal <= IF_ID_compressed_illegal;
                IF_ID_compressed_instruction <= IF_ID_compressed_instruction;
                IF_ID_predicted_next_pc <= IF_ID_predicted_next_pc;

                ID_EX_valid <= 1'b0;
                ID_EX_reg_write <= 1'b0;
                ID_EX_mem_write <= 1'b0;
                ID_EX_mem_read <= 1'b0;
                ID_EX_branch <= 1'b0;
                ID_EX_jump <= 1'b0;
                ID_EX_jump_register <= 1'b0;
                ID_EX_is_m_instruction <= 1'b0;
                ID_EX_is_atomic_instruction <= 1'b0;
                ID_EX_is_lr <= 1'b0;
                ID_EX_is_sc <= 1'b0;
                ID_EX_atomic_write <= 1'b0;
                ID_EX_csr_instruction <= 1'b0;
                ID_EX_csr_write <= 1'b0;
                ID_EX_mret <= 1'b0;
                ID_EX_sret <= 1'b0;
                ID_EX_exception <= 1'b0;

            end

            else if (branch_data_hazard_stall) begin

                // Hold the branch in the decode stage until its source registers are safe to compare.

                pc <= pc;

                IF_ID_valid <= IF_ID_valid;
                IF_ID_pc <= IF_ID_pc;
                IF_ID_instruction <= IF_ID_instruction;
                IF_ID_instruction_length <= IF_ID_instruction_length;
                IF_ID_compressed_illegal <= IF_ID_compressed_illegal;
                IF_ID_compressed_instruction <= IF_ID_compressed_instruction;
                IF_ID_predicted_next_pc <= IF_ID_predicted_next_pc;

                ID_EX_valid <= 1'b0;
                ID_EX_reg_write <= 1'b0;
                ID_EX_mem_write <= 1'b0;
                ID_EX_mem_read <= 1'b0;
                ID_EX_branch <= 1'b0;
                ID_EX_jump <= 1'b0;
                ID_EX_jump_register <= 1'b0;
                ID_EX_is_m_instruction <= 1'b0;
                ID_EX_is_atomic_instruction <= 1'b0;
                ID_EX_is_lr <= 1'b0;
                ID_EX_is_sc <= 1'b0;
                ID_EX_atomic_write <= 1'b0;
                ID_EX_csr_instruction <= 1'b0;
                ID_EX_csr_write <= 1'b0;
                ID_EX_mret <= 1'b0;
                ID_EX_sret <= 1'b0;
                ID_EX_exception <= 1'b0;
                ID_EX_fp_instruction <= 1'b0;
                ID_EX_fp_reg_write <= 1'b0;
                ID_EX_fp_to_int <= 1'b0;
                ID_EX_fp_mem_read <= 1'b0;
                ID_EX_fp_mem_write <= 1'b0;

            end

            else if (fp_hazard_stall) begin

                // Hold the floating point instruction in the decode stage and insert a bubble into execute.

                pc <= pc;

                IF_ID_valid <= IF_ID_valid;
                IF_ID_pc <= IF_ID_pc;
                IF_ID_instruction <= IF_ID_instruction;
                IF_ID_instruction_length <= IF_ID_instruction_length;
                IF_ID_compressed_illegal <= IF_ID_compressed_illegal;
                IF_ID_compressed_instruction <= IF_ID_compressed_instruction;
                IF_ID_predicted_next_pc <= IF_ID_predicted_next_pc;

                ID_EX_valid <= 1'b0;
                ID_EX_reg_write <= 1'b0;
                ID_EX_mem_write <= 1'b0;
                ID_EX_mem_read <= 1'b0;
                ID_EX_branch <= 1'b0;
                ID_EX_jump <= 1'b0;
                ID_EX_jump_register <= 1'b0;
                ID_EX_is_m_instruction <= 1'b0;
                ID_EX_is_atomic_instruction <= 1'b0;
                ID_EX_csr_instruction <= 1'b0;
                ID_EX_csr_write <= 1'b0;
                ID_EX_mret <= 1'b0;
                ID_EX_sret <= 1'b0;
                ID_EX_exception <= 1'b0;
                ID_EX_fp_instruction <= 1'b0;
                ID_EX_fp_reg_write <= 1'b0;
                ID_EX_fp_to_int <= 1'b0;
                ID_EX_fp_mem_read <= 1'b0;
                ID_EX_fp_mem_write <= 1'b0;

            end

            else if (load_use_stall) begin

                // Hold the instruction in the decode stage and insert a bubble into execute.

                pc <= pc;

                IF_ID_valid <= IF_ID_valid;
                IF_ID_pc <= IF_ID_pc;
                IF_ID_instruction <= IF_ID_instruction;
                IF_ID_instruction_length <= IF_ID_instruction_length;
                IF_ID_compressed_illegal <= IF_ID_compressed_illegal;
                IF_ID_compressed_instruction <= IF_ID_compressed_instruction;
                IF_ID_predicted_next_pc <= IF_ID_predicted_next_pc;

                ID_EX_valid <= 1'b0;
                ID_EX_reg_write <= 1'b0;
                ID_EX_mem_write <= 1'b0;
                ID_EX_mem_read <= 1'b0;
                ID_EX_branch <= 1'b0;
                ID_EX_jump <= 1'b0;
                ID_EX_jump_register <= 1'b0;
                ID_EX_is_m_instruction <= 1'b0;
                ID_EX_is_atomic_instruction <= 1'b0;
                ID_EX_is_lr <= 1'b0;
                ID_EX_is_sc <= 1'b0;
                ID_EX_atomic_write <= 1'b0;
                ID_EX_csr_instruction <= 1'b0;
                ID_EX_csr_write <= 1'b0;
                ID_EX_mret <= 1'b0;
                ID_EX_sret <= 1'b0;
                ID_EX_exception <= 1'b0;

            end

            else begin

                interrupt_draining <= 1'b0;

                // IF

                // Fetch the next instruction into the IF/ID pipeline register.

                IF_ID_valid <= 1'b1;
                IF_ID_pc <= pc;
                IF_ID_instruction <= fetched_instruction;
                IF_ID_instruction_length <= fetched_instruction_length;
                IF_ID_compressed_illegal <= fetched_compressed_illegal ||
                                              (fetched_instruction_compressed && (compressed_instruction == 16'h0000));
                IF_ID_compressed_instruction <= compressed_instruction;
                IF_ID_predicted_next_pc <= fetch_predict_next_pc;

                // The predicted next PC is selected in the fetch stage

                pc <= fetch_predict_next_pc;

                // ID

                // Save the decoded register values and control signals.

                ID_EX_valid <= IF_ID_valid;
                ID_EX_pc <= IF_ID_pc;
                ID_EX_rs1_data <= decode_rs1_data;
                ID_EX_rs2_data <= decode_rs2_data;
                ID_EX_immediate <= immediate;
                ID_EX_instruction_length <= IF_ID_instruction_length;
                ID_EX_predicted_next_pc <= IF_ID_predicted_next_pc;

                ID_EX_rs1 <= rs1;
                ID_EX_rs2 <= rs2;
                ID_EX_rd <= rd;
                ID_EX_funct3 <= funct3;
                ID_EX_funct7 <= funct7;
                ID_EX_opcode <= opcode;

                ID_EX_reg_write <= reg_write;
                ID_EX_mem_write <= mem_write;
                ID_EX_mem_read <= mem_read;
                ID_EX_alu_src_immediate <= alu_src_immediate;
                ID_EX_branch <= branch;
                ID_EX_jump <= jump;
                ID_EX_jump_register <= jump_register;
                ID_EX_alu_control <= alu_control;

                ID_EX_is_m_instruction <= is_m_instruction;
                ID_EX_is_atomic_instruction <= is_atomic_instruction;
                ID_EX_is_lr <= is_lr;
                ID_EX_is_sc <= is_sc;
                ID_EX_atomic_write <= atomic_write;
                ID_EX_atomic_operation <= atomic_operation;
                ID_EX_atomic_word <= atomic_word;

                ID_EX_csr_instruction <= csr_instruction_control;
                ID_EX_csr_write <= csr_write;
                ID_EX_csr_op <= csr_op;
                ID_EX_csr_address <= csr_addr_control;
                ID_EX_csr_zimm <= csr_zimm_control;
                ID_EX_csr_old_data <= csr_read_data;

                ID_EX_mret <= mret;
                ID_EX_sret <= sret;

                if (IF_ID_compressed_illegal ||
                    (IF_ID_instruction == 32'hFFFFFFFF) ||
                    ((IF_ID_instruction_length == 3'd2) && (IF_ID_compressed_instruction == 16'h0000))) begin
                    ID_EX_exception <= 1'b1;
                    ID_EX_exception_cause <= CAUSE_ILLEGAL_INSTRUCTION;
                    ID_EX_exception_tval <= {{(XLEN-16){1'b0}}, IF_ID_compressed_instruction};
                end
                else begin
                    ID_EX_exception <= exception;
                    ID_EX_exception_cause <= exception_cause;
                    ID_EX_exception_tval <= exception_tval;
                end

                ID_EX_mem_size <= mem_size;
                ID_EX_mem_unsigned <= mem_unsigned;
                ID_EX_fence_instruction <= fence_instruction;
                ID_EX_fence_i_instruction <= fence_i_instruction;
                ID_EX_result_select <= result_select;

                ID_EX_fp_instruction <= fp_instruction;
                ID_EX_fp_reg_write <= fp_reg_write;
                ID_EX_fp_to_int <= fp_to_int;
                ID_EX_fp_mem_read <= fp_mem_read;
                ID_EX_fp_mem_write <= fp_mem_write;
                ID_EX_fp_use_rs1 <= fp_use_rs1;
                ID_EX_fp_use_rs2 <= fp_use_rs2;
                ID_EX_fp_use_rs3 <= fp_use_rs3;
                ID_EX_fp_format_d <= fp_format_d;
                ID_EX_fp_operation <= fp_operation;
                ID_EX_fp_rounding_mode <= fp_rounding_mode;
                ID_EX_fp_rd <= rd;

                if (!fp_format_d && (fp_operation != FP_CVT_S_D) && (fp_rs1_data[63:32] != 32'hFFFFFFFF))
                    ID_EX_fp_rs1_data <= 64'hFFFFFFFF7FC00000;
                else
                    ID_EX_fp_rs1_data <= decode_fp_rs1_data;

                if (!fp_format_d && (fp_operation != FP_CVT_S_D) && (fp_rs2_data[63:32] != 32'hFFFFFFFF))
                    ID_EX_fp_rs2_data <= 64'hFFFFFFFF7FC00000;
                else
                    ID_EX_fp_rs2_data <= decode_fp_rs2_data;

                if (!fp_format_d && (fp_rs3_data[63:32] != 32'hFFFFFFFF))
                    ID_EX_fp_rs3_data <= 64'hFFFFFFFF7FC00000;
                else
                    ID_EX_fp_rs3_data <= decode_fp_rs3_data;
                ID_EX_fp_store_data <= decode_fp_rs2_data;

            end

            // Make sure x0 always stays zero

            registers[0] <= {XLEN{1'b0}};

        end

    end


    // MEMORY INITIALIZATION

    // Initialize instruction memory with NOP instructions

    // NOP = ADDI x0, x0, 0

    initial begin

        for (k = 0; k < IMEM_SIZE; k = k + 1)
            instruction_memory[k] = 32'h00000013;

        // Initialize data memory to zero

        for (k = 0; k < DMEM_SIZE; k = k + 1)
            data_memory[k] = {XLEN{1'b0}};

        // Example program:

        // ADDI x1, x0, 10
        // ADDI x2, x0, 20
        // ADD  x3, x1, x2
        // SD   x3, 0(x0)
        // LD   x4, 0(x0)

        // Result:

        // x1 = 10
        // x2 = 20
        // x3 = 30
        // x4 = 30

        instruction_memory[0] = 32'h00A00093;
        instruction_memory[1] = 32'h01400113;
        instruction_memory[2] = 32'h002081B3;
        instruction_memory[3] = 32'h00303023;
        instruction_memory[4] = 32'h00003203;

    end


    // DEBUG OUTPUTS

    // These signals can be used in the testbench and viewed in GTKWave

    assign debug_pc = pc;

    assign debug_instruction = IF_ID_instruction;

    assign debug_result = MEM_WB_write_data;

    assign debug_mtime = {{(XLEN-64){1'b0}}, mtime};

    assign debug_mtimecmp = {{(XLEN-64){1'b0}}, mtimecmp};

    assign debug_current_mode = current_mode;

    assign debug_mtip = timer_interrupt;

    assign debug_interrupt_taken = debug_interrupt_taken_reg;


endmodule // Ends the module (important)



// Floating point execution unit used by the RV64GC processor.

// The unit operates on IEEE-754 single and double precision bit patterns and keeps the datapath integer based so it can be synthesized with FPGA logic.

module RV64GC_FP_UNIT (

    input wire [4:0] operation,
    input wire format_d,
    input wire [2:0] rounding_mode,
    input wire [63:0] rs1_data,
    input wire [63:0] rs2_data,
    input wire [63:0] rs3_data,
    input wire [63:0] integer_data,

    output reg [63:0] fp_result,
    output reg [63:0] integer_result,
    output reg [4:0] exception_flags

);

    localparam [4:0] FP_ADD = 5'd0;
    localparam [4:0] FP_SUB = 5'd1;
    localparam [4:0] FP_MUL = 5'd2;
    localparam [4:0] FP_DIV = 5'd3;
    localparam [4:0] FP_SQRT = 5'd4;
    localparam [4:0] FP_SGNJ = 5'd5;
    localparam [4:0] FP_SGNJN = 5'd6;
    localparam [4:0] FP_SGNJX = 5'd7;
    localparam [4:0] FP_MIN = 5'd8;
    localparam [4:0] FP_MAX = 5'd9;
    localparam [4:0] FP_FEQ = 5'd10;
    localparam [4:0] FP_FLT = 5'd11;
    localparam [4:0] FP_FLE = 5'd12;
    localparam [4:0] FP_FCLASS = 5'd13;
    localparam [4:0] FP_CVT_W = 5'd14;
    localparam [4:0] FP_CVT_WU = 5'd15;
    localparam [4:0] FP_CVT_L = 5'd16;
    localparam [4:0] FP_CVT_LU = 5'd17;
    localparam [4:0] FP_CVT_FROM_W = 5'd18;
    localparam [4:0] FP_CVT_FROM_WU = 5'd19;
    localparam [4:0] FP_CVT_FROM_L = 5'd20;
    localparam [4:0] FP_CVT_FROM_LU = 5'd21;
    localparam [4:0] FP_MV_X_W = 5'd22;
    localparam [4:0] FP_MV_W_X = 5'd23;
    localparam [4:0] FP_CVT_S_D = 5'd24;
    localparam [4:0] FP_CVT_D_S = 5'd25;
    localparam [4:0] FP_MV_X_D = 5'd26;
    localparam [4:0] FP_MV_D_X = 5'd27;
    localparam [4:0] FP_FMADD = 5'd28;
    localparam [4:0] FP_FMSUB = 5'd29;
    localparam [4:0] FP_FNMSUB = 5'd30;
    localparam [4:0] FP_FNMADD = 5'd31;

    function is_nan32;
        input [31:0] a;
        begin is_nan32 = (&a[30:23]) && (a[22:0] != 0); end
    endfunction

    function is_inf32;
        input [31:0] a;
        begin is_inf32 = (&a[30:23]) && (a[22:0] == 0); end
    endfunction

    function is_zero32;
        input [31:0] a;
        begin is_zero32 = (a[30:0] == 0); end
    endfunction

    function is_nan64;
        input [63:0] a;
        begin is_nan64 = (&a[62:52]) && (a[51:0] != 0); end
    endfunction

    function is_inf64;
        input [63:0] a;
        begin is_inf64 = (&a[62:52]) && (a[51:0] == 0); end
    endfunction

    function is_zero64;
        input [63:0] a;
        begin is_zero64 = (a[62:0] == 0); end
    endfunction

    function [31:0] fp32_add_simple;

        input [31:0] a;
        input [31:0] b;
        input do_sub;

        reg sign_a, sign_b, sign_r;

        integer exp_a, exp_b, exp_r, diff;

        reg [23:0] ma, mb;
        reg [26:0] xa, xb;
        reg [27:0] sum;
        reg [23:0] main_sig;
        reg [7:0] exp_field;
        reg guard_bit, round_bit, sticky_bit, increment;

        integer i;

        begin

            sign_a = a[31];
            sign_b = b[31] ^ do_sub;

            if (is_nan32(a) || is_nan32(b)) begin
                fp32_add_simple = 32'h7FC00000;
            end

            else if (is_inf32(a) && is_inf32(b) && (sign_a != sign_b)) begin
                fp32_add_simple = 32'h7FC00000;
            end

            else if (is_inf32(a)) begin
                fp32_add_simple = a;
            end
            else if (is_inf32(b)) begin
                fp32_add_simple = b;
            end


            else if (is_zero32(a)) begin
                fp32_add_simple = b;
            end
            else if (is_zero32(b)) begin
                fp32_add_simple = a;
            end

            else begin

                exp_a = (a[30:23] == 0) ? -126 : a[30:23] - 127;
                exp_b = (b[30:23] == 0) ? -126 : b[30:23] - 127;

                ma = (a[30:23] == 0) ? {1'b0,a[22:0]} : {1'b1,a[22:0]};
                mb = (b[30:23] == 0) ? {1'b0,b[22:0]} : {1'b1,b[22:0]};

                xa = {ma,3'b000};
                xb = {mb,3'b000};

                if (exp_a < exp_b) begin

                    diff = exp_b - exp_a;
                    exp_r = exp_b;
                    xa = (diff >= 27) ? 0 : (xa >> diff);
                    xb = xb;
                    sign_r = sign_b;
                end


                else begin

                    diff = exp_a - exp_b;
                    exp_r = exp_a;
                    xb = (diff >= 27) ? 0 : (xb >> diff);
                    sign_r = sign_a;
                end

                if (sign_a == sign_b) begin
                    sum = xa + xb;
                    if (sum[27]) begin
                        sum = sum >> 1;
                        exp_r = exp_r + 1;
                    end
                end


                else begin
                    if (xa >= xb) begin
                        sum = xa - xb;
                        sign_r = sign_a;
                    end
                    else begin
                        sum = xb - xa;
                        sign_r = sign_b;
                    end
                    if (sum == 0) begin
                        fp32_add_simple = 32'b0;
                    end
                    else begin
                        for (i = 0; i < 26; i = i + 1)
                            if (!sum[26] && (exp_r > -149)) begin
                                sum = sum << 1;
                                exp_r = exp_r - 1;
                            end
                    end
                end
                if (sum != 0) begin

                    main_sig = sum[26:3];

                    guard_bit = sum[2];
                    round_bit = sum[1];

                    sticky_bit = sum[0];
                    increment = guard_bit && (round_bit || sticky_bit || main_sig[0]);

                    if (increment) begin
                        if (main_sig == 24'hFFFFFF) begin
                            main_sig = 24'h800000;
                            exp_r = exp_r + 1;
                        end

                        else begin
                            main_sig = main_sig + 1'b1;
                        end

                    end

                    if (exp_r > 127)
                        fp32_add_simple = {sign_r,8'hFF,23'b0};

                    else if (exp_r < -126) begin
                        main_sig = main_sig >> (-126-exp_r);
                        fp32_add_simple = {sign_r,8'b0,main_sig[22:0]};
                    end

                    else begin
                        exp_field = exp_r + 8'd127;
                        fp32_add_simple = {sign_r,exp_field,main_sig[22:0]};
                    end

                end
            end


        end
    endfunction

    function [63:0] fp64_add_simple;
        input [63:0] a;
        input [63:0] b;
        input do_sub;

        reg sign_a, sign_b, sign_r;

        integer exp_a, exp_b, exp_r, diff;

        reg [52:0] ma, mb;
        reg [55:0] xa, xb;
        reg [56:0] sum;
        reg [52:0] main_sig;
        reg [10:0] exp_field;
        reg guard_bit, round_bit, sticky_bit, increment;

        integer i;

        begin

            sign_a = a[63];
            sign_b = b[63] ^ do_sub;

            if (is_nan64(a) || is_nan64(b)) begin
                fp64_add_simple = 64'h7FF8000000000000;
            end

            else if (is_inf64(a) && is_inf64(b) && (sign_a != sign_b)) begin
                fp64_add_simple = 64'h7FF8000000000000;
            end

            else if (is_inf64(a)) begin
                fp64_add_simple = a;
            end

            else if (is_inf64(b)) begin
                fp64_add_simple = b;
            end

            else if (is_zero64(a)) begin
                fp64_add_simple = b;
            end

            else if (is_zero64(b)) begin
                fp64_add_simple = a;
            end


            else begin

                exp_a = (a[62:52] == 0) ? -1022 : a[62:52] - 1023;
                exp_b = (b[62:52] == 0) ? -1022 : b[62:52] - 1023;

                ma = (a[62:52] == 0) ? {1'b0,a[51:0]} : {1'b1,a[51:0]};
                mb = (b[62:52] == 0) ? {1'b0,b[51:0]} : {1'b1,b[51:0]};

                xa = {ma,3'b000};
                xb = {mb,3'b000};

                if (exp_a < exp_b) begin
                    diff = exp_b - exp_a;
                    exp_r = exp_b;
                    xa = (diff >= 56) ? 0 : (xa >> diff);
                    sign_r = sign_b;
                end

                else begin
                    diff = exp_a - exp_b;
                    exp_r = exp_a;
                    xb = (diff >= 56) ? 0 : (xb >> diff);
                    sign_r = sign_a;
                end

                if (sign_a == sign_b) begin
                    sum = xa + xb;

                    if (sum[56]) begin
                        sum = sum >> 1;
                        exp_r = exp_r + 1;
                    end
                end

                else begin

                    if (xa >= xb) begin sum = xa-xb; sign_r=sign_a; end

                    else begin sum=xb-xa; sign_r=sign_b; end

                    if (sum == 0) begin fp64_add_simple = 64'b0; end

                    else begin
                        for (i = 0; i < 55; i = i + 1)
                            if (!sum[55] && (exp_r > -1074)) begin sum = sum << 1; exp_r=exp_r-1; end
                    end
                end
                if (sum != 0) begin

                    main_sig = sum[55:3];
                    guard_bit = sum[2];
                    round_bit = sum[1];
                    sticky_bit = sum[0];

                    increment = guard_bit && (round_bit || sticky_bit || main_sig[0]);

                    if (increment) begin

                        if (main_sig == 53'h1FFFFFFFFFFFFF) begin
                            main_sig = 53'h10000000000000;
                            exp_r = exp_r + 1;
                        end

                        else begin
                            main_sig = main_sig + 1'b1;
                        end

                    end
                    if (exp_r > 1023)
                        fp64_add_simple = {sign_r,11'h7FF,52'b0};

                    else if (exp_r < -1022) begin
                        main_sig = main_sig >> (-1022-exp_r);
                        fp64_add_simple = {sign_r,11'b0,main_sig[51:0]};
                    end

                    else begin
                        exp_field = exp_r + 11'd1023;
                        fp64_add_simple = {sign_r,exp_field,main_sig[51:0]};
                    end
                end


            end
        end

    endfunction

    function [31:0] fp32_mul_simple;
        input [31:0] a;
        input [31:0] b;

        reg sign_r;

        integer exp_r;

        reg [23:0] ma, mb;
        reg [47:0] prod;
        reg [26:0] sig_ext;
        reg [23:0] main_sig;
        reg [7:0] exp_field;

        reg guard_bit, round_bit, sticky_bit, increment;

        begin
            sign_r = a[31] ^ b[31];

            if (is_nan32(a) || is_nan32(b)) fp32_mul_simple=32'h7FC00000;

            else if ((is_inf32(a)&&is_zero32(b)) || (is_inf32(b)&&is_zero32(a))) fp32_mul_simple=32'h7FC00000;

            else if (is_inf32(a)||is_inf32(b)) fp32_mul_simple={sign_r,8'hFF,23'b0};

            else if (is_zero32(a)||is_zero32(b)) fp32_mul_simple={sign_r,31'b0};

            else begin

                exp_r = ((a[30:23]==0)?-126:a[30:23]-127) + ((b[30:23]==0)?-126:b[30:23]-127);

                ma = (a[30:23]==0)?{1'b0,a[22:0]}:{1'b1,a[22:0]};
                mb = (b[30:23]==0)?{1'b0,b[22:0]}:{1'b1,b[22:0]};

                prod = ma*mb;

                if (prod[47]) begin sig_ext=prod[47:21]; exp_r=exp_r+1; end

                else sig_ext=prod[46:20];

                main_sig=sig_ext[26:3]; guard_bit=sig_ext[2]; round_bit=sig_ext[1]; sticky_bit=sig_ext[0];

                increment=guard_bit&&(round_bit||sticky_bit||main_sig[0]);

                if(increment) begin if(main_sig==24'hFFFFFF) begin main_sig=24'h800000; exp_r=exp_r+1; end else main_sig=main_sig+1'b1; end
                
                if(exp_r>127) fp32_mul_simple={sign_r,8'hFF,23'b0};

                else if(exp_r<-126) begin main_sig=main_sig>>(-126-exp_r); fp32_mul_simple={sign_r,8'b0,main_sig[22:0]}; end
                
                else begin exp_field=exp_r+8'd127; fp32_mul_simple={sign_r,exp_field,main_sig[22:0]}; end
            end
        end
    endfunction

    function [63:0] fp64_mul_simple;
        input [63:0] a;
        input [63:0] b;

        reg sign_r;

        integer exp_r;

        reg [52:0] ma, mb;
        reg [105:0] prod;
        reg [55:0] sig_ext;
        reg [52:0] main_sig;
        reg [10:0] exp_field;
        reg guard_bit, round_bit, sticky_bit, increment;

        begin
            sign_r=a[63]^b[63];

            if(is_nan64(a)||is_nan64(b)) fp64_mul_simple=64'h7FF8000000000000;
            
            else if((is_inf64(a)&&is_zero64(b))||(is_inf64(b)&&is_zero64(a))) fp64_mul_simple=64'h7FF8000000000000;
            
            else if(is_inf64(a)||is_inf64(b)) fp64_mul_simple={sign_r,11'h7FF,52'b0};
           
            else if(is_zero64(a)||is_zero64(b)) fp64_mul_simple={sign_r,63'b0};
            
            else begin
                exp_r=((a[62:52]==0)?-1022:a[62:52]-1023)+((b[62:52]==0)?-1022:b[62:52]-1023);
                
                ma=(a[62:52]==0)?{1'b0,a[51:0]}:{1'b1,a[51:0]};
                mb=(b[62:52]==0)?{1'b0,b[51:0]}:{1'b1,b[51:0]};
                
                prod=ma*mb;
                
                if(prod[105]) begin sig_ext=prod[105:50]; exp_r=exp_r+1; end
                else sig_ext=prod[104:49];
                
                main_sig=sig_ext[55:3]; guard_bit=sig_ext[2]; round_bit=sig_ext[1]; sticky_bit=sig_ext[0];
                
                increment=guard_bit&&(round_bit||sticky_bit||main_sig[0]);
                
                
                if(increment) begin if(main_sig==53'h1FFFFFFFFFFFFF) begin main_sig=53'h10000000000000; exp_r=exp_r+1; end else main_sig=main_sig+1'b1; end
                
                if(exp_r>1023) fp64_mul_simple={sign_r,11'h7FF,52'b0};
                
                else if(exp_r<-1022) begin main_sig=main_sig>>(-1022-exp_r); fp64_mul_simple={sign_r,11'b0,main_sig[51:0]}; end
                
                else begin exp_field=exp_r+11'd1023; fp64_mul_simple={sign_r,exp_field,main_sig[51:0]}; end
            end
        end
    endfunction

    function [31:0] fp32_div_simple;

        input [31:0] a; input [31:0] b;

        reg sign_r;

        integer exp_r;

        reg [23:0] ma,mb;
        reg [50:0] numerator;
        reg [50:0] quotient;
        reg [50:0] remainder;
        reg [26:0] normalized_quotient;
        reg [23:0] main_sig;
        reg [7:0] exp_field;
        reg guard_bit, round_bit, sticky_bit, increment;

        begin
            sign_r = a[31] ^ b[31];

            if (is_nan32(a) || is_nan32(b) ||
                (is_inf32(a) && is_inf32(b)) ||
                (is_zero32(a) && is_zero32(b))) begin

                fp32_div_simple = 32'h7FC00000;

            end

            else if (is_inf32(a)) begin
                fp32_div_simple = {sign_r, 8'hFF, 23'b0};
            end

            else if (is_inf32(b)) begin
                fp32_div_simple = {sign_r, 31'b0};
            end

            else if (is_zero32(b)) begin
                fp32_div_simple = {sign_r, 8'hFF, 23'b0};
            end

            else if (is_zero32(a)) begin
                fp32_div_simple = {sign_r, 31'b0};
            end

            else begin

                exp_r = ((a[30:23] == 0) ? -126 : a[30:23] - 127) - ((b[30:23] == 0) ? -126 : b[30:23] - 127);

                ma = (a[30:23] == 0) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
                mb = (b[30:23] == 0) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};

                numerator = {ma, 27'b0};
                quotient = numerator / mb;
                remainder = numerator % mb;

                if (quotient[27]) begin
                    normalized_quotient = quotient[27:1];
                end

                else begin
                    quotient = quotient << 1;
                    normalized_quotient = quotient[27:1];
                    exp_r = exp_r - 1;
                end

                main_sig = normalized_quotient[26:3];
                guard_bit = normalized_quotient[2];
                round_bit = normalized_quotient[1];
                sticky_bit = normalized_quotient[0] || (remainder != 0);
                increment = guard_bit && (round_bit || sticky_bit || main_sig[0]);

                if (increment) begin
                    if (main_sig == 24'hFFFFFF) begin
                        main_sig = 24'h800000;
                        exp_r = exp_r + 1;
                    end
                    else begin
                        main_sig = main_sig + 1'b1;
                    end
                end

                if (exp_r > 127)
                    fp32_div_simple = {sign_r, 8'hFF, 23'b0};

                else if (exp_r < -126) begin
                    main_sig = main_sig >> (-126 - exp_r);
                    fp32_div_simple = {sign_r, 8'b0, main_sig[22:0]};
                end

                else begin
                    exp_field = exp_r + 8'd127;
                    fp32_div_simple = {sign_r, exp_field, main_sig[22:0]};
                end

            end
        end
    endfunction

    function [63:0] fp64_div_simple;
        input [63:0] a; input [63:0] b;

        reg sign_r;
        integer exp_r;

        reg [52:0] ma,mb;
        reg [108:0] numerator;
        reg [108:0] quotient;
        reg [108:0] remainder;
        reg [55:0] normalized_quotient;
        reg [52:0] main_sig;
        reg [10:0] exp_field;
        reg guard_bit, round_bit, sticky_bit, increment;

        begin
            sign_r = a[63] ^ b[63];

            if (is_nan64(a) || is_nan64(b) ||
                (is_inf64(a) && is_inf64(b)) ||
                (is_zero64(a) && is_zero64(b))) begin

                fp64_div_simple = 64'h7FF8000000000000;

            end

            else if (is_inf64(a)) begin
                fp64_div_simple = {sign_r, 11'h7FF, 52'b0};
            end

            else if (is_inf64(b)) begin
                fp64_div_simple = {sign_r, 63'b0};
            end

            else if (is_zero64(b)) begin
                fp64_div_simple = {sign_r, 11'h7FF, 52'b0};
            end

            else if (is_zero64(a)) begin
                fp64_div_simple = {sign_r, 63'b0};
            end

            else begin

                exp_r = ((a[62:52] == 0) ? -1022 : a[62:52] - 1023) - ((b[62:52] == 0) ? -1022 : b[62:52] - 1023);

                ma = (a[62:52] == 0) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};
                mb = (b[62:52] == 0) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};

                numerator = {ma, 56'b0};
                quotient = numerator / mb;
                remainder = numerator % mb;

                if (quotient[56]) begin
                    normalized_quotient = quotient[56:1];
                end

                else begin
                    quotient = quotient << 1;
                    normalized_quotient = quotient[56:1];
                    exp_r = exp_r - 1;
                end

                main_sig = normalized_quotient[55:3];
                guard_bit = normalized_quotient[2];
                round_bit = normalized_quotient[1];
                sticky_bit = normalized_quotient[0] || (remainder != 0);
                increment = guard_bit && (round_bit || sticky_bit || main_sig[0]);

                if (increment) begin
                    if (main_sig == 53'h1FFFFFFFFFFFFF) begin
                        main_sig = 53'h10000000000000;
                        exp_r = exp_r + 1;
                    end
                    else begin
                        main_sig = main_sig + 1'b1;
                    end
                end

                if (exp_r > 1023)
                    fp64_div_simple = {sign_r, 11'h7FF, 52'b0};

                else if (exp_r < -1022) begin
                    main_sig = main_sig >> (-1022 - exp_r);
                    fp64_div_simple = {sign_r, 11'b0, main_sig[51:0]};
                end

                else begin
                    exp_field = exp_r + 11'd1023;
                    fp64_div_simple = {sign_r, exp_field, main_sig[51:0]};
                end

            end
        end
    endfunction

    function [31:0] fp32_to_fp32_bits; input [31:0] a; begin fp32_to_fp32_bits=a; end endfunction

    function [63:0] fp32_to_fp64_bits;

        input [31:0] a; integer e; reg [10:0] exp_field; reg [51:0] frac;
        begin

            if(is_nan32(a)) fp32_to_fp64_bits=64'h7FF8000000000000;

            else if(is_inf32(a)) fp32_to_fp64_bits={a[31],11'h7FF,52'b0};
            else if(is_zero32(a)) fp32_to_fp64_bits={a[31],63'b0};

            else if(a[30:23]==0) begin

                e=-126; frac={a[22:0],29'b0};

                while((frac[51]==0)&&(e>-149)) begin frac=frac<<1; e=e-1; end

                exp_field = e + 11'd1023;

                fp32_to_fp64_bits={a[31],exp_field,frac[51:29],29'b0};
            end
            else begin

                exp_field = a[30:23] - 8'd127 + 11'd1023;

                fp32_to_fp64_bits={a[31],exp_field,a[22:0],29'b0};
            end
        end
    endfunction

    function [31:0] fp64_to_fp32_bits;
        input [63:0] a; integer exp_s; reg [7:0] exp_field; reg [23:0] sig; reg inc;
        begin
            if(is_nan64(a)) fp64_to_fp32_bits=32'h7FC00000;
            else if(is_inf64(a)) fp64_to_fp32_bits={a[63],8'hFF,23'b0};
            else if(is_zero64(a)) fp64_to_fp32_bits={a[63],31'b0};
            else begin

                exp_s = (a[62:52]==0)?-1022:a[62:52]-1023;
                
                if(exp_s>127) fp64_to_fp32_bits={a[63],8'hFF,23'b0};
                else if(exp_s<-149) fp64_to_fp32_bits={a[63],31'b0};
                else begin

                    sig = (a[62:52]==0)?{1'b0,a[51:29]}:{1'b1,a[51:29]};
                    inc = (a[28] && (|a[27:0] || sig[0]));

                    if(inc) sig=sig+1'b1;

                    if(exp_s<-126) fp64_to_fp32_bits={a[63],8'b0,sig[22:0]};
                    else begin exp_field=exp_s+8'd127; fp64_to_fp32_bits={a[63],exp_field,sig[22:0]}; end
                end
            end
        end
    endfunction

    function fp32_less;
        input [31:0] a;
        input [31:0] b;
        begin
            if (a[31] != b[31])
                fp32_less = a[31] && !is_zero32(a) ? 1'b1 : (!a[31] && is_zero32(a) && is_zero32(b) ? 1'b0 : !a[31]);
            else if (!a[31])
                fp32_less = a[30:0] < b[30:0];
            else
                fp32_less = a[30:0] > b[30:0];
        end
    endfunction

    function fp64_less;
        input [63:0] a;
        input [63:0] b;
        begin
            if (a[63] != b[63])
                fp64_less = a[63] && !is_zero64(a) ? 1'b1 : (!a[63] && is_zero64(a) && is_zero64(b) ? 1'b0 : !a[63]);
            else if (!a[63])
                fp64_less = a[62:0] < b[62:0];
            else
                fp64_less = a[62:0] > b[62:0];
        end
    endfunction

    function [64:0] isqrt130;
        input [129:0] value;
        reg [132:0] remainder;
        reg [64:0] root;
        reg [131:0] trial;
        integer i;
        begin
            remainder = 0;
            root = 0;
            for (i = 64; i >= 0; i = i - 1) begin
                
                remainder = (remainder << 2) | value[(i*2) +: 2];
                root = root << 1;
                trial = (root << 1) | 1'b1;

                if (remainder >= trial) begin
                    remainder = remainder - trial;
                    root[0] = 1'b1;
                end
            end
            isqrt130 = root;
        end
    endfunction

    function [32:0] isqrt66;
        input [65:0] value;
        reg [68:0] remainder;
        reg [32:0] root;
        reg [67:0] trial;
        integer i;
        begin
            remainder = 0;
            root = 0;
            for (i = 32; i >= 0; i = i - 1) begin
                remainder = (remainder << 2) | value[(i*2) +: 2];
                root = root << 1;
                trial = (root << 1) | 1'b1;
                if (remainder >= trial) begin
                    remainder = remainder - trial;
                    root[0] = 1'b1;
                end
            end
            isqrt66 = root;
        end
    endfunction

    function [63:0] fp64_sqrt_simple;
        input [63:0] a;
        reg sign;
        integer exp_u;
        reg [52:0] mant;
        reg [129:0] rad;
        reg [64:0] root;
        reg [52:0] rounded_sig;
        reg [10:0] exp_field;
        integer i;
        begin
            sign = a[63];
            if (is_nan64(a))
                fp64_sqrt_simple = 64'h7FF8000000000000;
            else if (is_inf64(a))
                fp64_sqrt_simple = sign ? 64'h7FF8000000000000 : a;
            else if (is_zero64(a))
                fp64_sqrt_simple = a;
            else if (sign)
                fp64_sqrt_simple = 64'h7FF8000000000000;
            else begin
                if (a[62:52] == 0) begin
                    exp_u = -1022;
                    mant = {1'b0,a[51:0]};
                    for (i = 0; i < 52; i = i + 1)
                        if ((mant[52] == 0) && (mant != 0)) begin
                            mant = mant << 1;
                            exp_u = exp_u - 1;
                        end
                end
                else begin
                    exp_u = a[62:52] - 1023;
                    mant = {1'b1,a[51:0]};
                end

                if (exp_u[0] == 1'b1) begin
                    mant = mant << 1;
                    exp_u = exp_u - 1;
                end

                rad = 0;
                rad[52:0] = mant;
                rad = rad << 54;
                root = isqrt130(rad);
                rounded_sig = root[53:1];
                if (root[0])
                    rounded_sig = rounded_sig + 1'b1;
                exp_field = (exp_u / 2) + 11'd1023;
                fp64_sqrt_simple = {1'b0,exp_field,rounded_sig[51:0]};
            end
        end
    endfunction

    function [31:0] fp32_sqrt_simple;
        input [31:0] a;
        reg sign;
        integer exp_u;
        reg [23:0] mant;
        reg [65:0] rad;
        reg [32:0] root;
        reg [23:0] rounded_sig;
        reg [7:0] exp_field;
        integer i;
        begin
            sign = a[31];
            if (is_nan32(a))
                fp32_sqrt_simple = 32'h7FC00000;
            else if (is_inf32(a))
                fp32_sqrt_simple = sign ? 32'h7FC00000 : a;
            else if (is_zero32(a))
                fp32_sqrt_simple = a;
            else if (sign)
                fp32_sqrt_simple = 32'h7FC00000;
            else begin
                if (a[30:23] == 0) begin
                    exp_u = -126;
                    mant = {1'b0,a[22:0]};
                    for (i = 0; i < 23; i = i + 1)
                        if ((mant[23] == 0) && (mant != 0)) begin
                            mant = mant << 1;
                            exp_u = exp_u - 1;
                        end
                end
                else begin
                    exp_u = a[30:23] - 127;
                    mant = {1'b1,a[22:0]};
                end

                if (exp_u[0] == 1'b1) begin
                    mant = mant << 1;
                    exp_u = exp_u - 1;
                end

                rad = 0;
                rad[23:0] = mant;
                rad = rad << 25;
                root = isqrt66(rad);
                rounded_sig = root[24:1];
                if (root[0])
                    rounded_sig = rounded_sig + 1'b1;
                exp_field = (exp_u / 2) + 8'd127;
                fp32_sqrt_simple = {1'b0,exp_field,rounded_sig[22:0]};
            end
        end
    endfunction

    function [31:0] fp32_class;
        input [31:0] a; reg sign; reg [7:0] exp; reg [22:0] frac;
        begin
            sign=a[31]; exp=a[30:23]; frac=a[22:0]; fp32_class=0;
            if(exp==8'hFF) begin
                if(frac==0) fp32_class = sign ? 32'b1 : 32'h80;
                else if(frac[22]) fp32_class=32'h200;
                else fp32_class=32'h100;
            end
            else if(exp==0) begin
                if(frac==0) fp32_class=sign ? 32'h8 : 32'h10;
                else fp32_class=sign ? 32'h4 : 32'h20;
            end
            else fp32_class=sign ? 32'h2 : 32'h40;
        end
    endfunction

    function [63:0] fp64_class;
        input [63:0] a; reg sign; reg [10:0] exp; reg [51:0] frac;
        begin
            sign=a[63]; exp=a[62:52]; frac=a[51:0]; fp64_class=0;
            if(exp==11'h7FF) begin
                if(frac==0) fp64_class = sign ? 64'h1 : 64'h80;
                else if(frac[51]) fp64_class=64'h200;
                else fp64_class=64'h100;
            end
            else if(exp==0) begin
                if(frac==0) fp64_class=sign ? 64'h8 : 64'h10;
                else fp64_class=sign ? 64'h4 : 64'h20;
            end
            else fp64_class=sign ? 64'h2 : 64'h40;
        end
    endfunction

    function [63:0] fp_int_to_float;
        input [63:0] value; input signed_value; input to_double;
        reg sign; reg [63:0] mag; integer msb; integer exp_u; reg [10:0] exp_field64; reg [7:0] exp_field32; reg [52:0] sig; reg [23:0] sig32; reg [63:0] shifted;
        integer i;
        begin
            sign=0; mag=value;
            if(signed_value && value[63]) begin sign=1; mag=(~value)+1'b1; end
            if(mag==0) fp_int_to_float = to_double ? 64'b0 : 64'hFFFFFFFF00000000;
            else begin
                msb=0; for(i=0;i<64;i=i+1) if(mag[i]) msb=i; exp_u=msb;
                if(to_double) begin
                    if(msb>52) sig=mag>>(msb-52); else sig=mag<<(52-msb);
                    exp_field64=exp_u+11'd1023;
                    fp_int_to_float={sign,exp_field64,sig[51:0]};
                end
                else begin
                    if(msb>23) sig32=mag>>(msb-23); else sig32=mag<<(23-msb);
                    exp_field32=exp_u+8'd127;
                    fp_int_to_float={32'hFFFFFFFF,sign,exp_field32,sig32[22:0]};
                end
            end
        end
    endfunction

    function [63:0] fp_to_int;
        input [63:0] a; input from_double; input unsigned_value; input [2:0] rm; integer e; integer shift; reg [63:0] significand; reg [63:0] mag; reg sign; reg fractional; reg half_bit; reg sticky; reg do_inc; reg [63:0] rounded_mag;
        begin
            sign = from_double ? a[63] : a[31];
            fractional = 1'b0;
            half_bit = 1'b0;
            sticky = 1'b0;
            do_inc = 1'b0;
            rounded_mag = 64'b0;

            if(from_double) begin
                if(is_nan64(a)||is_inf64(a)) begin
                    fp_to_int = unsigned_value ? 64'hFFFFFFFFFFFFFFFF : 64'h8000000000000000;
                end
                else begin
                    e = (a[62:52] == 0) ? -1022 : a[62:52] - 1023;
                    significand = (a[62:52] == 0) ? {11'b0,a[51:0]} : {11'b1,a[51:0]};

                    if(e < 0) begin
                        mag = 64'b0;
                        fractional = (significand != 64'b0);
                        half_bit = 1'b0;
                        sticky = fractional;
                    end
                    else if(e >= 52) begin
                        shift = e - 52;
                        if(shift > 11)
                            mag = 64'hFFFFFFFFFFFFFFFF;
                        else
                            mag = significand << shift;
                        fractional = 1'b0;
                    end
                    else begin
                        shift = 52 - e;
                        mag = significand >> shift;
                        fractional = (significand != (mag << shift));
                        if(shift <= 53) begin
                            half_bit = significand[shift-1];
                            if(shift > 1)
                                sticky = |(significand & ((64'h1 << (shift-1)) - 1'b1));
                        end
                        else begin
                            half_bit = 1'b0;
                            sticky = fractional;
                        end
                    end

                    case (rm)
                        3'b000: do_inc = half_bit && (sticky || mag[0]);
                        3'b001: do_inc = 1'b0;
                        3'b010: do_inc = sign && fractional;
                        3'b011: do_inc = !sign && fractional;
                        3'b100: do_inc = half_bit;
                        default: do_inc = half_bit && (sticky || mag[0]);
                    endcase

                    rounded_mag = mag + (do_inc ? 64'd1 : 64'd0);

                    if(unsigned_value) begin
                        if(sign && (mag != 0 || fractional))
                            fp_to_int = 64'b0;
                        else
                            fp_to_int = rounded_mag;
                    end
                    else if(sign)
                        fp_to_int = (~rounded_mag) + 1'b1;
                    else
                        fp_to_int = rounded_mag;
                end
            end
            else begin
                if(is_nan32(a)||is_inf32(a)) begin
                    fp_to_int = unsigned_value ? 64'hFFFFFFFFFFFFFFFF : 64'h8000000000000000;
                end
                else begin
                    e = (a[30:23] == 0) ? -126 : a[30:23] - 127;
                    significand = (a[30:23] == 0) ? {40'b0,a[22:0]} : {40'b0,1'b1,a[22:0]};

                    if(e < 0) begin
                        mag = 64'b0;
                        fractional = (significand != 64'b0);
                        half_bit = 1'b0;
                        sticky = fractional;
                    end
                    else if(e >= 23) begin
                        shift = e - 23;
                        if(shift > 40)
                            mag = 64'hFFFFFFFFFFFFFFFF;
                        else
                            mag = significand << shift;
                        fractional = 1'b0;
                    end
                    else begin
                        shift = 23 - e;
                        mag = significand >> shift;
                        fractional = (significand != (mag << shift));
                        if(shift <= 24) begin
                            half_bit = significand[shift-1];
                            if(shift > 1)
                                sticky = |(significand & ((64'h1 << (shift-1)) - 1'b1));
                        end
                        else begin
                            half_bit = 1'b0;
                            sticky = fractional;
                        end
                    end

                    case (rm)
                        3'b000: do_inc = half_bit && (sticky || mag[0]);
                        3'b001: do_inc = 1'b0;
                        3'b010: do_inc = sign && fractional;
                        3'b011: do_inc = !sign && fractional;
                        3'b100: do_inc = half_bit;
                        default: do_inc = half_bit && (sticky || mag[0]);
                    endcase

                    rounded_mag = mag + (do_inc ? 64'd1 : 64'd0);

                    if(unsigned_value) begin
                        if(sign && (mag != 0 || fractional))
                            fp_to_int = 64'b0;
                        else
                            fp_to_int = rounded_mag;
                    end
                    else if(sign)
                        fp_to_int = (~rounded_mag) + 1'b1;
                    else
                        fp_to_int = rounded_mag;
                end
            end
        end
    endfunction

    reg [63:0] a_use, b_use, c_use;
    reg [63:0] mul_value;
    reg [63:0] add_value;
    reg [31:0] a32, b32, c32;
    reg [31:0] r32;
    reg [63:0] r64;
    reg [63:0] conv_int;

    always @(*) begin

        fp_result = format_d ? 64'h7FF8000000000000 : 64'hFFFFFFFF7FC00000;
        integer_result = 64'b0;
        exception_flags = 5'b0;
        conv_int = 64'b0;

        if (format_d) begin

            a_use = rs1_data;
            b_use = rs2_data;
            c_use = rs3_data;

            case (operation)
                FP_ADD: fp_result = fp64_add_simple(a_use,b_use,1'b0);
                FP_SUB: fp_result = fp64_add_simple(a_use,b_use,1'b1);
                FP_MUL: fp_result = fp64_mul_simple(a_use,b_use);
                FP_DIV: begin
                    fp_result = fp64_div_simple(a_use,b_use);
                    if (is_nan64(a_use) || is_nan64(b_use) || (is_zero64(a_use) && is_zero64(b_use)) || (is_inf64(a_use) && is_inf64(b_use)))
                        exception_flags[0] = 1'b1;
                    else if (is_zero64(b_use) && !is_inf64(a_use))
                        exception_flags[3] = 1'b1;
                end
                FP_SQRT: fp_result = fp64_sqrt_simple(a_use);
                FP_SGNJ: fp_result = {b_use[63],a_use[62:0]};
                FP_SGNJN: fp_result = {~b_use[63],a_use[62:0]};
                FP_SGNJX: fp_result = {a_use[63]^b_use[63],a_use[62:0]};
                FP_MIN: begin if(is_nan64(a_use)&&is_nan64(b_use)) fp_result=64'h7FF8000000000000; else if(is_nan64(a_use)) fp_result=b_use; else if(is_nan64(b_use)) fp_result=a_use; else fp_result=fp64_less(a_use,b_use)?a_use:b_use; end
                FP_MAX: begin if(is_nan64(a_use)&&is_nan64(b_use)) fp_result=64'h7FF8000000000000; else if(is_nan64(a_use)) fp_result=b_use; else if(is_nan64(b_use)) fp_result=a_use; else fp_result=fp64_less(a_use,b_use)?b_use:a_use; end
                FP_FEQ: integer_result = (is_nan64(a_use)||is_nan64(b_use)) ? 0 : ((is_zero64(a_use)&&is_zero64(b_use)) || (a_use==b_use));
                FP_FLT: integer_result = (is_nan64(a_use)||is_nan64(b_use)) ? 0 : fp64_less(a_use,b_use);
                FP_FLE: integer_result = (is_nan64(a_use)||is_nan64(b_use)) ? 0 : (fp64_less(a_use,b_use) || ((is_zero64(a_use)&&is_zero64(b_use)) || (a_use==b_use)));
                FP_FCLASS: integer_result = fp64_class(a_use);
                FP_CVT_W: begin conv_int = fp_to_int(a_use,1'b1,1'b0,rounding_mode); integer_result = {{32{conv_int[31]}},conv_int[31:0]}; end
                FP_CVT_WU: begin conv_int = fp_to_int(a_use,1'b1,1'b1,rounding_mode); integer_result = {32'b0,conv_int[31:0]}; end
                FP_CVT_L: integer_result = fp_to_int(a_use,1'b1,1'b0,rounding_mode);
                FP_CVT_LU: integer_result = fp_to_int(a_use,1'b1,1'b1,rounding_mode);
                FP_CVT_FROM_W: fp_result = fp_int_to_float({{32{integer_data[31]}},integer_data[31:0]},1'b1,1'b1);
                FP_CVT_FROM_WU: fp_result = fp_int_to_float({32'b0,integer_data[31:0]},1'b0,1'b1);
                FP_CVT_FROM_L: fp_result = fp_int_to_float(integer_data,1'b1,1'b1);
                FP_CVT_FROM_LU: fp_result = fp_int_to_float(integer_data,1'b0,1'b1);
                FP_MV_X_D: integer_result = a_use;
                FP_MV_D_X: fp_result = integer_data;
                FP_CVT_S_D: fp_result = {32'hFFFFFFFF,fp64_to_fp32_bits(a_use)};
                FP_CVT_D_S: fp_result = fp32_to_fp64_bits(a_use[31:0]);
                FP_FMADD: begin mul_value=fp64_mul_simple(a_use,b_use); add_value=fp64_add_simple(mul_value,c_use,1'b0); fp_result=add_value; end
                FP_FMSUB: begin mul_value=fp64_mul_simple(a_use,b_use); add_value=fp64_add_simple(mul_value,c_use,1'b1); fp_result=add_value; end
                FP_FNMSUB: begin mul_value=fp64_mul_simple(a_use,b_use); mul_value[63]=~mul_value[63]; fp_result=fp64_add_simple(mul_value,c_use,1'b1); end
                FP_FNMADD: begin mul_value=fp64_mul_simple(a_use,b_use); mul_value[63]=~mul_value[63]; fp_result=fp64_add_simple(mul_value,c_use,1'b0); end
                default: fp_result=64'h7FF8000000000000;
            endcase

        end

        else begin

            a32 = rs1_data[31:0];
            b32 = rs2_data[31:0];
            c32 = rs3_data[31:0];

            case (operation)
                FP_ADD: r32=fp32_add_simple(a32,b32,1'b0);
                FP_SUB: r32=fp32_add_simple(a32,b32,1'b1);
                FP_MUL: r32=fp32_mul_simple(a32,b32);
                FP_DIV: begin
                    r32=fp32_div_simple(a32,b32);
                    if (is_nan32(a32) || is_nan32(b32) || (is_zero32(a32) && is_zero32(b32)) || (is_inf32(a32) && is_inf32(b32)))
                        exception_flags[0] = 1'b1;
                    else if (is_zero32(b32) && !is_inf32(a32))
                        exception_flags[3] = 1'b1;
                end
                FP_SQRT: r32=fp32_sqrt_simple(a32);
                FP_SGNJ: r32={b32[31],a32[30:0]};
                FP_SGNJN: r32={~b32[31],a32[30:0]};
                FP_SGNJX: r32={a32[31]^b32[31],a32[30:0]};
                FP_MIN: begin if(is_nan32(a32)&&is_nan32(b32)) r32=32'h7FC00000; else if(is_nan32(a32)) r32=b32; else if(is_nan32(b32)) r32=a32; else r32=fp32_less(a32,b32)?a32:b32; end
                FP_MAX: begin if(is_nan32(a32)&&is_nan32(b32)) r32=32'h7FC00000; else if(is_nan32(a32)) r32=b32; else if(is_nan32(b32)) r32=a32; else r32=fp32_less(a32,b32)?b32:a32; end
                FP_FEQ: integer_result=(is_nan32(a32)||is_nan32(b32))?0:((is_zero32(a32)&&is_zero32(b32)) || (a32==b32));
                FP_FLT: integer_result=(is_nan32(a32)||is_nan32(b32))?0:fp32_less(a32,b32);
                FP_FLE: integer_result=(is_nan32(a32)||is_nan32(b32))?0:(fp32_less(a32,b32)||((is_zero32(a32)&&is_zero32(b32)) || (a32==b32)));
                FP_FCLASS: integer_result=fp32_class(a32);
                FP_CVT_W: integer_result=fp_to_int({32'b0,a32},1'b0,1'b0,rounding_mode);
                FP_CVT_WU: integer_result=fp_to_int({32'b0,a32},1'b0,1'b1,rounding_mode);
                FP_CVT_L: integer_result=fp_to_int({32'b0,a32},1'b0,1'b0,rounding_mode);
                FP_CVT_LU: integer_result=fp_to_int({32'b0,a32},1'b0,1'b1,rounding_mode);
                FP_CVT_FROM_W: fp_result=fp_int_to_float({{32{integer_data[31]}},integer_data[31:0]},1'b1,1'b0);
                FP_CVT_FROM_WU: fp_result=fp_int_to_float({32'b0,integer_data[31:0]},1'b0,1'b0);
                FP_CVT_FROM_L: fp_result=fp_int_to_float(integer_data,1'b1,1'b0);
                FP_CVT_FROM_LU: fp_result=fp_int_to_float(integer_data,1'b0,1'b0);
                FP_MV_X_W: integer_result={{32{a32[31]}},a32};
                FP_MV_W_X: fp_result={32'hFFFFFFFF,integer_data[31:0]};
                FP_CVT_S_D: fp_result={32'hFFFFFFFF,fp64_to_fp32_bits(rs1_data[63:0])};
                FP_CVT_D_S: fp_result=fp32_to_fp64_bits(a32);
                FP_MV_X_D: integer_result={32'hFFFFFFFF,a32};
                FP_MV_D_X: fp_result={32'hFFFFFFFF,integer_data[31:0]};
                FP_FMADD: begin r32=fp32_add_simple(fp32_mul_simple(a32,b32),c32,1'b0); end
                FP_FMSUB: begin r32=fp32_add_simple(fp32_mul_simple(a32,b32),c32,1'b1); end
                FP_FNMSUB: begin r32=fp32_mul_simple(a32,b32); r32[31]=~r32[31]; r32=fp32_add_simple(r32,c32,1'b1); end
                FP_FNMADD: begin r32=fp32_mul_simple(a32,b32); r32[31]=~r32[31]; r32=fp32_add_simple(r32,c32,1'b0); end
                default: r32=32'h7FC00000;
            endcase

            if ((operation != FP_FEQ) &&
                (operation != FP_FLT) &&
                (operation != FP_FLE) &&
                (operation != FP_FCLASS) &&
                (operation != FP_CVT_W) &&
                (operation != FP_CVT_WU) &&
                (operation != FP_CVT_L) &&
                (operation != FP_CVT_LU) &&
                (operation != FP_MV_X_W) &&
                (operation != FP_MV_X_D) &&
                (operation != FP_CVT_S_D) &&
                (operation != FP_CVT_D_S) &&
                (operation != FP_MV_W_X) &&
                (operation != FP_MV_D_X) &&
                (operation != FP_CVT_FROM_W) &&
                (operation != FP_CVT_FROM_WU) &&
                (operation != FP_CVT_FROM_L) &&
                (operation != FP_CVT_FROM_LU))
                fp_result={32'hFFFFFFFF,r32};

        end

    end

endmodule
