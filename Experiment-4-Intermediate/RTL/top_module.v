// ============================================================
// Project    : FAULTX - HIL (Hardware-In-the-Loop) Fault Injection
// Experiment : 4 (Intermediate)
// Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
// Team       : Mahasena  |  Lead: Manaswi
//
// Description:
//   A true Hardware-In-the-Loop fault-injection and fault-detection
//   rig, directly extending Experiment 1. It reuses Experiment 1's
//   verified 4-bit ALU (`alu4`) and its 8-vector test ROM as the
//   common stimulus, and runs TWO copies of the ALU in parallel:
//
//     - a clean "golden" copy, fed the ROM vectors unmodified, and
//     - a "faulted" copy, whose inputs (or output) can be corrupted
//       live by a configurable Fault Injection Wrapper.
//
//   A continuously free-running sequencer steps through all 8 ROM
//   vectors on both copies every cycle, comparing their outputs and
//   accumulating a running fault-coverage count (not just a single
//   first-failure flag, as in Experiment 1 - this is the Intermediate
//   step up: measuring HOW MANY of the 8 vectors actually detect the
//   injected fault, which is the real "fault coverage" metric used
//   in hardware fault-injection testing).
//
//   Switches select the fault TYPE (none / stuck-at-0 / stuck-at-1 /
//   single-bit-flip - a simple SEU model); buttons select the fault
//   TARGET (input a / input b / the ALU's output) and double as the
//   system reset. The engine free-runs continuously so fault settings
//   can be changed live and the effect is visible on the next pass.
//
// Module hierarchy:
//   top_module
//     +-- alu4 golden    (clean reference - Experiment 1's DUT, reused)
//     +-- alu4 faulted_core (same DUT core, fed possibly-corrupted inputs)
// ============================================================

