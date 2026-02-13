module decache #(
    parameter cache_line_size = 512,           // Size of each cache line in bytes
    parameter cache_lines = 4,                 // Total number of cache lines
    parameter sets = 32,                        // Number of sets in the cache
    parameter ways = 2,                        // Number of ways (associativity) in the cache
    parameter addr_width = 64,                 // Width of the address bus
    parameter data_width = 64                  // Width of the data bus 
)(
    input logic clock,
    input logic reset,
    input logic read_enable,                   // Signal to trigger a cache read
    input logic write_enable,                  // Signal to trigger a cache write
    input logic [63:0] address,                // Address to read/write from/to cache
    input logic [2:0] data_size,               // Size of data requested (in bytes)
    input logic [63:0] data_input,

    // AXI interface inputs for read transactions
    input logic m_axi_arready,                 // Ready signal from AXI for read address
    input logic m_axi_rvalid,                  // Data valid signal from AXI read data channel
    input logic m_axi_rlast,                   // Last transfer of the read burst
    input logic [63:0] m_axi_rdata,            // Data returned from AXI read channel

    // AXI interface outputs for read transactions
    output logic m_axi_arvalid,                // Valid signal for read address
    output logic [63:0] m_axi_araddr,          // Read address output to AXI
    output logic [7:0] m_axi_arlen,            // Length of the burst (fetches full line)
    output logic [2:0] m_axi_arsize,           // Size of each data unit in the burst
    output logic [1:0] m_axi_arburst,          // Burst type for read transaction
    output logic m_axi_rready,                 // Ready to accept data from AXI

    // AXI interface inputs for write transactions
    input logic m_axi_awready,                 // Ready signal from AXI for write address
    input logic m_axi_wready,                  // Ready signal from AXI for write data
    input logic m_axi_bvalid,                  // Write response valid from AXI
    input logic [1:0] m_axi_bresp,             // Write response from AXI

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

    // AXI Coherence Interface
    input  logic m_axi_acvalid,                     // Snoop request valid
    output logic m_axi_acready,                     // Snoop request ready
    input  logic [addr_width-1:0] m_axi_acaddr,     // Snoop address
    input  logic [3:0] m_axi_acsnoop,               // Snoop type
    output logic stall_core,

    // Data output and control signals
    output logic [63:0] data_out,                  // Data output to CPU
    output logic send_enable,                   // Indicates data is ready to send

    // Flush Dirty lines
    input logic ecall_clean,
    output logic clean_done,

    // sign input for load
    input logic load_sign,

    // AXI Control
    input logic instruction_cache_reading,
    output logic data_cache_reading
);


enum logic [3:0] {
    // Existing read operation states
    IDLE_HIT            = 4'b0000, // Idle and cache hit handling for reads
    MISS_REQUEST        = 4'b0001, // Handling read cache miss, initiating memory request
    MEMORY_WAIT         = 4'b0010, // Waiting for memory response after a miss
    MEMORY_ACCESS       = 4'b0011, // Accessing data as it's received from memory
    STORE_DATA          = 4'b0100, // Storing data into cache after a read miss
    SEND_DATA           = 4'b0101, // Sending data to the fetcher
    WRITE_MISS          = 4'b0110, // 
    WRITE_REQUEST       = 4'b0111, // Initiating memory request due to write miss
    WRITE_MEMORY_WAIT   = 4'b1000, // Waiting for acknowledgment from memory for write
    WRITE_MEMORY_ACCESS = 4'b1001, // Accessing or preparing data for the write operation
    WRITE_COMPLETE      = 4'b1010,  // Completing the write and updating cache state
    REPLACE_DATA        = 4'b1011,
    AC_SNOOP            = 4'b1100,
    FLUSH_DIRTY         = 4'b1101
} current_state, next_state;

// Derived parameters
localparam block_offset_width = $clog2(cache_line_size / data_width) + 3;
localparam set_index_width = $clog2(sets);
localparam tag_width = addr_width - set_index_width - block_offset_width;

// Cache storage arrays
logic [tag_width-1:0] tags [sets-1:0][ways-1:0];            // Array for storing tags
logic [cache_line_size-1:0] cache_data [sets-1:0][ways-1:0];      // Array for storing cache line data
logic valid_bits [sets-1:0][ways-1:0];                       // Valid bits array
// DIRTY BITS
logic dirty_bits [sets-1:0][ways-1:0];

