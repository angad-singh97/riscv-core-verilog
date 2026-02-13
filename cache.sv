// module cache #(
//     parameter cache_line_size = 64,
//     parameter cache_lines = 256,
//     parameter sets = 64,
//     parameter ways = 4,
//     parameter addr_width = 64,
//     parameter data_width = 32
// )(
//     input logic clock,
//     input logic reset,
//     input logic read_enable,                  // Signal to trigger a cache read
// 	  input logic write_enable, 
//     input logic [63:0] address,               // Address to read from
//     input logic [2:0] data_size,              // Size of data requested (in bytes)
//     input logic send_complete,

//     // AXI interface inputs for read transactions
//     input logic m_axi_arready,                // Ready signal from AXI for read address
//     input logic m_axi_rvalid,                 // Data valid signal from AXI read data channel
//     input logic m_axi_rlast,                  // Last transfer of the read burst
//     input logic [63:0] m_axi_rdata,           // Data returned from AXI read channel
    
//     // AXI interface outputs for read transactions
//     input logic m_axi_arvalid,                // Valid signal for read address
//     input logic [63:0] m_axi_araddr,          // Read address output to AXI
//     input logic [7:0] m_axi_arlen,            // Length of the burst (set to fetch full line)
//     input logic [2:0] m_axi_arsize,           // Size of each data unit in the burst
//     input logic m_axi_rready,                 // Ready to accept data from AXI

//     // Data output and control signals
//     output logic [63:0] data,                  // Data output to CPU
//     output logic send_enable,                  // Indicates data is ready to send
//     output logic read_complete                 // Indicates the read operation is complete
// );

// enum logic [3:0] {
//     IDLE          = 4'b0000,
//     CHECK_READ    = 4'b0001,
//     HIT_SEND      = 4'b0010,
//     MISS_REQUEST  = 4'b0011,
//     MEMORY_WAIT   = 4'b0100,
//     MEMORY_ACCESS = 4'b0101,
//     STORE_SEND    = 4'b0110,
//     CHECK_WRITE   = 4'b0111,  
//     HIT_WRITE     = 4'b1000,  
//     MEMORY_SETUP  = 4'b1001,  
//     WAIT_WRITE    = 4'b1010,  
//     WRITE_TO      = 4'b1011,  
//     MISS_WRITE    = 4'b1100   
// } current_state, next_state;


// // Derived parameters
// localparam block_offset_width = $clog2(cache_line_size / data_width);
// localparam set_index_width = $clog2(sets);
// localparam tag_width = addr_width - set_index_width - block_offset_width;

// // Cache storage arrays
// logic [tag_width-1:0] tags [sets-1:0][ways-1:0];            // Array for storing tags
// logic [cache_line_size-1:0] cache_data [sets-1:0][ways-1:0];      // Array for storing cache line data
// logic valid_bits [sets-1:0][ways-1:0];                       // Valid bits array
// // logic [ways-1:0] lru_counters [sets-1:0];                   // LRU counters for each set

// // internal logic bits
// logic cache_hit;
// logic check_done;
// logic [set_index_width-1:0] set_index;
// logic [tag_width-1:0] tag;
// logic [block_offset_width-1:0] block_offset;
// logic [data_width-1:0] data_out; 
// logic [31:0] buffer_array[0:15];    // 16 instructions, each 32 bits
// logic [3:0] buffer_pointer;          // Points to the next location in buffer_array
// logic [2:0] burst_counter;           // Counts each burst (0-7)
// logic [63:0] current_transfer_value;
// logic data_retrieved;

// // internal logic next bits
// logic cache_hit_next;
// logic check_done_next;
// logic [data_width-1:0] data_out_next;
// logic send_enable_next;
// logic data_retrieved_next;

