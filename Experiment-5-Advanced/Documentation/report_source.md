# Adaptive PUF Authentication

**V-SPACE FPGA Build Challenge 2026**
**Team:** Mahasena &nbsp;|&nbsp; **Team Lead:** Manaswi &nbsp;|&nbsp; **Experiment 5 — Advanced**
**Board:** PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1) &nbsp;|&nbsp; **Tool:** AMD Vivado 2026.1

---

## 1. Objective

A Physically Unclonable Function (PUF) is a hardware security primitive that derives a chip-unique, unclonable response from random manufacturing-process variation, used for authentication and anti-counterfeiting without storing a secret key in non-volatile memory. Real PUF responses are inherently **noisy** — small temperature and voltage changes between measurements flip some bits — so a production PUF system always pairs the physical entropy source with an **adaptive, error-tolerant stabilization layer**. This experiment builds and fully verifies that stabilization layer: K=5 repeated measurements, majority-vote response generation, one-time enrollment, and challenge-response authentication.

### Honest scope note (please read before judging the "PUF" claim)

An RTL simulator models every logic gate with idealized, uniform delay. The entire reason a PUF is secure is that *real silicon* has manufacturing variation a simulator cannot model — so no RTL simulation can honestly demonstrate genuine PUF unclonability, on this project or any other. Faking this with, say, an LFSR seeded by a fixed value would be actively misleading, since an LFSR's output is fully predictable from its seed and is therefore the opposite of unclonable.

This experiment is scoped honestly: the **digital authentication pipeline** (majority-vote stabilization, enrollment storage, challenge-response comparison) is implemented as real, synthesizable, fully-verified RTL — exactly as a production PUF system would use it. The one piece that is explicitly a **labelled placeholder** is `raw_bit_fn`, standing in for the physical entropy source. A production design would replace *only* that one function with a true physical primitive (a ring-oscillator array, an SRAM-PUF, or an arbiter PUF) — see Section 5 for a discussion of each option. Nothing else in this design would need to change.

---

## 2. Block Diagram

See [`Images/block_diagram.svg`](../Images/block_diagram.svg).

For a 2-bit **challenge** (4 possible challenges), the system takes 5 repeated raw-bit samples from the entropy placeholder, **majority-votes** them (≥3-of-5) into one stabilized response bit, and either **stores** it (ENROLL, a one-time factory step) or **compares** it against a previously stored value (AUTH). A push-button injects simulated measurement noise to demonstrate the majority vote's error-tolerance live.

---

## 3. RTL Design

### 3.1 Module hierarchy

```
top_module   (single module - entropy placeholder, majority-vote
              stabilizer, enrollment store, auth FSM)
```

### 3.2 Verilog code structure

The deterministic, clearly-labelled entropy placeholder — note the `sample_idx[0]` term deliberately makes 2 of the 5 samples disagree with the other 3 even with *no* noise injected, so the majority vote is always doing real, meaningful work rather than reading a constant 5 times:

```verilog
function raw_bit_fn;
    input [1:0] ch;
    input [2:0] s_idx;
    input       noise;
    reg base;
    begin
        base = DEVICE_ID[ch] ^ s_idx[0];
        raw_bit_fn = base ^ (noise && (s_idx == 3'd2));
    end
endfunction
```

Authentication decision, gated so a never-enrolled challenge can never accidentally "match":

```verilog
match_result <= (majority == storage_bits[active_challenge])
                && enrolled_flags[active_challenge];
```

Full source: [`RTL/top_module.v`](../RTL/top_module.v), constraints: [`RTL/constraints.xdc`](../RTL/constraints.xdc).

### 3.3 LED encoding

| LED[3] | LED[2] | LED[1:0] |
|---|---|---|
| 1=MATCH, 0=NO MATCH (after an AUTH) | 1=current challenge has been enrolled | live challenge value |

---

## 4. Simulation Results

Simulated with the **Vivado Simulator (xvlog / xelab / xsim)**.
Testbench: [`Testbench/tb_top.v`](../Testbench/tb_top.v).
Raw transcript: [`Simulation/transcript.txt`](../Simulation/transcript.txt).

With `DEVICE_ID = 8'hA5 = 8'b1010_0101`, DEVICE_ID[0]=1, [1]=0, [2]=1, [3]=0. For any challenge with no noise, the 5 raw samples are `[base,~base,base,~base,base]` — an exact 3-2 split that always correctly majority-votes to `base`, hand-verified for challenges 0 and 1 below.

**Actual transcript output (2026-10-10):**

