# SPDX-FileCopyrightText: © 2026 Chipathon 2026 - A48 Hore Team
# SPDX-License-Identifier: Apache-2.0
#
# Standalone testbench for the Multi-TRC block (delay_paths.sv +
# trc_behavioral_chain.sv), following the same get_runner() convention
# as chip_top_tb.py so it can be invoked the same way.

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotb_tools.runner import get_runner

sim = os.getenv("SIM", "icarus")
pdk_root = os.getenv("PDK_ROOT", Path("~/.ciel").expanduser())
pdk = os.getenv("PDK", "gf180mcuD")
scl = os.getenv("SCL", "gf180mcu_fd_sc_mcu7t5v0")
gl = os.getenv("GL", False)

hdl_toplevel = "delay_paths"


async def reset_dut(dut, cycles=3):
    dut.iRST.value = 0
    dut.iTRC_SEL.value = 0
    await Timer(15, unit="ns")
    dut.iRST.value = 1
    for _ in range(cycles):
        await RisingEdge(dut.iCLK)


@cocotb.test()
async def test_nominal_no_glitch(dut):
    """At nominal 100 MHz, no TRC channel should report an error."""
    clock = Clock(dut.iCLK, 10, unit="ns")  # 10 ns = 100 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    for _ in range(20):
        await RisingEdge(dut.iCLK)

    dut._log.info(f"oTRC_ERR (nominal) = {dut.oTRC_ERR.value}")
    assert dut.oTRC_ERR.value == 0, (
        f"Expected no glitch at nominal clock, got oTRC_ERR={dut.oTRC_ERR.value}. "
        "If this fails, the delay chain lengths (192/144/96/48 inverters) "
        "need to be re-tuned against the target clock period -- this is "
        "the 'vGlitch' calibration step described in the Black Hat TRC "
        "reference this project is based on."
    )


@cocotb.test()
async def test_glitch_injection(dut):
    """Speeding the clock up drastically should trip at least one TRC channel."""
    clock = Clock(dut.iCLK, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    for _ in range(10):
        await RisingEdge(dut.iCLK)

    # Overclocking glitch scenario: starve the delay chains of time to
    # settle before the next capture edge.
    fast_clock = Clock(dut.iCLK, 1, unit="ns")  # 1 ns = 1 GHz
    cocotb.start_soon(fast_clock.start())

    for _ in range(30):
        await RisingEdge(dut.iCLK)

    dut._log.info(f"oTRC_ERR (during glitch) = {dut.oTRC_ERR.value}")
    assert dut.oTRC_ERR.value != 0, (
        "Expected at least one TRC channel to trip under a severe "
        "overclocking glitch, but oTRC_ERR stayed 0000."
    )


@cocotb.test()
async def test_mux_selects_correct_channel(dut):
    """Prove oTRC_MUX is a real mux: cycle iTRC_SEL through 0..3 and check
    oTRC_MUX always matches oTRC_ERR[iTRC_SEL] -- i.e. only ONE channel is
    being observed at a time, selected by iTRC_SEL, while oTRC_ERR keeps
    reporting all 4 channels in parallel underneath."""
    clock = Clock(dut.iCLK, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    for _ in range(10):
        await RisingEdge(dut.iCLK)

    # Force a glitch first so oTRC_ERR has some 1-bits to actually
    # distinguish between channels (all-zero would "pass" trivially).
    fast_clock = Clock(dut.iCLK, 1, unit="ns")
    cocotb.start_soon(fast_clock.start())
    for _ in range(20):
        await RisingEdge(dut.iCLK)

    err_bus = dut.oTRC_ERR.value
    dut._log.info(f"oTRC_ERR snapshot for mux test = {err_bus}")

    for sel in range(4):
        dut.iTRC_SEL.value = sel
        await Timer(1, unit="ns")  # let the combinational mux settle

        expected_bit = (int(err_bus) >> sel) & 0x1
        actual_bit = int(dut.oTRC_MUX.value)

        dut._log.info(
            f"iTRC_SEL={sel} -> oTRC_MUX={actual_bit} "
            f"(expected oTRC_ERR[{sel}]={expected_bit})"
        )
        assert actual_bit == expected_bit, (
            f"MUX MISMATCH at iTRC_SEL={sel}: oTRC_MUX={actual_bit}, "
            f"but oTRC_ERR[{sel}]={expected_bit}. oTRC_MUX is not "
            f"correctly selecting channel {sel}."
        )

    dut._log.info("Confirmed: oTRC_MUX correctly tracks each individually "
                   "selected TRC channel -- this IS a real 4:1 mux.")


def delay_paths_runner():

    proj_path = Path(__file__).resolve().parent

    sources = []
    defines = {}
    includes = [proj_path / "../src/"]

    if gl:
        # SCL models -- NOTE: as of writing, libs.ref/<scl>/verilog/<scl>.v
        # is EMPTY in the gf180mcuD PDK checkout used for this project, so
        # this branch will currently fail to find sources. Flagging here
        # rather than silently producing a confusing missing-file error.
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / f"{scl}.v")
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / "primitives.v")
        defines = {"FUNCTIONAL": True}
    else:
        sources.append(proj_path / "../src/rtl/trc/trc_behavioral_chain.sv")
        sources.append(proj_path / "../src/rtl/trc/delay_paths.sv")

    build_args = []
    if sim == "verilator":
        build_args = ["--timing", "--trace", "--trace-fst", "--trace-structs"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        defines=defines,
        always=True,
        includes=includes,
        build_args=build_args,
        timescale=("1ns", "1ps"),
        waves=True,
    )

    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module="delay_paths_tb,",
        waves=True,
    )


if __name__ == "__main__":
    delay_paths_runner()