// // State transition logic - always_comb block
// // This always_comb block will handle the next_state calculations for us.
// always_comb begin
//   case (current_state)
//     IDLE: begin
//       // Transition to CHECK_READ if a read is enabled or CHECK_MISS if a write is enabled.
//       next_state = (read_enable) ? CHECK_READ : IDLE;
//       next_state = (write_enable) ? CHECK_MISS : IDLE;
//     end

//     CHECK_READ: begin
//       // If cache hit and check is done, transition to HIT_SEND to send data.
//       // Otherwise, if cache miss and check is done, transition to MISS_REQUEST for a memory read.
//       next_state = (cache_hit && check_done) ? HIT_SEND : CHECK_READ;
//       next_state = (!cache_hit && check_done) ? MISS_REQUEST : CHECK_READ;
//     end

//     HIT_SEND: begin
//       // Transition to IDLE once data has been sent and send enable is disabled.
//       next_state = (send_complete && !send_enable) ? IDLE : HIT_SEND;
//     end

//     MISS_REQUEST: begin
//       // Wait for the memory address handshake to complete, then transition to MEMORY_WAIT.
//       next_state = (m_axi_arvalid && m_axi_arready) ? MEMORY_WAIT : MISS_REQUEST;
//     end

//     MEMORY_WAIT: begin
//       // Wait for the memory to be ready to send data; then transition to MEMORY_ACCESS.
//       next_state = (m_axi_rready) ? MEMORY_ACCESS : MEMORY_WAIT;
//     end

//     MEMORY_ACCESS: begin
//       // If data retrieval is complete, transition to STORE_SEND to store data in the cache.
//       next_state = (data_retrieved) ? STORE_SEND : MEMORY_ACCESS;
//     end

//     STORE_SEND: begin
//       // Transition to IDLE once data is stored and sending is complete.
//       next_state = (send_complete && !send_enable) ? IDLE : STORE_SEND;
//     end

//     CHECK_MISS: begin
//       // On a cache miss, if cache hit is confirmed, transition to HIT_WRITE for writing.
//       // Otherwise, transition to MEMORY_SETUP to set up the memory for a write.
//       next_state = (cache_hit) ? HIT_WRITE : IDLE;
//       next_state = (!cache_hit) ? MEMORY_SETUP : IDLE;
//     end

//     HIT_WRITE: begin
//       // If the write operation is complete, transition to MEMORY_SETUP.
//       next_state = (write_complete) ? MEMORY_SETUP : HIT_WRITE;
//     end

//     MEMORY_SETUP: begin
//       // Prepare for memory access; if a write is enabled, transition to WAIT_WRITE.
//       next_state = (write_enable) ? WAIT_WRITE : MEMORY_SETUP;
//     end

//     WAIT_WRITE: begin
//       // Wait until memory is ready to accept a write, then proceed to WRITE_TO.
//       next_state = (m_axi_awready) ? WRITE_TO : WAIT_WRITE;
//     end

//     WRITE_TO: begin
//       // If the write is done and there was a cache hit, return to IDLE.
//       // If the write is done but there was no cache hit, go to MISS_WRITE to handle the miss.
//       next_state = (write_done && cache_hit) ? IDLE : WRITE_TO;
//       next_state = (write_done && !cache_hit) ? IDLE : MISS_WRITE;
//     end

//     MISS_WRITE: begin
//       // On a confirmed write miss, transition back to IDLE.
//       next_state = (write_miss_confirmed) ? IDLE : MISS_WRITE;
//     end

//     default: begin
//       next_state = IDLE;
//     end
//   endcase
// end

// // State and control signal updates - always_ff block
// // This always_ff block handles resetting and updating states, signals, and variables.
// // State and control signal updates - always_ff block
// // This always_ff block handles resetting and updating states, signals, and variables.
// always_ff @(posedge clock) begin
//     if (reset) begin
//         // Initialize state and relevant variables
//         current_state <= IDLE;
//         data_out <= 0;
//         check_done <= 0;
//         cache_hit <= 0;
//         send_enable <= 0;
//         m_axi_arvalid <= 0;
//         m_axi_rready <= 0;
//         buffer_pointer <= 0;
//         burst_counter <= 0;

