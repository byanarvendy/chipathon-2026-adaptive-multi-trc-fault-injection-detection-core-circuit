# Multi-TRC — RTL, LibreLane synthesis, and waveform simulation

Scope: the Multi-TRC fault-injection detection block only
(`delay_paths.sv` + `trc_behavioral_chain.sv`) — team A48 Hore's SSCS
Chipathon 2026 project. Tool stack: cocotb + Icarus + LibreLane 3.x +
GF180MCU, via the `hpretl/iic-osic-tools:chipathon26` container
(`start_x.sh`).

```
multi_trc_librelane/
├── rtl/
│   ├── trc_behavioral_chain.sv   # single TRC channel
│   └── delay_paths.sv            # top: 4 channels + mux + parallel bus
├── cocotb/
│   └── delay_paths_tb.py         # get_runner()-style tb, matches the
│                                  # project repo's chip_top_tb.py convention
├── tb/                           # standalone classic-Makefile cocotb flow
│   ├── Makefile                  # (only needed if testing outside the repo)
│   ├── timescale.v
│   └── test_delay_paths.py
└── librelane/
    └── trc_macro.yaml            # standalone macro synthesis config
```

## Module interface

```systemverilog
module delay_paths (
    input  logic       iCLK,
    input  logic       iRST,
    input  logic [1:0] iTRC_SEL,   // channel select, drives oTRC_MUX
    output logic [3:0] oTRC_ERR,   // {TRC3,TRC2,TRC1,TRC0}, parallel, always active
    output logic [3:0] oTRC_MUX    // selected channel's bit only, rest zeroed;
                                    // same bit-width/position as oTRC_ERR
);
```

- `oTRC_ERR[3:0]` — parallel thermometer-coded bus, feeds `failure_estimation`
  (needs all 4 channels simultaneously, per the spec docs — this is why
  the original single-bit MUX-only design was replaced).
- `oTRC_MUX[3:0]` + `iTRC_SEL` — added back for **per-channel calibration**
  (the "vGlitch" tuning process from the Black Hat reference is done one
  channel at a time). `oTRC_MUX` is 4 bits wide (same width as `oTRC_ERR`)
  but only the bit at the selected channel's position can ever be set —
  e.g. `iTRC_SEL=2'b01` with TRC1 tripped gives `oTRC_MUX=4'b0010`, never
  `4'b0001` or `4'b1111`. This keeps bit-position meaning consistent with
  `oTRC_ERR` while still only reporting one channel at a time. `iTRC_SEL`
  is meant to be driven by `adaptive_calibration`'s `oVIRTUAL_ACTIVE_TRC`
  output (auto mode) or `REG_CONTROL_CONFIG.TRC_SEL` (manual mode) — not
  wired up yet, needs coordination with whoever owns `adaptive_calibration`.

Channel sensitivities: TRC0=192 inverters (Extreme), TRC1=144 (High),
TRC2=96 (Medium), TRC3=48 (Low), per `Adaptive_Multi_TRC_Spec.pdf`.

**Synthesis note:** the delay chain uses structural instantiation of the
real GF180MCU inverter cell (`gf180mcu_fd_sc_mcu7t5v0__inv_1`, pin `I`→`ZN`)
rather than behavioral `assign ~x`. This is required, not stylistic: a
zero-delay behavioral chain with an even inverter count is logically
identical to its own input, so Yosys/ABC proves the whole path (including
both flip-flops) is a compile-time constant and deletes it entirely.
Structural cell instances are opaque black boxes and can't be collapsed
that way. See the comments in `trc_behavioral_chain.sv` for the full story.

## 1. Environment

```bash
docker pull hpretl/iic-osic-tools:chipathon26
export DESIGNS=~/myproject/IC   # parent folder containing this repo checkout
./start_x.sh
```
Inside the container, PDK env vars need to point at GF180 explicitly
(the container defaults to a different PDK):
```bash
sak-pdk gf180mcuD
```

