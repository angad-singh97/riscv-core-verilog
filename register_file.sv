// module register_file 
// #(
//   ADDR_WIDTH = 5,
//   DATA_WIDTH = 64
// )
// (
//     // Global Signals
//     input clk,
//     input reset,
//     input [DATA_WIDTH-1:0] stackptr,

//     // For Read
//     input [ADDR_WIDTH-1:0] read_addr1,                       // Address of the first register to read
//     input [ADDR_WIDTH-1:0] read_addr2,                       // Address of the second register to read
//     //input rs2_valid,
//     output signed [DATA_WIDTH-1:0] read_data1,                  // 64-bit data from the first read register
//     output signed [DATA_WIDTH-1:0] read_data2,                   // 64-bit data from the second read register

//     // For Write
//     input write_enable,                                      // Write enable signal
//     input [ADDR_WIDTH-1:0] write_addr,                 // Address of the register to write
//     input signed [DATA_WIDTH-1:0] write_data,                       // 64-bit data to write into the register
//     input [ADDR_WIDTH-1:0] destination_reg,
//     output write_complete,                             // Write Completed
//     output [DATA_WIDTH-1:0] register [31:0],
//     output register_busy [31:0]
// );

//     // Declare a register array of size 32. Each register 64 bit.

//     // Sync write
//     always_ff @(posedge clk) begin
//         if (reset) begin
//             // If reset, register is initiated as 0
//             integer i;
//             for (i = 0; i < 32; i = i + 1) begin
//                 if (i==2) begin
//                     register[i] <= stackptr;
//                 end else begin
//                     register[i] <= 64'b0;
//                 end
//             end
            
//         end 
//         else if (write_enable) begin
//             if (write_addr != 0) begin
//                 register[write_addr] <= write_data;
//             end
//             write_complete <= 1;
//         end else begin
//             write_complete <= 0;
//         end
//     end

//     // Async Read
//     always_comb begin
//         read_data1 = register[read_addr1];
//         //if (rs2_valid) begin
//         read_data2 = register[read_addr2];
//         //end else
//             //read_data2 = 64'b0;
//     end
// endmodule


module register_file 
#(
  parameter ADDR_WIDTH = 5,
  parameter DATA_WIDTH = 64
)
(
    // Global Signals
    input clk,
    input reset,
    input [DATA_WIDTH-1:0] stackptr,

    // For Read
    input [ADDR_WIDTH-1:0] read_addr1,                       // Address of the first register to read
    input [ADDR_WIDTH-1:0] read_addr2,                       // Address of the second register to read
    output signed [DATA_WIDTH-1:0] read_data1,                  // 64-bit data from the first read register
    output signed [DATA_WIDTH-1:0] read_data2,                   // 64-bit data from the second read register

    // For Write
    input write_enable,                                      // Write enable signal
    input [ADDR_WIDTH-1:0] write_addr,                       // Address of the register to write
    input signed [DATA_WIDTH-1:0] write_data,                // 64-bit data to write into the register
    output write_complete,                                   // Write Completed
    output [DATA_WIDTH-1:0] register [31:0],
    // output logic [31:0] register_busy,                        // Busy status for each register
    input [ADDR_WIDTH-1:0] destination_reg,
    input [ADDR_WIDTH-1:0] reset_write_addr,
    output logic raw_dependency
);

    // Declare a register array of size 32. Each register is 64 bits.
    logic [DATA_WIDTH-1:0] register [31:0];
    logic write_complete;
    logic [31:0] register_busy; // Busy bits for the registers
    logic raw_dep1;
    logic raw_dep2;
    // Sync write
    always_ff @(posedge clk) begin
        if (reset) begin
            // If reset, initialize registers and busy bits
            integer i;
            for (i = 0; i < 32; i = i + 1) begin
                if (i == 2) begin
                    register[i] <= stackptr;
                end else begin
                    register[i] <= 64'd0;
                end
                register_busy[i] <= 1'b0; // All registers are initially not busy
            end
            write_complete <= 0;
        end 
        else if (write_enable) begin
            if (write_addr != 0) begin
                register[write_addr] <= write_data;
                register_busy[write_addr] <= 1'b0; // Clear busy bit when write completes
            end
            write_complete <= 1;
        end else begin
            write_complete <= 0;
        end
    end

    // Mark register as busy when a write is scheduled
    always_ff @(posedge clk) begin
        if (reset_write_addr) begin
            register_busy[reset_write_addr] <= 1'b0; // Set busy bit
        end
    end

    always_ff @(posedge clk) begin
        if (destination_reg) begin
            register_busy[destination_reg] <= 1'b1; // Set busy bit
        end
    end
    // Async Read
    always_comb begin
        // Output register data only if it is not busy
        if (!register_busy[read_addr1]) begin
            read_data1 = register[read_addr1];
            raw_dep1 = 0;
        end else begin
            read_data1 = register[read_addr1];
            raw_dep1 = 1;
            //read_data1 = 64'b0; // Default value if the register is busy
        end

        if (!register_busy[read_addr2]) begin
            read_data2 = register[read_addr2];
            raw_dep2 = 0;
        end else begin
            read_data2 = register[read_addr2];
            raw_dep2 = 1;
            //read_data2 = 64'b0; // Default value if the register is busy
        end
    end

    always_comb begin
        if (raw_dep1 || raw_dep2) begin
            raw_dependency = 1;
        end 
        else begin
            raw_dependency = 0;
        end 
    end
endmodule
