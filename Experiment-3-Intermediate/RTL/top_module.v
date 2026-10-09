// ============================================================
// Project    : CPU-FPGA Decision Engine
// Experiment : 3 (Intermediate)
// Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
// Team       : Mahasena  |  Lead: Manaswi
//
// Description:
//   A fixed-priority, combinational rule-based decision engine - the
//   kind of safety/response logic a CPU would normally evaluate as a
//   sequential if/else-if chain in software (with non-deterministic
//   timing due to the OS, interrupts, and cache effects). Implemented
//   directly in hardware it becomes a single-cycle, deterministic
//   O(1) decision, which is the core "CPU work moved to the FPGA"
//   idea behind this experiment.
//
//   A simulated "temperature" sensor (reusing the verified triangle-
//   wave generator pattern from Experiment 2) is classified into a
//   LOW/MID/HIGH band. Two switches set an operating "mode" register
//   (as a CPU would), and three buttons model asynchronous hardware
//   events (like interrupts). An 8-entry fixed-priority rule table
//   (rule 0 = highest priority, first match wins) converts these
//   into one of 8 distinct action codes, shown on the LEDs.
//
// Module hierarchy:
//   top_module  (single module - temperature model + priority
//                decision logic; Intermediate scope)
// ============================================================

module top_module #(
    parameter TICK_DIV     = 25_000_000, // temperature update rate (hardware default)
    parameter BASE_MIN     = 8'd10,
    parameter BASE_MAX     = 8'd245,
    parameter HIGH_THRESH  = 8'd180,     // temp >  HIGH_THRESH -> HIGH band
    parameter LOW_THRESH   = 8'd80       // temp <= LOW_THRESH  -> LOW band
) (
    input  wire       clk,          // 125 MHz board clock (pin H16)
    input  wire       rst,          // BTN0 - active-high synchronous reset
    input  wire       event0,       // BTN1 - async event 0
    input  wire       event1,       // BTN2 - async event 1 (manual safe-mode request)
    input  wire       event2,       // BTN3 - async event 2 (critical event)
    input  wire [1:0] mode,         // SW1:SW0 - operating mode register
                                     //   00=Normal 01=PowerSave 10=Performance 11=Maintenance
    output wire [3:0] led           // LED[3]=tick heartbeat, LED[2:0]=action code
);

    // ---------------------------------------------------------
    // 1. Clock divider -> tick (paces the simulated temperature)
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
    // 2. Simulated temperature sensor: triangle wave (as Exp.2)
    // ---------------------------------------------------------
    reg [7:0] temp;
    reg       temp_dir;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            temp     <= BASE_MIN;
            temp_dir <= 1'b0;
        end else if (tick) begin
            if (!temp_dir) begin
                if (temp >= BASE_MAX) begin
                    temp_dir <= 1'b1;
                    temp     <= temp - 1'b1;
                end else begin
                    temp <= temp + 1'b1;
                end
            end else begin
                if (temp <= BASE_MIN) begin
                    temp_dir <= 1'b0;
                    temp     <= temp + 1'b1;
                end else begin
                    temp <= temp - 1'b1;
                end
            end
        end
    end

    // Temperature classification (combinational)
    wire [1:0] temp_band = (temp > HIGH_THRESH) ? 2'b10 :
                            (temp > LOW_THRESH)  ? 2'b01 : 2'b00;
    // 2'b10 = HIGH, 2'b01 = MID, 2'b00 = LOW

    // ---------------------------------------------------------
    // 3. Fixed-priority rule table (rule 0 = highest priority)
    //    Deliberate priority rationale: automatic thermal
    //    protection (R0/R1) always preempts a manual request
    //    (R2) - a standard safety-system design choice.
    //
    //    R0: event2 & HIGH temp        -> ALERT      (001)
    //    R1: HIGH temp (alone)         -> THROTTLE    (010)
    //    R2: event1 (manual request)   -> SAFE_MODE   (101)
    //    R3: mode == Maintenance       -> CALIBRATE   (110)
    //    R4: event0 & Performance mode -> BOOST        (011)
    //    R5: Performance mode & LOW temp -> ECO_BOOST  (111)
    //    R6: event0 (alone)            -> LOG_EVENT   (100)
    //    R7: (default - no match)      -> NONE        (000)
    // ---------------------------------------------------------
    reg [2:0] action;

    always @(*) begin
        if (event2 && (temp_band == 2'b10))
            action = 3'b001; // ALERT
        else if (temp_band == 2'b10)
            action = 3'b010; // THROTTLE
        else if (event1)
            action = 3'b101; // SAFE_MODE
        else if (mode == 2'b11)
            action = 3'b110; // CALIBRATE
        else if (event0 && (mode == 2'b10))
            action = 3'b011; // BOOST
        else if ((mode == 2'b10) && (temp_band == 2'b00))
            action = 3'b111; // ECO_BOOST
        else if (event0)
            action = 3'b100; // LOG_EVENT
        else
            action = 3'b000; // NONE
    end

    // ---------------------------------------------------------
    // 4. LED display: heartbeat + current action (single-cycle,
    //    always live - this decision has no "done" state, since
    //    the whole point is it is continuously available in O(1))
    // ---------------------------------------------------------
    assign led = {tick, action};

endmodule
