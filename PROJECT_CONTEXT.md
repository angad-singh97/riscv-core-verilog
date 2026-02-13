# Pipelined RISC-V Processor — Project Context for LLMs

> **Purpose**: This document gives an AI/LLM enough context to understand, modify, and debug this codebase without reading every file.

---

## 1. Project Overview

This is a **5-stage fully pipelined RISC-V 64-bit CPU** with:
- **Set-associative caches** (instruction + data)
- **Branch predictor**: always not taken
- **AXI** memory interface
- **Verilator** simulation + C++ testbench (DRAMSim2 for memory)

Author: Angad Singh (CSE502 course project).

---

## 2. Architecture Summary

### 2.1 Pipeline Stages

| Stage | Module | File | Purpose |
|-------|--------|------|---------|
| 1. Fetch | `InstructionFetcher` | `fetcher.sv` | Fetch instruction from I-cache, PC selection |
| 2. Decode | `InstructionDecoder` | `decoder.sv` | Decode instruction, read registers, emit control signals |
| 3. Execute | `InstructionExecutor` | `execute.sv` | ALU, branch resolution, jump target |
| 4. Memory | `InstructionMemoryHandler` | `memory.sv` | Load/store via D-cache |
| 5. Write-back | `InstructionWriteBack` | `write_back.sv` | Write result to register file, handle ECALL |

### 2.2 Pipeline Registers (top.sv)

- **IF/ID**: `if_id_instruction_reg`, `if_id_pc_plus_i_reg`, `if_id_valid_reg`
- **ID/EX**: `id_ex_reg_a_data`, `id_ex_reg_b_data`, `id_ex_pc_plus_I_reg`, `id_ex_control_signal_struct`
- **EX/MEM**: `ex_mem_alu_data`, `ex_mem_reg_b_data`, `ex_mem_pc_plus_I_offset_reg`, `ex_mem_control_signal_struct`
- **MEM/WB**: `mem_wb_loaded_data`, `mem_wb_alu_data`, `mem_wb_control_signals_reg`, `mem_wb_valid_reg`

### 2.3 Control Flow

- **Branch predictor**: always not taken; on misprediction, pipeline is flushed and `upstream_disable` disables Fetch/Decode/Execute.
- **Branches/Jumps**: resolved in Execute; `jump_signal` → `upstream_disable`, `initial_pc` set to target.
- **ECALL**: detected in Fetch (opcode `0x00000073`); special handling in Write-back and Memory stages.

---

## 3. Key Data Structures

### 3.1 `control_signals_struct` (control_signals_struct.svh)

```systemverilog
typedef struct packed {
    logic [63:0] imm;
    logic [6:0] opcode;
    logic [63:0] shamt;
    logic [7:0] instruction;   // Internal instruction type (0–65)
    logic [2:0] data_size;    // 1=byte, 2=half, 4=word, 7=double
    logic read_memory_access;
    logic write_memory_access;
    logic [4:0] dest_reg;
    logic jump_signal;
    logic [63:0] pc;
    logic signed_type;        // For sign-extended loads
} control_signals_struct;
```

### 3.2 Instruction Type Encoding (decoder → ALU)

Decoder maps RISC-V opcodes/funct3/funct7 to internal `instruction` codes (0–65), e.g.:

- **R-type**: 0=ADD, 1=SUB, 2=XOR, 3=OR, 4=AND, 5=SLL, 6=SRL, 7=SRA, 8=SLT, 9=SLTU, 10–17=MUL/DIV/REM, etc.
- **I-type**: 18=ADDI, 19=XORI, 20=ORI, 21=ANDI, 22–26=shift/slti, 29–32=ADDIW/SLLIW/SRLIW/SRAIW
- **RV64M**: 33–42=ADDW, SUBW, MULW, DIVW, etc.
- **Loads**: 59–65=LB, LH, LW, LBU, LHU, LWU, LD
- **Stores**: 43–46=SB, SH, SW, SD
- **Branches**: 47–52=BEQ, BNE, BLT, BGE, BLTU, BGEU
- **Jumps**: 53=JAL, 54=JALR
- **Other**: 55=LUI, 56=AUIPC, 57=ECALL, 58=EBREAK

---

## 4. Module Descriptions

### 4.1 Instruction Fetcher (`fetcher.sv`)

- Uses `recache` (instruction cache) fronting AXI.
- PC: `select_target` → `target_address` (branch/jump) else `pc_current + 4`.
- Detects ECALL (`0x00000073`), sets `ecall_detected`.
- Handshake: `fetch_enable`, `recache_request_ready`, `recache_result_ready`, `fetcher_done`.

### 4.2 Decoder (`decoder.sv`)

- Combinational decode: opcode, funct3, funct7 → `instruction`, `imm`, `shamt`, `rs1`, `rs2`, `rd`.
- Produces `control_signals_struct` and `decode_complete`.
- Handles R, I, S, B, J, U, W, IW types and system instructions.

### 4.3 Execute (`execute.sv`)

