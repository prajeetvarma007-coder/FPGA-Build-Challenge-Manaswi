// ============================================================
// Testbench   : tb_top.v
// DUT         : top_module (CPU-FPGA Decision Engine)
// Experiment  : 3 (Intermediate)
//
// Strategy:
//   The simulated temperature is a free-running triangle wave, so
//   each phase below waits (white-box, on the internal `temp`
//   register) for temperature to reach a specific, known value
//   before checking the action code - every expected value is a
//   hand-derived, exact result from the priority rule table.
//
//   Phase 1 - LOW temperature (temp=10): exercises R6, R2, R3,
//             R5, R4 (R0/R1 require HIGH temp, so are untestable here).
//   Phase 2 - HIGH temperature (temp=200): exercises R1, R0, and
//             confirms R1 preempts R2 (automatic > manual priority).
//   Phase 3 - MID temperature (temp=120): confirms MID triggers no
//             temperature-based rule, and that R4 is temperature-
//             independent.
//   Phase 4 - Reset behaviour.
// ============================================================
`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg rst;
    reg event0, event1, event2;
    reg [1:0] mode;
    wire [3:0] led;

    integer errors;

    top_module #(.TICK_DIV(4)) uut (
        .clk    (clk),
        .rst    (rst),
        .event0 (event0),
        .event1 (event1),
        .event2 (event2),
        .mode   (mode),
        .led    (led)
    );

    initial clk = 1'b0;
    always #4 clk = ~clk;

    initial begin
        #100000;
        $display("*** WATCHDOG TIMEOUT - simulation did not finish in time ***");
        $finish;
    end

    task check_action;
        input [2:0] expected;
        input [639:0] label;
        begin
            if (led[2:0] === expected) begin
                $display("  [PASS] %0s : action=%b (expected %b)", label, led[2:0], expected);
            end else begin
                $display("  [FAIL] %0s : action=%b (expected %b)", label, led[2:0], expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        event0 = 1'b0; event1 = 1'b0; event2 = 1'b0; mode = 2'b00;

        $display("================================================");
        $display(" CPU-FPGA Decision Engine - Testbench");
        $display("================================================");

        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // -------- Phase 1: LOW temperature (temp == BASE_MIN == 10) --------
        $display("\n-- Phase 1: LOW temperature (temp=10, right after reset) --");
        #1;
        check_action(3'b000, "No inputs -> NONE (R7 default)");

        event0 = 1'b1; #1;
        check_action(3'b100, "event0 only -> LOG_EVENT (R6)");
        event0 = 1'b0; #1;

        event1 = 1'b1; #1;
        check_action(3'b101, "event1 only -> SAFE_MODE (R2)");
        event1 = 1'b0; #1;

        mode = 2'b11; #1;
        check_action(3'b110, "mode=Maintenance -> CALIBRATE (R3)");
        mode = 2'b00; #1;

        mode = 2'b10; #1;
        check_action(3'b111, "mode=Performance, LOW temp, no event -> ECO_BOOST (R5)");

        event0 = 1'b1; #1;
        check_action(3'b011, "mode=Performance + event0 -> BOOST (R4 beats R5)");
        event0 = 1'b0; mode = 2'b00; #1;

        // -------- Phase 2: HIGH temperature --------
        $display("\n-- Phase 2: HIGH temperature (wait for temp > 180) --");
        wait (uut.temp == 8'd200);
        @(posedge clk); #1;
        $display("  temp pinned near 200 (band=HIGH)");

        check_action(3'b010, "HIGH temp alone -> THROTTLE (R1)");

        event2 = 1'b1; #1;
        check_action(3'b001, "event2 + HIGH temp -> ALERT (R0 overrides R1)");
        event2 = 1'b0; #1;

        event1 = 1'b1; #1;
        check_action(3'b010, "event1 + HIGH temp -> THROTTLE still wins (R1 preempts R2)");
        event1 = 1'b0; #1;

        // -------- Phase 3: MID temperature --------
        $display("\n-- Phase 3: MID temperature (wait for temp == 120) --");
        // temp is descending now (it passed BASE_MAX on the way up already
        // only if BASE_MAX was reached - with TICK_DIV small this happens
        // quickly; wait for either the rising or falling pass through 120)
        wait (uut.temp == 8'd120);
        @(posedge clk); #1;
        $display("  temp pinned at 120 (band=MID)");

        check_action(3'b000, "MID temp alone, no events -> NONE (no rule matches)");

        mode = 2'b10; event0 = 1'b1; #1;
        check_action(3'b011, "mode=Performance + event0 at MID temp -> BOOST (R4 is temp-independent)");
        mode = 2'b00; event0 = 1'b0; #1;

        // -------- Phase 4: Reset --------
        $display("\n-- Phase 4: Reset behaviour --");
        rst = 1'b1;
        repeat (3) @(posedge clk);
        if (uut.temp === 8'd10 && led[2:0] === 3'b000) begin
            $display("  [PASS] Reset returns temp to BASE_MIN and action to NONE.");
        end else begin
            $display("  [FAIL] temp=%0d action=%b after reset (expected temp=10, action=000).",
                       uut.temp, led[2:0]);
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
