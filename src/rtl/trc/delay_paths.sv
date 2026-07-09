// =============================================================
// Module : delay_paths  (UPDATED -- mux re-added for calibration)
//
// History:
//   1. Instance names (u_trc0..u_trc3) no longer collide with net
//      names (trc0_err..trc3_err) -- the original file used the
//      SAME identifiers for both, which is illegal Verilog.
//   2. Output changed from a single MUX'd bit to a 4-bit PARALLEL
//      error bus oTRC_ERR[3:0], since failure_estimation.sv needs
//      the full thermometer-coded vector, not one bit at a time.
//   3. Inverter counts corrected to 192/144/96/48 per the spec table.
//   4. UPDATE: per-channel calibration (the "vGlitch" tuning process
//      from the Black Hat reference) needs to observe ONE TRC channel
//      at a time, not the whole bus at once. Added back oTRC_MUX,
//      selected by iTRC_SEL[1:0] -- this does NOT replace oTRC_ERR
//      (failure_estimation still needs the full parallel bus), it's
//      an additional debug/calibration tap. iTRC_SEL is meant to be
//      driven by adaptive_calibration's oVIRTUAL_ACTIVE_TRC output
//      (or REG_CONTROL_CONFIG.TRC_SEL in manual mode), matching the
//      "which TRC channel is currently the enforced boundary" concept
//      already described in the spec docs.
// =============================================================
module delay_paths (
    input  logic       iCLK,
    input  logic       iRST,

    input  logic [1:0] iTRC_SEL,   // channel select for oTRC_MUX (calibration/debug)

    output logic [3:0] oTRC_ERR,   // {TRC3, TRC2, TRC1, TRC0}, always active (parallel)
    output logic       oTRC_MUX    // single selected channel (calibration/debug)
);

    localparam real DELAY_ELEMENT = 0.05; // ns, sim-only per-inverter delay

    /* ------------------------------------------------------------
       TRC CHANNELS -- run in parallel at all times, per spec
    ------------------------------------------------------------ */
    trc_behavioral_chain #(
        .NUM_INVERTERS(192),   // Extreme sensitivity
        .DELAY_VAL(DELAY_ELEMENT)
    ) u_trc0 (
        .iCLK (iCLK), .iRST (iRST), .oTRC (oTRC_ERR[0])
    );

    trc_behavioral_chain #(
        .NUM_INVERTERS(144),   // High sensitivity
        .DELAY_VAL(DELAY_ELEMENT)
    ) u_trc1 (
        .iCLK (iCLK), .iRST (iRST), .oTRC (oTRC_ERR[1])
    );

    trc_behavioral_chain #(
        .NUM_INVERTERS(96),    // Medium sensitivity
        .DELAY_VAL(DELAY_ELEMENT)
    ) u_trc2 (
        .iCLK (iCLK), .iRST (iRST), .oTRC (oTRC_ERR[2])
    );

    trc_behavioral_chain #(
        .NUM_INVERTERS(48),    // Low sensitivity
        .DELAY_VAL(DELAY_ELEMENT)
    ) u_trc3 (
        .iCLK (iCLK), .iRST (iRST), .oTRC (oTRC_ERR[3])
    );

    /* ------------------------------------------------------------
       CALIBRATION MUX -- observe one channel at a time
    ------------------------------------------------------------ */
    always_comb begin
        case (iTRC_SEL)
            2'b00:   oTRC_MUX = oTRC_ERR[0];
            2'b01:   oTRC_MUX = oTRC_ERR[1];
            2'b10:   oTRC_MUX = oTRC_ERR[2];
            2'b11:   oTRC_MUX = oTRC_ERR[3];
            default: oTRC_MUX = oTRC_ERR[0];
        endcase
    end

endmodule
