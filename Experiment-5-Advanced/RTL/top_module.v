// ============================================================
// Project    : Adaptive PUF Authentication
// Experiment : 5 (Advanced)
// Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
// Team       : Mahasena  |  Lead: Manaswi
//
// IMPORTANT - HONEST SCOPE NOTE (read first):
//   A real Physically Unclonable Function (PUF) derives its security
//   from genuine silicon manufacturing variation (e.g. ring-oscillator
//   frequency mismatches, SRAM power-up states, or arbiter-chain
//   delay races). That entropy exists ONLY on fabricated hardware -
//   an RTL simulator models every gate with idealized/uniform delay,
//   so no behavioral simulation can honestly demonstrate real PUF
//   unclonability. Faking this with e.g. an LFSR and calling it a
//   "PUF" would be actively misleading: an LFSR's output is fully
//   predictable from its seed, i.e. clonable - the opposite of what
//   a PUF is for.
//
//   This experiment is scoped honestly: it implements and FULLY
//   VERIFIES the real, synthesizable DIGITAL authentication pipeline
//   - adaptive (majority-vote) response stabilization, enrollment
//   storage, and challenge-response authentication - exactly as a
//   real PUF-based system would use it. The one piece that is a
//   clearly-labelled PLACEHOLDER is `raw_bit_fn`, standing in for the
//   physical entropy source. In a production design, ONLY that
//   function would be replaced by a true physical primitive (a
//   ring-oscillator array, SRAM-PUF, or arbiter PUF) - see Section 5
//   of the documentation for the hardware extension path. Nothing
//   else in this design would need to change.
//
// Description:
//   For a 2-bit challenge (4 possible challenges), the system takes
//   K=5 repeated raw-bit samples and takes a majority vote (>=3-of-5)
//   to produce one stabilized response bit - this is the "Adaptive"
//   part: real PUF measurements are noisy from one read to the next
//   (thermal/voltage drift), and majority voting is a standard,
//   lightweight way to make the response repeatable. ENROLL captures
//   the stabilized bit into on-chip storage (one-time factory step);
//   AUTH re-measures and compares against the stored value.
//
// Module hierarchy:
//   top_module  (single module - entropy placeholder, majority-vote
//                stabilizer, enrollment store, auth FSM; Advanced scope)
// ============================================================

module top_module #(
    parameter TICK_DIV        = 25_000_000, // per-sample rate (hardware default)
    parameter [7:0] DEVICE_ID = 8'hA5       // placeholder per-board "fingerprint"
                                             // (see honest scope note above)
) (
    input  wire       clk,           // 125 MHz board clock (pin H16)
    input  wire        rst,          // BTN0 - active-high synchronous reset
    input  wire        enroll,       // BTN1 - capture response for current challenge
    input  wire        auth,         // BTN2 - verify response for current challenge
    input  wire        noise_inject, // BTN3 - inject simulated measurement noise (held)
    input  wire [1:0]  challenge,    // SW1:SW0 - selects 1 of 4 challenges
    output reg  [3:0]  led           // LED[3]=match, LED[2]=enrolled?, LED[1:0]=challenge
);

    // ---------------------------------------------------------
    // 1. Clock divider -> tick (paces each of the K repeated samples)
    // ---------------------------------------------------------
    localparam DIV_W = 25;
    reg [DIV_W-1:0] div_cnt;
    wire tick = (div_cnt == TICK_DIV-1);

    always @(posedge clk or posedge rst) begin
        if (rst)       div_cnt <= {DIV_W{1'b0}};
        else if (tick) div_cnt <= {DIV_W{1'b0}};
        else           div_cnt <= div_cnt + 1'b1;
    end

    // ---------------------------------------------------------
    // 2. Edge detectors for enroll / auth (same pattern as Exp.1's
    //    "start" button)
    // ---------------------------------------------------------
    reg e1, e2, e3, a1, a2, a3;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            e1 <= 1'b0; e2 <= 1'b0; e3 <= 1'b0;
            a1 <= 1'b0; a2 <= 1'b0; a3 <= 1'b0;
        end else begin
            e1 <= enroll; e2 <= e1; e3 <= e2;
            a1 <= auth;   a2 <= a1; a3 <= a2;
        end
    end
    wire enroll_pulse = e2 & ~e3;
    wire auth_pulse   = a2 & ~a3;

    // ---------------------------------------------------------
    // 3. Placeholder entropy source - see honest scope note above.
    //    Deterministic given (challenge, sample index, DEVICE_ID);
    //    the sample_idx[0] term deliberately makes 2 of the 5
    //    samples disagree with the other 3 even with no noise
    //    injected, so the majority vote below is always doing real,
    //    meaningful work (not simply reading a constant 5 times).
    // ---------------------------------------------------------
    function raw_bit_fn;
        input [1:0] ch;
        input [2:0] s_idx;
        input       noise;
        reg base;
        begin
            base = DEVICE_ID[ch] ^ s_idx[0];
            // noise_inject additionally corrupts sample index 2,
            // which (see Documentation Section 7) is always on the
            // 3-vote majority side - a single corrupted sample is
            // enough to flip the outcome, which is the point of the
            // demonstration.
            raw_bit_fn = base ^ (noise && (s_idx == 3'd2));
        end
    endfunction

    // ---------------------------------------------------------
    // 4. Enrollment storage (4 challenges x 1 bit each)
    // ---------------------------------------------------------
    reg [3:0] storage_bits;
    reg [3:0] enrolled_flags;

    // ---------------------------------------------------------
    // 5. Sampling / majority-vote / enroll-or-auth FSM
    // ---------------------------------------------------------
    localparam S_IDLE = 2'd0, S_SAMPLE = 2'd1, S_FINISH = 2'd2;

    reg [1:0] state;
    reg [2:0] sample_idx;
    reg [2:0] ones_count;
    reg       op_is_enroll;
    reg [1:0] active_challenge;
    reg       match_result;
    reg       match_valid;

    wire sample_bit = raw_bit_fn(active_challenge, sample_idx, noise_inject);
    wire majority   = (ones_count >= 3'd3);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            sample_idx       <= 3'd0;
            ones_count       <= 3'd0;
            storage_bits     <= 4'd0;
            enrolled_flags   <= 4'd0;
            match_result     <= 1'b0;
            match_valid      <= 1'b0;
            op_is_enroll     <= 1'b0;
            active_challenge <= 2'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (enroll_pulse || auth_pulse) begin
                        active_challenge <= challenge;
                        op_is_enroll     <= enroll_pulse; // enroll wins if both held
                        sample_idx       <= 3'd0;
                        ones_count       <= 3'd0;
                        state            <= S_SAMPLE;
                    end
                end

                S_SAMPLE: begin
                    if (tick) begin
                        if (sample_bit)
                            ones_count <= ones_count + 1'b1;
                        if (sample_idx == 3'd4)
                            state <= S_FINISH;
                        else
                            sample_idx <= sample_idx + 1'b1;
                    end
                end

                S_FINISH: begin
                    if (op_is_enroll) begin
                        storage_bits[active_challenge]   <= majority;
                        enrolled_flags[active_challenge] <= 1'b1;
                        match_valid <= 1'b0;
                    end else begin
                        match_result <= (majority == storage_bits[active_challenge])
                                        && enrolled_flags[active_challenge];
                        match_valid  <= 1'b1;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 6. LED display
    // ---------------------------------------------------------
    always @(*) begin
        led = { (match_valid & match_result), enrolled_flags[challenge], challenge };
    end

endmodule