// internal logic bits
logic cache_hit;
logic check_done;
logic [set_index_width-1:0] set_index;
logic [set_index_width-1:0] set_index_next;

logic [tag_width-1:0] tag;
logic [tag_width-1:0] tag_next;

logic [block_offset_width-1:0] block_offset;
logic [data_width-1:0] data_out; 
logic [63:0] buffer_array [7:0];    // 16 instructions, each 32 bits
logic [3:0] buffer_pointer;          // Points to the next location in buffer_array
logic [3:0] burst_counter;           // Counts each burst (0-7)
logic [63:0] current_transfer_value;
logic data_retrieved;

logic [63:0] temp_data; // Temporary variable for extracted data
logic [63:0] write_mask;
// internal logic next bits
logic cache_hit_next;
logic check_done_next;
logic [data_width-1:0] data_out_next;
logic send_enable_next;
logic data_retrieved_next;
logic data_received_mem;
// Control signals and variables
// logic cache_hit;
// logic [31:0] data_out;
// logic [cache_line_size-1:0] cache_memory [sets-1:0][ways-1:0]; 
logic [7:0]  m_axi_arlen;          // Number of transfers in burst
logic        m_axi_arvalid;        // Memory request signal
logic        m_axi_rready;         // Memory ready to receive data
logic        m_axi_rvalid;         // Memory response valid signal
logic [31:0] memory_data;          // Data from memory

logic [63:0] modified_address;
logic [63:0] increment_address;
integer empty_way;
integer empty_way_next;
integer replace_line_number;
logic [63:0] data_shifted;

logic write_data_done;
logic write_data_to_mem;
logic way_cleaned;
logic data_stored;
logic replace_line;
logic [$clog2(ways)-1:0] way_to_replace;
logic [$clog2(ways)-1:0] counter;
logic [$clog2(ways)-1:0] clean_way;
// logic [:0] data_size_temp = 32;
integer data_size_temp = 32; 
integer block_number;
integer i;

logic invalidation_check_done;
logic cache_invalidated;
logic [addr_width-1:0] ac_address;
logic [2:0] within_block_offset; 
// State register update (sequential block)
logic need_cleaning;
logic cleaning_check_done;
logic clean_done_next;
logic cleaning_ecall_now;
always_ff @(posedge clock) begin
    if (reset)
        counter <= 0;              // Reset counter
    else if (replace_line)
        counter <= (counter + 1) % ways; // Increment counter cyclically
end

assign way_to_replace = counter;

// AC SNOOP Logic

always_ff @(posedge clock) begin
    if (ecall_clean) begin
        cleaning_ecall_now <= ecall_clean;
    end
    if (cleaning_ecall_now && clean_done) begin
        cleaning_ecall_now <= 0;
    end

end