module top_module #(
    parameter TICK_DIV = 25_000_000  // vector-step rate (hardware default)
) (
    input  wire        clk,            // 125 MHz board clock (pin H16)
    input  wire        rst,            // BTN0 - active-high synchronous reset
    input  wire        target_a,       // BTN1 - inject fault on ALU input a
    input  wire        target_b,       // BTN2 - inject fault on ALU input b
    input  wire        target_result,  // BTN3 - inject fault on ALU output
                                        //   (priority if multiple held: a > b > result)
    input  wire [1:0]  fault_type,     // SW1:SW0 - 00=none 01=stuck-at-0
                                        //           10=stuck-at-1 11=bit-flip (bit1)
    output wire [3:0]  led             // LED[3]=tick heartbeat / ALL-MATCH flag
                                        // LED[2:0]=current idx / first-mismatch idx
);

    // ---------------------------------------------------------
    // 1. Clock divider -> single-cycle "tick" pulse
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
    // 2. Test-vector ROM - identical to Experiment 1, reused for
    //    direct comparability against that experiment's baseline.
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
    wire [14:0] vec    = test_vector(idx);
    wire [3:0]  vec_a  = vec[14:11];
    wire [3:0]  vec_b  = vec[10:7];
    wire [1:0]  vec_op = vec[6:5];

    // ---------------------------------------------------------
    // 3. Golden (clean) ALU copy
    // ---------------------------------------------------------
    wire       golden_cout;
    wire [3:0] golden_result;

    alu4 golden (
        .a      (vec_a),
        .b      (vec_b),
        .opcode (vec_op),
        .cout   (golden_cout),
        .result (golden_result)
    );

    // ---------------------------------------------------------
    // 4. Fault injection wrapper - applied to a/b before the
    //    faulted ALU copy, or to its output afterward
    // ---------------------------------------------------------
    function [3:0] fault4;
        input [1:0] ftype;
        input [3:0] val;
        begin
            case (ftype)
                2'b01:   fault4 = 4'b0000;       // stuck-at-0
                2'b10:   fault4 = 4'b1111;       // stuck-at-1
                2'b11:   fault4 = val ^ 4'b0010; // bit-flip (bit 1)
                default: fault4 = val;           // 2'b00 - no fault
            endcase
        end
    endfunction

    function [4:0] fault5;
        input [1:0] ftype;
        input [4:0] val;
        begin
            case (ftype)
                2'b01:   fault5 = 5'b00000;
                2'b10:   fault5 = 5'b11111;
                2'b11:   fault5 = val ^ 5'b00010; // flips result[1]
                default: fault5 = val;
            endcase
        end
    endfunction

    wire fault_active = (fault_type != 2'b00) && (target_a | target_b | target_result);

    wire a_fault_sel      = fault_active &&  target_a;
    wire b_fault_sel      = fault_active && !target_a &&  target_b;
    wire result_fault_sel = fault_active && !target_a && !target_b && target_result;

    wire [3:0] a_faulted = a_fault_sel ? fault4(fault_type, vec_a) : vec_a;
    wire [3:0] b_faulted = b_fault_sel ? fault4(fault_type, vec_b) : vec_b;

    wire       raw_fcout;
    wire [3:0] raw_fresult;

    alu4 faulted_core (
        .a      (a_faulted),
        .b      (b_faulted),
        .opcode (vec_op),
        .cout   (raw_fcout),
        .result (raw_fresult)
    );

    wire [4:0] faulted_raw   = {raw_fcout, raw_fresult};
    wire [4:0] faulted_final = result_fault_sel ? fault5(fault_type, faulted_raw) : faulted_raw;
    wire       faulted_cout_f   = faulted_final[4];
    wire [3:0] faulted_result_f = faulted_final[3:0];

    // ---------------------------------------------------------
    // 5. Comparator
    // ---------------------------------------------------------
    wire vector_mismatch = (faulted_cout_f != golden_cout) || (faulted_result_f != golden_result);

    // ---------------------------------------------------------
    // 6. Free-running sequencer: RUN (step idx 0..7) -> DONE
    //    (hold one tick, then auto-relaunch). No manual start is
    //    needed, so all three non-reset buttons can be dedicated
    //    to fault targets - fault settings may be changed live
    //    while the engine keeps testing in the background, just
    //    like a real HIL rig continuously monitoring a DUT.
    // ---------------------------------------------------------
    localparam S_RUN = 1'b0, S_DONE = 1'b1;
    reg       state;
    reg       any_mismatch;
    reg [2:0] first_mismatch_idx;
    reg [3:0] mismatch_count; // 0-8, inspect via simulation waveform

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state               <= S_RUN;
            idx                 <= 3'd0;
            any_mismatch        <= 1'b0;
            first_mismatch_idx  <= 3'd0;
            mismatch_count      <= 4'd0;
        end else begin
            case (state)
                S_RUN: begin
                    if (tick) begin
                        if (vector_mismatch) begin
                            mismatch_count <= mismatch_count + 1'b1;
                            if (!any_mismatch) begin
                                any_mismatch       <= 1'b1;
                                first_mismatch_idx <= idx;
                            end
                        end
                        if (idx == 3'd7)
                            state <= S_DONE;
                        else
                            idx <= idx + 1'b1;
                    end
                end

                S_DONE: begin
                    if (tick) begin
                        idx                 <= 3'd0;
                        any_mismatch        <= 1'b0;
                        first_mismatch_idx  <= 3'd0;
                        mismatch_count      <= 4'd0;
                        state               <= S_RUN;
                    end
                end

                default: state <= S_RUN;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 7. LED display (same convention as Experiment 1)
    //    RUN  : led[3]=tick heartbeat   led[2:0]=current vector index
    //    DONE : led[3]=ALL-MATCH(1)/ANY-MISMATCH(0)  led[2:0]=first-mismatch index
    // ---------------------------------------------------------
    assign led = (state == S_RUN) ? {tick, idx}
                                   : {~any_mismatch, (any_mismatch ? first_mismatch_idx : 3'd0)};

endmodule


// ============================================================
// Device Under Test: 4-bit ALU (identical to Experiment 1)
//   opcode : 00=ADD  01=SUB  10=AND  11=OR
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
