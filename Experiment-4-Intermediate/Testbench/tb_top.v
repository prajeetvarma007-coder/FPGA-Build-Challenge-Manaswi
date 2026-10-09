// ============================================================
// Testbench   : tb_top.v
// DUT         : top_module (FAULTX - HIL Fault Injection)
// Experiment  : 4 (Intermediate)
//
// Strategy:
//   The engine free-runs continuously (no manual start). For each
//   scenario, the fault configuration is set, reset is pulsed (which
//   also clears mismatch_count/idx), and the testbench waits for the
//   FSM to reach S_DONE for the first time - at which point the full
//   8-vector pass ran entirely under that fault configuration. Every
//   expected mismatch count below was derived by hand, re-computing
//   the alu4 arithmetic for each of Experiment 1's 8 ROM vectors
//   under the stated fault.
//
//   Phase 1 - fault_type=NONE: sanity check, 0/8 mismatches.
//   Phase 2 - STUCK_AT_0 on input a: 7/8 mismatches (vector 6, a
//             already 0 with b=0, is the one undetected/"masked"
//             fault case - a genuine fault-coverage finding).
//   Phase 3 - BIT_FLIP (bit 1) on the output: 8/8 mismatches (full
//             coverage - an output-stage bit-flip is never masked).
//   Phase 4 - Reset behaviour.
// ============================================================
`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg rst;
    reg target_a, target_b, target_result;
    reg [1:0] fault_type;
    wire [3:0] led;

    integer errors;

    top_module #(.TICK_DIV(4)) uut (
        .clk           (clk),
        .rst           (rst),
        .target_a      (target_a),
        .target_b      (target_b),
        .target_result (target_result),
        .fault_type    (fault_type),
        .led           (led)
    );

    initial clk = 1'b0;
    always #4 clk = ~clk;

    initial begin
        #200000;
        $display("*** WATCHDOG TIMEOUT - simulation did not finish in time ***");
        $finish;
    end

    task run_to_done;
        begin
            rst = 1'b1;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            wait (uut.state == 1'b1); // S_DONE
            @(posedge clk); #1;
        end
    endtask

    task check_result;
        input       expect_all_match;
        input [2:0] expect_first_fail_idx;
        input [3:0] expect_mismatch_count;
        input [639:0] label;
        begin
            if (led[3] === expect_all_match &&
                (expect_all_match || led[2:0] === expect_first_fail_idx) &&
                uut.mismatch_count === expect_mismatch_count) begin
                $display("  [PASS] %0s : led=%b mismatch_count=%0d", label, led, uut.mismatch_count);
            end else begin
                $display("  [FAIL] %0s : led=%b mismatch_count=%0d (expected all_match=%b first_idx=%0d count=%0d)",
                          label, led, uut.mismatch_count, expect_all_match, expect_first_fail_idx, expect_mismatch_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        target_a = 1'b0; target_b = 1'b0; target_result = 1'b0; fault_type = 2'b00;

        $display("================================================");
        $display(" FAULTX - HIL Fault Injection - Testbench");
        $display("================================================");

        // -------- Phase 1: no fault (sanity check) --------
        $display("\n-- Phase 1: fault_type=NONE, target_a held --");
        fault_type = 2'b00;
        target_a   = 1'b1;
        run_to_done;
        check_result(1'b1, 3'd0, 4'd0, "No fault -> 0/8 mismatches (golden == faulted)");
        target_a = 1'b0;

        // -------- Phase 2: stuck-at-0 on input a --------
        $display("\n-- Phase 2: fault_type=STUCK_AT_0, target_a held --");
        fault_type = 2'b01;
        target_a   = 1'b1;
        run_to_done;
        check_result(1'b0, 3'd0, 4'd7,
            "a stuck-at-0 -> 7/8 mismatches, first at idx 0 (idx6 is masked: a was already 0)");
        target_a = 1'b0;

        // -------- Phase 3: bit-flip on the output --------
        $display("\n-- Phase 3: fault_type=BIT_FLIP, target_result held --");
        fault_type     = 2'b11;
        target_result  = 1'b1;
        run_to_done;
        check_result(1'b0, 3'd0, 4'd8,
            "result bit1 flipped -> 8/8 mismatches (full coverage, no masking)");
        target_result = 1'b0;
        fault_type = 2'b00;

        // -------- Phase 4: reset mid-run --------
        $display("\n-- Phase 4: Reset behaviour --");
        fault_type = 2'b01;
        target_a   = 1'b1;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        if (uut.idx === 3'd0 && uut.mismatch_count === 4'd0 && uut.state === 1'b0) begin
            $display("  [PASS] Reset clears idx/mismatch_count and returns FSM to S_RUN.");
        end else begin
            $display("  [FAIL] idx=%0d mismatch_count=%0d state=%0d after reset.",
                       uut.idx, uut.mismatch_count, uut.state);
            errors = errors + 1;
        end
        rst = 1'b0;
        target_a = 1'b0;
        fault_type = 2'b00;
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
