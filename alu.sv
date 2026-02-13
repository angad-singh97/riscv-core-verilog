/*
ALU Instruction Mapping (8-bit codes to mnemonics):

R TYPE:
	8'd0 : ADD
	8'd1 : SUB
	8'd2 : XOR
	8'd3 : OR
	8'd4 : AND
	8'd5 : SLL
	8'd6 : SRL
	8'd7 : SRA
	8'd8 : SLT
	8'd9 : SLTU
	8'd10 : MUL
  8'd11 : MULH
  8'd12 : MULHSU
  8'd13 : MULHU
  8'd14 : DIV
  8'd15 : DIVU
  8'd16 : REM
  8'd17 : REMU

I TYPE:
	8'd18 : ADDI
	8'd19 : XORI
	8'd20 : ORI
	8'd21 : ANDI
	8'd22 : SLLI
	8'd23 : SRLI
	8'd24 : SRAI
	8'd25 : SLTI
	8'd26 : SLTIU

RV64I:
  8'd26 : SLLI (shamt)
  8'd27 : SRLI (shamt)
  8'd28 : SRAI (shamt)
  8'd29 : ADDIW
  8'd30 : SLLIW
  8'd31 : SRLIW
  8'd32 : SRAIW
  8'd33 : ADDW
  8'd34 : SUBW
  8'd35 : SLLW
  8'd36 : SRLW
  8'd37 : SRAW

RV64M:
  8'd38 : MULW
  8'd39 : DIVW
  8'd40 : DIVUW
  8'd41 : REMW
  8'd42 : REMUW

	**UNUSED IN ALU**
S-TYPE:
	8'd43 : SB
	8'd44 : SH
	8'd45 : SW
	8'd46 : SD

B-TYPE:
	8'd47 : BEQ
	8'd48 : BNE
	8'd49 : BLT
	8'd50 : BGE
	8'd51 : BLTU
	8'd52 : BGEU

	8'd53 : JAL
	8'd54 : JALR
	8'd55 : LUI
	8'd56 : AUIPC
	8'd57 : ECALL
	8'd58 : EBREAK

	8'd59 : LB
	8'd60 : LH
	8'd61 : LW
	8'd62 : LBU
	8'd63 : LHU
	8'd64 : LWU
	8'd65 : LD
*/

module alu (
	input logic [7:0] instruction,
	input logic [63:0] rs1, //value
	input logic [63:0] rs2, //value
	input signed [63:0] imm, //value
	input logic [63:0] shamt,
	input [63:0] pc_alu,
	input logic alu_enable,
	output signed [63:0] result
	//output logic alu_done_flag
);
logic signed [63:0] signed_imm;

