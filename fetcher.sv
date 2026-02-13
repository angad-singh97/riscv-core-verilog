`include "recache.sv"

module InstructionFetcher (
    input  logic        clk,                // Clock signal
    input  logic        reset,            // Active-low reset 
    input  logic        fetch_enable,
    input  logic [63:0] pc_current,         // Current PC value (64 bits)
    input  logic [63:0] target_address,     // Target address for branches/jumps (64 bits)
    input  logic        select_target,      // Control signal for address selection
    input  logic if_id_pipeline_valid,
    input  logic data_cache_reading,


    output logic [63:0] instruction_out,    // Instruction bits fetched from cache (64 bits)
    output logic [63:0] cache_request_address,        // Address used for fetching (64 bits)
    output logic        fetcher_done,               // Ready signal indicating fetch completion
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
    output logic instruction_cache_reading,
    output logic [4:0] destination_reg,
    output logic ecall_detected,
    input logic jump_reset
);

// Internal wires and registers (if needed)
logic recache_request_ready;
logic recache_result_ready;


    recache instruction_cache (
        .clock(clk),
        .reset(reset),
        .read_enable(recache_request_ready), //input that fetcher send
        .address(cache_request_address), // input that fetcher sends
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
        .data_out(instruction_out),
        .send_enable(recache_result_ready),
        .instruction_cache_reading(instruction_cache_reading), // Instruction cache is not in reading mode
        .data_cache_reading(data_cache_reading),        // Not currently reading data cache
        .jump_reset(jump_reset)
    );  


     
always_ff @(posedge clk) begin
    if (reset) begin
        ecall_detected <= 0;
    end
    else begin
        if (fetch_enable) begin
            if (recache_request_ready) begin
                destination_reg <= 0;
            end else if (recache_result_ready) begin
                if (instruction_out == 8'h000000073) begin
                    ecall_detected <= 1;
                end 
            end
        end 
    end 
end 
// No states
always_comb begin
    if (reset) begin
        fetcher_done = 0;
        cache_request_address  = 64'b0;
        recache_request_ready = 0;
        
    end else begin
        if (fetch_enable) begin // clk 1
            if (
                !(fetcher_done && !if_id_pipeline_valid)  
                // case where we are waiting for a latch - HL
                
                && 
                
                !(fetcher_done && if_id_pipeline_valid)  
                // case where latch is done -HH

                &&

                !(!fetcher_done && if_id_pipeline_valid)  
                // case where latch is done, but next stage (decoder) is yet to use the values - LH
                
                
                
                ) begin
                // if (cache_request_address == 64'hFFFFFFFC100E6580) begin
                // if (cache_request_address[63:36] == 28'hFFFFFFF) begin
                //     // $display("in fetch", cache_request_address);
                // end
                cache_request_address = select_target ? target_address : pc_current;
                recache_request_ready = 1;
            end

            //WAITING MISS GAP - 1 - WAITING FOR CACHE TO BE DONE 

            if (recache_result_ready) begin // CLK 2
                recache_request_ready = 0;
                fetcher_done = 1;
            end
            
            //WAITING GAP - 2 - WAITING FOR VALUES TO BE LATCHED 
            
            if (if_id_pipeline_valid) begin  // clk 3 
                fetcher_done = 0;
            //WAITING GAP - 3 starts because of this  - WAITING FOR THE PV TO BECOME ZERO ALSO 
            end
        end else begin // in next clk
            recache_request_ready = 0;
            fetcher_done = 0;
        end
    end
end


endmodule