#!/usr/bin/env python3
"""
run.py - one entry point for everything (works on Linux, macOS and Windows).

  python scripts/run.py directed               run the 6 hand-written test programs
  python scripts/run.py random --seeds 50      random programs, RTL vs Python model
  python scripts/run.py bugs                   switch on each planted bug, see if tests catch it
  python scripts/run.py wave hazard_test       run one test and save wave.vcd (open in GTKWave)
  python scripts/run.py build-asm              re-assemble tests/asm/*.S -> tests/hex/*.hex
                                               (needs riscv64-unknown-elf binutils + cpp)

Needs: Icarus Verilog (iverilog + vvp on PATH) and Python 3.8+.
"""
import argparse
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "model"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from rv32i_iss import RV32I, load_hex          # noqa: E402
import gen_random                               # noqa: E402

BUILD = os.path.join(ROOT, "build")
DIRECTED = ["alu_test", "mem_test", "branch_test", "hazard_test", "bubble_sort", "fib"]
BUGS = ["BUG_NO_EXMEM_FWD", "BUG_NO_LOAD_STALL", "BUG_NO_FLUSH_IFID", "BUG_SRA_AS_SRL"]


def compile_rtl(defines=(), out="sim.vvp"):
    os.makedirs(BUILD, exist_ok=True)
    vvp = os.path.join(BUILD, out)
    srcs = sorted(glob.glob(os.path.join(ROOT, "rtl", "*.v"))) + [os.path.join(ROOT, "tb", "tb_soc.v")]
    cmd = ["iverilog", "-g2005", "-Wall", "-Wno-timescale", "-I", os.path.join(ROOT, "rtl"), "-o", vvp]
    cmd += [f"-D{d}" for d in defines] + srcs
    subprocess.run(cmd, check=True)
    return vvp


def simulate(vvp, hexfile, dump=None, vcd=False, max_cycles=200000):
    cmd = ["vvp", "-n", vvp, f"+HEX={hexfile}", f"+MAXCYCLES={max_cycles}"]
    if dump:
        cmd.append(f"+DUMP={dump}")
    if vcd:
        cmd.append("+VCD")
    out = subprocess.run(cmd, capture_output=True, text=True, cwd=BUILD).stdout
    for line in out.splitlines():
        if line.startswith(("[PASS]", "[FAIL]", "[TIMEOUT]")):
            return line
    return "[ERROR] simulator printed no result:\n" + out


def run_directed(vvp, quiet=False):
    failures = 0
    for t in DIRECTED:
        result = simulate(vvp, os.path.join(ROOT, "tests", "hex", f"{t}.hex"))
        ok = result.startswith("[PASS]")
        failures += not ok
        if not quiet:
            print(f"  {t:<12} {result}")
    return failures


def compare_with_model(vvp, seed, length):
    """Run one random program on RTL and on the ISS. Returns a list of mismatch strings."""
    prog = gen_random.gen_program(seed, length)
    hexfile = os.path.join(BUILD, f"random_{seed}.hex")
    dump = os.path.join(BUILD, f"random_{seed}.dump")
    gen_random.write_hex(prog, hexfile)
    if os.path.exists(dump):
        os.remove(dump)

    result = simulate(vvp, hexfile, dump=dump)
    if not result.startswith("[PASS]") or not os.path.exists(dump):
        return [f"RTL did not finish cleanly: {result}"], 0

    with open(dump) as f:
        rtl = [int(x, 16) for x in f.read().split()]
    iss = RV32I(load_hex(hexfile))
    iss.run()

    diffs = []
    for r in range(32):
        if rtl[r] != iss.x[r]:
            diffs.append(f"x{r}: rtl={rtl[r]:08x} model={iss.x[r]:08x}")
    for i in range(0x200):
        addr = 0x1000 + 4 * i
        if rtl[32 + i] != iss.word(addr):
            diffs.append(f"mem[0x{addr:04x}]: rtl={rtl[32 + i]:08x} model={iss.word(addr):08x}")
    return diffs, iss.instret


