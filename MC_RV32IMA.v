`timescale 1ns/1ps

// A simple parameterized multi-cycle RISC-V processor based on the RV32IMA ISA.

// The architecture is inspired by the Bitspinner RV32I
// Link: https://www.bit-spinner.com/rv32i/rv32i-data-memory

// Multi-cycle design inspired by Bitspinner
// Link: https://www.bit-spinner.com/rv32i-multi-cycle/rv32i-multi-cycle-introduction


// The CPU contains:
//  - Program Counter (PC)
//  - Instruction Memory
//  - Register File (32 x XLEN-bit)
//  - Immediate Generator
//  - ALU
//  - Branch / Jump Logic
//  - Data Memory
//  - Instruction Decoder
//  - Write Back logic
//  - Multiply / Divide instructions
//  - Atomic Memory instructions


module RV32IMA_CPU #(

    // Parameters

    // XLEN controls the register, ALU, PC, address, and data width

    // Number of words in instruction/data memory
    // 256 words = 1024 bytes for XLEN = 32

    parameter XLEN = 32,
    parameter IMEM_SIZE = 256,
    parameter DMEM_SIZE = 256

)(

    input wire clk,
    input wire rst,

    // Debug outputs
    output wire [XLEN-1:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire [XLEN-1:0] debug_result

);

    localparam SHIFT_WIDTH = (XLEN <= 32) ? 5 : 6;
    localparam IMEM_ADDR_WIDTH = (IMEM_SIZE <= 1) ? 1 : $clog2(IMEM_SIZE);
    localparam DMEM_ADDR_WIDTH = (DMEM_SIZE <= 1) ? 1 : $clog2(DMEM_SIZE);


    // OPCODES

    localparam [6:0] OPCODE_OP = 7'b0110011;     // R-type
    localparam [6:0] OPCODE_OP_IMM = 7'b0010011; // I-type ALU
    localparam [6:0] OPCODE_LOAD = 7'b0000011;   // Load
    localparam [6:0] OPCODE_STORE = 7'b0100011;  // Store
    localparam [6:0] OPCODE_BRANCH = 7'b1100011; // Branch
    localparam [6:0] OPCODE_LUI = 7'b0110111;    // LUI
    localparam [6:0] OPCODE_AUIPC = 7'b0010111;  // AUIPC
    localparam [6:0] OPCODE_JAL = 7'b1101111;    // JAL
    localparam [6:0] OPCODE_JALR = 7'b1100111;   // JALR
    localparam [6:0] OPCODE_ATOMIC = 7'b0101111; // Atomic memory operations

    // ALU operations

    localparam [3:0] ALU_ADD = 4'd0;
    localparam [3:0] ALU_SUB = 4'd1;
    localparam [3:0] ALU_SLL = 4'd2;
    localparam [3:0] ALU_SLT = 4'd3;
    localparam [3:0] ALU_SLTU = 4'd4;
    localparam [3:0] ALU_XOR = 4'd5;
    localparam [3:0] ALU_SRL = 4'd6;
    localparam [3:0] ALU_SRA = 4'd7;
    localparam [3:0] ALU_OR = 4'd8;
    localparam [3:0] ALU_AND = 4'd9;

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


    // CPU STATES

    // Each instruction is divided into multiple clock cycles.

    localparam [2:0] STATE_FETCH = 3'd0;
    localparam [2:0] STATE_DECODE = 3'd1;
    localparam [2:0] STATE_EXECUTE = 3'd2;
    localparam [2:0] STATE_MEMORY = 3'd3;
    localparam [2:0] STATE_WRITEBACK = 3'd4;

    reg [2:0] state;
    reg [2:0] next_state;


    // REGISTERS AND MEMORIES

    // Program Counter

    reg [XLEN-1:0] pc;

    // Instruction Register

    // Holds the current instruction while it moves through the multi-cycle datapath

    reg [31:0] instruction_register;

    // Program Counter Register

    // Holds the address of the current instruction

    reg [XLEN-1:0] instruction_pc;

    // 32 general purpose registers
    // x0 is hardwired to zero according to the RISC-V specification

    reg [XLEN-1:0] registers [0:31];

    // Instruction memory
    // Each address contains one 32-bit instruction

    reg [31:0] instruction_memory [0:IMEM_SIZE-1];

    // Data memory
    // Used by LW and SW instructions
    // Atomic instructions also access this memory

    reg [XLEN-1:0] data_memory [0:DMEM_SIZE-1];

    // Reservation used by LR.W / SC.W
    // This implementation models one reservation at a time

    reg reservation_valid;
    reg [XLEN-1:0] reservation_address;


    // INSTRUCTION

    wire [31:0] instruction;


    // Since every base RISC-V instruction is 32 bits and normally aligned to 4 bytes, divide the byte address by 4

    assign instruction = instruction_memory[pc[IMEM_ADDR_WIDTH+1:2]];


    // INSTRUCTION FIELDS

    // These fields are present in different instruction formats and are extracted directly from the instruction

    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;

    assign opcode = instruction_register[6:0];
    assign rd = instruction_register[11:7];
    assign funct3 = instruction_register[14:12];
    assign rs1 = instruction_register[19:15];
    assign rs2 = instruction_register[24:20];
    assign funct7 = instruction_register[31:25];


    // REGISTER FILE READ

    // The register file has two asynchronous read ports
    // Reading x0 always returns zero

    wire [XLEN-1:0] rs1_data;
    wire [XLEN-1:0] rs2_data;

    assign rs1_data = (rs1 == 5'd0) ? {XLEN{1'b0}} : registers[rs1];
    assign rs2_data = (rs2 == 5'd0) ? {XLEN{1'b0}} : registers[rs2];

    // DECODED REGISTER VALUES

    // These registers hold the source operands while the instruction moves through the datapath

    reg [XLEN-1:0] rs1_data_register;
    reg [XLEN-1:0] rs2_data_register;
    reg [XLEN-1:0] immediate_register;


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
            // LW
            // JALR

            OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_JALR: immediate = {{(XLEN-12){instruction_register[31]}}, instruction_register[31:20]};


            // S-TYPE

            // Used by:
            // SW

            OPCODE_STORE: immediate = {{(XLEN-12){instruction_register[31]}}, instruction_register[31:25], instruction_register[11:7]};


            // B-TYPE

            // Used by:
            // BEQ
            // BNE
            // BLT
            // BGE
            // BLTU
            // BGEU

            // The lowest bit is always zero because branches are aligned

            OPCODE_BRANCH: immediate = {{(XLEN-13){instruction_register[31]}}, instruction_register[31], instruction_register[7], instruction_register[30:25], instruction_register[11:8], 1'b0};


            // U-TYPE

            // Used by:
            // LUI
            // AUIPC

            OPCODE_LUI, OPCODE_AUIPC: immediate = {{(XLEN-32){instruction_register[31]}}, instruction_register[31:12], 12'b0};


            // J-TYPE

            // Used by:
            // JAL

            OPCODE_JAL: immediate = {{(XLEN-21){instruction_register[31]}}, instruction_register[31], instruction_register[19:12], instruction_register[20], instruction_register[30:21], 1'b0};


            default: immediate = {XLEN{1'b0}};

        endcase

    end


    // CONTROL SIGNALS

    reg reg_write;
    reg mem_write;
    reg mem_read;

    reg alu_src_immediate;

    reg branch;
    reg jump;
    reg jump_register;

    reg [3:0] alu_control;

    reg is_m_instruction;
    reg is_atomic_instruction;
    reg is_lr;
    reg is_sc;
    reg atomic_write;
    reg [4:0] atomic_operation;

    // Selects what is written back into the register file.

    // 00 = ALU result
    // 01 = Memory result
    // 10 = PC + 4
    // 11 = PC + imediate

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

        result_select = 2'b00;


        case (opcode)


            // R-TYPE

            // Used by:
            // ADD
            // SUB
            // SLL
            // SLT
            // SLTU
            // XOR
            // SRL
            // SRA
            // OR
            // AND
            // MUL
            // MULH
            // MULHSU
            // MULHU
            // DIV
            // DIVU
            // REM
            // REMU

            OPCODE_OP: begin

                reg_write = 1'b1;

                // The M extension uses funct7 = 000001.

                if (funct7 == 7'b0000001) begin
                    is_m_instruction = 1'b1;
                end

                else begin

                    case (funct3)

                        3'b000: begin

                            // ADD and SUB use funct7 to distinguish between them.

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

                            // SRL and SRA use funct7 to distinguish between them.

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


            // I-TYPE ALU

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

            OPCODE_OP_IMM: begin

                reg_write = 1'b1;

                // The second ALU input comes from the immediate instead of rs2.

                alu_src_immediate = 1'b1;

                case (funct3)

                    3'b000: alu_control = ALU_ADD;

                    3'b010: alu_control = ALU_SLT;

                    3'b011: alu_control = ALU_SLTU;

                    3'b100: alu_control = ALU_XOR;

                    3'b110: alu_control = ALU_OR;

                    3'b111: alu_control = ALU_AND;

                    3'b001: alu_control = ALU_SLL;

                    3'b101: begin

                        // SRLI and SRAI use funct7 to distinguish between them.

                        if (funct7 == 7'b0100000)
                            alu_control = ALU_SRA;
                        else
                            alu_control = ALU_SRL;

                    end

                    default: alu_control = ALU_ADD;

                endcase

            end


            // LOAD

            // Currently supports LW
            // The ALU calculates the memory address: address = rs1 + immediate

            OPCODE_LOAD: begin

                reg_write = 1'b1;
                mem_read = 1'b1;

                alu_src_immediate = 1'b1;

                alu_control = ALU_ADD;

                // Write data from memory back to rd.

                result_select = 2'b01;

            end


            // STORE

            // Currently supports SW.

            // The ALU calculates the memory address:
            // address = rs1 + immediate

            // The data comes from rs2.

            OPCODE_STORE: begin
                mem_write = 1'b1;
                alu_src_immediate = 1'b1;
                alu_control = ALU_ADD;
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
            end


            // LUI

            // Loads the upper 20 bits of the immediate into the destination register.

            OPCODE_LUI: begin
                reg_write = 1'b1;
                result_select = 2'b11;
            end


            // AUIPC

            // Adds the upper immediate to the current PC

            OPCODE_AUIPC: begin
                reg_write = 1'b1;
                result_select = 2'b11;
            end


            // JAL

            // Saves PC + 4 in rd
            // Jumps to PC + immediate

            OPCODE_JAL: begin
                reg_write = 1'b1;
                jump = 1'b1;
                result_select = 2'b10;
            end


            // JALR

            // Saves PC + 4 in rd
            // Jumps to rs1 + immediate

            OPCODE_JALR: begin
                reg_write = 1'b1;
                jump_register = 1'b1;
                alu_src_immediate = 1'b1;
                result_select = 2'b10;
            end


            // ATOMIC

            // Used by:
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

            OPCODE_ATOMIC: begin

                if (funct3 == 3'b010) begin

                    is_atomic_instruction = 1'b1;
                    reg_write = 1'b1;

                    case (funct7[6:2])

                        ATOMIC_LR: begin
                            is_lr = 1'b1;
                        end

                        ATOMIC_SC: begin
                            is_sc = 1'b1;
                        end

                        default: begin
                            atomic_write = 1'b1;
                            atomic_operation = funct7[6:2];
                        end

                    endcase

                end

            end


            default: begin
                // Unsupported instruction.
                // All control signals stay disabled.
            end

        endcase

    end


    // ALU INPUTS

    wire [XLEN-1:0] alu_input_a;

    wire [XLEN-1:0] alu_input_b;


    // The first ALU input always comes from the saved rs1 value

    assign alu_input_a = rs1_data_register;


    // The second ALU input can come from either the saved rs2 value or the immediate value

    assign alu_input_b = alu_src_immediate ? immediate_register : rs2_data_register;


    // ALU

    reg [XLEN-1:0] alu_result;

    always @(*) begin

        case (alu_control)

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

            default: alu_result = {XLEN{1'b0}};

        endcase

    end


    // M EXTENSION

    // Implements the RISC-V M multiply and divide instructions.

    reg [XLEN-1:0] m_result;
    reg signed [(2*XLEN)-1:0] signed_multiply;
    reg signed [(2*XLEN)-1:0] signed_multiply_hsu;
    reg [(2*XLEN)-1:0] unsigned_multiply;

    always @(*) begin

        signed_multiply = $signed(rs1_data_register) * $signed(rs2_data_register);
        signed_multiply_hsu = $signed(rs1_data_register) * $signed({{XLEN{1'b0}}, rs2_data_register});
        unsigned_multiply = {{XLEN{1'b0}}, rs1_data_register} * {{XLEN{1'b0}}, rs2_data_register};

        m_result = {XLEN{1'b0}};

        case (funct3)

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

                if (rs2_data_register == {XLEN{1'b0}})
                    m_result = {XLEN{1'b1}};
                else if ((rs1_data_register == {1'b1, {(XLEN-1){1'b0}}}) && (rs2_data_register == {XLEN{1'b1}}))
                    m_result = {1'b1, {(XLEN-1){1'b0}}};
                else
                    m_result = $signed(rs1_data_register) / $signed(rs2_data_register);

            end


            // DIVU
            3'b101: begin

                if (rs2_data_register == {XLEN{1'b0}})
                    m_result = {XLEN{1'b1}};
                else
                    m_result = rs1_data_register / rs2_data_register;

            end


            // REM

            3'b110: begin

                if (rs2_data_register == {XLEN{1'b0}})
                    m_result = rs1_data_register;
                else if ((rs1_data_register == {1'b1, {(XLEN-1){1'b0}}}) && (rs2_data_register == {XLEN{1'b1}}))
                    m_result = {XLEN{1'b0}};
                else
                    m_result = $signed(rs1_data_register) % $signed(rs2_data_register);

            end


            // REMU

            3'b111: begin

                if (rs2_data_register == {XLEN{1'b0}})
                    m_result = rs1_data_register;
                else
                    m_result = rs1_data_register % rs2_data_register;

            end


            default: m_result = {XLEN{1'b0}};

        endcase

    end


    // ATOMIC MEMORY OPERATION

    // The atomic instructions read a memory word, calculate a new value, and write the new value back as one atomic operation in this CPU.

    reg [XLEN-1:0] atomic_address;
    reg [XLEN-1:0] atomic_memory_data;
    reg [XLEN-1:0] atomic_result;
    reg [XLEN-1:0] atomic_old_value;
    reg atomic_sc_success;

    always @(*) begin

        atomic_address = rs1_data_register;
        atomic_memory_data = data_memory[atomic_address[DMEM_ADDR_WIDTH+1:2]];

        // The value returned in rd is the old memory value
        atomic_old_value = atomic_memory_data;

        // atomic_result is the new value written to memory
        atomic_result = atomic_memory_data;
        atomic_sc_success = 1'b0;

        if (is_sc) begin

            if (reservation_valid && (reservation_address == atomic_address))
                atomic_sc_success = 1'b1;

            atomic_result = atomic_sc_success ? {{(XLEN-1){1'b0}}, 1'b0} : {{(XLEN-1){1'b0}}, 1'b1};


        end

        else if (is_lr) begin

            atomic_result = atomic_memory_data;
        end

        else begin

            case (atomic_operation)

                // AMOADD.W
                ATOMIC_ADD: atomic_result = atomic_memory_data + rs2_data_register;

                // AMOSWAP.W
                ATOMIC_SWAP: atomic_result = rs2_data_register;

                // AMOXOR.W
                ATOMIC_XOR: atomic_result = atomic_memory_data ^ rs2_data_register;

                // AMOOR.W
                ATOMIC_OR: atomic_result = atomic_memory_data | rs2_data_register;

                // AMOAND.W
                ATOMIC_AND: atomic_result = atomic_memory_data & rs2_data_register;

                // AMOMIN.W
                ATOMIC_MIN: atomic_result = ($signed(atomic_memory_data) < $signed(rs2_data_register)) ? atomic_memory_data : rs2_data_register;

                // AMOMAX.W
                ATOMIC_MAX: atomic_result = ($signed(atomic_memory_data) > $signed(rs2_data_register)) ? atomic_memory_data : rs2_data_register;

                // AMOMINU.W
                ATOMIC_MINU: atomic_result = (atomic_memory_data < rs2_data_register) ? atomic_memory_data : rs2_data_register;

                // AMOMAXU.W
                ATOMIC_MAXU: atomic_result = (atomic_memory_data > rs2_data_register) ? atomic_memory_data : rs2_data_register;

                default: atomic_result = atomic_memory_data;

            endcase

        end

    end


    // BRANCH COMPARISON

    // Checks if the branch condition is true.

    reg branch_taken;

    always @(*) begin

        branch_taken = 1'b0;

        if (branch) begin

            case (funct3)

                // BEQ
                3'b000: branch_taken = (rs1_data_register == rs2_data_register);

                // BNE
                3'b001: branch_taken = (rs1_data_register != rs2_data_register);

                // BLT
                3'b100: branch_taken = ($signed(rs1_data_register) < $signed(rs2_data_register));

                // BGE
                3'b101: branch_taken = ($signed(rs1_data_register) >= $signed(rs2_data_register));

                // BLTU
                3'b110: branch_taken = (rs1_data_register < rs2_data_register);

                // BGEU
                3'b111: branch_taken = (rs1_data_register >= rs2_data_register);

                default: branch_taken = 1'b0;

            endcase

        end

    end


    // DATA MEMORY

    // The ALU calculates the address used to access the data memory

    // Holds the calculated memory address while the instruction moves through the memory state

    reg [XLEN-1:0] memory_address_register;


    // Read data from memory

    wire [XLEN-1:0] memory_read_data;

    assign memory_read_data = data_memory[memory_address_register[DMEM_ADDR_WIDTH+1:2]];


    // MEMORY DATA REGISTER

    // Holds memory data before the write back cycle

    reg [XLEN-1:0] memory_data_register;


    // ALU RESULT REGISTER

    // Holds the result of an ALU operation before the write back cycle

    reg [XLEN-1:0] alu_result_register;



    // ATOMIC DATA REGISTERS

    // Holds the atomic result and old value before the write back cycle

    reg [XLEN-1:0] atomic_result_register;
    reg [XLEN-1:0] atomic_old_value_register;


    // WRITE BACK

    // Selects the value that will be written
    // back into the register file.

    reg [XLEN-1:0] write_back_data;

    always @(*) begin

        if (is_m_instruction) begin
            write_back_data = m_result;

        end

        else if (is_atomic_instruction) begin


            if (is_sc)
                write_back_data = atomic_result_register;
            else if (is_lr)
                write_back_data = memory_data_register;
            else
                write_back_data = atomic_old_value_register;

        end

        else begin

            case (result_select)

                // ALU result
                2'b00: write_back_data = alu_result_register;

                // Memory result
                2'b01: write_back_data = memory_data_register;

                // PC + 4
                2'b10: write_back_data = instruction_pc + {{(XLEN-3){1'b0}}, 3'd4};

                // PC + immediate

                // Used by LUI and AUIPC

                2'b11: begin
                    if (opcode == OPCODE_LUI)
                        write_back_data = immediate_register;
                    else
                        write_back_data = instruction_pc + immediate_register;

                end

                default: write_back_data = alu_result_register;

            endcase

        end

    end


    // NEXT PROGRAM COUNTER

    // Normaly the PC increases by 4

    // For a branch or jump the PC changes to the target adress instead

    reg [XLEN-1:0] next_pc;

    always @(*) begin

        // The next sequentail instruction is already selected in the fetch state

        next_pc = pc;

        // Conditional branch

        if (branch && branch_taken)
            next_pc = instruction_pc + immediate_register;

        // JAL

        if (jump)
            next_pc = instruction_pc + immediate_register;

        // JALR

        // Bit 0 is cleared according to the RISC-V specification

        if (jump_register)
            next_pc = (rs1_data_register + immediate_register) & {{(XLEN-1){1'b1}}, 1'b0};

    end


    // CPU SEQUENTIAL LOGIC

    // The PC, register file, and multi-cycle state are updated on the rising edge of the clock

    integer i;

    always @(posedge clk) begin

        if (rst) begin

            // Reset the PC

            pc <= {XLEN{1'b0}};

            // Reset the instruction register

            instruction_register <= 32'h00000013;

            // Reset the instruction PC

            instruction_pc <= {XLEN{1'b0}};

            // Reset decoded register values

            rs1_data_register <= {XLEN{1'b0}};
            rs2_data_register <= {XLEN{1'b0}};
            immediate_register <= {XLEN{1'b0}};

            // Reset datapath registers

            alu_result_register <= {XLEN{1'b0}};
            memory_address_register <= {XLEN{1'b0}};
            memory_data_register <= {XLEN{1'b0}};
            atomic_result_register <= {XLEN{1'b0}};
            atomic_old_value_register <=  {XLEN{1'b0}};

            // Reset all registers

            for (i = 0; i < 32; i = i + 1)
                registers[i] <= {XLEN{1'b0}};

            // Reset the atomic reservation

            reservation_valid <= 1'b0;
            reservation_address <= {XLEN{1'b0}};

            // Reset the CPU state

            state <= STATE_FETCH;

        end

        else begin

            // CPU state machine

            state <= next_state;


            // FETCH

            if (state == STATE_FETCH) begin

                // Load the instruction into the instruction register

                instruction_register <= instruction;

                // Save the address of the current instruction

                instruction_pc <= pc;

                // Move to the next sequential instruction

                pc <= pc + {{(XLEN-3){1'b0}}, 3'd4};

            end


            // DECODE

            if (state == STATE_DECODE) begin

                // Save the source register values

                rs1_data_register <= rs1_data;
                rs2_data_register <= rs2_data;

                // Save the immediate value

                immediate_register <= immediate;

            end


            // EXECUTE

            if (state == STATE_EXECUTE) begin

                // Save the ALU result

                alu_result_register <= alu_result;

                // Save the memory address for load/store instructions

                memory_address_register <= alu_result;

                // Change PC for branches and jumps

                if ((branch && branch_taken) || jump || jump_register)
                    pc <= next_pc;



            end


            // MEMORY

            if (state == STATE_MEMORY) begin

                if (mem_read)
                    memory_data_register <= memory_read_data;


                // Store data into memory

                if (mem_write)
                    data_memory[memory_address_register[DMEM_ADDR_WIDTH+1:2]] <= rs2_data_register;


                // LR.W reads a memory word and creates a reservation

                if (is_lr) begin

                    memory_data_register <= atomic_memory_data;

                    reservation_valid <= 1'b1;
                    reservation_address <= atomic_address;

                end


                // SC.W stores the data only when the reservation is still valid

                if (is_sc) begin

                    atomic_result_register <= atomic_result;

                    if (atomic_sc_success)
                        data_memory[atomic_address[DMEM_ADDR_WIDTH+1:2]] <= rs2_data_register;

                    reservation_valid <= 1'b0;

                end


                // AMO instructions always read and write the selected memory wrod

                if (is_atomic_instruction && atomic_write) begin

                    atomic_old_value_register <= atomic_old_value;

                    data_memory[atomic_address[DMEM_ADDR_WIDTH+1:2]] <= atomic_result;

                    reservation_valid <= 1'b0;

                end

            end


            // WRITE BACK

            if (state == STATE_WRITEBACK) begin

                // x0 cannot be written because it must always contain zero

                if (reg_write && (rd != 5'd0))
                    registers[rd] <= write_back_data;

            end


            // A normal store removes the reservation in this single-CPU implementation

            if (state == STATE_MEMORY && mem_write)
                reservation_valid <= 1'b0;


            // Make sure x0 always stays zero

            registers[0] <= {XLEN{1'b0}};

        end
    end


    // NEXT STATE LOGIC

    // Determines which cycle comes next for the current instruction.

    always @(*) begin

        next_state = STATE_FETCH;

        case (state)

            // FETCH

            STATE_FETCH:
                next_state = STATE_DECODE;

            // DECODE

            STATE_DECODE:
                next_state = STATE_EXECUTE;


            // EXECUTE

            STATE_EXECUTE: begin

                // Loads, stores, and atomic instructions need the memory cycle

                if (mem_read || mem_write || is_atomic_instruction)
                    next_state = STATE_MEMORY;
                else if (reg_write)
                    next_state = STATE_WRITEBACK;
                else
                    next_state = STATE_FETCH;

            end


            // MEMORY

            STATE_MEMORY: begin

                // Loads and instructions that write a result need the write back cycle

                if (mem_read || is_atomic_instruction)
                    next_state = STATE_WRITEBACK;
                else
                    next_state = STATE_FETCH;

            end



            // WRITE BACK

            STATE_WRITEBACK:
                next_state = STATE_FETCH;


            default:
                next_state = STATE_FETCH;

        endcase

    end


    // MEMORY INITIALIZATION

    // Initialize instruction memory with NOP instructions

    // NOP = ADDI x0, x0, 0

    integer j;

    initial begin

        for (j = 0; j < IMEM_SIZE; j = j + 1)
            instruction_memory[j] = 32'h00000013;


        // Initialize data memory to zero

        for (j = 0; j < DMEM_SIZE; j = j + 1)
            data_memory[j] = {XLEN{1'b0}};


        // Example program:

        // ADDI x1, x0, 10
        // ADDI x2, x0, 20
        // ADD  x3, x1, x2
        // SW   x3, 0(x0)
        // LW   x4, 0(x0)

        // Result:

        // x1 = 10
        // x2 = 20
        // x3 = 30
        // x4 = 30

        instruction_memory[0] = 32'h00A00093;
        instruction_memory[1] = 32'h01400113;
        instruction_memory[2] = 32'h002081B3;
        instruction_memory[3] = 32'h00302023;
        instruction_memory[4] = 32'h00002203;

    end


    // DEBUG OUTPUTS

    // These signals can be used in the testbench and viewed in GTKWave

    assign debug_pc = pc;

    assign debug_instruction = instruction_register;

    assign debug_result = write_back_data;


endmodule
