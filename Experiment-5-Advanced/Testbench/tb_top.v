// ============================================================
// Testbench   : tb_top.v
// DUT         : top_module (Adaptive PUF Authentication)
// Experiment  : 5 (Advanced)
//
// Strategy (see the RTL file's "HONEST SCOPE NOTE" for why the
// entropy source is a labelled placeholder, not real PUF entropy):
//   With DEVICE_ID = 8'hA5 = 8'b1010_0101, so DEVICE_ID[0]=1,
//   DEVICE_ID[1]=0, DEVICE_ID[2]=1, DEVICE_ID[3]=0. For any
//   challenge, the 5 raw samples (no noise) are
//   [base,~base,base,~base,base] (from the sample_idx[0] term),
//   a 3-2 split that always majority-votes to `base` exactly -
//   hand-verified for all 4 challenges below.
//
//   Phase 1 - Enroll + auth challenge 0 (no noise) -> MATCH.
//   Phase 2 - Auth challenge 0 again WITH noise -> flips the vote
//             (idx2's sample is always on the 3-side) -> NO MATCH.
//   Phase 3 - Enroll + auth challenge 1 (different base) -> MATCH.
//   Phase 4 - Auth challenge 2, which was NEVER enrolled -> NO
//             MATCH (even without noise - enrolled_flags gates it).
//   Phase 5 - Confirm challenge 0's stored value is unaffected by
//             challenge 1/2 activity.
//   Phase 6 - Reset clears all storage.
// ============================================================
`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg rst;
    reg enroll, auth, noise_inject;
    reg [1:0] challenge;
    wire [3:0] led;

    integer errors;

    top_module #(.TICK_DIV(4), .DEVICE_ID(8'hA5)) uut (
        .clk          (clk),
        .rst          (rst),
        .enroll       (enroll),
        .auth         (auth),
        .noise_inject (noise_inject),
        .challenge    (challenge),
        .led          (led)
    );

    initial clk = 1'b0;
    always #4 clk = ~clk;

    initial begin
        #200000;
        $display("*** WATCHDOG TIMEOUT - simulation did not finish in time ***");
        $finish;
    end

    // Pulses are driven relative to the falling edge, half a cycle away
    // from the always block's active (rising) edge, so there is no
    // race between the testbench's blocking assignment and the DUT
    // sampling it - the standard, race-free way to drive synchronous
    // stimulus in a testbench.
    task pulse_enroll;
        begin
            @(negedge clk);
            enroll = 1'b1;
            @(negedge clk);
            enroll = 1'b0;
            wait (uut.state != 2'd0);
            wait (uut.state == 2'd0);
            #1;
        end
    endtask

    task pulse_auth;
        begin
            @(negedge clk);
            auth = 1'b1;
            @(negedge clk);
            auth = 1'b0;
            wait (uut.state != 2'd0);
            wait (uut.state == 2'd0);
            #1;
        end
    endtask

    task check_led;
        input [3:0] expected;
        input [639:0] label;
        begin
            if (led === expected) begin
                $display("  [PASS] %0s : led=%b (expected %b)", label, led, expected);
            end else begin
                $display("  [FAIL] %0s : led=%b (expected %b)", label, led, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        enroll = 1'b0; auth = 1'b0; noise_inject = 1'b0; challenge = 2'b00;

        $display("================================================");
        $display(" Adaptive PUF Authentication - Testbench");
        $display("================================================");

        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // -------- Phase 1: enroll + auth challenge 0 --------
        $display("\n-- Phase 1: Enroll then authenticate challenge 0 (no noise) --");
        challenge = 2'b00;
        pulse_enroll;
        $display("  Enrolled ch0: stored bit = %b (expected 1)", uut.storage_bits[0]);
        pulse_auth;
        check_led(4'b1100, "Auth ch0, no noise -> MATCH, enrolled, challenge=00");

        // -------- Phase 2: auth challenge 0 with noise --------
        $display("\n-- Phase 2: Authenticate challenge 0 WITH noise injected --");
        noise_inject = 1'b1;
        pulse_auth;
        check_led(4'b0100, "Auth ch0, with noise -> NO MATCH (vote flipped), still enrolled");
        noise_inject = 1'b0;

        // -------- Phase 3: enroll + auth challenge 1 --------
        $display("\n-- Phase 3: Enroll then authenticate challenge 1 (no noise) --");
        challenge = 2'b01;
        pulse_enroll;
        $display("  Enrolled ch1: stored bit = %b (expected 0)", uut.storage_bits[1]);
        pulse_auth;
        check_led(4'b1101, "Auth ch1, no noise -> MATCH, enrolled, challenge=01");

        // -------- Phase 4: auth a never-enrolled challenge --------
        $display("\n-- Phase 4: Authenticate challenge 2, which was never enrolled --");
        challenge = 2'b10;
        pulse_auth;
        check_led(4'b0010, "Auth ch2, never enrolled -> NO MATCH, not enrolled, challenge=10");

        // -------- Phase 5: challenge 0's data is undisturbed --------
        $display("\n-- Phase 5: Re-authenticate challenge 0 (confirm isolation) --");
        challenge = 2'b00;
        pulse_auth;
        check_led(4'b1100, "Auth ch0 again, no noise -> still MATCH (unaffected by ch1/ch2)");

        // -------- Phase 6: reset clears storage --------
        $display("\n-- Phase 6: Reset behaviour --");
        rst = 1'b1;
        repeat (3) @(posedge clk);
        if (uut.storage_bits === 4'd0 && uut.enrolled_flags === 4'd0) begin
            $display("  [PASS] Reset clears all enrollment storage.");
        end else begin
            $display("  [FAIL] storage_bits=%b enrolled_flags=%b after reset (expected both 0000).",
                       uut.storage_bits, uut.enrolled_flags);
            errors = errors + 1;
        end
        rst = 1'b0;
        repeat (5) @(posedge clk);

        $display("\n================================================");
        if (errors == 0)
            $display(" TESTBENCH SUMMARY: ALL CHECKS PASSED (0 errors)");
        else
            $display(" TESTBENCH SUMMARY: %0d CHECK(S) FAILED", errors);
        $display("================================================");

        $finish;
    end

    initial begin
        $dumpfile("simulation.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