def run_random(vvp, seeds, length, quiet=False):
    bad_seeds, total_instr = 0, 0
    for seed in range(1, seeds + 1):
        diffs, n = compare_with_model(vvp, seed, length)
        total_instr += n
        if diffs:
            bad_seeds += 1
            if not quiet:
                print(f"  seed {seed}: MISMATCH ({len(diffs)} differences)")
                for d in diffs[:5]:
                    print(f"      {d}")
    return bad_seeds, total_instr


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["directed", "random", "bugs", "wave", "build-asm"])
    ap.add_argument("test", nargs="?", default="hazard_test", help="test name for 'wave'")
    ap.add_argument("--seeds", type=int, default=50)
    ap.add_argument("--len", type=int, default=300, help="random instructions per program")
    args = ap.parse_args()

    if args.mode == "build-asm":
        build_asm()
        return

    if args.mode == "directed":
        print("Directed tests:")
        fails = run_directed(compile_rtl())
        print(f"\n{len(DIRECTED) - fails}/{len(DIRECTED)} directed tests passed")
        sys.exit(1 if fails else 0)

    if args.mode == "random":
        print(f"Random regression: {args.seeds} programs x {args.len} random instructions")
        bad, n = run_random(compile_rtl(), args.seeds, args.len)
        print(f"\n{args.seeds - bad}/{args.seeds} programs matched the reference model "
              f"({n} instructions executed in total)")
        sys.exit(1 if bad else 0)

    if args.mode == "wave":
        vvp = compile_rtl()
        print(simulate(vvp, os.path.join(ROOT, "tests", "hex", f"{args.test}.hex"), vcd=True))
        print(f"waveform written to {os.path.join(BUILD, 'wave.vcd')}")
        return

    if args.mode == "bugs":
        print("Bug hunt: each planted bug is switched on alone, then all tests run.\n")
        print(f"  {'bug':<20} {'directed tests failing':<24} {'random seeds failing'}")
        caught = 0
        for bug in BUGS:
            vvp = compile_rtl([bug], out=f"sim_{bug}.vvp")
            d_fail = run_directed(vvp, quiet=True)
            r_fail, _ = run_random(vvp, args.seeds, args.len, quiet=True)
            caught += (d_fail + r_fail) > 0
            print(f"  {bug:<20} {f'{d_fail}/{len(DIRECTED)}':<24} {r_fail}/{args.seeds}")
        print(f"\n{caught}/{len(BUGS)} planted bugs were detected")


def build_asm():
    asm_dir = os.path.join(ROOT, "tests", "asm")
    hex_dir = os.path.join(ROOT, "tests", "hex")
    os.makedirs(BUILD, exist_ok=True)
    pre = "riscv64-unknown-elf-"
    for t in DIRECTED:
        src = os.path.join(asm_dir, f"{t}.S")
        s, o, elf, binf = (os.path.join(BUILD, f"{t}.{e}") for e in ("s", "o", "elf", "bin"))
        subprocess.run(["cpp", "-P", "-undef", "-nostdinc", "-I", asm_dir, src, "-o", s], check=True)
        subprocess.run([pre + "as", "-march=rv32i", "-mabi=ilp32", s, "-o", o], check=True)
        subprocess.run([pre + "ld", "-m", "elf32lriscv", "-T", os.path.join(asm_dir, "link.ld"), o, "-o", elf],
                       check=True)
        subprocess.run([pre + "objcopy", "-O", "binary", elf, binf], check=True)
        data = open(binf, "rb").read()
        with open(os.path.join(hex_dir, f"{t}.hex"), "w") as f:
            for i in range(0, len(data), 4):
                word = int.from_bytes(data[i:i + 4].ljust(4, b"\0"), "little")
                f.write(f"{word:08x}\n")
        print(f"  {t}.hex  ({len(data) // 4} instructions)")


if __name__ == "__main__":
    main()