//   	end else begin
//         // Update current state and other variables as per state transitions
//         current_state <= next_state;
//         check_done <= check_done_next;
//         data_out <= data_out_next;
//         cache_hit <= cache_hit_next;
//         send_enable <= send_enable_next;
//         data_retrieved <= data_retrieved_next;
    
//         case (current_state)
//             IDLE: begin
//                 // Reset signals, prepare for new operation
//                 if (reset) begin
//                     for (int i = 0; i < 16; i = i + 1) begin
//                         buffer_array[i] <= 32'b0;
//                     end
//                 end
//             end

//             CHECK_READ: begin
//                 // Prepare signals/variables for checking cache
//                 check_done <= check_done_next;
//                 data_out <= data_out_next;
//                 cache_hit <= cache_hit_next;
//                 send_enable <= send_enable_next;
//             end

//             HIT_SEND: begin
//                 // Set signals/variables for sending data on a cache hit
//                 send_enable <= send_enable_next;
//             end

//             MISS_REQUEST: begin
//                 // Initiate memory access on cache miss by setting read address valid signal
//                 m_axi_arvalid <= 1;
//             end

//             MEMORY_WAIT: begin
//                 // Wait for memory to be ready for data retrieval
//                 m_axi_rready <= 1;
//             end

//             MEMORY_ACCESS: begin
//                 // Manage data retrieval and store it in buffer_array
//                 if (m_axi_rvalid) begin
//                     buffer_array[buffer_pointer] <= m_axi_rdata[31:0];
//                     buffer_array[buffer_pointer + 1] <= m_axi_rdata[63:32];
//                     buffer_pointer <= buffer_pointer + 2;
//                     burst_counter <= burst_counter + 1;

//                     // Check if last burst transfer is reached
//                     if (m_axi_rlast && (burst_counter == 7)) begin
//                         buffer_pointer <= 0;
//                         burst_counter <= 0;
//                     end
//                 end
//                 data_retrieved <= data_retrieved_next;
//             end

//             STORE_SEND: begin
//                 // Handle data storing or sending after retrieval
//                 send_enable <= send_enable_next;
//                 data_out <= data_out_next;
//             end

//             CHECK_WRITE: begin
//                 // Check if data can be written on a cache hit, otherwise prepare for memory access
//                 check_done <= check_done_next;
//                 cache_hit <= cache_hit_next;
//             end

//             HIT_WRITE: begin
//                 // Handle cache hit on write, set signals to complete write operation
//                 if (cache_hit) begin
//                     data_out <= data_out_next;
//                     send_enable <= send_enable_next;
//                 end
//             end

//             MEMORY_SETUP: begin
//                 // Set up memory for write or read operations
//                 m_axi_arvalid <= 1;
//                 m_axi_rready <= 0;
//             end

//             WAIT_WRITE: begin
//                 // Wait for memory to accept write address
//                 if (m_axi_awready) begin
//                     m_axi_awvalid <= 0;
//                 end
//             end

//             WRITE_TO: begin
//                 // Initiate data write to memory
//                 if (write_done) begin
//                     data_out <= data_out_next;
//                 end
//             end

//             MISS_WRITE: begin
//                 // Handle cache miss on write and confirm memory setup
//                 if (write_miss_confirmed) begin
//                     send_enable <= 0;
//                 end
//             end

//             default: begin
//                 // Default case to reset to IDLE in case of undefined states
//                 current_state <= IDLE;
//             end
//         endcase
//   	end
// end


// // Control signals and state-related updates - always_comb block
// // This is the always_comb block that manages signal changes at each state transition
// always_comb begin
//   // Initialize default values for control signals
//   send_enable = 0;
//   cache_data = 0;

