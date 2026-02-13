module recache #(
    parameter cache_line_size = 512,           // Size of each cache line in bytes
    parameter cache_lines = 4,              // Total number of cache lines
    parameter sets = 32,                      // Number of sets in the cache
    parameter ways = 2,                       // Number of ways (associativity) in the cache
    parameter addr_width = 64,                // Width of the address bus
    parameter data_width = 32                 // Width of the data bus
)(
    input logic clock,
    input logic reset,
    input logic read_enable,                  // Signal to trigger a cache read
    input logic [63:0] address,               // Address to read/write from/to cache
    // input logic [2:0] data_size,              // Size of data requested (in bytes)
    // input logic send_complete,                // Indicates data transfer is complete

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

    // Data output and control signals
    output logic [31:0] data_out,                 // Data output to CPU
    output logic send_enable,                 // Indicates data is ready to send
    //output logic read_complete                // Indicates the read operation is complete

    // AXI Control
    input logic data_cache_reading,
    output logic instruction_cache_reading,
    input logic jump_reset
);

enum logic [3:0] {
    IDLE_HIT      = 4'b0000, // Idle and cache hit handling for reads
    MISS_REQUEST  = 4'b0001, // Handling read cache miss, initiating memory request
    MEMORY_WAIT   = 4'b0010, // Waiting for memory response after a miss
    MEMORY_ACCESS = 4'b0011, // Accessing data as it's received from memory
    STORE_DATA    = 4'b0100,  // Storing data into cache after a read miss
    SEND_DATA     = 4'b0101,  // Sending data to the fetcher
    REPLACE_DATA  = 4'b0110
} current_state, next_state;

// Derived parameters
localparam block_offset_width = $clog2(cache_line_size / data_width) + 2;
// localparam block_offset_width = ;
localparam set_index_width = $clog2(sets);
localparam tag_width = addr_width - set_index_width - block_offset_width;

// Cache storage arrays
logic [tag_width-1:0] tags [sets-1:0][ways-1:0];            // Array for storing tags
logic [cache_line_size-1:0] cache_data [sets-1:0][ways-1:0];      // Array for storing cache line data
logic valid_bits [sets-1:0][ways-1:0];                       // Valid bits array

// internal logic bits
logic cache_hit;
logic check_done;

logic [set_index_width-1:0] set_index;
logic [set_index_width-1:0] set_index_next;

logic [tag_width-1:0] tag;
logic [tag_width-1:0] tag_next;

logic [block_offset_width-1:0] block_offset;
logic [data_width-1:0] data_out; 
logic [31:0] buffer_array [15:0];    // 16 instructions, each 32 bits
logic [3:0] buffer_pointer;          // Points to the next location in buffer_array
logic [3:0] burst_counter;           // Counts each burst (0-7)
logic [63:0] current_transfer_value;
logic data_retrieved;

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
integer empty_way;
integer empty_way_next;
integer set;
integer way;
logic data_stored;
logic way_cleaned;
logic replace_line;
logic [$clog2(ways)-1:0] way_to_replace;
logic [$clog2(ways)-1:0] counter;
logic local_jump_reset;

integer data_size_temp = 32; 
integer block_number;
integer i;
// State register update (sequential block)

always_ff @(posedge clock) begin
    if (reset)
        counter <= 0;              // Reset counter
    else if (replace_line)
        counter <= (counter + 1) % ways; // Increment counter cyclically
end

assign way_to_replace = counter;

