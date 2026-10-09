# FPGA Build Challenge 2026 — Team Mahasena

## Team Information

| Field | Details |
|-------|---------|
| **Team Name** | Mahasena |
| **Team Lead** | Manaswi |
| **Team Members** | *(add remaining member names here)* |
| **Registration Numbers** | *(add here)* |
| **Selected FPGA Board** | PYNQ-Z2 |
| **FPGA Chip** | Xilinx Zynq XC7Z020CLG400-1 |
| **Toolchain** | AMD Vivado 2026.1 |

---

## Project Summary

| # | Folder | Experiment | Difficulty | RTL | Simulation | Bitstream | Docs |
|---|--------|------------|------------|:---:|:---:|:---:|:---:|
| 1 | `Experiment-1-Beginner` | **Automated Digital Circuit Tester** | Beginner | ✅ | ✅ 0 errors | ⏳ pending | ✅ |
| 2 | `Experiment-2-Beginner` | **TrustFuse — Hardware Sensor Trust** | Beginner | ✅ | ✅ 0 errors | ⏳ pending | ✅ |
| 3 | `Experiment-3-Intermediate` | **CPU–FPGA Decision Engine** | Intermediate | 🔲 | 🔲 | 🔲 | 🔲 |
| 4 | `Experiment-4-Intermediate` | **FAULTX — HIL Fault Injection** | Intermediate | 🔲 | 🔲 | 🔲 | 🔲 |
| 5 | `Experiment-5-Advanced` | **Adaptive PUF Authentication** | Advanced | 🔲 | 🔲 | 🔲 | 🔲 |

### Experiment 1 — Automated Digital Circuit Tester
An FSM-driven "mini ATE" that automatically applies 8 stored test vectors to a 4-bit ALU (Device Under Test), compares every result against a hand-verified expected value, and reports PASS/FAIL + failing-vector index on the LEDs.

### Experiment 2 — TrustFuse: Hardware Sensor Trust
A triple-sensor cross-validation and fusion circuit. Three simulated sensors track one quantity with known offsets; pairwise deviation checking computes a live trust level (NONE/LOW/MEDIUM/HIGH) and flags a single faulty sensor. Push-buttons inject live faults for demonstration.

### Experiments 3–5
Not yet started — placeholder folders only (see table above).

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
├── Experiment-2-Beginner/        (same layout as above)
├── Experiment-3-Intermediate/    (empty - placeholder)
├── Experiment-4-Intermediate/    (empty - placeholder)
├── Experiment-5-Advanced/        (empty - placeholder)
│
└── Final_Report/
    └── Mahasena_Final_Report.pdf   <- TODO, combine all 5 experiment reports
```

---

## Known Gaps — Please Complete (Manaswi)

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
   This produces `Experiment-1-Beginner/Bitstream/top_module.bit` automatically
   (Experiment 2 needs the project name/paths in the script updated the same way).

2. **Program the PYNQ-Z2** with each bitstream and take:
   - `Images/board_setup.jpg` (board powered & wired)
   - `Images/hardware_output.jpg` (LEDs showing a result)

3. **Waveform screenshots** — open `Simulation/tb_top_sim.wdb` in the Vivado
   GUI waveform viewer and save a screenshot as `Images/waveform.png` for
   each experiment (the simulations themselves are already done and verified
   — see `Simulation/transcript.txt`).

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

## What's Already Done

- ✅ Experiment 1 & 2: complete, synthesizable RTL (clean compile, no errors)
- ✅ Experiment 1 & 2: self-checking testbenches, **run and verified** —
  0 errors, every expected value hand-calculated and matched exactly
- ✅ Experiment 1 & 2: PYNQ-Z2 XDC constraints (pins verified against an
  independent published PYNQ-Z2 pin reference)
- ✅ Experiment 1 & 2: block diagrams, full documentation PDFs (7-section
  format per the competition brief)
- ✅ `.gitignore` configured to exclude Vivado project junk
- ✅ Local git repository initialized with a `dev` branch

## How to Re-run the Simulations Yourself

```bash
cd Experiment-1-Beginner\Simulation
C:\AMDDesignTools\2026.1\Vivado\bin\xvlog.bat ..\RTL\top_module.v ..\Testbench\tb_top.v --work work
C:\AMDDesignTools\2026.1\Vivado\bin\xelab.bat tb_top -debug typical -s tb_top_sim
C:\AMDDesignTools\2026.1\Vivado\bin\xsim.bat tb_top_sim -R
```
(Same for `Experiment-2-Beginner`.)