always_comb begin
	// if (alu_enable) begin
		case(instruction)
		// R TYPE
			8'd0: begin // ADD
				result = rs1 + rs2;  
			end

			8'd1: begin // SUB
				result = rs1 - rs2;  
			end

			8'd2: begin // XOR
				result = rs1 ^ rs2;  
			end

			8'd3: begin // OR
				result = rs1 | rs2;  
			end

			8'd4: begin // AND
				result = rs1 & rs2;  
			end

			8'd5: begin // SLL
				result = rs1 << rs2;  
			end

			8'd6: begin // SRL
				result = rs1 >> rs2;  
			end

			8'd7: begin // SRA
				result = rs1 >>> rs2;  
			end

			8'd8: begin // SLT
				result = (rs1 < rs2) ? 1 : 0;
			end

			8'd9: begin // SLTU
				result = (rs1 < rs2) ? 1 : 0;
			end

		// I TYPE
			8'd18: begin // ADDI
			// Extract the lower 12 bits of the immediate
			logic [11:0] imm_12bit = imm[11:0];

			// Sign-extend the 12-bit immediate to 64 bits
			signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

			// Perform the addi operation
			result = rs1 + $signed(signed_imm);

			// result = $signed(rs1) + $signed(imm);  
			end

			8'd19: begin // XORI
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit
				
				result = rs1 ^ $signed(signed_imm);  
			end

			8'd20: begin // ORI
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

				result = rs1 | $signed(signed_imm);
			end

			8'd21: begin // ANDI
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

				result = rs1 & $signed(signed_imm);  
			end

			// 8'd22: begin // SLLI
			// 	result = rs1 << imm;  
			// end

			// 8'd23: begin // SRLI
			// 	result = rs1 >> imm;  
			// end

			// 8'd24: begin // SRAI
			// 	result = rs1 >>> imm;  
			// end

			8'd25: begin // SLTI
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

				result = (rs1 < $signed(signed_imm)) ? 1 : 0;
			end

			8'd26: begin // SLTIU
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

				result = ($unsigned(rs1) < $unsigned(signed_imm)) ? 1 : 0;
			end

		// RV32M
			8'd10: begin // MUL
				result = rs1 * rs2;  
			end

			8'd11: begin // MULH
				result = (rs1 * rs2) >> 32;  
			end

			8'd12: begin // MULHSU
				result = ($signed(rs1) * $unsigned(rs2)) >> 32;  
			end

			8'd13: begin // MULHU
				result = (rs1 * rs2) >> 32;  
			end

			8'd14: begin // DIV
				result = rs1 / rs2;  
			end

			8'd15: begin // DIVU
				result = $unsigned(rs1) / $unsigned(rs2); 
			end

			8'd16: begin // REM
				result = rs1 % rs2;  
			end

			8'd17: begin // REMU
				result = $unsigned(rs1) % $unsigned(rs2);  
			end

		// RV64I
			8'd22: begin // SLLI
				result = rs1 << shamt[5:0];  // Masking shamt to 6 bits
			end

			8'd23: begin // SRLI
				result = rs1 >> shamt[5:0];  // Masking shamt to 6 bits
			end

			8'd24: begin // SRAI
				result = rs1 >>> shamt[5:0];  // Masking shamt to 6 bits
			end

			8'd29: begin // ADDIW
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit
				result = $signed(rs1[31:0]) + $signed(signed_imm);  
			end

			8'd30: begin // SLLIW
				result = $signed(rs1[31:0]) << shamt[4:0];  // Masking shamt to 5 bits
			end

			8'd31: begin // SRLIW
				result = $unsigned(rs1[31:0]) >> shamt[4:0];  // Masking shamt to 5 bits
			end

			8'd32: begin // SRAIW
				result = $signed(rs1[31:0]) >>> shamt[4:0];  // Masking shamt to 5 bits
			end

			8'd33: begin // ADDW
				result = $signed(rs1[31:0]) + $signed(rs2[31:0]);  
			end

			8'd34: begin // SUBW
				result = $signed(rs1[31:0]) - $signed(rs2[31:0]);  
			end

			8'd35: begin // SLLW
				result = rs1[31:0] << rs2[4:0];  
			end

			8'd36: begin // SRLW
				result = $unsigned(rs1[31:0]) >> rs2[4:0];  
			end

			8'd37: begin // SRAW
				result = $signed(rs1[31:0]) >>> rs2[4:0];  
			end

		// RV64M
			8'd38: begin // MULW
				result = $signed(rs1[31:0]) * $signed(rs2[31:0]);  
			end

			8'd39: begin // DIVW
				result = $signed(rs1[31:0]) / $signed(rs2[31:0]);  
			end

			8'd40: begin // DIVUW
				result = $unsigned(rs1[31:0]) / $unsigned(rs2[31:0]);  
			end

			8'd41: begin // REMW
				result = $signed(rs1[31:0]) % $signed(rs2[31:0]);  
			end

			8'd42: begin // REMUW
				result = $unsigned(rs1[31:0]) % $unsigned(rs2[31:0]);  
			end

		// B - Type : check branch conditions
			8'd47: begin // BEQ
				result = (rs1 == rs2) ? 64'b1 : 64'b0;
			end
			8'd48: begin // BNE
				result = (rs1 != rs2) ? 64'b1 : 64'b0;
			end
			8'd49: begin // BLT
				result = ($signed(rs1) < $signed(rs2)) ? 64'b1 : 64'b0;
			end
			8'd50: begin // BGE
				result = ($signed(rs1) >= $signed(rs2)) ? 64'b1 : 64'b0;
			end
			8'd51: begin // BLTU
				result = (rs1 < rs2) ? 64'b1 : 64'b0;
			end
			8'd52: begin // BGEU
				result = (rs1 >= rs2) ? 64'b1 : 64'b0;
			end

			8'd55: begin //LUI
				// logic [19:0] imm_20bit = imm[19:0];

				// // Sign-extend the 12-bit immediate to 64 bits
				// logic signed [63:0] signed_imm;
				// signed_imm = {{44{imm_20bit[19]}}, imm_20bit};  // imm_12bit[11] is the sign bit

				// result = $signed(signed_imm) << 12;
				result = imm;

			end 

		 //AUIPC: Add Upper Immediate to Program Counter Value
		 	8'd56 : begin
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				logic signed [63:0] signed_imm;
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

				result = pc_alu + ($signed(signed_imm) << 12);
			end

			// Load Instructions
			8'd59, 8'd60, 8'd61, 8'd62, 8'd63, 8'd64, 8'd65, 8'd43, 8'd44, 8'd45, 8'd46: begin
				// Extract the lower 12 bits of the immediate
				logic [11:0] imm_12bit = imm[11:0];

				// Sign-extend the 12-bit immediate to 64 bits
				logic signed [63:0] signed_imm;
				signed_imm = {{52{imm_12bit[11]}}, imm_12bit};  // imm_12bit[11] is the sign bit

				// Perform the addi operation to compute the effective address
				result = rs1 + $signed(signed_imm);
        	end

		endcase
		// if (pc_alu == 64'h0000000000018810) begin
		// 	// $display("IN ALU");
		// 	// $display("rs1 ", rs1);
		// 	// $display("imm ", signed_imm);
		// end
	// end
	end
endmodule
