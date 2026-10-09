// ============================================================
// Project    : Automated Digital Circuit Tester
// Experiment : 1 (Beginner)
// Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
// Team       : Mahasena  |  Lead: Manaswi
//
// Description:
//   An FSM-driven automatic test sequencer ("mini ATE"). It stores
//   a fixed bank of 8 test vectors in an internal ROM, applies each
//   one to a 4-bit ALU (the Device Under Test), compares the DUT's
//   result against the pre-computed expected value, and reports
//   PASS / FAIL plus the index of the first failing vector on the
//   on-board LEDs. BTN0 resets the system, BTN1 starts/restarts the
//   test run.
//
// Module hierarchy:
//   top_module
//     +-- alu4   (Device Under Test)
// ============================================================

module top_module #(
    parameter TICK_DIV = 25_000_000   // ~5 Hz vector-step rate @125 MHz.
                                       // The testbench overrides this with a
                                       // small value for fast simulation.
) (
    input  wire       clk,   // 125 MHz board clock   (pin H16)
    input  wire       rst,   // BTN0 - active-high synchronous reset
    input  wire       start, // BTN1 - start / restart the test sequence
    output reg  [3:0] led    // Status LEDs - see README for encoding
);

    // ---------------------------------------------------------
    // 1. Clock divider -> single-cycle "tick" pulse
    // ---------------------------------------------------------
    localparam DIV_W = 25; // wide enough for TICK_DIV up to ~33M
    reg [DIV_W-1:0] div_cnt;
    wire tick = (div_cnt == TICK_DIV-1);

    always @(posedge clk or posedge rst) begin
        if (rst)
            div_cnt <= {DIV_W{1'b0}};
        else if (tick)
            div_cnt <= {DIV_W{1'b0}};
        else
            div_cnt <= div_cnt + 1'b1;
    end

    // ---------------------------------------------------------
    // 2. Start-button synchronizer + rising-edge detector
    // ---------------------------------------------------------
    reg start_ff1, start_ff2, start_ff3;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_ff1 <= 1'b0;
            start_ff2 <= 1'b0;
            start_ff3 <= 1'b0;
        end else begin
            start_ff1 <= start;
            start_ff2 <= start_ff1;
            start_ff3 <= start_ff2;
        end
    end
    wire start_pulse = start_ff2 & ~start_ff3;

    // ---------------------------------------------------------
    // 3. Test-vector ROM (8 vectors), packed function lookup
    //    Layout (MSB->LSB, 15 bits):
    //    {a[3:0], b[3:0], opcode[1:0], exp_cout, exp_result[3:0]}
    //    opcode: 00=ADD 01=SUB 10=AND 11=OR
    // ---------------------------------------------------------
    function [14:0] test_vector;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: test_vector = 15'b0011_0010_00_0_0101; // 3+2=5
                3'd1: test_vector = 15'b1111_0001_00_1_0000; // 15+1=16 (carry)
                3'd2: test_vector = 15'b0101_0011_01_1_0010; // 5-3=2
                3'd3: test_vector = 15'b0010_0101_01_0_1101; // 2-5=-3 (borrow)
                3'd4: test_vector = 15'b1010_0110_10_0_0010; // A AND 6
                3'd5: test_vector = 15'b1100_0011_11_0_1111; // C OR  3
                3'd6: test_vector = 15'b0000_0000_00_0_0000; // 0+0=0
                3'd7: test_vector = 15'b1001_1001_01_1_0000; // 9-9=0
                default: test_vector = 15'b0;
            endcase
        end
    endfunction

    reg  [2:0]  idx;
    wire [14:0] vec       = test_vector(idx);
    wire [3:0]  vec_a     = vec[14:11];
    wire [3:0]  vec_b     = vec[10:7];
    wire [1:0]  vec_op    = vec[6:5];
    wire        vec_ecout = vec[4];
    wire [3:0]  vec_eres  = vec[3:0];

    // ---------------------------------------------------------
    // 4. Device Under Test: 4-bit ALU
    // ---------------------------------------------------------
    wire       dut_cout;
    wire [3:0] dut_result;

    alu4 dut (
        .a      (vec_a),
        .b      (vec_b),
        .opcode (vec_op),
        .cout   (dut_cout),
        .result (dut_result)
    );

    wire vector_pass = (dut_cout == vec_ecout) && (dut_result == vec_eres);

    // ---------------------------------------------------------
    // 5. FSM: IDLE -> RUN -> DONE
    // ---------------------------------------------------------
    localparam S_IDLE = 2'd0,
               S_RUN  = 2'd1,
               S_DONE = 2'd2;

    reg [1:0] state;
    reg       fail_flag;
    reg [2:0] fail_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            idx       <= 3'd0;
            fail_flag <= 1'b0;
            fail_idx  <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        idx       <= 3'd0;
                        fail_flag <= 1'b0;
                        fail_idx  <= 3'd0;
                        state     <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (tick) begin
                        if (!vector_pass && !fail_flag) begin
                            fail_flag <= 1'b1;
                            fail_idx  <= idx;
                        end
                        if (idx == 3'd7)
                            state <= S_DONE;
                        else
                            idx <= idx + 1'b1;
                    end
                end

                S_DONE: begin
                    if (start_pulse) begin
                        idx       <= 3'd0;
                        fail_flag <= 1'b0;
                        fail_idx  <= 3'd0;
                        state     <= S_RUN;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 6. LED display
    //    RUN  : led[3]=tick heartbeat   led[2:0]=current vector index
    //    DONE : led[3]=PASS(1)/FAIL(0)  led[2:0]=first-fail index (000 if PASS)
    //    IDLE : all LEDs off
    // ---------------------------------------------------------
    always @(*) begin
        case (state)
            S_RUN:   led = {tick, idx};
            S_DONE:  led = {~fail_flag, (fail_flag ? fail_idx : 3'd0)};
            default: led = 4'b0000;
        endcase
    end

endmodule


// ============================================================
// Device Under Test: 4-bit ALU
//   opcode : 00=ADD  01=SUB  10=AND  11=OR
//   SUB implemented as a + (~b) + 1 ; cout=1 means NO borrow,
//   cout=0 means a borrow occurred (a < b).
// ============================================================
module alu4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [1:0] opcode,
    output reg         cout,
    output reg  [3:0]  result
);
    always @(*) begin
        case (opcode)
            2'b00:   {cout, result} = {1'b0, a} + {1'b0, b};
            2'b01:   {cout, result} = {1'b0, a} + {1'b0, ~b} + 5'b00001;
            2'b10:   {cout, result} = {1'b0, (a & b)};
            2'b11:   {cout, result} = {1'b0, (a | b)};
            default: {cout, result} = 5'b00000;
        endcase
    end
endmodule
