typedef struct packed {
    logic [63:0] pc;            // Program Counter
    logic [31:0] instruction;   // Fetched instruction
} if_id_reg_struct;

typedef struct packed {
    logic [63:0] pc;              // Program Counter
    logic [31:0] reg_data1;       // Data from register file
    logic [31:0] reg_data2;       // Data from register file
    logic [31:0] imm;             // Immediate value
    logic [4:0]  rs1, rs2, rd;    // Register addresses
    logic [3:0]  alu_control;     // ALU control signals
    logic        reg_write;       // Control signal for register write
} id_ex_reg_struct;

typedef struct packed {
    logic [31:0] alu_result;     // Result from ALU
    logic [31:0] reg_data2;      // Data to be stored to memory
    logic [4:0]  rd;             // Destination register
    logic        mem_write;      // Control signal for memory write
    logic        reg_write;      // Control signal for register write
} ex_mem_reg_struct;

typedef struct packed {
    logic [31:0] alu_result;    // Result from ALU or memory
    logic [31:0] mem_read_data; // Data read from memory
    logic [4:0]  rd;            // Destination register
    logic        reg_write;     // Control signal for register write
} mem_wb_reg_struct;