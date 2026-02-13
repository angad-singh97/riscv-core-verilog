`include "Sysbus.defs"
`include "fetcher.sv"
// `include "pipeline_register.sv"
`include "pipeline_reg_struct.svh"
`include "write_back.sv"
`include "decoder.sv"
`include "execute.sv"
`include "memory.sv"
`include "control_signals_struct.svh"


module top
#(
  ID_WIDTH = 13,
  ADDR_WIDTH = 64,
  DATA_WIDTH = 64,
  STRB_WIDTH = DATA_WIDTH/8
)
(
  input  clk,
         reset,
         hz32768timer,

  // 64-bit addresses of the program entry point and initial stack pointer
  input  [63:0] entry,
  input  [63:0] stackptr,
  input  [63:0] satp,

  // interface to connect to the bus
  output  wire [ID_WIDTH-1:0]    m_axi_awid,
  output  wire [ADDR_WIDTH-1:0]  m_axi_awaddr,
  output  wire [7:0]             m_axi_awlen,
  output  wire [2:0]             m_axi_awsize,
  output  wire [1:0]             m_axi_awburst,
  output  wire                   m_axi_awlock,
  output  wire [3:0]             m_axi_awcache,
  output  wire [2:0]             m_axi_awprot,
  output  wire                   m_axi_awvalid,
  input   wire                   m_axi_awready,
  output  wire [DATA_WIDTH-1:0]  m_axi_wdata,
  output  wire [STRB_WIDTH-1:0]  m_axi_wstrb,
  output  wire                   m_axi_wlast,
  output  wire                   m_axi_wvalid,
  input   wire                   m_axi_wready,
  input   wire [ID_WIDTH-1:0]    m_axi_bid,
  input   wire [1:0]             m_axi_bresp,
  input   wire                   m_axi_bvalid,
  output  wire                   m_axi_bready,
  output  wire [ID_WIDTH-1:0]    m_axi_arid,
  output  wire [ADDR_WIDTH-1:0]  m_axi_araddr,
  output  wire [7:0]             m_axi_arlen,
  output  wire [2:0]             m_axi_arsize,
  output  wire [1:0]             m_axi_arburst,
  output  wire                   m_axi_arlock,
  output  wire [3:0]             m_axi_arcache,
  output  wire [2:0]             m_axi_arprot,
  output  wire                   m_axi_arvalid,
  input   wire                   m_axi_arready,
  input   wire [ID_WIDTH-1:0]    m_axi_rid,
  input   wire [DATA_WIDTH-1:0]  m_axi_rdata,
  input   wire [1:0]             m_axi_rresp,
  input   wire                   m_axi_rlast,
  input   wire                   m_axi_rvalid,
  output  wire                   m_axi_rready,
  input   wire                   m_axi_acvalid,
  output  wire                   m_axi_acready,
  input   wire [ADDR_WIDTH-1:0]  m_axi_acaddr,
  input   wire [3:0]             m_axi_acsnoop
);


// Initial PC
logic [63:0] initial_pc;
logic [63:0] target_address;
logic initial_selector;

// Initialise Register


logic [63:0] register [31:0];
// logic register_busy [31:0];
logic [4:0] destination_reg;
logic [4:0] destination_reg_next;
logic raw_dependency;

logic reg_write_enable;
logic [4:0] reg_write_addr;
logic [4:0] reg_reset_busy_addr;
logic [63:0] reg_write_data;
logic [4:0] read_addr1, read_addr2;
logic [63:0] read_data1, read_data2;
logic reg_write_complete;

logic instruction_cache_reading;
logic data_cache_reading;

logic upstream_disable;
logic decache_wait_disable;
logic memory_disable;



register_file registerFile(
    .clk(clk),
    .reset(reset),
    .stackptr(stackptr),
    .read_addr1(read_addr1),
    .read_addr2(read_addr2),
    .read_data1(read_data1),
    .read_data2(read_data2),
    .write_enable(reg_write_enable),
    .write_addr(reg_write_addr),
    .write_data(reg_write_data),
    .write_complete(reg_write_complete),
    .register(register),
    // .register_busy(register_busy),
    .destination_reg(destination_reg),
    .raw_dependency(raw_dependency),
    .reset_write_addr(reg_reset_busy_addr)
);