## 2. Testing — two ways

**A) Matching this project's repo convention** (`cocotb/delay_paths_tb.py`,
same `get_runner()` style as `chip_top_tb.py`):
```bash
cd cocotb
python3 delay_paths_tb.py
```

**B) Standalone classic-Makefile flow** (useful outside the repo, e.g.
quick iteration on the TRC block alone):
```bash
cd tb
WAVES=1 make SIM=icarus
```

Both run the same two scenarios:
- nominal 100 MHz clock -> `oTRC_ERR` reads `0000`
- severe glitch (clock sped up to 1 ns) -> `oTRC_ERR` reads `0011`
  (TRC0 + TRC1, the two most sensitive channels, trip)

Waveform: `sim_build/delay_paths.fst` (whichever `sim_build/` the run
you used created). Open with:
```bash
gtkwave sim_build/delay_paths.fst
```
Worth adding to the view: `iCLK`, `iRST`, `oTRC_ERR[3:0]`, `oTRC_MUX`,
and inside `u_trc0..u_trc3`: `launch_q`, `trc_data_actual`, `capture_q`.

## 3. Synthesis with LibreLane

```bash
cd librelane
python3 -m librelane --manual-pdk --pdk-root $PDK_ROOT --pdk gf180mcuD trc_macro.yaml
```

`--manual-pdk` skips Ciel's version-pinned auto-download and uses
whatever GF180 PDK is already installed locally -- important if your
network is slow, since LibreLane's pinned PDK commit often isn't the
one you already have cached.

Confirmed working end-to-end (80/80 stages, full GDS) with this config.
Key settings that mattered (see comments in `trc_macro.yaml` for the
full debugging story):
- `USE_SLANG: true` + `VERILOG_DEFINES: [SYNTHESIS]` -- needed so Slang
  doesn't choke on the sim-only `#(DELAY_VAL)` timing control.
- `FP_SIZING: absolute` + explicit `DIE_AREA`/`CORE_AREA` -- the default
  utilization-based sizing produces a core too small for the PDN grid to
  fit power straps on ("PDN-0185: Insufficient width"). Setting
  `DIE_AREA` alone silently does nothing without `FP_SIZING: absolute`.

Gate-level netlist after a run lands at:
```
runs/RUN_<timestamp>/final/nl/delay_paths.nl.v    # post-synthesis
runs/RUN_<timestamp>/final/pnl/delay_paths.pnl.v  # post-place&route (use this one)
```

To look at just the synthesized schematic without waiting for full P&R:
```bash
yosys -p "read_verilog -sv -DSYNTHESIS ../rtl/trc_behavioral_chain.sv ../rtl/delay_paths.sv; \
          synth -top delay_paths; show -format svg -prefix delay_paths_schem"
```

**Read the STA report before trusting anything.** The TRC's whole job
is to violate timing on that internal delay-chain path under
slow/hot/low-voltage conditions -- that IS the detection mechanism.
Confirmed via `12-openroad-staprepnr/<corner>/max.rpt`: 0 violations at
the fast-fast corner, setup violations present at the slow-slow corner
(125C, 4.5V), tracing cleanly through `u_trc0.gen_inv_stage[N].u_inv`
for each real inverter cell. Don't let the optimizer "fix" this path if
you later add SDC constraints -- `set_false_path`/`set_multicycle_path`
on the delay_wire nets.

## 4. Post-synthesis (gate-level) simulation -- currently blocked

`GL=1` gate-level simulation needs a Verilog behavioral model for
`gf180mcu_fd_sc_mcu7t5v0` (and every other cell used). As of writing,
`libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/` is **empty** in the PDK
checkout pulled by this project -- so this isn't possible yet for this
or any other block, not a bug specific to this RTL. Validation for now
relies on the RTL-level cocotb waveform (step 2) plus the STA report
(step 3), which together confirm both functional and timing behavior.
Worth flagging to whoever manages the PDK/toolchain setup.
