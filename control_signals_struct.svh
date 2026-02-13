`ifndef CONTROL_SIGNALS_STRUCT_SVH
`define CONTROL_SIGNALS_STRUCT_SVH

typedef struct packed {
    logic [63:0] imm;
    logic [6:0] opcode;
    logic [63:0] shamt;
    logic [7:0] instruction;
    logic [2:0] data_size;
    logic read_memory_access;
    logic write_memory_access;
    logic [4:0] dest_reg;
    logic jump_signal;              // Domino to halt everything prev
    logic [63:0] pc;
    logic signed_type;
} control_signals_struct;

`endif