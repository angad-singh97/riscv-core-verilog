`include "control_signals_struct.svh"
/* module InstructionWriteBack (
    input  logic        clk,                          // Clock signal
    input  logic        reset,                        // Active-low reset
    input  logic [63:0] loaded_data,                  // Loaded data
    input  logic [63:0] alu_data,                     // ALU result data
    input  logic [63:0] control_signals,              // Control Signals
    output  logic [63:0] dest_reg_out,              // Control Signals
    output  logic [63:0] data_out,              // Control Signals
    output logic        write_back_done               // Ready signal indicating fetch completion
);
endmodule */

module InstructionWriteBack 
#()
(
    input logic clk,
    input logic reset,

    input [63:0] alu_result,
    input [63:0] loaded_data,
    input  control_signals_struct control_signals,
    input logic [63:0] register [31:0],
    input logic wb_module_enable,
    input wb_write_complete,
    output [63:0] register_write_data,
    output [4:0] register_write_addr,
    output register_write_enable,
    output write_back_done

);


    logic ecall_done;
    logic [2:0] ecall_counter; // Counter for tracking ECALL cycles (3-bit to count up to 4)
    logic ecall_active;        // Flag to indicate if ECALL is currently active
    logic [63:0] ecall_data_out; // Temporary storage for ECALL output


    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ecall_counter <= 0;
            ecall_active <= 0;
            ecall_done <= 0;
            
        end else if (wb_module_enable) begin
            if (control_signals.instruction == 8'd57) begin
                if (!ecall_done && !ecall_active) begin
                    do_ecall(register[17], register[10], register[11], register[12], register[13], register[14], register[15], register[16], ecall_data_out);
                    ecall_active <= 1; // Start ECALL
                    ecall_counter <= 1;
                end else if (ecall_active && ecall_counter < 4) begin
                    ecall_counter <= ecall_counter + 1; // Increment counter
                end else begin
                    ecall_done <= 1; // Set ECALL as done
                    ecall_active <= 0;
                end
            end else begin
                ecall_counter <= 0;
                ecall_active <= 0;
                ecall_done <= 0;
            end
        end
    end

    always_comb begin
        if (reset) begin
            register_write_data = 64'b0;
            register_write_addr = 5'b0;
            register_write_enable = 0;
            write_back_done = 0;
            ecall_data_out = 0;
        end 
        if (wb_module_enable) begin

            if (!wb_write_complete) begin
                // Jump, Store, Branch => Nothing happens
                if (control_signals.opcode == 7'b0100011 ||         // S-Type Store
                    control_signals.opcode == 7'b1100011 ||         // B-Type Branch
                    control_signals.opcode == 7'b0001111            // FENCE (I-Type)
                    ) begin      
                    register_write_data = 64'b0;
                    register_write_addr = 5'b0;
                    register_write_enable = 1;
                    
                end else begin
                // Write back is happening
                    register_write_addr = control_signals.dest_reg;
                    // Write back from ALU
                    if (control_signals.opcode == 7'b1110011) begin
                        if (control_signals.instruction == 8'd57) begin
                            // Set execute_done based on ECALL state
                            if (ecall_done) begin
                                register_write_data = ecall_data_out;
                                register_write_enable = 1;
                            end else begin
                                register_write_enable = 0;
                            end
                        end else begin
                            register_write_data = 64'b0;
                            register_write_addr = 5'b0;
                            register_write_enable = 1;
                        end
                    end else if ((control_signals.opcode == 7'b0110011) ||                // R-Type ALU instructions
                        (control_signals.opcode == 7'b0111011) ||                // R-Type with multiplication
                        (control_signals.opcode == 7'b0010011) ||                // I-Type ALU (immediate) instructions
                        (control_signals.opcode == 7'b0011011) ||                // I-Type ALU (immediate, 32M)
                        (control_signals.opcode == 7'b0010111) ||                // AUIPC (U-Type)
                        (control_signals.opcode == 7'b0110111)) begin           // LUI (U-Type)) 
                        register_write_data = alu_result;
                        register_write_enable = 1;
                    end else if (control_signals.opcode == 7'b0000011) begin      // I-Type Load
                        // Write back from data load
                        register_write_data = loaded_data;
                        register_write_enable = 1;
                    end else if (
                        (control_signals.opcode ==  7'b1101111)  || //jal
                        (control_signals.opcode == 7'b1100111)      //jalr
                                                            ) begin
                        if (register_write_addr != 5'b0) begin
                            register_write_data = control_signals.pc + 4;
                            register_write_enable = 1;
                        end else begin
                            register_write_data = 64'b0;
                            register_write_enable = 0;
                        end
                    end   
                    if (register_write_enable == 1) begin
                        // $display("Regfile: PC: %h ---- Writing %h (%d) to x%d", control_signals.pc, register_write_data, register_write_data, register_write_addr);
                    end
                    // if (register_write_data == 64'hfffffffc100e65b0) begin
                    //     // $display("PC value in WB: ", control_signals.pc, " while data: ", register_write_data, " and instr: ", control_signals.instruction);
                    // end
                end
            end else begin
                register_write_enable = 0;
                write_back_done = 1;
            end
        end else begin
            write_back_done = 0;
        end
    end
endmodule