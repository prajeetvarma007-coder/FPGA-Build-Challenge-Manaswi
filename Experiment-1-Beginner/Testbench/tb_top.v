// ============================================================
// Testbench   : tb_top.v
// DUT         : top_module (Automated Digital Circuit Tester)
// Experiment  : 1 (Beginner)
//
// Strategy:
//   Phase 1 - Cross-check an independent golden ALU reference model
//             against the hand-derived expected values used inside
//             the DUT's test ROM (catches a wrong expected value).
//   Phase 2 - Run the real hardware FSM (start button, full 8-vector
//             sweep) and confirm it reports PASS with index 0.
//   Phase 3 - Confirm synchronous reset returns the system to IDLE.
//   A self-checking pass/fail summary is printed at the end.
// ============================================================
`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg rst;
    reg start;
    wire [3:0] led;

    integer errors;
    integer i;

    // Golden reference vectors, written independently from the
    // spec (NOT copy-pasted from the DUT's ROM) to catch bugs in
    // either the ALU or the ROM contents.
    reg [3:0] exp_a    [0:7];
    reg [3:0] exp_b    [0:7];
    reg [1:0] exp_op   [0:7];
    reg       exp_cout [0:7];
    reg [3:0] exp_res  [0:7];

    reg       ref_cout;
    reg [3:0] ref_result;

    // Small TICK_DIV => fast simulation. Hardware default (25,000,000)
    // is unchanged for synthesis/implementation.
    top_module #(.TICK_DIV(4)) uut (
        .clk   (clk),
        .rst   (rst),
        .start (start),
        .led   (led)
    );

    // 125 MHz clock
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // Reference ALU model (independent re-implementation)
    function [4:0] alu_ref;
        input [3:0] a, b;
        input [1:0] op;
        begin
            case (op)
                2'b00:   alu_ref = {1'b0, a} + {1'b0, b};
                2'b01:   alu_ref = {1'b0, a} + {1'b0, ~b} + 5'b00001;
                2'b10:   alu_ref = {1'b0, (a & b)};
                2'b11:   alu_ref = {1'b0, (a | b)};
                default: alu_ref = 5'b00000;
            endcase
        end
    endfunction

    // Safety watchdog - prevents a runaway simulation
    initial begin
        #100000;
        $display("*** WATCHDOG TIMEOUT - simulation did not finish in time ***");
        $finish;
    end

    initial begin
        errors = 0;

        exp_a[0]=4'h3; exp_b[0]=4'h2; exp_op[0]=2'b00; exp_cout[0]=1'b0; exp_res[0]=4'h5;
        exp_a[1]=4'hF; exp_b[1]=4'h1; exp_op[1]=2'b00; exp_cout[1]=1'b1; exp_res[1]=4'h0;
        exp_a[2]=4'h5; exp_b[2]=4'h3; exp_op[2]=2'b01; exp_cout[2]=1'b1; exp_res[2]=4'h2;
        exp_a[3]=4'h2; exp_b[3]=4'h5; exp_op[3]=2'b01; exp_cout[3]=1'b0; exp_res[3]=4'hD;
        exp_a[4]=4'hA; exp_b[4]=4'h6; exp_op[4]=2'b10; exp_cout[4]=1'b0; exp_res[4]=4'h2;
        exp_a[5]=4'hC; exp_b[5]=4'h3; exp_op[5]=2'b11; exp_cout[5]=1'b0; exp_res[5]=4'hF;
        exp_a[6]=4'h0; exp_b[6]=4'h0; exp_op[6]=2'b00; exp_cout[6]=1'b0; exp_res[6]=4'h0;
        exp_a[7]=4'h9; exp_b[7]=4'h9; exp_op[7]=2'b01; exp_cout[7]=1'b1; exp_res[7]=4'h0;

        $display("================================================");
        $display(" Automated Digital Circuit Tester - Testbench");
        $display("================================================");

        // -------- Phase 1: golden-model self-check --------
        $display("\n-- Phase 1: Golden-model cross-check --");
        for (i = 0; i < 8; i = i + 1) begin
            {ref_cout, ref_result} = alu_ref(exp_a[i], exp_b[i], exp_op[i]);
            if (ref_cout !== exp_cout[i] || ref_result !== exp_res[i]) begin
                $display("  [FAIL] vector %0d golden mismatch: got cout=%b res=%h, expected cout=%b res=%h",
                          i, ref_cout, ref_result, exp_cout[i], exp_res[i]);
                errors = errors + 1;
            end else begin
                $display("  [OK]   vector %0d: a=%h b=%h op=%b -> cout=%b result=%h",
                          i, exp_a[i], exp_b[i], exp_op[i], ref_cout, ref_result);
            end
        end

        // -------- Phase 2: hardware FSM full run --------
        $display("\n-- Phase 2: Hardware FSM test sequence --");
        rst   = 1'b1;
        start = 1'b0;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Wait until the FSM reaches S_DONE (led[3] meaningful) -
        // poll the internal state register directly (white-box check).
        wait (uut.state == 2'd2); // S_DONE
        @(posedge clk);
        $display("  Final LED = %b (led[3]=PASS/FAIL, led[2:0]=index)", led);

        if (led === 4'b1000) begin
            $display("  [PASS] All 8 vectors passed, as expected for a correct ALU.");
        end else begin
            $display("  [FAIL] Unexpected result. led=%b", led);
            errors = errors + 1;
        end

        // -------- Phase 3: reset returns FSM to IDLE --------
        $display("\n-- Phase 3: Reset behaviour --");
        rst = 1'b1;
        repeat (3) @(posedge clk);
        if (led === 4'b0000 && uut.state == 2'd0) begin
            $display("  [PASS] Reset clears LEDs and returns FSM to IDLE.");
        end else begin
            $display("  [FAIL] Reset did not clear state. led=%b state=%0d", led, uut.state);
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