//   case (current_state)
//     IDLE: begin
//       // Set control signals for the IDLE state
//       check_done_next = 0;
//       data_out_next = 0;
//       cache_hit_next = 0;
//       send_enable_next = 0;
//       data_retrieved_next = 0;
//     end

//     CHECK_READ: begin
//       // Set control signals for the CHECK_READ state
//       set_index = address[block_offset_width +: set_index_width];
//       tag = address[addr_width-1:addr_width-tag_width];
//       block_offset = address[block_offset_width-1:0];

//       for (int i = 0; i < ways; i++) begin
//         if (tags[set_index][i] == tag) begin  // Check for tag match
//           cache_hit_next = 1;   // Cache hit
//           data_out_next = cache_data[set_index][i][block_offset * data_size +: data_size];
//           send_enable_next = 1;
//         end
//         check_done_next = 1;
//       end
//     end

//     HIT_SEND: begin
//       // Set control signals for the HIT_SEND state
//       if (send_complete) begin
//         send_enable_next = 0;
//       end
//     end

//     MISS_REQUEST: begin
//       // Set control signals for the MISS_REQUEST state
//       modified_address = {address[addr_width-1:block_offset_width], {block_offset_width{1'b0}}};
//       m_axi_arvalid = 1;
//       m_axi_arlen = 7;
//       m_axi_arsize = 3;
//       m_axi_arburst = 2;
//       m_axi_araddr = modified_address;
//     end

//     MEMORY_WAIT: begin
//       // Set control signals for the MEMORY_WAIT state
//       m_axi_rready = 1;
//       m_axi_arvalid = 0;
//     end    

//     MEMORY_ACCESS: begin
//       // Set control signals for the MEMORY_ACCESS state
//       current_transfer_value = m_axi_rdata;
//       if (m_axi_rlast && m_axi_rready) begin
//         m_axi_rready = 0;
//         data_retrieved_next = 1;
//       end
//     end

//     STORE_DATA: begin
//       // Set control signals for the STORE_SEND state
//       set_index = modified_address[block_offset_width + set_index_width - 1 : block_offset_width];
//       tag = modified_address[addr_width-1 : addr_width - tag_width];
//       int empty_way = -1;
//       for (int w = 0; w < ways; w++) begin
//         if (!valid_bits[set_index][w]) begin
//           empty_way = w;
//           break;
//         end
//       end

//       if (empty_way != -1) begin
//         // Write tag and data into cache
//         tags[set_index][empty_way] = tag;
//         cache_data[set_index][empty_way] = {buffer_array[15], buffer_array[14], buffer_array[13], buffer_array[12],
//                                             buffer_array[11], buffer_array[10], buffer_array[9], buffer_array[8],
//                                             buffer_array[7], buffer_array[6], buffer_array[5], buffer_array[4],
//                                             buffer_array[3], buffer_array[2], buffer_array[1], buffer_array[0]};
//         valid_bits[set_index][empty_way] = 1;
//       end
//       data_out_next = cache_data[set_index][i][block_offset * data_size +: data_size];
//       send_enable_next = 1;
//       if (send_complete) begin
//         send_enable_next = 0;
//       end
//     end

//     CHECK_WRITE: begin
//       // Prepare control signals for the CHECK_WRITE state
//     end

//     HIT_WRITE: begin
//       // Set control signals for HIT_WRITE state
//     end

//     MEMORY_SETUP: begin
//       // Set control signals for MEMORY_SETUP state
//     end

//     WAIT_WRITE: begin
//       // Set control signals for WAIT_WRITE state
//     end

//     WRITE_TO: begin
//       // Control signals for WRITE_TO state
//     end

//     MISS_WRITE: begin
//       // Set control signals for MISS_WRITE state
//     end

//     default: begin
//       // Default case to reset signals if current state is undefined
//       send_enable = 0;
//       cache_data = 0;
//     end
//   endcase
// end



// endmodule