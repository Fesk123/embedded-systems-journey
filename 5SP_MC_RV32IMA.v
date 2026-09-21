`timescale 1ns/1ps

// A simple parameterized pipelined RISC-V processor based on the RV32IMA ISA.

// The architecture is inspired by the Bitspinner RV32I
// Link: https://www.bit-spinner.com/rv32i/rv32i-data-memory

// Multi-cycle design inspired by Bitspinner
// Link: https://www.bit-spinner.com/rv32i-multi-cycle/rv32i-multi-cycle-introduction

// Pipelined design uses the same datapath as the previous multi-cycle design and is divided into five pipeline stages.


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
//  - Hazard Detection
//  - Forwarding logic
//  - Pipeline registers


module RV32IMA_5SP_CPU #(

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

    // Since every base RISC-V instruction is 32 bits and normally aligned to 4 bytes, divide the byte address by 4

    wire [31:0] instruction;

    assign instruction = instruction_memory[pc[IMEM_ADDR_WIDTH+1:2]];


    // IF / ID PIPELINE REGISTER

    // Holds the fetched instruction and its PC before the decode stage.

    reg IF_ID_valid;
    reg [XLEN-1:0] IF_ID_pc;
    reg [31:0] IF_ID_instruction;

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
    wire [6:0] funct7;

    assign opcode = IF_ID_instruction[6:0];
    assign rd = IF_ID_instruction[11:7];
    assign funct3 = IF_ID_instruction[14:12];
    assign rs1 = IF_ID_instruction[19:15];
    assign rs2 = IF_ID_instruction[24:20];
    assign funct7 = IF_ID_instruction[31:25];


    // REGISTER FILE READ

    // The register file has two asynchronous read ports
    // Reading x0 always returns zero

    wire [XLEN-1:0] rs1_data;
    wire [XLEN-1:0] rs2_data;

    assign rs1_data = (rs1 == 5'd0) ? {XLEN{1'b0}} : registers[rs1];
    assign rs2_data = (rs2 == 5'd0) ? {XLEN{1'b0}} : registers[rs2];


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

            OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_JALR: immediate = {{(XLEN-12){IF_ID_instruction[31]}}, IF_ID_instruction[31:20]};


            // S-TYPE

            // Used by:
            // SW

            OPCODE_STORE: immediate = {{(XLEN-12){IF_ID_instruction[31]}}, IF_ID_instruction[31:25], IF_ID_instruction[11:7]};


            // B-TYPE

            // Used by:
            // BEQ
            // BNE
            // BLT
            // BGE
            // BLTU
            // BGEU

            // The lowest bit is always zero because branches are aligned

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

    reg use_rs1;
    reg use_rs2;

    // Selects what is written back into the register file.

    // 00 = ALU result
    // 01 = Memory result
    // 10 = PC + 4
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

        use_rs1 = 1'b0;
        use_rs2 = 1'b0;

        result_select = 2'b00;


        if (IF_ID_valid) begin

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
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;

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
                    use_rs1 = 1'b1;

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
                    use_rs1 = 1'b1;

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
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;
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
                    use_rs1 = 1'b1;
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
                        use_rs1 = 1'b1;

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

                end


                default: begin
                    // Unsupported instruction.
                    // All control signals stay disabled.
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
    reg [3:0] ID_EX_alu_control;

    reg ID_EX_is_m_instruction;
    reg ID_EX_is_atomic_instruction;
    reg ID_EX_is_lr;
    reg ID_EX_is_sc;
    reg ID_EX_atomic_write;
    reg [4:0] ID_EX_atomic_operation;

    reg [1:0] ID_EX_result_select;


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


    // ALU INPUTS

    wire [XLEN-1:0] alu_input_a;

    wire [XLEN-1:0] alu_input_b;

    // The first ALU input comes from the forwarded rs1 value

    assign alu_input_a = forwarded_rs1_data;

    // The second ALU input can come from either the forwarded rs2 value or the immediate value

    assign alu_input_b = ID_EX_alu_src_immediate ? ID_EX_immediate : forwarded_rs2_data;


    // ALU

    reg [XLEN-1:0] alu_result;

    always @(*) begin

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

        signed_multiply = $signed(forwarded_rs1_data) * $signed(forwarded_rs2_data);
        signed_multiply_hsu = $signed(forwarded_rs1_data) * $signed({{XLEN{1'b0}}, forwarded_rs2_data});
        unsigned_multiply = {{XLEN{1'b0}}, forwarded_rs1_data} * {{XLEN{1'b0}}, forwarded_rs2_data};

        m_result = {XLEN{1'b0}};

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


    // ATOMIC MEMORY OPERATION

    // The atomic instructions read a memory word, calculate a new value, and write the new value back as one atomic operation in this CPU.

    wire [XLEN-1:0] atomic_address;
    wire [XLEN-1:0] atomic_memory_data;
    reg [XLEN-1:0] atomic_result;
    reg [XLEN-1:0] atomic_old_value;
    reg atomic_sc_success;

    assign atomic_address = EX_MEM_atomic_address;
    assign atomic_memory_data = data_memory[atomic_address[DMEM_ADDR_WIDTH+1:2]];

    always @(*) begin

        atomic_old_value = atomic_memory_data;
        atomic_result = atomic_memory_data;
        atomic_sc_success = 1'b0;

        if (EX_MEM_is_sc) begin

            if (reservation_valid && (reservation_address == atomic_address))
                atomic_sc_success = 1'b1;

            atomic_result = atomic_sc_success ? {{(XLEN-1){1'b0}}, 1'b0} : {{(XLEN-1){1'b0}}, 1'b1};

        end

        else if (EX_MEM_is_lr) begin

            atomic_result = atomic_memory_data;

        end

        else begin

            case (EX_MEM_atomic_operation)

                // AMOADD.W
                ATOMIC_ADD: atomic_result = atomic_memory_data + EX_MEM_atomic_rs2_data;

                // AMOSWAP.W
                ATOMIC_SWAP: atomic_result = EX_MEM_atomic_rs2_data;

                // AMOXOR.W
                ATOMIC_XOR: atomic_result = atomic_memory_data ^ EX_MEM_atomic_rs2_data;

                // AMOOR.W
                ATOMIC_OR: atomic_result = atomic_memory_data | EX_MEM_atomic_rs2_data;

                // AMOAND.W
                ATOMIC_AND: atomic_result = atomic_memory_data & EX_MEM_atomic_rs2_data;

                // AMOMIN.W
                ATOMIC_MIN: atomic_result = ($signed(atomic_memory_data) < $signed(EX_MEM_atomic_rs2_data)) ? atomic_memory_data : EX_MEM_atomic_rs2_data;

                // AMOMAX.W
                ATOMIC_MAX: atomic_result = ($signed(atomic_memory_data) > $signed(EX_MEM_atomic_rs2_data)) ? atomic_memory_data : EX_MEM_atomic_rs2_data;

                // AMOMINU.W
                ATOMIC_MINU: atomic_result = (atomic_memory_data < EX_MEM_atomic_rs2_data) ? atomic_memory_data : EX_MEM_atomic_rs2_data;

                // AMOMAXU.W
                ATOMIC_MAXU: atomic_result = (atomic_memory_data > EX_MEM_atomic_rs2_data) ? atomic_memory_data : EX_MEM_atomic_rs2_data;

                default: atomic_result = atomic_memory_data;

            endcase

        end

    end


    // BRANCH COMPARISON

    // Checks if the branch condition is true.

    reg branch_taken;

    always @(*) begin

        branch_taken = 1'b0;

        if (ID_EX_branch) begin

            case (ID_EX_funct3)

                // BEQ
                3'b000: branch_taken = (forwarded_rs1_data == forwarded_rs2_data);

                // BNE
                3'b001: branch_taken = (forwarded_rs1_data != forwarded_rs2_data);

                // BLT
                3'b100: branch_taken = ($signed(forwarded_rs1_data) < $signed(forwarded_rs2_data));

                // BGE
                3'b101: branch_taken = ($signed(forwarded_rs1_data) >= $signed(forwarded_rs2_data));

                // BLTU
                3'b110: branch_taken = (forwarded_rs1_data < forwarded_rs2_data);

                // BGEU
                3'b111: branch_taken = (forwarded_rs1_data >= forwarded_rs2_data);

                default: branch_taken = 1'b0;

            endcase

        end

    end


    // NEXT PROGRAM COUNTER

    // Normaly the PC increases by 4

    // For a branch or jump the PC changes to the target adress instead

    reg [XLEN-1:0] next_pc;

    always @(*) begin

        next_pc = ID_EX_pc + {{(XLEN-3){1'b0}}, 3'd4};

        // Conditional branch

        if (ID_EX_branch && branch_taken)
            next_pc = ID_EX_pc + ID_EX_immediate;

        // JAL

        if (ID_EX_jump)
            next_pc = ID_EX_pc + ID_EX_immediate;

        // JALR

        // Bit 0 is cleared according to the RISC-V specification

        if (ID_EX_jump_register)
            next_pc = (forwarded_rs1_data + ID_EX_immediate) & {{(XLEN-1){1'b1}}, 1'b0};

    end


    // EXECUTE RESULT

    // Selects the result that will continue to the memory and write back stages.

    reg [XLEN-1:0] execute_result;

    always @(*) begin

        if (ID_EX_is_m_instruction) begin
            execute_result = m_result;

        end

        else begin

            case (ID_EX_result_select)

                // ALU result
                2'b00: execute_result = alu_result;

                // Memory address
                2'b01: execute_result = alu_result;

                // PC + 4
                2'b10: execute_result = ID_EX_pc + {{(XLEN-3){1'b0}}, 3'd4};

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

    reg EX_MEM_is_m_instruction;
    reg EX_MEM_is_atomic_instruction;
    reg EX_MEM_is_lr;
    reg EX_MEM_is_sc;
    reg EX_MEM_atomic_write;
    reg [4:0] EX_MEM_atomic_operation;
    reg [XLEN-1:0] EX_MEM_atomic_address;
    reg [XLEN-1:0] EX_MEM_atomic_rs2_data;

    // Debug aliases for the current pipeline values

    wire [XLEN-1:0] alu_result_register;
    wire [XLEN-1:0] memory_address_register;

    assign alu_result_register = EX_MEM_result;
    assign memory_address_register = EX_MEM_result;


    // DATA MEMORY

    // The ALU calculates the address used to access the data memory

    // Read data from memory

    wire [XLEN-1:0] memory_read_data;

    assign memory_read_data = data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+1:2]];


    // MEMORY DATA REGISTER

    // Holds memory data before the write back cycle

    reg [XLEN-1:0] memory_data_register;


    // MEM / WB PIPELINE REGISTER

    // Holds the final result before it is written to the register file.

    reg MEM_WB_valid;
    reg [XLEN-1:0] MEM_WB_write_data;
    reg [4:0] MEM_WB_rd;
    reg MEM_WB_reg_write;


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


    // CPU SEQUENTIAL LOGIC

    // The PC, register file, and pipeline registers are updated on the rising edge of the clock

    integer i;

    always @(posedge clk) begin

        if (rst) begin

            // Reset the PC

            pc <= {XLEN{1'b0}};

            // Reset the pipeline registers

            IF_ID_valid <= 1'b0;
            IF_ID_pc <= {XLEN{1'b0}};
            IF_ID_instruction <= 32'h00000013;

            ID_EX_valid <= 1'b0;
            ID_EX_pc <= {XLEN{1'b0}};
            ID_EX_rs1_data <= {XLEN{1'b0}};
            ID_EX_rs2_data <= {XLEN{1'b0}};
            ID_EX_immediate <= {XLEN{1'b0}};
            ID_EX_rs1 <= 5'd0;
            ID_EX_rs2 <= 5'd0;
            ID_EX_rd <= 5'd0;
            ID_EX_funct3 <= 3'b000;
            ID_EX_funct7 <= 7'b0000000;
            ID_EX_opcode <= 7'b0010011;

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
            ID_EX_result_select <= 2'b00;

            EX_MEM_valid <= 1'b0;
            EX_MEM_result <= {XLEN{1'b0}};
            EX_MEM_store_data <= {XLEN{1'b0}};
            EX_MEM_rd <= 5'd0;
            EX_MEM_reg_write <= 1'b0;
            EX_MEM_mem_write <= 1'b0;
            EX_MEM_mem_read <= 1'b0;
            EX_MEM_is_m_instruction <= 1'b0;
            EX_MEM_is_atomic_instruction <= 1'b0;
            EX_MEM_is_lr <= 1'b0;
            EX_MEM_is_sc <= 1'b0;
            EX_MEM_atomic_write <= 1'b0;
            EX_MEM_atomic_operation <= ATOMIC_ADD;
            EX_MEM_atomic_address <= {XLEN{1'b0}};
            EX_MEM_atomic_rs2_data <= {XLEN{1'b0}};

            memory_data_register <= {XLEN{1'b0}};

            MEM_WB_valid <= 1'b0;
            MEM_WB_write_data <= {XLEN{1'b0}};
            MEM_WB_rd <= 5'd0;
            MEM_WB_reg_write <= 1'b0;

            // Reset all registers

            for (i = 0; i < 32; i = i + 1)
                registers[i] <= {XLEN{1'b0}};

            // Reset the atomic reservation

            reservation_valid <= 1'b0;
            reservation_address <= {XLEN{1'b0}};

        end

        else begin

            // WRITE BACK

            // x0 cannot be written because it must always contain zero

            if (MEM_WB_valid && MEM_WB_reg_write && (MEM_WB_rd != 5'd0))
                registers[MEM_WB_rd] <= MEM_WB_write_data;


            // MEMORY

            // Move the current memory result into the write back pipeline register.

            MEM_WB_valid <= EX_MEM_valid;
            MEM_WB_rd <= EX_MEM_rd;
            MEM_WB_reg_write <= EX_MEM_reg_write;

            if (EX_MEM_valid && EX_MEM_mem_read) begin

                memory_data_register <= memory_read_data;
                MEM_WB_write_data <= memory_read_data;
            end

            else if (EX_MEM_valid && EX_MEM_is_atomic_instruction) begin

                // LR.W reads a memory word and creates a reservation

                if (EX_MEM_is_lr) begin

                    memory_data_register <= data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+1:2]];
                    MEM_WB_write_data <= data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+1:2]];

                    reservation_valid <= 1'b1;

                    reservation_address <= EX_MEM_atomic_address;

                end

                // SC.W stores the data only when the reservation is still valid

                else if (EX_MEM_is_sc) begin

                    if (reservation_valid && (reservation_address == EX_MEM_atomic_address)) begin
                        data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+1:2]] <= EX_MEM_atomic_rs2_data;
                        
                        MEM_WB_write_data <= {{(XLEN-1){1'b0}}, 1'b0};
                    end

                    else begin
                        MEM_WB_write_data <= {{(XLEN-1){1'b0}}, 1'b1};
                    end



                    reservation_valid <= 1'b0;

                end

                // AMO instructions always read and write the selected memory word

                else if (EX_MEM_atomic_write) begin
                    MEM_WB_write_data <= data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+1:2]];

                    data_memory[EX_MEM_atomic_address[DMEM_ADDR_WIDTH+1:2]] <= atomic_result;

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

            if (EX_MEM_valid && EX_MEM_mem_write)
                data_memory[EX_MEM_result[DMEM_ADDR_WIDTH+1:2]] <= EX_MEM_store_data;

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

            EX_MEM_is_m_instruction <= ID_EX_is_m_instruction;
            EX_MEM_is_atomic_instruction <= ID_EX_is_atomic_instruction;
            EX_MEM_is_lr <= ID_EX_is_lr;
            EX_MEM_is_sc <= ID_EX_is_sc;
            EX_MEM_atomic_write <= ID_EX_atomic_write;
            EX_MEM_atomic_operation <= ID_EX_atomic_operation;
            EX_MEM_atomic_address <= alu_result;
            EX_MEM_atomic_rs2_data <= forwarded_rs2_data;


            // CONTROL HAZARDS

            if (branch_taken || ID_EX_jump || ID_EX_jump_register) begin

                // Flush the instructions that were fetched after the taken branch or jump.

                pc <= next_pc;

                IF_ID_valid <= 1'b0;
                IF_ID_pc <= {XLEN{1'b0}};
                IF_ID_instruction <= 32'h00000013;

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

            end

            else if (load_use_stall) begin

                // Hold the instruction in the decode stage and insert a bubble into execute.

                pc <= pc;

                IF_ID_valid <= IF_ID_valid;
                IF_ID_pc <= IF_ID_pc;
                IF_ID_instruction <= IF_ID_instruction;

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

            end

            else begin

                // IF

                // Fetch the next instruction into the IF/ID pipeline register.

                IF_ID_valid <= 1'b1;
                IF_ID_pc <= pc;
                IF_ID_instruction <= instruction;

                // The next sequential instruction is selected in the fetch stage

                pc <= pc + {{(XLEN-3){1'b0}}, 3'd4};


                // ID

                // Save the decoded register values and control signals.

                ID_EX_valid <= IF_ID_valid;
                ID_EX_pc <= IF_ID_pc;
                ID_EX_rs1_data <= rs1_data;
                ID_EX_rs2_data <= rs2_data;
                ID_EX_immediate <= immediate;

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

                ID_EX_result_select <= result_select;

            end


            // Make sure x0 always stays zero

            registers[0] <= {XLEN{1'b0}};

        end
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

    assign debug_instruction = IF_ID_instruction;

    assign debug_result = MEM_WB_write_data;


endmodule // Ends the module (important)