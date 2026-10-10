# FPGA Build Challenge 2026 — Team Mahasena

## Team Information

| Field | Details |
|-------|---------|
| **Team Name** | Mahasena |
| **Team Lead** | Prajeet Varma |
| **Team Members** |Manaswi |
| **Registration Numbers** | 24BEC0059,24BEC420 |
| **Selected FPGA Board** | PYNQ-Z2 |
| **FPGA Chip** | Xilinx Zynq XC7Z020CLG400-1 |
| **Toolchain** | AMD Vivado 2026.1 |

---

## Project Summary

| # | Folder | Experiment | Difficulty | RTL | Simulation | Bitstream | Docs |
|---|--------|------------|------------|:---:|:---:|:---:|:---:|
| 1 | `Experiment-1-Beginner` | **Automated Digital Circuit Tester** | Beginner 
| 2 | `Experiment-2-Beginner` | **TrustFuse — Hardware Sensor Trust** | Beginner 
| 3 | `Experiment-3-Intermediate` | **CPU–FPGA Decision Engine** | Intermediate 
| 4 | `Experiment-4-Intermediate` | **FAULTX — HIL Fault Injection** | Intermediate 
| 5 | `Experiment-5-Advanced` | **Adaptive PUF Authentication** | Advanced 

**All 5 experiments are RTL-complete and simulation-verified (0 errors each, every expected value hand-derived before running).** Only hardware bring-up (bitstream + board photos + video) remains — see "Known Gaps" below.

### Experiment 1 — Automated Digital Circuit Tester *(Beginner)*
An FSM-driven "mini ATE" that automatically applies 8 stored test vectors to a 4-bit ALU (Device Under Test), compares every result against a hand-verified expected value, and reports PASS/FAIL + failing-vector index on the LEDs.

### Experiment 2 — TrustFuse: Hardware Sensor Trust *(Beginner)*
A triple-sensor cross-validation and fusion circuit. Three simulated sensors track one quantity with known offsets; pairwise deviation checking computes a live trust level (NONE/LOW/MEDIUM/HIGH) and flags a single faulty sensor. Push-buttons inject live faults for demonstration.

### Experiment 3 — CPU–FPGA Decision Engine *(Intermediate)*
A fixed-priority, single-cycle combinational decision engine — the FPGA-fabric replacement for a CPU's sequential if/else-if decision chain. 8 prioritized rules combine a simulated temperature band, a 2-bit mode register, and 3 async "event" buttons into one of 8 action codes, with deliberate, verified priority ordering (automatic thermal protection always preempts a manual request).

### Experiment 4 — FAULTX: HIL Fault Injection *(Intermediate)*
A true Hardware-In-the-Loop fault-injection rig, directly extending Experiment 1: runs a clean "golden" ALU and a live-faultable "faulted" ALU in parallel against the same 8 test vectors, continuously comparing them and tracking a real fault-coverage metric (not just pass/fail) — including the honest discovery that an input stuck-at fault can be *masked* by coincidence, while an output bit-flip fault achieves full coverage.

### Experiment 5 — Adaptive PUF Authentication *(Advanced)*
A fully-verified PUF-style authentication pipeline: K=5-sample majority-vote "adaptive" response stabilization, per-challenge enrollment, and gated challenge-response authentication. Honestly scoped: the digital pipeline is real, synthesizable RTL; the physical entropy source is a clearly-labelled placeholder, since no RTL simulator can honestly demonstrate real silicon-variation-based unclonability (see the experiment's own documentation for the full explanation and the real hardware options).

---

## Repository Structure

```
FPGA-Build-Challenge-Manaswi/
├── README.md
├── .gitignore
├── run_vivado_full.tcl          <- full synth->impl->bitstream flow (Tcl)
├── build_docs.py                <- regenerates the PDF reports
│
├── Experiment-1-Beginner/
│   ├── RTL/            top_module.v, constraints.xdc
│   ├── Testbench/      tb_top.v
│   ├── Simulation/     transcript.txt, *.wdb, *.vcd  (REAL, verified results)
│   ├── Images/         block_diagram.svg  (+ photos/screenshots - pending)
│   ├── Documentation/  report_source.md + Experiment1_*.pdf
│   ├── Bitstream/      (pending - see Known Gaps below)
│   └── Video_Link.txt
│
├── Experiment-2-Beginner/        (same layout - TrustFuse)
├── Experiment-3-Intermediate/    (same layout - CPU-FPGA Decision Engine)
├── Experiment-4-Intermediate/    (same layout - FAULTX)
├── Experiment-5-Advanced/        (same layout - Adaptive PUF Authentication)
│
└── Final_Report/
    └── Mahasena_Final_Report.pdf   <- TODO, combine all 5 experiment reports
```

---

## Known Gaps — Please Complete (PRAJEET)

These are the items that need **physical hardware access or a license fix**
that could not be completed from this environment:

1. **Vivado license tier** — the installed license defaults to "ALVEO" which
   does not cover the Zynq-7000/XC7Z020 part. The same license file *also*
   contains a WebPACK/BASIC tier that does cover it.
   Fix: **Vivado → Help → Manage License** → select the BASIC/WebPACK tier.
   Then run, from this folder:
   ```bash
   vivado -mode batch -source run_vivado_full.tcl
   ```
   This produces `Experiment-1-Beginner/Bitstream/top_module.bit` automatically.
   For Experiments 2-5, copy `run_vivado_full.tcl`, rename it, and update
   `project_name` + `src_dir` to point at that experiment's folder (a one-line
   note to this effect is already in the script's header comment).

2. **Program the PYNQ-Z2** with each of the 5 bitstreams and take:
   - `Images/board_setup.jpg` (board powered & wired)
   - `Images/hardware_output.jpg` (LEDs showing a result — for Experiment 4
     and 5, a great shot is mid-demo with a fault/noise button held)

3. **Waveform screenshots** — open each experiment's `Simulation/tb_top_sim.wdb`
   in the Vivado GUI waveform viewer and save a screenshot as
   `Images/waveform.png` (the simulations themselves are already done and
   verified for all 5 experiments — see each `Simulation/transcript.txt`).

4. **Demo videos** — record per the competition brief (Introduction, Problem
   Statement, Design Explanation, Hardware Demonstration, Conclusion), upload
   to Google Drive, and paste the link into each `Video_Link.txt`.

5. **Push to GitHub** — this repo is initialized locally with a `dev` branch
   and an initial commit. Create the GitHub repo
   (`FPGA-Build-Challenge-Manaswi`) and run:
   ```bash
   git remote add origin <your-repo-URL>
   git push -u origin main
   git push -u origin dev
   ```

6. Fill in remaining **team member names & registration numbers** above.

---

## How to Re-run Any Simulation Yourself

```bash
cd Experiment-<N>-<Difficulty>\Simulation
C:\AMDDesignTools\2026.1\Vivado\bin\xvlog.bat ..\RTL\top_module.v ..\Testbench\tb_top.v --work work
C:\AMDDesignTools\2026.1\Vivado\bin\xelab.bat tb_top -debug typical -s tb_top_sim
C:\AMDDesignTools\2026.1\Vivado\bin\xsim.bat tb_top_sim -R
```
(Works identically for all 5 experiment folders.)