always_ff @(posedge clock) begin
    if (reset) begin
        // Initialize state and relevant variables
        current_state <= IDLE_HIT;
        buffer_pointer <= 0;
        burst_counter <= 0;
        send_enable <= 0;
        data_received_mem <= 0;
        m_axi_acready <= 0; 
    end else begin
        // Update current state and other variables as per state transitions
        current_state <= next_state;
        send_enable <= send_enable_next;
        data_retrieved <= data_retrieved_next;
        clean_done <= clean_done_next;
        // set_index <= set_index_next;
        // empty_way <= empty_way_next;
        case (current_state)
            IDLE_HIT: begin
                // Idle state for cache hits (no actions yet)
                for (i = 0; i < 8; i = i + 1) begin
                    buffer_array[i] <= 64'b0;
                end
                data_received_mem <= 0;
                way_cleaned <= 0;
                write_data_done <= 0;
                write_data_to_mem <= 0;
                m_axi_acready <= 0;
            end

            MISS_REQUEST: begin
                // Issue memory read request on a cache miss
            end

            MEMORY_WAIT: begin
                // Wait for memory response
            end

            MEMORY_ACCESS: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    buffer_array[burst_counter] <= m_axi_rdata;
                    // $display("AXIRead Data %h at %d", m_axi_rdata, buffer_pointer);
                    buffer_pointer <= buffer_pointer + 2;
                    burst_counter <= burst_counter + 1;
                end
                    
                    // Check if last burst transfer is reached
                if (m_axi_rlast && (burst_counter == 8)) begin
                    buffer_pointer <= 0;
                    burst_counter <= 0;
                    data_received_mem <= 1;
                end
                data_retrieved <= data_retrieved_next;
            end

            STORE_DATA: begin
                // Store fetched data in cache
                if (empty_way_next != -1) begin
                    // Write tag and data into cache
                    tags[set_index_next][empty_way_next] <= tag;
                    cache_data[set_index_next][empty_way_next] <= {buffer_array[7], buffer_array[6], buffer_array[5], buffer_array[4],
                                                    buffer_array[3], buffer_array[2], buffer_array[1], buffer_array[0]};

                    valid_bits[set_index_next][empty_way_next] <= 1;
                    data_stored <= 1;
                end
            end

            SEND_DATA: begin
                // Send data to the fetcher or CPU
            end
            
            WRITE_MISS: begin
                // Issue memory write request on a cache miss (to be implemented)
            end
            // New states for write operations
            WRITE_REQUEST: begin
                // Issue memory write request on a cache miss (to be implemented)
                increment_address <= modified_address; 
            end

            WRITE_MEMORY_WAIT: begin
                // Wait for memory acknowledgment after issuing a write request (to be implemented)
            end

            WRITE_MEMORY_ACCESS: begin
                if (m_axi_wready && !m_axi_wlast) begin
                    m_axi_wvalid <= 1;
                    if (!cleaning_ecall_now) begin
                        m_axi_wdata <= cache_data[set_index][way_to_replace][(burst_counter * 64) +: 64];
                    end
                    else if (cleaning_ecall_now) begin
                        m_axi_wdata <= cache_data[set_index][clean_way][(burst_counter * 64) +: 64];
                    end 
                    // $display("AXI WData %h at %d", m_axi_wdata, burst_counter);
                    m_axi_wstrb <= 8'hFF;
                    
                    burst_counter <= burst_counter + 1;
                    increment_address <= increment_address + 8;
                    // Check if last burst transfer is reached
                end
                if (burst_counter == 7) begin
                    m_axi_wlast <= 1;
                    // burst_counter <= 0; 
                end 
                if (m_axi_wlast) begin
                    m_axi_wvalid <= 0;
                    // m_axi_wlast <= 0;
                end 
            end

            WRITE_COMPLETE: begin
                burst_counter <= 0; 
                if (m_axi_bvalid && !m_axi_bready) begin
                    m_axi_bready <= 1;
                end else if (m_axi_bready && m_axi_bvalid) begin
                    m_axi_bready <= 0;
                    write_data_done <= 1;  
                    m_axi_wlast <= 0;
                end 
            end
            
            REPLACE_DATA: begin
                if (dirty_bits[set_index][way_to_replace] == 1) begin
                    valid_bits[set_index][way_to_replace] <= 0;
                    write_data_to_mem <= 1;
                    way_cleaned <= 1;
                end

                else begin
                    valid_bits[set_index][way_to_replace] <= 0;
                    way_cleaned <= 1;
                end  
            end

            AC_SNOOP: begin
                if (m_axi_acvalid && m_axi_acsnoop == 4'b1101 && !m_axi_acready) begin
                    m_axi_acready <= 1;
                    ac_address <= m_axi_acaddr;
                    // $display("ACSNOOP ", ac_address);
                end

                if (m_axi_acready) begin
                    m_axi_acready <= 0;
                end 
            end

            FLUSH_DIRTY: begin
                write_data_done <= 0;
            end 
        endcase
    end
end


// Next State Logic (combinational block)
always_comb begin
    case (current_state)
        IDLE_HIT: begin
            // Transition to MISS_REQUEST if cache miss
            if (!cache_hit && check_done && !instruction_cache_reading) begin
                next_state = MISS_REQUEST;
            end else if (m_axi_acvalid) begin
                next_state = AC_SNOOP;
            end else if (ecall_clean) begin
                next_state = FLUSH_DIRTY;
            end else begin
                next_state = IDLE_HIT;
            end
        end

        MISS_REQUEST: begin
            // Move to MEMORY_WAIT after initiating request
            next_state = (m_axi_arvalid && m_axi_arready) ? MEMORY_WAIT : MISS_REQUEST;
        end

        MEMORY_WAIT: begin
            // Transition to MEMORY_ACCESS when memory data is valid
            next_state = (m_axi_rready) ? MEMORY_ACCESS : MEMORY_WAIT;
        end

        MEMORY_ACCESS: begin
            // Transition to STORE_DATA after receiving memory data
            next_state = (data_retrieved) ? STORE_DATA : MEMORY_ACCESS;
        end

        STORE_DATA: begin
            if (replace_line) begin
                next_state = REPLACE_DATA;
            end else if (read_enable && data_stored) begin
                next_state = SEND_DATA;
            end else if (write_enable && data_stored) begin
                next_state = WRITE_MISS;
            end else if (cache_invalidated && data_stored) begin
                next_state = IDLE_HIT;
            end else begin
                next_state = STORE_DATA;  // Default case
            end
        end

        SEND_DATA: begin
            next_state = (!read_enable && !send_enable) ? IDLE_HIT : SEND_DATA;
        end 

        WRITE_MISS: begin
            next_state = (!write_enable && !send_enable) ? IDLE_HIT : WRITE_MISS;
        end 
        // New states for write operations
        WRITE_REQUEST: begin
            // Transition to WRITE_MEMORY_WAIT after initiating write request
            next_state = (m_axi_awvalid && m_axi_awready) ? WRITE_MEMORY_WAIT : WRITE_REQUEST;
        end

        WRITE_MEMORY_WAIT: begin
            // Transition to WRITE_MEMORY_ACCESS when memory is ready for data
            next_state = (m_axi_wready) ? WRITE_MEMORY_ACCESS : WRITE_MEMORY_WAIT;
        end

        WRITE_MEMORY_ACCESS: begin
            // Transition to WRITE_DATA after staging data for memory
            next_state = (burst_counter == 8 && !m_axi_wvalid) ? WRITE_COMPLETE : WRITE_MEMORY_ACCESS;
        end

        WRITE_COMPLETE: begin
            if (write_data_done && way_cleaned) begin
                next_state = STORE_DATA;
            end else if (write_data_done && cleaning_ecall_now) begin
                next_state = FLUSH_DIRTY;
            end else begin
                next_state = WRITE_COMPLETE; // Default case if no conditions are met
            end
        end

        REPLACE_DATA: begin
            if (!write_data_to_mem && way_cleaned) begin
                next_state = STORE_DATA;
            end else if (write_data_to_mem && way_cleaned) begin
                next_state = WRITE_REQUEST;
            end else begin
                next_state = REPLACE_DATA; // Default case if no conditions are met
            end
        end

        AC_SNOOP: begin
            if (invalidation_check_done && !m_axi_acvalid) begin
                next_state = IDLE_HIT;
            end else begin
                next_state = AC_SNOOP;
            end
        end
        
        FLUSH_DIRTY: begin
            if (!need_cleaning && cleaning_check_done) begin
                next_state = IDLE_HIT;
            end else if (need_cleaning && cleaning_check_done) begin
                next_state = WRITE_REQUEST;
            end else begin
                next_state = FLUSH_DIRTY;
            end
        end

        default: next_state = IDLE_HIT;
    endcase
end

// Output Logic (combinational block)
always_comb begin
    // Initialize default values for control signals
    if (reset) begin
        data_out = 0;
        check_done = 0;
        cache_hit = 0;
        m_axi_arvalid = 0;
        m_axi_rready = 0;
        send_enable_next = 0;
        next_state = 0;
        replace_line = 0;
        data_cache_reading = 0;
        set_index = 0;
        tag = 0;
        block_offset = 0;
        empty_way_next = 0;
        write_mask = 64'h0;
        data_shifted = 0;
        within_block_offset = 0;
        cache_invalidated = 0;
        clean_way = 0;
        need_cleaning = 0;
        cleaning_check_done = 0;
        clean_done_next = 0;
        stall_core = 0;
        for (int set = 0; set < sets; set++) begin
            for (int way = 0; way < ways; way++) begin
                cache_data[set][way] = '0; // Initialize each cache line to 0
                dirty_bits[set][way] = 0;
            end
        end
    end 
    else begin
        case (current_state)
            IDLE_HIT: begin
                // m_axi_arvalid = 0;
                // m_axi_rready = 0;
                data_retrieved_next = 0;
                replace_line = 0;
                data_cache_reading = 0;
                cleaning_check_done = 0;
                need_cleaning = 0;
                clean_done_next = 0;
                // write_data_done = 0;
                if (read_enable && !check_done) begin
                    set_index = address[block_offset_width +: set_index_width];
                    tag = address[addr_width-1 -: tag_width];
                    block_offset = address[block_offset_width-1:3];
                    within_block_offset = address[2:0];
                    for (int i = 0; i < ways; i++) begin
                        if (tags[set_index][i] == tag && valid_bits[set_index][i] == 1) begin  // Check for tag match
                            cache_hit = 1;   // Cache hit
                            temp_data = cache_data[set_index][i][(block_offset) * 64 +: 64];
                            // $display("Cache Hit");
                            // $display("Cache line at %h tag and %h set index with %h block offset. Makes address %h. Start address %h", tag, set_index, block_offset, {tag, set_index, block_offset}, {tag, set_index, {block_offset_width{1'b0}}});
                            // $display("Cache line is %h.", cache_data[set_index][i]);
                            // $display("Temp data is %h.", temp_data);
                            case (data_size)
                                3'b001: begin // 1 byte
                                    if (load_sign)
                                        data_out = {{56{temp_data[(within_block_offset * 8) + 7]}}, temp_data[(within_block_offset * 8) +: 8]};
                                    else
                                        data_out = {56'b0, temp_data[(within_block_offset * 8) +: 8]};
                                end
                                3'b010: begin // 2 bytes
                                    if (load_sign)
                                        data_out = {{48{temp_data[(within_block_offset * 8) + 15]}}, temp_data[(within_block_offset * 8) +: 16]};
                                    else
                                        data_out = {48'b0, temp_data[(within_block_offset * 8) +: 16]};
                                end
                                3'b100: begin // 4 bytes
                                    if (load_sign)
                                        data_out = {{32{temp_data[(within_block_offset * 8) + 31]}}, temp_data[(within_block_offset * 8) +: 32]};
                                    else
                                        data_out = {32'b0, temp_data[(within_block_offset * 8) +: 32]};
                                end
                                3'b111: begin // 8 bytes
                                    data_out = temp_data; // Entire block
                                end
                                default: begin
                                    data_out = 64'b0; // Default case, shouldn't happen
                                end
                            endcase
                        end
                    end
                    check_done = 1;
                end

                if (check_done && cache_hit && read_enable) begin
                    send_enable_next = 1;
                end 

                if (!read_enable && !write_enable) begin
                    check_done = 0;
                    cache_hit = 0;
                    // data_out = 0;
                    send_enable_next = 0;
                end

                if (write_enable) begin
                    set_index = address[block_offset_width +: set_index_width];
                    tag = address[addr_width-1 -: tag_width];
                    block_offset = address[block_offset_width-1:3];
                    within_block_offset = address[2:0];
                    case (data_size)
                        3'b001: begin  // 1 byte
                            write_mask = 64'hFF << (within_block_offset * 8);
                            data_shifted = data_input[7:0] << (within_block_offset * 8);
                            do_pending_write(address, data_input[7:0], 1);
                        end
                        3'b010: begin  // 2 bytes
                            write_mask = 64'hFFFF << (within_block_offset * 8);
                            data_shifted = data_input[15:0] << (within_block_offset * 8);
                            do_pending_write(address, data_input[15:0], 2); 
                        end
                        3'b100: begin  // 4 bytes
                            write_mask = 64'hFFFFFFFF << (within_block_offset * 8);
                            data_shifted = data_input[31:0] << (within_block_offset * 8);
                            do_pending_write(address, data_input[31:0], 4); 
                        end
                        3'b111: begin  // 8 bytes
                            write_mask = 64'hFFFFFFFFFFFFFFFF; // Entire block
                            data_shifted = data_input[63:0];   // No shifting needed
                            do_pending_write(address, data_input[63:0], 8); 
                        end
                        default: write_mask = 64'h0;  // Default case
                    endcase

                    for (int i = 0; i < ways; i++) begin
                        if (tags[set_index][i] == tag && valid_bits[set_index][i] == 1) begin  // Check for tag match
                            cache_hit = 1;   // Cache hit
                            cache_data[set_index][i][(block_offset) * 64 +: 64] = 
                                (cache_data[set_index][i][(block_offset) * 64 +: 64] & ~write_mask) | 
                                (data_shifted & write_mask);
                            dirty_bits[set_index][i] = 1;  // Mark block as dirty
                            // $display("Cache Write Hit");
                            // $display("Cache line at %h tag and %h set index with %h block offset. Makes address %h. Start address %h", tag, set_index, block_offset, {tag, set_index, block_offset}, {tag, set_index, {block_offset_width{1'b0}}});
                            // $display("Cache line is %h.", cache_data[set_index][i]);
                            // $display("Input data is %h.", data_input);
                        end
                    end
                    check_done = 1;
                end

                if (write_enable && check_done && cache_hit) begin
                    send_enable_next = 1;
                end 
                
                if (m_axi_acvalid) begin
                    stall_core = 1;
                end

                if (ecall_clean) begin 
                    // stall_core = 1;
                end 

                if (cache_invalidated || invalidation_check_done) begin
                    cache_invalidated = 0;
                    invalidation_check_done = 0;
                    stall_core = 0;
                end  
            end 

            MISS_REQUEST: begin
                // if (!cache_invalidated) begin 
                modified_address = {address[addr_width-1:block_offset_width], {block_offset_width{1'b0}}};
                // end 
                // else begin
                //     modified_address = {address[addr_width-1:block_offset_width], {block_offset_width{1'b0}}};
                // end 
                m_axi_arvalid = 1;
                m_axi_arlen = 7;
                m_axi_arsize = 3;
                m_axi_arburst = 2;
                m_axi_araddr = modified_address;
                data_cache_reading = 1;
                // $display("Modified Read Address %h", modified_address);
            end

            MEMORY_WAIT: begin
                m_axi_rready = 1;
                m_axi_arvalid = 0;
            end

            MEMORY_ACCESS: begin
                current_transfer_value = m_axi_rdata;
                if (data_received_mem) begin
                    // m_axi_rready = 0;
                    data_retrieved_next = 1;
                end
                empty_way_next = -1;
            end

            STORE_DATA: begin
                m_axi_arvalid = 0;
                m_axi_rready = 0;
                
                set_index_next = modified_address[block_offset_width + set_index_width - 1 : block_offset_width];
                tag_next = modified_address[addr_width-1 : addr_width - tag_width];
                
                if (empty_way_next == -1) begin
                    for (int w = 0; w < ways; w++) begin
                        if (!valid_bits[set_index_next][w]) begin
                            empty_way_next = w;
                            break;
                        end
                    end
                end

                if (empty_way_next == -1) begin
                    replace_line = 1;
                end 
            end

            SEND_DATA: begin
                data_cache_reading = 0;
                temp_data = cache_data[set_index][empty_way_next][(block_offset) * 64 +: 64]; 
                // $display("Cache Miss");
                // $display("Cache line at %h tag and %h set index with %h block offset. Makes address %h. Start address", tag, set_index, {tag, set_index, block_offset}, {tag, set_index, {block_offset_width{1'b0}}});
                // $display("Cache line is %h.", cache_data[set_index][empty_way_next]);
                // $display("Temp data is %h.", temp_data);
                case (data_size)
                    3'b001: begin // 1 byte
                        if (load_sign)
                            data_out = {{56{temp_data[(within_block_offset * 8) + 7]}}, temp_data[(within_block_offset * 8) +: 8]};
                        else
                            data_out = {56'b0, temp_data[(within_block_offset * 8) +: 8]};
                    end
                    3'b010: begin // 2 bytes
                        if (load_sign)
                            data_out = {{48{temp_data[(within_block_offset * 8) + 15]}}, temp_data[(within_block_offset * 8) +: 16]};
                        else
                            data_out = {48'b0, temp_data[(within_block_offset * 8) +: 16]};
                    end
                    3'b100: begin // 4 bytes
                        if (load_sign)
                            data_out = {{32{temp_data[(within_block_offset * 8) + 31]}}, temp_data[(within_block_offset * 8) +: 32]};
                        else
                            data_out = {32'b0, temp_data[(within_block_offset * 8) +: 32]};
                    end
                    3'b111: begin // 8 bytes
                        data_out = temp_data; // Entire block
                    end
                    default: begin
                        data_out = 64'b0; // Default case, shouldn't happen
                    end
                endcase
                send_enable_next = 1;
                if (!read_enable) begin
                    send_enable_next = 0;
                    // data_out = 0;
                    check_done = 0;
                end
            end 

            WRITE_MISS: begin
                data_cache_reading = 0;
                cache_data[set_index][empty_way_next][(block_offset) * 64 +: 64] = 
                                (cache_data[set_index][empty_way_next][(block_offset) * 64 +: 64] & ~write_mask) | 
                                (data_shifted & write_mask);
                send_enable_next = 1;
                dirty_bits[set_index][empty_way_next] = 1;
                // $display("Cache Write Miss");
                // $display("Cache line at %h tag and %h set index with %h block offset. Makes address %h. Start address %h", tag, set_index, block_offset, {tag, set_index, block_offset}, {tag, set_index, {block_offset_width{1'b0}}});
                // $display("Cache line is %h.", cache_data[set_index][empty_way_next]);
                // $display("Data Input is %h", data_input);
                if (!write_enable) begin
                    send_enable_next = 0;
                    check_done = 0;
                end                 
            end 
            // New states for write operations
            WRITE_REQUEST: begin
                // Add actions for WRITE_REQUEST state if needed
                need_cleaning = 0;
                cleaning_check_done = 0;
                clean_done_next = 0;
                if (cleaning_ecall_now) begin
                    modified_address = {tags[set_index][clean_way], set_index, {block_offset_width{1'b0}}};
                    dirty_bits[set_index][clean_way] = 0;
                    // $display("Modified Write Address E Call %h", modified_address);
                    // $display("Cache data being written %h", cache_data[set_index][clean_way]);
                end else begin
                    modified_address = {tags[set_index][way_to_replace], set_index, {block_offset_width{1'b0}}};
                    dirty_bits[set_index][way_to_replace] = 0;
                    // $display("Modified Write Address Normal Replace %h", modified_address);
                    // $display("Cache data being written %h", cache_data[set_index][way_to_replace]);
                end 
                m_axi_awvalid = 1;
                m_axi_awlen = 7;
                m_axi_awsize = 3;
                m_axi_awburst = 1;
                m_axi_awaddr = modified_address;
            end

            WRITE_MEMORY_WAIT: begin
                m_axi_awvalid = 0;            
            end

            WRITE_MEMORY_ACCESS: begin
                // m_axi_wvalid = 1;
                // if (burst_counter == 7) begin
                //     m_axi_wvalid = 0;
                // end 
            end

            WRITE_COMPLETE: begin
                // if (!m_axi_wlast && !m_axi_bready) begin
                //     write_data_done = 1; //TODO: Reset this 
                // end 
            end

            REPLACE_DATA: begin
                replace_line = 0;
            end
            
            AC_SNOOP: begin
                if (m_axi_acready) begin
                    set_index = ac_address[block_offset_width +: set_index_width];
                    tag = ac_address[addr_width-1:addr_width-tag_width];
                    for (int i = 0; i < ways; i++) begin
                        if (tags[set_index][i] == tag) begin
                            valid_bits[set_index][i] = 0;  // Invalidate the cache line
                            // cache_invalidated = 1;
                        end
                    end
                end
                if (!m_axi_acvalid && !m_axi_acready) begin
                    invalidation_check_done = 1;
                end
            end

            FLUSH_DIRTY: begin
                if (!cleaning_check_done) begin
                    for (int s = 0; s < sets; s++) begin  // Iterate through all sets
                        for (int w = 0; w < ways; w++) begin  // Iterate through all ways in each set
                            if (dirty_bits[s][w] == 1) begin  // Check if dirty bit is set
                                need_cleaning = 1;  // Notify that a replacement is possible
                                set_index = s;  // Capture the set index
                                clean_way = w;  // Capture the way index
                            end
                        end
                    end
                    cleaning_check_done = 1;
                end 
                if (cleaning_check_done && !need_cleaning) begin// Exit the outer loop if replacement found
                    clean_done_next = 1;
                end
            end 

            default: begin
                //data_out = 0;
                check_done = 0;
                cache_hit = 0;
                m_axi_arvalid = 0;
                m_axi_rready = 0;
                send_enable_next = 0;
                next_state = 0;
            end
        endcase
    end 
end

endmodule