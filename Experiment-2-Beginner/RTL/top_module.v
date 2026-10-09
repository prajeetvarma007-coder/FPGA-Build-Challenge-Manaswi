// ============================================================
// Project    : TrustFuse - Hardware Sensor Trust
// Experiment : 2 (Beginner)
// Board      : PYNQ-Z2 (Xilinx Zynq XC7Z020CLG400-1)
// Team       : Mahasena  |  Lead: Manaswi
//
// Description:
//   A triple-sensor cross-validation and fusion circuit. Three
//   simulated sensors (sensor1/2/3) track one common physical
//   quantity ("base_value") with small, known calibration offsets.
//   Every sensor is pairwise compared against the other two; a
//   sensor is "trusted" if it agrees (within TOLERANCE) with at
//   least one of the others. A trust level (0-3 sensors trusted)
//   is computed and a priority-fused output is produced from the
//   first trusted sensor. BTN1/BTN2/BTN3 let a user inject a live
//   fault on sensor 1/2/3 (while held) to demonstrate fault
//   detection; BTN0 resets the system; SW0 freezes the simulated
//   reading for easier observation.
//
// Module hierarchy:
//   top_module   (all logic - single module, Beginner scope)
// ============================================================

module top_module #(
    parameter TICK_DIV  = 25_000_000, // base-value update rate (hardware default)
    parameter TOLERANCE = 8'd8,       // max allowed deviation between agreeing sensors
    parameter BASE_MIN  = 8'd10,
    parameter BASE_MAX  = 8'd245,
    parameter OFFSET    = 8'd3        // nominal sensor2/sensor3 calibration offset
) (
    input  wire       clk,     // 125 MHz board clock (pin H16)
    input  wire       rst,     // BTN0 - active-high synchronous reset
    input  wire       fault1,  // BTN1 - inject fault on sensor 1 (while held)
    input  wire       fault2,  // BTN2 - inject fault on sensor 2 (while held)
    input  wire       fault3,  // BTN3 - inject fault on sensor 3 (while held)
    input  wire       freeze,  // SW0  - pause the simulated base reading
    output wire [3:0] led      // LED[3:2]=trust level, LED[1:0]=untrusted-sensor id
);

    // ---------------------------------------------------------
    // 1. Clock divider -> tick (paces the simulated base reading)
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
    // 2. Simulated physical quantity: triangle wave base_value
    // ---------------------------------------------------------
    reg [7:0] base_value;
    reg       base_dir; // 0 = counting up, 1 = counting down

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            base_value <= BASE_MIN;
            base_dir   <= 1'b0;
        end else if (tick && !freeze) begin
            if (!base_dir) begin
                if (base_value >= BASE_MAX) begin
                    base_dir   <= 1'b1;
                    base_value <= base_value - 1'b1;
                end else begin
                    base_value <= base_value + 1'b1;
                end
            end else begin
                if (base_value <= BASE_MIN) begin
                    base_dir   <= 1'b0;
                    base_value <= base_value + 1'b1;
                end else begin
                    base_value <= base_value - 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------
    // 3. Three simulated sensors (nominal readings)
    // ---------------------------------------------------------
    wire [7:0] sensor1_nom = base_value;
    wire [7:0] sensor2_nom = base_value + OFFSET;
    wire [7:0] sensor3_nom = base_value - OFFSET;

    // ---------------------------------------------------------
    // 4. Live fault injection (combinational, saturating adders
    //    so a fault always reads as clearly out-of-range)
    // ---------------------------------------------------------
    wire [8:0] s3_fault_full = {1'b0, sensor3_nom} + 9'd60;
    wire [7:0] sensor3_fault = s3_fault_full[8] ? 8'hFF : s3_fault_full[7:0];

    wire [7:0] sensor1 = fault1 ? 8'hFF         : sensor1_nom;
    wire [7:0] sensor2 = fault2 ? 8'h00         : sensor2_nom;
    wire [7:0] sensor3 = fault3 ? sensor3_fault : sensor3_nom;

    // ---------------------------------------------------------
    // 5. Pairwise deviation & agreement checks
    // ---------------------------------------------------------
    function [7:0] abs_diff;
        input [7:0] x, y;
        begin
            abs_diff = (x >= y) ? (x - y) : (y - x);
        end
    endfunction

    wire [7:0] d12 = abs_diff(sensor1, sensor2);
    wire [7:0] d13 = abs_diff(sensor1, sensor3);
    wire [7:0] d23 = abs_diff(sensor2, sensor3);

    wire agree12 = (d12 <= TOLERANCE);
    wire agree13 = (d13 <= TOLERANCE);
    wire agree23 = (d23 <= TOLERANCE);

    wire trust1 = agree12 | agree13;
    wire trust2 = agree12 | agree23;
    wire trust3 = agree13 | agree23;

    wire [1:0] num_trusted = trust1 + trust2 + trust3;

    // ---------------------------------------------------------
    // 6. Priority-fused output (inspect via simulation waveform;
    //    PYNQ-Z2 base board has no numeric display for this value)
    // ---------------------------------------------------------
    wire [7:0] fused_value = trust1 ? sensor1 :
                              trust2 ? sensor2 :
                              trust3 ? sensor3 :
                                       8'h00;  // no trusted sensor -> fail-safe 0

    // ---------------------------------------------------------
    // 7. LED status encoding
    //    LED[3:2] : trust level  (00=NONE 01=LOW 10=MEDIUM 11=HIGH)
    //    LED[1:0] : id of the single untrusted sensor (01/10/11);
    //               00 when zero or two-or-more sensors are untrusted
    // ---------------------------------------------------------
    reg [1:0] trust_level;
    always @(*) begin
        case (num_trusted)
            2'd3:    trust_level = 2'b11; // HIGH   - all three agree
            2'd2:    trust_level = 2'b10; // MEDIUM - one outlier
            2'd1:    trust_level = 2'b01; // LOW    - only one usable sensor
            default: trust_level = 2'b00; // NONE   - total disagreement
        endcase
    end

    reg [1:0] bad_id;
    always @(*) begin
        if      (!trust1 &&  trust2 &&  trust3) bad_id = 2'b01; // sensor1 is the outlier
        else if ( trust1 && !trust2 &&  trust3) bad_id = 2'b10; // sensor2 is the outlier
        else if ( trust1 &&  trust2 && !trust3) bad_id = 2'b11; // sensor3 is the outlier
        else                                    bad_id = 2'b00;
    end

    assign led = {trust_level, bad_id};

endmodule