- Instantiates `alu` for arithmetic and address computation.
- Branch resolution: B-type → compare rs1/rs2; I-type JAL/JALR → compute target.
- Sets `jump_signal` and `pc_I_offset_out` for taken branches/jumps.

### 4.4 ALU (`alu.sv`)

- Single `always_comb` case on `instruction`.
- Handles arithmetic, logical, shift, compare, address calc for loads/stores.
- Branch conditions produce 1 or 0.

### 4.5 Memory (`memory.sv`)

- Uses `decache` for data cache.
- Read: `read_memory_access` → request from decache, wait for `decache_result_ready`.
- Write: `write_memory_access` → store via decache.
- ECALL: special path when `ecall_clean` and `instruction == 57`.

### 4.6 Instruction Cache (`recache.sv`)

- 2-way set-associative, 32 sets, 512-byte lines.
- States: IDLE_HIT → MISS_REQUEST → MEMORY_WAIT → MEMORY_ACCESS → STORE_DATA → SEND_DATA.
- Conflicts with data cache via `instruction_cache_reading` / `data_cache_reading`.

### 4.7 Data Cache (`decache.sv`)

- 2-way set-associative, 32 sets, 512-byte lines.
- Supports read miss, write miss, dirty eviction, AC snoop (MakeInvalid), ECALL flush.
- Writes use `do_pending_write` (DPI-C) to merge store traffic with memory model.

### 4.8 Register File (`register_file.sv`)

- 32 × 64-bit registers; x2 initialized to `stackptr`.
- Busy bits for RAW hazard; `raw_dependency` when rs1/rs2 read busy register.
- Sync write, async read.

### 4.9 Write-back (`write_back.sv`)

- Selects source: ALU result, loaded data, or PC+4 (JAL/JALR).
- ECALL: uses `do_ecall` (DPI-C), multi-cycle handling.

---

## 5. Hazard Handling

- **RAW**: `destination_reg` / `register_busy`; decode stalls until `!raw_dependency`.
- **Control**: branch/jump in EX → `upstream_disable`, flush IF/ID/ID/EX.
- **Cache**: instruction and data caches share AXI; `instruction_cache_reading` / `data_cache_reading` prevent concurrent use.

---

## 6. Build & Run

```bash
make          # Build
make run      # Run (uses PROG in Makefile)
```

- **Makefile**: `PROG` = program binary; `verilator` compiles `top.sv` and links with C++ (system, fake-os, hardware).
- **Program binary**: set `RUNELF` or `PROG` in Makefile.
- **Trace**: `trace.vcd`; view with `gtkwave trace.vcd`.

---

## 7. DPI-C / C++ Interface (`Sysbus.defs`, `fake-os.cpp`)

| Function | Purpose |
|----------|---------|
| `do_pending_write(addr, val, size)` | Buffer store before memory model sees it |
| `do_finish_write(addr, size)` | Notify memory model that write completed |
| `do_ecall(a7, a0–a6, a0ret)` | System call emulation |

- `fake-os.cpp`: Linux syscall emulation, `do_pending_write` buffer, `do_ecall` dispatch.
- `system.cpp`: DRAMSim2, AXI bus, ELF loading, MMU (optional).

---

## 8. File Map

| File | Role |
|------|------|
| `top.sv` | Top-level, pipeline glue, stage enables |
| `fetcher.sv` | Fetch stage |
| `decoder.sv` | Decode stage |
| `execute.sv` | Execute stage |
| `alu.sv` | ALU |
| `memory.sv` | Memory stage |
| `write_back.sv` | Write-back stage |
| `register_file.sv` | Register file |
| `recache.sv` | Instruction cache |
| `decache.sv` | Data cache |
| `control_signals_struct.svh` | Control struct |
| `pipeline_reg_struct.svh` | Pipeline reg structs (partially used) |
| `Sysbus.defs` | DPI-C declarations |
| `main.cpp` | Verilator testbench entry |
| `system.cpp` | Memory system, DRAMSim2, bus |
| `fake-os.cpp` | Syscall emulation |
| `hardware.cpp` | Device handlers (UART, CLINT) |

---

## 9. Notable Conventions

- **64-bit**: Addresses and data are 64-bit.
- **PC update**: Sequential in Fetch; branches/jumps override in Execute.
- **ECALL**: ECALL detected in Fetch; `ecall_detected` propagates; pipeline stalls until ECALL completes in Write-back.
- **Simulation stop**: `$finish()` when `initial_pc == 0x14` (debug breakpoint).
- **mux_selector**: Selects PC source (sequential vs target) in Fetch.

---

## 10. Common Edit Points

- **Add instruction**: Decoder case + ALU case + control signals.
- **Change cache**: Adjust `recache.sv` / `decache.sv` parameters or logic.
- **Branch predictor**: Modify Fetch/Decode/Execute control paths.
- **Fix hazards**: Adjust `destination_reg` / `raw_dependency` use in `top.sv` and register file.