always_ff @(posedge clock) begin
    if (reset) begin
        // Initialize state and relevant variables
        current_state <= IDLE_HIT;
        buffer_pointer <= 0;
        burst_counter <= 0;
        data_received_mem <= 0;
        for (set = 0; set < sets; set = set + 1) begin
            for (way = 0; way < ways; way = way + 1) begin
                tags[set][way] <= {tag_width{1'b0}};         // Initialize tags to 0
                cache_data[set][way] <= {cache_line_size{1'b0}}; // Initialize cache data to 0
                valid_bits[set][way] <= 1'b0;               // Initialize valid bits to 0
            end
        end
  	end else begin
        // Update current state and other variables as per state transitions
        current_state <= next_state;
        send_enable <= send_enable_next;
        data_retrieved <= data_retrieved_next;
        if (!local_jump_reset) begin
            local_jump_reset <= jump_reset;
        end 
    case (current_state)
        IDLE_HIT: begin
            for (i = 0; i < 16; i = i + 1) begin
                buffer_array[i] <= 32'b0;
            end
            data_received_mem <= 0;
            way_cleaned <= 0;
            if (local_jump_reset) begin
                local_jump_reset <= 0;
            end 
        end

        MISS_REQUEST: begin
            // Issue memory read request on a cache miss

        end

        MEMORY_WAIT: begin
            // Wait for memory response

        end

        MEMORY_ACCESS: begin
            if (m_axi_rvalid && m_axi_rready) begin
                buffer_array[buffer_pointer] <= m_axi_rdata[31:0];
                buffer_array[buffer_pointer + 1] <= m_axi_rdata[63:32];
                buffer_pointer <= buffer_pointer + 2;
                burst_counter <= burst_counter + 1;
            end

            if (m_axi_rlast && (burst_counter == 8)) begin
                buffer_pointer <= 0;
                burst_counter <= 0;
                data_received_mem <= 1;
            end
        end

        STORE_DATA: begin
            // Store fetched data in cache
            if (empty_way_next != -1) begin
                // Write tag and data into cache
                tags[set_index_next][empty_way_next] <= tag;
                cache_data[set_index_next][empty_way_next] <= {buffer_array[15], buffer_array[14], buffer_array[13], buffer_array[12],
                                                    buffer_array[11], buffer_array[10], buffer_array[9], buffer_array[8],
                                                    buffer_array[7], buffer_array[6], buffer_array[5], buffer_array[4],
                                                    buffer_array[3], buffer_array[2], buffer_array[1], buffer_array[0]};

                valid_bits[set_index_next][empty_way_next] <= 1;
                data_stored <= 1;
            end
        end

        SEND_DATA: begin

        end

        REPLACE_DATA: begin
            valid_bits[set_index][way_to_replace] <= 0;
            way_cleaned <= 1;
        end  
    endcase
    end 
end

// Next State Logic (combinational block)
always_comb begin
    case (current_state)
        IDLE_HIT: begin
            // Transition to MISS_REQUEST if cache miss
            next_state = (!cache_hit && check_done && !data_cache_reading) ? MISS_REQUEST : IDLE_HIT;
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
            // Return to IDLE_HIT after storing data
            if (local_jump_reset) begin
                next_state = IDLE_HIT;
            end else if (replace_line) begin
                next_state = REPLACE_DATA;
            end else if (data_stored) begin
                next_state = SEND_DATA;
            end else begin
                next_state = STORE_DATA;
            end
        end

        SEND_DATA: begin
            next_state = (!read_enable && !send_enable) ? IDLE_HIT : SEND_DATA;
        end

        REPLACE_DATA: begin
            next_state = (way_cleaned) ? STORE_DATA : REPLACE_DATA;
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
        instruction_cache_reading = 0;
    end 
    else begin

    case (current_state)
        IDLE_HIT: begin
            data_retrieved_next = 0;
            instruction_cache_reading = 0;
            if (read_enable && !check_done) begin
                set_index = address[block_offset_width +: set_index_width];
                tag = address[addr_width-1:addr_width-tag_width];
                block_offset = address[block_offset_width-1:2];

                for (int i = 0; i < ways; i++) begin
                    if (tags[set_index][i] == tag && valid_bits[set_index][i] == 1) begin  // Check for tag match
                        cache_hit = 1;   // Cache hit
                        data_out = cache_data[set_index][i][(block_offset) * 32 +: 32];
                    end
                end
                check_done = 1;
            end
            if (check_done && cache_hit) begin
                send_enable_next = 1;
            end 
            if (!read_enable) begin
                check_done = 0;
                cache_hit = 0;
                send_enable_next = 0;
            end          
        end

        MISS_REQUEST: begin
            instruction_cache_reading = 1;
            modified_address = {address[addr_width-1:block_offset_width], {block_offset_width{1'b0}}};
            m_axi_arvalid = 1;
            m_axi_arlen = 7;
            m_axi_arsize = 3;
            m_axi_arburst = 2;
            m_axi_araddr = modified_address;
            check_done = 0;
        end

        MEMORY_WAIT: begin
            m_axi_rready = 1;
            m_axi_arvalid = 0;
        end

        MEMORY_ACCESS: begin
            current_transfer_value = m_axi_rdata;
            if (data_received_mem) begin
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
            if (!jump_reset) begin
                data_out = cache_data[set_index][empty_way_next][(block_offset) * 32 +: 32]; 
            end
            send_enable_next = 1;
            instruction_cache_reading = 0;
            if (!read_enable) begin
                send_enable_next = 0;
                check_done = 0;
            end
        end

        REPLACE_DATA: begin
            replace_line = 0;
        end

    endcase
    end 
end

    // Internal signals and logic go here

endmodule