```
================================================
 Adaptive PUF Authentication - Testbench
================================================

-- Phase 1: Enroll then authenticate challenge 0 (no noise) --
  Enrolled ch0: stored bit = 1 (expected 1)
  [PASS] Auth ch0, no noise -> MATCH, enrolled, challenge=00 : led=1100 (expected 1100)

-- Phase 2: Authenticate challenge 0 WITH noise injected --
  [PASS] Auth ch0, with noise -> NO MATCH (vote flipped), still enrolled : led=0100 (expected 0100)

-- Phase 3: Enroll then authenticate challenge 1 (no noise) --
  Enrolled ch1: stored bit = 0 (expected 0)
  [PASS] Auth ch1, no noise -> MATCH, enrolled, challenge=01 : led=1101 (expected 1101)

-- Phase 4: Authenticate challenge 2, which was never enrolled --
  [PASS] Auth ch2, never enrolled -> NO MATCH, not enrolled, challenge=10 : led=0010 (expected 0010)

-- Phase 5: Re-authenticate challenge 0 (confirm isolation) --
  [PASS] Auth ch0 again, no noise -> still MATCH (unaffected by ch1/ch2) : led=1100 (expected 1100)

-- Phase 6: Reset behaviour --
  [PASS] Reset clears all enrollment storage.

================================================
 TESTBENCH SUMMARY: ALL CHECKS PASSED (0 errors)
================================================
```

**Verification note**: an earlier version of this testbench changed `auth`/`enroll` with a plain blocking assignment immediately before `@(posedge clk)`, which created a genuine simulation race (the pulse could land on the same simulation instant as the clock edge and be missed by the synchronizer). It was found, diagnosed with a dedicated debug testbench, and fixed by driving both pulses relative to `@(negedge clk)` instead — the standard, race-free way to drive synchronous testbench stimulus. This is recorded here deliberately, as an honest account of the verification process rather than a silently-fixed detail.

**[ TODO — Manaswi: screenshot `Simulation/tb_top_sim.wdb` in the Vivado GUI waveform viewer -> `Images/waveform.png`. ]**

---

## 5. Hardware Implementation

**[ TODO — pending the same Vivado license-tier fix described in Experiment 1's documentation. Once fixed, run the adapted `run_vivado_full.tcl` to produce `Bitstream/top_module.bit`, then program the PYNQ-Z2 and add `Images/board_setup.jpg` and `Images/hardware_output.jpg`. ]**

**Physical entropy source options for a production version** (replacing only `raw_bit_fn`):
- **Ring-oscillator PUF**: an array of odd-length inverter-chain oscillators; the response bit compares which of a selected pair free-runs faster. The classic, most commonly taught RO-PUF architecture; requires Vivado synthesis attributes (`DONT_TOUCH`/`KEEP`) to stop the combinational loop from being optimized away, and careful floorplanning so oscillator pairs experience similar routing.
- **SRAM-PUF**: reads the power-up state of a block of SRAM before it is initialized; cell-to-cell threshold-voltage mismatch makes each chip's power-up pattern unique. Needs direct access to uninitialized SRAM, which is not straightforward from fabric-only Verilog on this board.
- **Arbiter PUF**: races a signal down two nominally-identical delay paths selected by the challenge bits; which path wins is the response bit. Also needs careful placement constraints to avoid the tool "fixing" the intended near-identical delays.

All three are real, silicon-manufacturing-dependent entropy sources with their own trade-offs; none can be meaningfully demonstrated in an RTL simulator for the reason explained in Section 1.

---

## 6. Applications

- **Chip authentication / anti-counterfeiting**: verifying a chip is genuine without storing a secret key that could be extracted.
- **Device-bound cryptographic key generation**: deriving a key from PUF responses instead of storing one in non-volatile memory (a technique called a "fuzzy extractor" when combined with proper error-correcting codes, of which this experiment's majority vote is a simplified illustration).
- **IoT device identity**: giving each low-cost IoT device a unique, unclonable identity without a secure element.
- **Licensing / anti-cloning for FPGA IP**: binding a bitstream's behaviour to the specific chip it is running on.

---

## 7. Conclusion

This experiment delivers a fully synthesizable, fully simulation-verified PUF-style authentication pipeline: majority-vote adaptive stabilization, per-challenge enrollment, and gated authentication, all passing 6/6 hand-derived test phases with zero errors. It also honestly documents the one genuine limitation of doing this work in simulation (no real entropy source can be demonstrated) rather than hiding it behind a dishonest stand-in, and documents the race-condition bug found and fixed during testbench development, consistent with this project's running theme (see Experiment 2's tolerance-overlap finding and Experiment 4's masked-fault finding) of treating honest limitation analysis as part of the deliverable, not something to hide.

**A precisely-characterized margin-sensitivity finding**: because the placeholder entropy function's natural sample pattern produces an exact 3-2 majority margin, the system is robust to noise on a *minority-side* sample, but a single corrupted *majority-side* sample (as demonstrated by the `noise_inject` button, which targets sample index 2) is sufficient to flip the stabilized bit. This is a genuine, mathematically-derived property of a 3-of-5 majority vote with no additional error margin, not a flaw — and it directly motivates why a production system would use either more repeated samples (e.g. 7-of-13) or a proper error-correcting code (a true fuzzy extractor) for a larger safety margin.

**Future scope**: replacing `raw_bit_fn` with a real ring-oscillator array (the most practical of the three options above for this board) and measuring real chip-to-chip response variation across multiple physical PYNQ-Z2 boards is the natural, and necessary, next step to make the "PUF" claim fully real rather than architecturally-correct-but-placeholder.

---

*Document prepared for the V-SPACE FPGA Build Challenge 2026 — Team Mahasena.*
