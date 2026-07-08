// =============================================================
// Module : delay_paths  (FIXED)
//
// Fixes applied vs original file:
//   1. Instance names (u_trc0..u_trc3) no longer collide with net
//      names (trc0_err..trc3_err) -- the original file used the
//      SAME identifiers for both, which is illegal Verilog and
//      failed to elaborate in both Icarus and Verilator:
//        "Instance has the same name as variable: 'trc0'"
//   2. Output changed from a single MUX'd bit (oTRC, selected by
//      iTRC_SEL) to a 4-bit PARALLEL error bus oTRC_ERR[3:0].
//      This matches how the rest of the design actually consumes
//      it: failure_estimation.sv expects a 4-bit thermometer-coded
//      vector (see its casez patterns 4'b1???/01??/001?/0001), and
//      the chipathon spec explicitly says the Adaptive Decision
//      block "processes a 4-bit parallel error bus representing
//      all TRC channels simultaneously... instead of routing a
//      single analog clock signal through a physical multiplexer."
//      A single-bit MUX'd output (as the original file produced)
//      is architecturally incompatible with that.
//   3. Inverter counts corrected to match the documented table in
//      Adaptive_Multi_TRC_Spec.pdf / the Chipathon core-circuit doc
//      (192/144/96/48), instead of the RTL's previous 45/35/25/15
//      (which also happened to be odd -- see trc_behavioral_chain
//      fix notes on why that matters).
// =============================================================
module delay_paths (
    input  logic       iCLK,
    input  logic       iRST,

    output logic [3:0] oTRC_ERR   // {TRC3, TRC2, TRC1, TRC0}, always active
);

    localparam real DELAY_ELEMENT = 0.05; // ns, sim-only per-inverter delay

    /* ------------------------------------------------------------
       TRC CHANNELS -- run in parallel at all times, per spec
       (manual single-channel select via REG_CONTROL_CONFIG.TRC_SEL
       is a register/diagnostic concept, not a physical mux on the
       detection path -- see top-level wiring notes)
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

endmodule
