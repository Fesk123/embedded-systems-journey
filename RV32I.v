`timescale 1ns/1ps

// A simple 32-bit RISC-V processor based on the RV32I ISA.

// The architecture is inspired by the Bitspinner RV32I
// Link: https://www.bit-spinner.com/rv32i/rv32i-data-memory


// The RV32I contains:
//  - Program Counter (PC)
//  - Instruction Memory
//  - Register File (32 x 32-bit)
//  - Immediate Generator
//  - ALU
//  - Branch / Jump Logic
//  - Data Memory
//  - Instruction Decoder
//  - Write Back logic


module RV32I_CPU (

    input wire clk,
    input wire rst,

    // Debug outputs
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire [31:0] debug_result

);


    // Parameters

    // Number of 32-bit words in instruction/data memory
    // 256 words = 1024 bytes

    parameter IMEM_SIZE = 256;
    parameter DMEM_SIZE = 256;


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


    // REGISTERS AND MEMORIES


    // Program Counter

    reg [31:0] pc;


    // 32 general purpose registers
    // x0 is hardwired to zero according to the RISC-V specification

    reg [31:0] registers [0:31];


    // Instruction memory
    // Each address contains one 32-bit instruction

    reg [31:0] instruction_memory [0:IMEM_SIZE-1];


    // Data memory
    // Used by LW and SW instructions

    reg [31:0] data_memory [0:DMEM_SIZE-1];


    // INSTRUCTION

    wire [31:0] instruction;


    // Since every RV32I instruction is 32 bits and normally aligned to 4 bytes, divide the byte address by 4

    assign instruction = instruction_memory[pc[31:2]];


    // INSTRUCTION FIELDS

    // These fields are present in different instruction formats and are extracted directly from the instruction

    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;

    assign opcode = instruction[6:0];
    assign rd = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign funct7 = instruction[31:25];


    // REGISTER FILE READ

    // The register file has two asynchronous read ports
    // Reading x0 always returns zero

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    assign rs1_data = (rs1 == 5'd0) ? 32'd0 : registers[rs1];
    assign rs2_data = (rs2 == 5'd0) ? 32'd0 : registers[rs2];


    // IMMEDIATE GENERATOR

    // RISC-V's immediate formats:
    // I-type
    // S-type
    // B-type
    // U-type
    // J-type

    // The immediate is selected based on the opcode

    reg [31:0] immediate;

    always @(*) begin

        immediate = 32'd0;

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

            OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_JALR:
                immediate = {{20{instruction[31]}}, instruction[31:20]};


            // S-TYPE

            // Used by:
            // SW

            OPCODE_STORE:
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};


            // B-TYPE

            // Used by:
            // BEQ
            // BNE
            // BLT
            // BGE
            // BLTU
            // BGEU

            // The lowest bit is always zero because branches are aligned

            OPCODE_BRANCH:
                immediate = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};


            // U-TYPE

            // Used by:
            // LUI
            // AUIPC

            OPCODE_LUI, OPCODE_AUIPC:
                immediate = {instruction[31:12], 12'b0};


            // J-TYPE

            // Used by:
            // JAL

            OPCODE_JAL:
                immediate = {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};


            default:
                immediate = 32'd0;

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

            OPCODE_OP: begin

                reg_write = 1'b1;

                case (funct3)

                    3'b000: begin

                        // ADD and SUB use funct7 to distinguish between them.

                        if (funct7 == 7'b0100000)
                            alu_control = ALU_SUB;
                        else
                            alu_control = ALU_ADD;

                    end

                    3'b001:
                        alu_control = ALU_SLL;

                    3'b010:
                        alu_control = ALU_SLT;

                    3'b011:
                        alu_control = ALU_SLTU;

                    3'b100:
                        alu_control = ALU_XOR;

                    3'b101: begin

                        // SRL and SRA use funct7 to distinguish between them.

                        if (funct7 == 7'b0100000)
                            alu_control = ALU_SRA;
                        else
                            alu_control = ALU_SRL;

                    end

                    3'b110:
                        alu_control = ALU_OR;

                    3'b111:
                        alu_control = ALU_AND;

                    default:
                        alu_control = ALU_ADD;

                endcase

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

                    3'b000:
                        alu_control = ALU_ADD;

                    3'b010:
                        alu_control = ALU_SLT;

                    3'b011:
                        alu_control = ALU_SLTU;

                    3'b100:
                        alu_control = ALU_XOR;

                    3'b110:
                        alu_control = ALU_OR;

                    3'b111:
                        alu_control = ALU_AND;

                    3'b001:
                        alu_control = ALU_SLL;

                    3'b101: begin

                        // SRLI and SRAI use funct7 to distinguish between them.

                        if (funct7 == 7'b0100000)
                            alu_control = ALU_SRA;
                        else
                            alu_control = ALU_SRL;

                    end

                    default:
                        alu_control = ALU_ADD;

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


            default: begin
                // Unsupported instruction.
                // All control signals stay disabled.
            end

        endcase

    end


    // ALU INPUTS

    wire [31:0] alu_input_a;
    wire [31:0] alu_input_b;


    // The first ALU input always comes from rs1

    assign alu_input_a = rs1_data;


    // The second ALU input can come from either rs2 or the immediate value

    assign alu_input_b = alu_src_immediate ? immediate : rs2_data;


    // ALU

    reg [31:0] alu_result;

    always @(*) begin

        case (alu_control)

            ALU_ADD:
                alu_result = alu_input_a + alu_input_b;


            ALU_SUB:
                alu_result = alu_input_a - alu_input_b;


            ALU_SLL:
                alu_result = alu_input_a << alu_input_b[4:0];


            ALU_SLT:
                alu_result = ($signed(alu_input_a) < $signed(alu_input_b)) ? 32'd1 : 32'd0;


            ALU_SLTU:
                alu_result = (alu_input_a < alu_input_b) ? 32'd1 : 32'd0;


            ALU_XOR:
                alu_result = alu_input_a ^ alu_input_b;


            ALU_SRL:
                alu_result = alu_input_a >> alu_input_b[4:0];


            ALU_SRA:
                alu_result = $signed(alu_input_a) >>> alu_input_b[4:0];


            ALU_OR:
                alu_result = alu_input_a | alu_input_b;


            ALU_AND:
                alu_result = alu_input_a & alu_input_b;


            default:
                alu_result = 32'd0;

        endcase

    end


    // BRANCH COMPARISON

    // Checks if the branch condition is true.

    reg branch_taken;

    always @(*) begin

        branch_taken = 1'b0;

        if (branch) begin

            case (funct3)


                // BEQ

                3'b000:
                    branch_taken = (rs1_data == rs2_data);


                // BNE

                3'b001:
                    branch_taken = (rs1_data != rs2_data);


                // BLT
                3'b100:
                    branch_taken = ($signed(rs1_data) < $signed(rs2_data));


                // BGE

                3'b101:
                    branch_taken = ($signed(rs1_data) >= $signed(rs2_data));


                // BLTU

                3'b110:
                    branch_taken = (rs1_data < rs2_data);


                // BGEU

                3'b111:
                    branch_taken = (rs1_data >= rs2_data);


                default:
                    branch_taken = 1'b0;

            endcase

        end

    end


    // DATA MEMORY

    // The ALU calculates the address used to access the data memory

    wire [31:0] memory_address;

    assign memory_address = alu_result;


    // Read data from memory

    wire [31:0] memory_read_data;

    assign memory_read_data = data_memory[memory_address[31:2]];


    // WRITE BACK

    // Selects the value that will be written
    // back into the register file.

    reg [31:0] write_back_data;

    always @(*) begin

        case (result_select)


            // ALU result
            2'b00:
                write_back_data = alu_result;


            // Memory result

            2'b01:
                write_back_data = memory_read_data;


            // PC + 4

            2'b10:
                write_back_data = pc + 32'd4;


            // PC + immediate

            // Used by LUI and AUIPC
            
            2'b11: begin

                if (opcode == OPCODE_LUI)
                    write_back_data = immediate;

                else
                    write_back_data = pc + immediate;

            end


            default:
                write_back_data = alu_result;

        endcase

    end


    // NEXT PROGRAM COUNTER

    // Normally the PC increases by 4

    // For a branch or jump the PC changes to the target address instead

    reg [31:0] next_pc;

    always @(*) begin

        // Normal instruction flow

        next_pc = pc + 32'd4;


        // Conditional branch

        if (branch && branch_taken)
            next_pc = pc + immediate;


        // JAL

        if (jump)
            next_pc = pc + immediate;


        // JALR
        
        // Bit 0 is cleared according to the RISC-V specification

        if (jump_register)
            next_pc = (rs1_data + immediate) & 32'hFFFFFFFE;

    end


    // CPU SEQUENTIAL LOGIC

    // The PC and register file are updated on the rising edge of the clock

    integer i;

    always @(posedge clk) begin

        if (rst) begin

            // Reset the PC

            pc <= 32'd0;


            // Reset all registers

            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;

        end

        else begin

            // Update the PC

            pc <= next_pc;


            // Write the result back to the register file
            
            // x0 cannot be written because it must always contain zero

            if (reg_write && (rd != 5'd0))
                registers[rd] <= write_back_data;


            // Store data into memory

            if (mem_write)
                data_memory[memory_address[31:2]] <= rs2_data;


            // Make sure x0 always stays zero

            registers[0] <= 32'd0;

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
            data_memory[j] = 32'd0;


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

    assign debug_instruction = instruction;

    assign debug_result = write_back_data;


endmodule