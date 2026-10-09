// ============================================================
// Testbench   : tb_top.v
// DUT         : top_module (TrustFuse - Hardware Sensor Trust)
// Experiment  : 2 (Beginner)
//
// Strategy:
//   The simulated base reading is pinned at a known value
//   (base_value == 50, via SW0 "freeze") so every expected LED
//   code below is a hand-calculated, exact value - not a guess.
//   With base_value = 50: sensor1=50, sensor2=53, sensor3=47.
//
//   Phase 1 - Nominal case: all three sensors agree -> HIGH trust.
//   Phase 2 - Fault on sensor1 only -> MEDIUM trust, sensor1 flagged.
//   Phase 3 - Fault on sensor2 only -> MEDIUM trust, sensor2 flagged.
//   Phase 4 - Fault on sensor3 only -> MEDIUM trust, sensor3 flagged.
//   Phase 5 - Faults on sensor1 AND sensor2 -> NONE trust (total fault).
//   Phase 6 - Reset returns base_value to BASE_MIN.
// ============================================================
`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg rst;
    reg fault1, fault2, fault3;
    reg freeze;
    wire [3:0] led;

    integer errors;

    // Small TICK_DIV => fast simulation.
    top_module #(.TICK_DIV(4)) uut (
        .clk    (clk),
        .rst    (rst),
        .fault1 (fault1),
        .fault2 (fault2),
        .fault3 (fault3),
        .freeze (freeze),
        .led    (led)
    );

    initial clk = 1'b0;
    always #4 clk = ~clk;

    // Safety watchdog
    initial begin
        #100000;
        $display("*** WATCHDOG TIMEOUT - simulation did not finish in time ***");
        $finish;
    end

    task check_led;
        input [3:0] expected;
        input [639:0] label; // string label for the message (up to 80 chars)
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
        fault1 = 1'b0; fault2 = 1'b0; fault3 = 1'b0;
        freeze = 1'b0;

        $display("================================================");
        $display(" TrustFuse - Hardware Sensor Trust - Testbench");
        $display("================================================");

        // -------- Reset --------
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // -------- Let base_value ramp from 10 up to exactly 50, then freeze --------
        // (white-box wait on the internal counter - standard practice)
        wait (uut.base_value == 8'd50);
        @(posedge clk);
        freeze = 1'b1;
        repeat (3) @(posedge clk);
        $display("\nBase value pinned at %0d (sensor1=%0d sensor2=%0d sensor3=%0d)",
                   uut.base_value, uut.sensor1, uut.sensor2, uut.sensor3);

        // -------- Phase 1: nominal, all agree --------
        $display("\n-- Phase 1: Nominal (no fault) --");
        check_led(4'b1100, "All three sensors agree -> HIGH trust");

        // -------- Phase 2: fault on sensor1 --------
        $display("\n-- Phase 2: Fault injected on sensor1 --");
        fault1 = 1'b1;
        #1;
        check_led(4'b1001, "sensor1 forced to 0xFF -> MEDIUM trust, sensor1 flagged");
        fault1 = 1'b0;
        #1;

        // -------- Phase 3: fault on sensor2 --------
        $display("\n-- Phase 3: Fault injected on sensor2 --");
        fault2 = 1'b1;
        #1;
        check_led(4'b1010, "sensor2 forced to 0x00 -> MEDIUM trust, sensor2 flagged");
        fault2 = 1'b0;
        #1;

        // -------- Phase 4: fault on sensor3 --------
        $display("\n-- Phase 4: Fault injected on sensor3 --");
        fault3 = 1'b1;
        #1;
        check_led(4'b1011, "sensor3 driven to +60 (saturated) -> MEDIUM trust, sensor3 flagged");
        fault3 = 1'b0;
        #1;

        // -------- Phase 5: double fault - total disagreement --------
        $display("\n-- Phase 5: Faults on sensor1 AND sensor2 simultaneously --");
        fault1 = 1'b1;
        fault2 = 1'b1;
        #1;
        check_led(4'b0000, "Two sensors faulted -> NONE trust (total fault)");
        fault1 = 1'b0;
        fault2 = 1'b0;
        #1;

        // -------- Phase 6: reset --------
        $display("\n-- Phase 6: Reset behaviour --");
        freeze = 1'b0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        if (uut.base_value === 8'd10) begin
            $display("  [PASS] Reset returns base_value to BASE_MIN (10).");
        end else begin
            $display("  [FAIL] base_value=%0d after reset (expected 10).", uut.base_value);
            errors = errors + 1;
        end
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // -------- Summary --------
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
