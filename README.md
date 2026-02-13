# RISC-V 5-Stage Pipelined Processor

A fully pipelined **64-bit RISC-V** processor implementation with set-associative caches, built in SystemVerilog and simulated with Verilator.

![RISC-V](https://img.shields.io/badge/RISC--V-64--bit-2a2a2a?style=flat-square&logo=riscv)
![SystemVerilog](https://img.shields.io/badge/SystemVerilog-HDL-2a2a2a?style=flat-square)
![Verilator](https://img.shields.io/badge/Verilator-Verified-2a2a2a?style=flat-square)

---

## Architecture

```
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌──────────┐
│  Fetch  │──▶│ Decode  │──▶│ Execute │──▶│ Memory  │──▶│Write-back│
└────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘   └────┬──────┘
     │            │             │             │             │
     ▼            ▼             ▼             ▼             ▼
  I-Cache    Reg File        ALU         D-Cache      Reg File
  (recache)                  Branch      (decache)
                             Resolve
```

### Features

- **5-stage pipeline** — Fetch, Decode, Execute, Memory, Write-back
- **2-way set-associative caches** — Separate instruction (recache) and data (decache) caches
- **Branch predictor** — Always-not-taken; pipeline flush on misprediction
- **Full RV64IM** — RISC-V 64-bit base + multiply/divide extensions
- **AXI memory interface** — Connectable to DRAMSim2 for realistic memory modeling
- **ECALL support** — Linux syscall emulation for running binaries

---

## Project Structure

```
├── top.sv              # Top-level pipeline glue
├── fetcher.sv           # Stage 1: Instruction fetch
├── decoder.sv           # Stage 2: Decode & control
├── execute.sv            # Stage 3: ALU & branch resolve
├── alu.sv               # Arithmetic logic unit
├── memory.sv            # Stage 4: Load/store
├── write_back.sv        # Stage 5: Register write-back
├── register_file.sv     # 32×64-bit register file
├── recache.sv           # Instruction cache
├── decache.sv           # Data cache
├── control_signals_struct.svh
├── pipeline_reg_struct.svh
├── Sysbus.defs          # DPI-C declarations
├── main.cpp             # Verilator testbench
├── system.cpp           # Memory system, DRAMSim2
├── fake-os.cpp          # Syscall emulation
├── hardware.cpp         # UART, CLINT devices
└── dramsim2/            # DRAM configuration
```

---

## Getting Started

### Prerequisites

- **Verilator** — Simulation
- **DRAMSim2** — Memory model (linked from course environment)
- **libelf, ncurses** — C++ dependencies

### Build & Run

```bash
make          # Compile
make run      # Run simulation (uses PROG binary from Makefile)
make clean    # Remove build artifacts
```

### Configuring the Program Binary

Edit the `PROG` variable in the Makefile:

```makefile
PROG=/path/to/your/riscv64-elf-binary
```

### Viewing Waveforms

After running, open `trace.vcd`:

```bash
gtkwave trace.vcd
```

---

## Custom Test Programs

Use `mktest/` to build simple RISC-V binaries:

```bash
cd mktest && make
# Then set PROG in main Makefile to mktest/test
```

---

## Documentation

- **[PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)** — Detailed architecture and design notes for contributors and AI-assisted development

---

## Authors

| Name | LinkedIn |
|------|----------|
| Jayesh Rathi | [Connect](https://www.linkedin.com/in/jayesh-rathi) |
| Deboparna Banerjee | [Connect](https://www.linkedin.com/in/deboparna-banerjee) |
| Angad Singh | [Connect](https://www.linkedin.com/in/angadsingh) |

*CSE502 — Computer Architecture Course Project*

---

## License

This project was developed as a course assignment. Please check with course policies before reuse.
