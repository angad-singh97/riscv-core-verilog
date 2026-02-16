# RISC-V 5-Stage Pipelined Processor

> **A cycle-accurate 64-bit RISC-V CPU** — 5-stage pipeline, set-associative caches, hazard handling, and ECALL support. Built from scratch in SystemVerilog.

[![RISC-V](https://img.shields.io/badge/RISC--V-64--bit-F2D017?style=flat-square&logo=riscv&logoColor=black)](https://riscv.org/)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-HDL-DA1A32?style=flat-square)](https://www.systemverilog.io/)
[![Verilator](https://img.shields.io/badge/Verilator-Verified-DA1A32?style=flat-square)](https://www.veripool.org/verilator/)

---

## What This Is

A **fully functional RISC-V processor** implementing the RV64IM instruction set. It fetches, decodes, executes, loads/stores, and writes back — with real caches, branch resolution, and RAW hazard detection. Designed to run RISC-V binaries via Verilator simulation.

**Skills demonstrated:** RTL design · Pipelining · Cache design · Hazard handling · AXI protocol · Low-level systems

---

## Architecture

```
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌──────────┐
│  Fetch  │──▶│ Decode  │──▶│ Execute │──▶│ Memory  │──▶│Write-back│
└────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘   └────┬──────┘
     │             │             │             │             │
     ▼             ▼             ▼             ▼             ▼
  I-Cache     Reg File         ALU        D-Cache      Reg File
  (2-way SA)   RAW stall    Branches    (2-way SA)   ECALL
```

### Implemented Features

| Component | Description |
|-----------|-------------|
| **5-stage pipeline** | Fetch → Decode → Execute → Memory → Write-back |
| **2-way set-associative caches** | Separate I-cache & D-cache, LRU replacement |
| **Branch predictor** | Always-not-taken; pipeline flush on misprediction |
| **RAW hazard handling** | Register busy bits, decode-stage stall |
| **RV64IM ISA** | Base integer + multiply/divide extensions |
| **ECALL support** | Linux syscall emulation in write-back stage |
| **AXI interface** | Connects to course-provided DRAMSim2 memory model |

---

## Project Structure

| File | Role |
|------|------|
| `top.sv` | Pipeline control, stage enables, hazard logic |
| `fetcher.sv` | Instruction fetch, PC select, I-cache front-end |
| `decoder.sv` | R/I/S/B/J/U-type decode, control signals |
| `execute.sv` | ALU, branch resolution, jump target |
| `memory.sv` | Load/store via D-cache |
| `write_back.sv` | Reg write, ECALL handling |
| `recache.sv` | 2-way SA instruction cache |
| `decache.sv` | 2-way SA data cache (write-back, snoop) |

---

## Quick Start

```bash
make          # Compile with Verilator
make run      # Run simulation (set PROG in Makefile to your RISC-V binary)
make clean    # Remove build artifacts
gtkwave trace.vcd   # View waveforms after run
```

**Prerequisites:** Verilator, DRAMSim2 (course env), libelf, ncurses

---

## Authors

| Name |
|------|
| **Angad Singh** · [LinkedIn](https://www.linkedin.com/in/angad-sde-nyc/) |
| Jayesh Rathi |
| Deboparna Banerjee |

*CSE-502 — Computer Architecture, Stony Brook University, Prof. Michael Ferdman*

---

## License

Course project — see course policies for reuse.
