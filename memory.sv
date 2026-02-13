module InstructionMemoryHandler
#(
    parameter addr_width = 64                 // Width of the address bus
) 
(
    input  logic        clk,                // Clock signal
    input  logic        reset,            // Active-low reset
    input logic memory_enable,
    input  logic [63:0] pc_I_offset,         // Current PC value (64 bits)
    input  logic [63:0] reg_b_contents,         // Reg B contents
    input  logic [63:0] alu_data,         // ALU result data
    input  control_signals_struct control_signals, //todo = change the type      // Control Signals
    input logic mem_wb_pipeline_valid,
    input logic instruction_cache_reading,

    output logic [63:0] loaded_data_out,
    output logic        memory_done,            // Ready signal indicating fetch completion

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
    output logic [1:0] m_axi_arburst,
    output logic m_axi_rready,                // Ready to accept data from AXI
    
    // AXI interface inputs for write transactions
    input logic m_axi_awready,                 // Ready signal from AXI for write address
    input logic m_axi_wready,                  // Ready signal from AXI for write data
    input logic m_axi_bvalid,                  // Write response valid from AXI
    input logic [1:0] m_axi_bresp,             // Write response from AXI
    input logic ecall_clean,

    // AXI interface outputs for write transactions
    output logic m_axi_awvalid,                // Valid signal for write address
    output logic [63:0] m_axi_awaddr,          // Write address output to AXI
    output logic [7:0] m_axi_awlen,            // Length of the burst for write
    output logic [2:0] m_axi_awsize,           // Size of each data unit in the burst for write
    output logic [1:0] m_axi_awburst,          // Burst type for write transaction
    output logic [63:0] m_axi_wdata,           // Data to be written to AXI
    output logic [7:0] m_axi_wstrb,            // Write strobe for data masking
    output logic m_axi_wvalid,                 // Valid signal for write data
    output logic m_axi_wlast,                  // Last transfer in the write burst
    output logic m_axi_bready,                 // Ready to accept write response

    output logic data_cache_reading,
    
    //ACSnoop AXI 
    input  logic m_axi_acvalid,                     // Snoop request valid
    output logic m_axi_acready,                     // Snoop request ready
    input  logic [addr_width-1:0] m_axi_acaddr,     // Snoop address
    input  logic [3:0] m_axi_acsnoop,               // Snoop type
    output logic snoop_stall

);

logic decache_request_ready;
logic decache_result_ready;
logic [63:0] decache_request_address;

logic mem_clean_done;


decache data_cache (
    .clock(clk),
    .reset(reset),
    .read_enable(read_enable),              // Fetcher signals no read
    .write_enable(write_enable),             // Write enable is active
    .address(decache_request_address),            // Address from ALU result
    .data_size(control_signals.data_size),              // Indicates 64-bit data (log2(8 bytes) = 3'b100)
    .data_input(reg_b_contents),              // Placeholder for data to write, if needed

    // AXI interface for read transactions
    .m_axi_arready(m_axi_arready),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_rready(m_axi_rready),

    //load-type information
    .load_sign(control_signals.signed_type),

    //ecall-related signals
    .ecall_clean(ecall_clean),
    .clean_done(mem_clean_done),

    // AXI interface for write transactions
    .m_axi_awready(m_axi_awready),
    .m_axi_wready(m_axi_wready),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_wdata(m_axi_wdata),             // Placeholder for write data
    .m_axi_wstrb(m_axi_wstrb),       // Write strobe (all bytes valid)
    .m_axi_wvalid(m_axi_wvalid),             // Not writing any data currently
    .m_axi_wlast(m_axi_wlast),              // No burst write in progress
    .m_axi_bready(m_axi_bready),             // Ready to accept write responses

    // AC SNOOPS
    .m_axi_acvalid(m_axi_acvalid),                    // Snoop request valid
    .m_axi_acready(m_axi_acready),                     // Snoop request ready
    .m_axi_acaddr(m_axi_acaddr),                       // Snoop address
    .m_axi_acsnoop(m_axi_acsnoop),                      // Snoop type
    .stall_core(snoop_stall),

    // Data output and control signals
    .data_out(loaded_data_out),          // Output to CPU (instruction data)
    .send_enable(decache_result_ready),// Indicates data is ready to send

    // AXI Control
    .instruction_cache_reading(instruction_cache_reading),// Instruction cache is not in reading mode
    .data_cache_reading(data_cache_reading)        // Not currently reading data cache
);

    /*
        todo - make the cache talking more like the fetcher

        todo - 
    
    */
    logic read_enable;
    logic write_enable;
    always_comb begin
        if (reset) begin
            
        end else begin
            if (memory_enable) begin
                if (!decache_result_ready) begin
                    read_enable = control_signals.read_memory_access;
                    write_enable = control_signals.write_memory_access;                    
                end 
                else if (decache_result_ready) begin
                    if (control_signals.write_memory_access == 1) begin
                        // $display("MemWrite: PC: %h ---- Writing %h (%d) to %h", control_signals.pc, reg_b_contents, reg_b_contents , decache_request_address);
                    end
                    read_enable = 0;
                    write_enable = 0;
                end
            end
        end
    end

    always_comb begin
        if (reset) begin
            loaded_data_out = 0;
            memory_done = 0;
            decache_request_address = 64'b0;
            decache_request_ready = 0;
        end else begin
            logic[1:0] memoryCaseVariable = 0;
            if (memory_enable) begin
                if (memory_enable && control_signals.read_memory_access) begin
                    memoryCaseVariable = 1;
                end else if (memory_enable && control_signals.write_memory_access) begin
                    memoryCaseVariable = 2;
                end else if (!memory_enable) begin
                    memoryCaseVariable = 3;
                end
                if (control_signals.read_memory_access || control_signals.write_memory_access) begin
                    
                    // if (decache_request_address[63:36] == 28'hFFFFFFF) begin
                    //     // $display("in mem", decache_request_address);
                    // end
                    decache_request_address = alu_data;
                    decache_request_ready = 1;
                    


                    //WAITING MISS GAP - 1 - WAITING FOR CACHE TO BE DONE 

                    if (decache_result_ready) begin // CLK 2
                        if (control_signals.read_memory_access == 1) begin
                            // $display("MemRead: PC: %h ---- Reading %h (%d) from %h into x%d", control_signals.pc, loaded_data_out, loaded_data_out , decache_request_address, control_signals.dest_reg);
                        end
                        decache_request_ready = 0;
                        memory_done = 1;
                    end
                    
                    //WAITING GAP - 2 - WAITING FOR VALUES TO BE LATCHED 
                    
                    if (mem_wb_pipeline_valid) begin  // clk 3
                        memory_done = 0;
                    //WAITING GAP - 3 starts because of this  - WAITING FOR THE PV TO BECOME ZERO ALSO 
                    end
                end else if (ecall_clean && control_signals.instruction == 8'd57) begin 
                    if (mem_clean_done) begin // CLK 2
                        memory_done = 1;
                    end
                    
                    if (mem_wb_pipeline_valid) begin  // clk 3
                        memory_done = 0;
                    end
                end else begin
                    //loaded_data_out = 0;
                    memory_done = 1;
                end
        
            end else begin
                //loaded_data_out = 0;
                memory_done = 0;
            end


            
        end
    end

endmodule