// Assign initial PC value from entry point

  // Ready/valid handshakes for Fetch, Decode, and Execute stages
  logic fetcher_done, fetch_enable;

   //InstructionFetcher's pipeline register vars
   logic if_id_valid_reg;
   logic [31:0] if_id_instruction_reg, if_id_instruction_reg_next;
   logic [63:0] if_id_pc_plus_i_reg, if_id_pc_plus_i_reg_next;


   /*
   
   
       // AXI interface inputs for read transactions
    input logic m_axi_arready,                // Ready signal from AXI for read address
    input logic m_axi_rvalid,                 // Data valid signal from AXI read data channel
    input logic m_axi_rlast,                  // Last transfer of the read burst
    input logic [63:0] m_axi_rdata,           // Data returned from AXI read channel
    // AXI interface outputs for read transactions
    output logic m_axi_arvalid,               // Valid signal for read address
    output logic [63:0] m_axi_araddr,         // Read address output to AXI
    output logic [7:0] m_axi_arlen,           // Length of the burst (fetches full line)
    output logic [2:0] m_axi_arsize,          // Size of each data unit in the burst
    output logic m_axi_rready,                // Ready to accept data from AXI
   */

   always_ff @(posedge clk) begin
    // $display("At %h: %b %b %b %b %b", initial_pc, fetcher_done, decode_done, execute_done, memory_done, write_back_done);
    if (initial_pc == 64'h0000000000000014) begin
        $finish();
    end
   end

    //InstructionFetcher instantiation
    InstructionFetcher instructionFetcher (
        .clk(clk),
        .reset(reset),
        .fetch_enable(fetch_enable),
        .pc_current(initial_pc),
        .target_address(target_address),
        .select_target(mux_selector),
        .instruction_out(if_id_instruction_reg_next),
        .cache_request_address(if_id_pc_plus_i_reg_next),
        .m_axi_arready(m_axi_arready),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_rready(m_axi_rready),
        .m_axi_arburst(m_axi_arburst),
        .if_id_pipeline_valid(if_id_valid_reg),
        .fetcher_done(fetcher_done),
        .instruction_cache_reading(instruction_cache_reading),
        .data_cache_reading(data_cache_reading),
        .destination_reg(destination_reg),
        .jump_reset(upstream_disable),
        .ecall_detected(ecall_detected)
    );

    logic fetch_reset_done;
    logic ecall_stall;
    logic ecall_detected;


    // IF/ID Pipeline Register Logic (between Fetch and Decode stages)
    always_ff @(posedge clk) begin
        if (reset) begin
            if_id_instruction_reg <= 32'b0;
            if_id_pc_plus_i_reg <= 64'b0;
            initial_pc <= entry;
            target_address <= 0;
            mux_selector <= 0;
            fetch_enable <= 1;
            fetch_reset_done <= 0;
            upstream_disable <= 0;
            ecall_detected <= 0;
            // decache_wait_disable <= 0;
        end else begin
            if (!fetch_enable) begin
                if (upstream_disable) begin
                    if_id_instruction_reg <= 32'b0;
                    if_id_pc_plus_i_reg <= 64'b0;
                    if_id_valid_reg <= 0;
                    fetch_reset_done <= 1'b1;    
                    mux_selector <= 0;   
                    reg_reset_busy_addr <= destination_reg;
                    destination_reg <= 0; 
                    if (fetch_reset_done) begin
                        fetch_enable <= 1;
                        decode_enable <= 1;
                        execute_enable <= 1;
                        memory_enable <= 1;
                        fetch_reset_done <= 1'b0;       // Clear the flag
                        upstream_disable <= 0;
                    end
                end
            end else begin
                if (fetcher_done && !ecall_detected) begin
                    // Load fetched instruction into IF/ID pipeline registers
                    if_id_instruction_reg <= if_id_instruction_reg_next;
                    if_id_pc_plus_i_reg <= if_id_pc_plus_i_reg_next;
                    if_id_valid_reg <= 1; 
                    // destination_reg <= 0;

                /*   
                    MD_imm = {52'b0, __instruction[7], __instruction[30:25], __instruction[11:8], 1'b0};
                    if (__opcode == 7'b1100011) begin //BRANCH Instruction True
                    // Extract the lower 12 bits of the immediate
                    logic [11:0] imm_12bit = id_ex_control_signal_struct.imm[11:0];
                    // Sign-extend the 12-bit immediate to 64 bits
                    logic signed [63:0] signed_imm;
                    signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit
                    initial_pc <= id_ex_control_signal_struct.pc + $signed(signed_imm);
                    end else begin
                    end 
                */
                    if (!ecall_detected && !ex_mem_control_signal_struct_next.jump_signal) begin
                        initial_pc <= initial_pc + 4;
                    end 
                end else if (fetcher_done && ecall_detected) begin
                    fetch_enable <= 0;
                end
            end
        end
    end


    // DECODER STARTS
    logic decode_done, decode_ready, decode_enable;

    //InstructionDecoder's pipeline register vars
    logic id_ex_valid_reg;
    logic [63:0] id_ex_reg_a_data, id_ex_reg_a_addr;
    logic [63:0] id_ex_reg_b_data, id_ex_reg_b_addr;
    logic [63:0] id_ex_pc_plus_I_reg;
    control_signals_struct id_ex_control_signal_struct, id_ex_control_signal_struct_next;
    logic register_values_ready;

    logic [31:0] decoder_instruction_input;
    logic [63:0] decoder_pc_current_input;
    logic decoder_enable_input;
/* 
    InstructionDecoder instructionDecoder (
        .clk(clk),
        .reset(reset),
        .instruction(if_id_instruction_reg),
        .pc_current(if_id_pc_plus_i_reg),
        .decode_enable(if_id_valid_reg),
        .rs1(id_ex_reg_a_addr),      // Example output: reg_a
        .rs2(id_ex_reg_b_addr),      // Example output: reg_b
        .register_values_ready(register_values_ready),
        .control_signals_out(id_ex_control_signal_struct_next), // Example output: control signals
        .decode_complete(decode_done),
        .decode_latch_complete()
        .rd(destination_reg)
    ); */

    InstructionDecoder instructionDecoder (
        .clk(clk),
        .reset(reset),
        .instruction(decoder_instruction_input),
        .pc_current(decoder_pc_current_input),
        .decode_enable(decoder_enable_input),
        .rs1(read_addr1),      // Example output: reg_a
        .rs2(read_addr2),      // Example output: reg_b
        .register_values_ready(register_values_ready),
        .control_signals_out(id_ex_control_signal_struct_next), // Example output: control signals
        .decode_complete(decode_done),
        .rd(destination_reg_next)
    );

    always_comb begin
        if (!decode_enable) begin
            if (upstream_disable) begin
                    id_ex_control_signal_struct_next = '0;
                    destination_reg_next = 0;
            end
        end
    end

    

    logic flag1;
    logic flag2;
    // ID/EX Pipeline Register Logic (between Decode and Execute stages)
    always_ff @(posedge clk) begin
        if (reset) begin
            id_ex_pc_plus_I_reg <= 64'b0;
            id_ex_reg_a_data <= 64'b0;
            id_ex_reg_b_data <= 64'b0;
            id_ex_valid_reg <= 1'b0;
            id_ex_control_signal_struct <= '0;
            decode_enable <= 1;
        end else begin
            if (!decode_enable) begin
                if (upstream_disable) begin
                    decoder_instruction_input <= 0;
                    decoder_pc_current_input <= 0;
                    decoder_enable_input <= 0;
                    id_ex_pc_plus_I_reg <= 0;
                    id_ex_control_signal_struct <= '0;
                    id_ex_reg_a_data <= 0;
                    id_ex_reg_b_data <= 0;
                    id_ex_valid_reg <= 0;
                end
            end else begin
                if (!decode_done) begin
                    if (if_id_valid_reg) begin
                        decoder_instruction_input <= if_id_instruction_reg;
                        decoder_pc_current_input <= if_id_pc_plus_i_reg;
                        decoder_enable_input <= if_id_valid_reg;
                        if_id_valid_reg <= 0;
                        // destination_reg <= 0;
                    end
                end else begin
                // Load fetched instruction into ID/EX pipeline registers
                    id_ex_pc_plus_I_reg <= if_id_pc_plus_i_reg;
                    id_ex_control_signal_struct <= id_ex_control_signal_struct_next;
                    

                    //if this current instruction has matching rd, rs1
                    // flag1 = !raw_dependency;
                    // flag2 = raw_dependency && (read_addr1 != id_ex_control_signal_struct.dest_reg);

                    if (!raw_dependency) begin
                        // Step 2: Latch register file output values to pipeline registers
                        if (!ecall_detected) begin
                            id_ex_reg_a_data <= read_data1;
                            id_ex_reg_b_data <= read_data2;
                            destination_reg <= destination_reg_next;
                        end
                        id_ex_valid_reg <= 1;
                        decoder_enable_input <= 0;
                    end 
                end 
            end

            
        end
    end

    // EXECUTOR STARTS
    logic execute_done, execute_ready, execute_enable;

    //InstructionExecutor's pipeline register vars
    logic ex_mem_valid_reg;
    logic [63:0] ex_mem_pc_plus_I_offset_reg, ex_mem_pc_plus_I_offset_reg_next;
    logic [63:0] ex_mem_alu_data, ex_mem_alu_data_next;
    logic [63:0] ex_mem_reg_b_data;
    control_signals_struct ex_mem_control_signal_struct_next, ex_mem_control_signal_struct;



    logic [63:0] executor_pc_current_input;
    logic [63:0] executor_reg_a_data_input;
    logic [63:0] executor_reg_b_data_input;
    control_signals_struct executor_control_signals_struct_input;
    logic executor_enable_input;

    InstructionExecutor instructionExecutor (
        .clk(clk),
        .reset(reset),
        .execute_enable(executor_enable_input),
        .pc_current(executor_pc_current_input),
        .reg_a_contents(executor_reg_a_data_input), 
        .reg_b_contents(executor_reg_b_data_input), 
        .control_signals(executor_control_signals_struct_input),
        .alu_data_out(ex_mem_alu_data_next),
        .pc_I_offset_out(ex_mem_pc_plus_I_offset_reg_next),
        .control_signals_out(ex_mem_control_signal_struct_next),
        .execute_done(execute_done)
    );

    /*     InstructionExecutor instructionExecutor (
        .clk(clk),
        .reset(reset),
        .execute_enable(id_ex_valid_reg),
        .pc_current(id_ex_pc_plus_I_reg),
        .reg_a_contents(id_ex_reg_a_data), 
        .reg_b_contents(id_ex_reg_b_data), 
        .control_signals(id_ex_control_signal_struct),
        .alu_data_out(ex_mem_alu_data_next),
        .pc_I_offset_out(ex_mem_pc_plus_I_offset_reg_next),
        .control_signals_out(ex_mem_control_signal_struct_next),
        .execute_done(execute_done)
    ); */

    // EX/MEM Pipeline Register Logic (between Execute and Memory stages)

    always_comb begin
        if (!execute_enable) begin
            if (upstream_disable) begin
                ex_mem_alu_data_next = 64'b0;
                ex_mem_pc_plus_I_offset_reg_next = 0;
                //ex_mem_reg_b_data_next = 0;
                ex_mem_control_signal_struct_next = '0;
            end
        end else begin
            if (!execute_done) begin
                if (ecall_detected && id_ex_valid_reg) begin
                    destination_reg_next = 0;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ex_mem_alu_data <= 64'b0;
            ex_mem_pc_plus_I_offset_reg <= 64'b0;
            ex_mem_reg_b_data <= 64'b0;
            ex_mem_control_signal_struct <= '0;
            execute_enable <= 1;
        end else begin
            if (!execute_enable) begin
                if (upstream_disable) begin
                    executor_enable_input <= 0;
                    executor_pc_current_input <= 0;
                    executor_reg_a_data_input <= 0;
                    executor_reg_b_data_input <= 0;
                    executor_control_signals_struct_input <= 0;
                end
            end else begin
                if (!execute_done) begin
                    if (id_ex_valid_reg) begin
                        executor_enable_input <= id_ex_valid_reg;
                        executor_pc_current_input <= id_ex_pc_plus_I_reg;
                        executor_reg_a_data_input <= id_ex_reg_a_data;
                        executor_reg_b_data_input <= id_ex_reg_b_data;
                        executor_control_signals_struct_input <= id_ex_control_signal_struct;
                        id_ex_valid_reg <= 0;
                        // id_ex_pc_plus_I_reg <= 0;
                        // id_ex_reg_a_data <= 0;
                        // id_ex_reg_b_data <= 0;
                        // id_ex_control_signal_struct <= 0;
                    end
                end else begin
                     // Load decoded instruction into EX/MEM pipeline registers
                    ex_mem_pc_plus_I_offset_reg <= ex_mem_pc_plus_I_offset_reg_next;
                    ex_mem_alu_data <= ex_mem_alu_data_next;
                    ex_mem_reg_b_data <= id_ex_reg_b_data;
                    ex_mem_control_signal_struct <= ex_mem_control_signal_struct_next;
                    // if (ex_mem_alu_data_next == 64'hfffffffc100e65b8) begin
                    //     // $display("PC for ", ex_mem_alu_data_next, " is at ", ex_mem_control_signal_struct_next.pc);
                    //     // $display("Instr: ", ex_mem_control_signal_struct_next.instruction);
                    //     // $display("RegB: ", id_ex_reg_b_data);
                    //     // $display("dest reg: ", ex_mem_control_signal_struct_next.dest_reg);
                    // end
                    if (ex_mem_control_signal_struct_next.jump_signal) begin
                        upstream_disable <= 1;
                        initial_pc <= ex_mem_pc_plus_I_offset_reg_next;
                        target_address <= ex_mem_pc_plus_I_offset_reg_next;
                        mux_selector <= ex_mem_control_signal_struct_next.jump_signal;
                        execute_enable <= 0;
                        decode_enable <= 0;
                        fetch_enable <= 0;
                        //memory_enable <= 0;
                        decache_wait_disable <= 0;

                        decoder_instruction_input <= 0;
                        decoder_pc_current_input <= 0;
                        decoder_enable_input <= 0;

                        executor_enable_input <= 0;
                        executor_pc_current_input <= 0;
                        executor_reg_a_data_input <= 0;
                        executor_reg_b_data_input <= 0;
                        executor_control_signals_struct_input <= '0;                        
                    end else begin
                        if (!ecall_detected) begin
                            //memory_enable <= 0;
                            execute_enable <= 0;
                            decode_enable <= 0;
                            fetch_enable <= 0;
                            upstream_disable <= 0;
                            decache_wait_disable <= 1;
                        end
                    end
                    executor_enable_input <= 0;
                    ex_mem_valid_reg <= 1;
                end
            end
        end           
    end
    

    // MEMORY STARTS
    logic memory_done, memory_ready, memory_enable;

    //InstructionMemory's pipeline register vars
    logic [63:0] mem_wb_loaded_data, mem_wb_loaded_data_next;
    control_signals_struct mem_wb_control_signals_reg;
    logic [63:0] mem_wb_alu_data;
    logic mem_wb_valid_reg;

    logic [63:0] memory_pc_plus_I_input;
    logic [63:0] memory_alu_data_input;
    logic [63:0] memory_reg_b_data_input;
    control_signals_struct memory_control_signals_struct_input;
    logic memory_enable_input;
    logic mem_snoop_stall;
    logic top_stall_core;

    InstructionMemoryHandler instructionMemoryHandler (
        .clk(clk),                
        .reset(reset),
        .pc_I_offset(memory_pc_plus_I_input),        
        .reg_b_contents(memory_reg_b_data_input),         
        .alu_data(memory_alu_data_input),    
        .control_signals(memory_control_signals_struct_input),    
        .memory_enable(memory_enable_input),
        .mem_wb_pipeline_valid(mem_wb_valid_reg),
        .instruction_cache_reading(instruction_cache_reading),
        .m_axi_arready(m_axi_arready),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_awready(m_axi_awready),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bresp(m_axi_bresp),
        .loaded_data_out(mem_wb_loaded_data_next),
        .memory_done(memory_done),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_rready(m_axi_rready),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bready(m_axi_bready),
        .data_cache_reading(data_cache_reading),
        .m_axi_acvalid(m_axi_acvalid),                    // Snoop request valid
        .m_axi_acready(m_axi_acready),                     // Snoop request ready
        .m_axi_acaddr(m_axi_acaddr),                       // Snoop address
        .m_axi_acsnoop(m_axi_acsnoop),                      // Snoop type
        .ecall_clean(memory_ecall_clean),
        .snoop_stall(top_stall_core)
    );


    // assign memory_ready = ~ex_mem_imm_reg;

    logic[6:0] localOpcodeSignal;
    logic memory_ecall_clean;
    

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_wb_control_signals_reg <= '0;
            mem_wb_loaded_data <= 64'b0;
            mem_wb_alu_data <= 64'b0;
            memory_enable <= 1;
            memory_ecall_clean <= 0;
        end else begin
            memory_ecall_clean <= ecall_detected;
            if (memory_enable) begin
                //todo - this area may be weird during a jump/branch
                //todo - why aren't we resetting signals here during a stall?
                if(!memory_done) begin
                    if(ex_mem_valid_reg) begin
                        memory_enable_input <= ex_mem_valid_reg;
                        memory_pc_plus_I_input <= ex_mem_pc_plus_I_offset_reg;
                        memory_alu_data_input <= ex_mem_alu_data;
                        memory_reg_b_data_input <= ex_mem_reg_b_data;
                        memory_control_signals_struct_input <= ex_mem_control_signal_struct;
                        ex_mem_valid_reg <= 0;
                    end
                end else begin
                    memory_enable_input <= 0;
                    ex_mem_control_signal_struct.read_memory_access <= 0;
                    ex_mem_control_signal_struct.write_memory_access <= 0;
                    mem_wb_control_signals_reg <= ex_mem_control_signal_struct;
                    mem_wb_loaded_data <= mem_wb_loaded_data_next;
                    mem_wb_alu_data <= ex_mem_alu_data;
                    // memory_ecall_clean <= 0;
                    mem_wb_valid_reg <= 1;
                    /* memory_enable <= 0;
                    memory_disable <= 1; */
                    if (!upstream_disable && (!ecall_detected || ex_mem_control_signal_struct.instruction != 8'd57)) begin
                        fetch_enable <= 1;
                        decode_enable <= 1;
                        execute_enable <= 1; 
                        //don't want to come in fetcher's way, let that restart things as it was doing
                        decache_wait_disable <= 0;
                    end
                end
            end
            
        end
    end

    // WRITE BACK STARTS
    logic write_back_ready;

    //InstructionWriteBacks's output vars
    logic [63:0] wb_dest_reg_out, wb_dest_reg_out_next;
    logic [63:0] wb_data_out, wb_data_out_next;


    logic [63:0] writeback_loaded_data_input;
    logic [63:0] writeback_alu_data_input;
    control_signals_struct writeback_control_signals_struct_input;
    logic writeback_enable_input;

    logic write_back_done;
    logic write_back_enable;

    InstructionWriteBack instructionWriteBack (
        .clk(clk),
        .reset(reset),


        .loaded_data(writeback_loaded_data_input),
        .alu_result(writeback_alu_data_input),
        .control_signals(writeback_control_signals_struct_input),
        .wb_write_complete(reg_write_complete),



        .register_write_addr(reg_write_addr),
        .register_write_data(reg_write_data),
        .register_write_enable(reg_write_enable),

        .write_back_done(write_back_done),
        .wb_module_enable(writeback_enable_input),
        .register(register)
    );

    logic [63:0] currInstAtWB;

    always_ff @(posedge clk) begin
        if (reset) begin
            wb_dest_reg_out <= 64'b0;
            wb_data_out <= 64'b0;
            write_back_enable <= 1;
        end else begin
            if (write_back_enable) begin
                if (!write_back_done) begin
                    if (mem_wb_valid_reg) begin
                        writeback_loaded_data_input <= mem_wb_loaded_data;
                        writeback_alu_data_input <= mem_wb_alu_data;
                        writeback_control_signals_struct_input <= mem_wb_control_signals_reg;
                        writeback_enable_input <= mem_wb_valid_reg;
                        mem_wb_valid_reg <= 0;
                    end
                end else begin
                    currInstAtWB = writeback_control_signals_struct_input.instruction;
                    if (currInstAtWB == 8'd57) begin
                        if (!top_stall_core) begin
                            // // $display("setting ecall to 0");
                            ecall_detected <= 0;
                            fetch_enable <= 1;
                            writeback_enable_input <= 0;
                        end 
                    end else begin 
                        writeback_enable_input <= 0;
                    end
                end
            end
        end
    end
endmodule

