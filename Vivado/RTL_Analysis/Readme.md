
---

# SCALES-X: Microarchitectural Schematic Reference

This document provides a descriptive walkthrough of the hardware schematics and internal datapath configurations for the **SCALES-X** accelerator fabric. The architecture is designed to map spatial matrix-vector products onto an area-optimized, multiplierless systolic array.

---

## 🎛️ 1. Top-Level Co-Processor Macro

The global system architecture unifies control, memory, processing arrays, and security boundaries into a tightly integrated coprocessor pipeline:

```text
                 [ Input Data Stream ]
                          │
                          ▼
  mode ──► [ Control Unit (FSM) ] ──► [ Batch Controller (Ping-Pong) ]
                  ▲                            │
                  │                            ▼
           [ Fault Monitor ] ◄───────── [ B-REG Shifting Array ]
            (Parity Check)                     │
                  ▲                            ▼
                  └─────────────────── [ PEC (Systolic Array) ]
                                               │
                                               ▼
                                      [ Accumulator (ACC) ]
                                               │
                                               ▼
                                      [ Output Data Stream ]

```

### Architectural Blocks:

* **Control Unit (Mealy FSM):** Orchestrates nested loop execution states based on the active mode (BFV vs. NTRU) and structural dimensions.
* **Batch Controller (Ping-Pong Engine):** Manages the dual-buffered memory banks to concurrently load subsequent batches while the systolic core processes the current block.
* **Fault Monitor (CED Module):** Samples data lines inline, executing real-time parity checks to assert `error_flag` and halt operation upon detecting single-event upsets (SEUs).

---

## ⛓️ 2. Processing Element Cluster (PEC) & Datapath Routing

The core computational kernel implements a localized matrix-vector product ($[T] = \mathbf{M}_B \times [D]$). The hardware bypasses heavy multi-bit multipliers by utilizing an array of adder-only processing nodes.

```text
               b_in
                 │
                 ▼
             [ B-REG ] ──( b_n-1 ... b_0 )──► [ MUX ]
                                               │
  [ Control Unit ] ────────────────────────────┤ (Ternary Decode: k)
                                               ▼
  [ D-RAM-0 ] ──► [ PE-0 ] ─── T_out ───► [ PE-1 ] ─── T_out ───► [ ACC ] ──► Stream Out
                     ▲                       ▲
                     │                       │
                  d_in[0]                 d_in[1]

```

### Data-Flow Interconnects:

* **Polymorphic Shifting Array (B-REG):** Holds unextended 2-bit encoded ternary coefficients ($\{-1, 0, 1\}$). A runtime multiplexer selects boundary-wrap paths based on the protocol:
* **BFV Mode (`mode = 0`):** Negacyclic wrap-around path inverts the sign of boundary coefficients.
* **NTRU Mode (`mode = 1`):** Cyclic wrap-around path bypasses sign inversion.


* **Linear Vector Processing Elements (PE-0 to PE-3):** Arranged in a pipelined cascade to minimize critical-path delay. Inside each PE, a sign-inverting multiplexer routes $+d_k$, $-d_k$, or $0$ straight into the accumulation path based on the decoded ternary token, achieving modular arithmetic with zero multiplier overhead.
* **Accumulator Fabric (ACC):** Captures incoming partial products from the final chain step using 32-bit registers, achieving modular reduction natively via standard integer overflow truncation.
