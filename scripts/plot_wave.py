"""
plot_wave.py - turns build/wave.vcd (from `run.py wave hazard_test`) into two
annotated pictures of the pipeline at work:

  docs/waveform_load_use_stall.png   first load-use stall (freeze + bubble + forward)
  docs/waveform_jalr_flush.png       load -> jalr: stall, then jump and flush

Usage:  python scripts/run.py wave hazard_test
        python scripts/plot_wave.py
Needs:  matplotlib  (pip install matplotlib)
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                        # noqa: E402
from matplotlib.patches import Polygon, Rectangle      # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from rv32i_disasm import disasm                        # noqa: E402

CORE = "tb_soc.dut.u_core."
SIGNALS = ["pc", "if_id_instr", "if_id_valid", "id_ex_pc", "id_ex_valid", "stall", "redirect"]


def read_cycles(vcd_path):
    """Return a list of (start_ns, end_ns, {signal: int}) - the value held during each clock cycle."""
    ids, scope, changes, t = {}, [], [], 0
    timescale_ps = 1
    lines = open(vcd_path).read().split("\n")
    for i, line in enumerate(lines):
        s = line.split()
        if not s:
            continue
        if s[0] == "$timescale":
            unit = (s[1] if len(s) > 1 and s[1] != "$end" else lines[i + 1].split()[0])
            timescale_ps = {"1ps": 1, "1ns": 1000, "10ps": 10, "100ps": 100}.get(unit, 1)
        elif s[0] == "$scope":
            scope.append(s[2])
        elif s[0] == "$upscope":
            scope.pop()
        elif s[0] == "$var":
            path = ".".join(scope + [s[4]])
            if path == "tb_soc.clk":
                ids[s[3]] = "clk"
            elif path.startswith(CORE) and path[len(CORE):] in SIGNALS:
                ids[s[3]] = s[4]
        elif s[0].startswith("#"):
            t = int(s[0][1:]) * timescale_ps / 1000.0
        elif s[0][0] in "01xz" and len(s) == 1 and s[0][1:] in ids:
            changes.append((t, ids[s[0][1:]], s[0][0]))
        elif s[0][0] == "b" and len(s) == 2 and s[1] in ids:
            changes.append((t, ids[s[1]], s[0][1:]))

    cycles, cur, prev_clk, last_edge = [], {}, "0", None
    for tt, name, v in changes:
        if name == "clk":
            if prev_clk == "0" and v == "1":
                if last_edge is not None:
                    vals = {k: int(x, 2) if set(x) <= {"0", "1"} else 0 for k, x in cur.items()}
                    cycles.append((last_edge, tt, vals))
                last_edge = tt
            prev_clk = v
        else:
            cur[name] = v
    return cycles


def load_program(hex_path):
    with open(hex_path) as f:
        return [int(x, 16) for x in f if x.strip()]


def instr_at(prog, addr):
    i = addr // 4
    return disasm(prog[i]) if 0 <= i < len(prog) else "?"


# ---------------------------------------------------------------- drawing helpers
LANES = ["clk", "IF  (pc)", "ID  (decode)", "EX  (execute)", "stall", "redirect"]
LANE_Y = {name: len(LANES) - 1 - i for i, name in enumerate(LANES)}
H = 0.32                                                  # half height of a lane


def bus_box(ax, x0, x1, y, text, face="#ffffff", edge="#2b5d9b", color="#111111", weight="normal"):
    s = 0.6
    pts = [(x0, y), (x0 + s, y + H), (x1 - s, y + H), (x1, y), (x1 - s, y - H), (x0 + s, y - H)]
    ax.add_patch(Polygon(pts, closed=True, facecolor=face, edgecolor=edge, lw=1.2))
    ax.text((x0 + x1) / 2, y, text, ha="center", va="center", fontsize=8.3, color=color,
            family="monospace", weight=weight)


def bit_wave(ax, cycles, key, y, color):
    xs, ys = [], []
    for (a, b, v) in cycles:
        level = y - H + (2 * H if v.get(key, 0) else 0)
        xs += [a, b]
        ys += [level, level]
    ax.plot(xs, ys, color=color, lw=2.2, drawstyle="steps-post")


def clock_wave(ax, cycles, y):
    xs, ys = [], []
    for (a, b, _) in cycles:
        m = (a + b) / 2
        xs += [a, a, m, m, b]
        ys += [y - H, y + H, y + H, y - H, y - H]
    ax.plot(xs, ys, color="#555555", lw=1.4)


def draw(cycles, prog, title, notes, highlights, marks, out_path):
    t0, t1 = cycles[0][0], cycles[-1][1]
    fig, ax = plt.subplots(figsize=(13, 6.0), dpi=150)
    fig.subplots_adjust(left=0.1, right=0.985, top=0.9, bottom=0.27)
    ax.set_xlim(t0 - 1, t1 + 1)
    ax.set_ylim(-0.6, len(LANES) - 0.35)

    for (a, b, color, label) in highlights:
        ax.add_patch(Rectangle((a, -0.6), b - a, len(LANES) - 0.05, facecolor=color, alpha=0.18, lw=0))
        ax.text((a + b) / 2, len(LANES) - 0.48, label, ha="center", va="bottom", fontsize=8.5,
                color=color, weight="bold")

    clock_wave(ax, cycles, LANE_Y["clk"])
    prev_redirect = False
    prev_id_flushed = False
    for (a, b, v) in cycles:
        bus_box(ax, a, b, LANE_Y["IF  (pc)"], f"0x{v['pc']:x}")
        flushed = prev_redirect
        if v.get("if_id_valid", 1):
            bus_box(ax, a, b, LANE_Y["ID  (decode)"], disasm(v["if_id_instr"]))
        else:
            bus_box(ax, a, b, LANE_Y["ID  (decode)"], "flushed" if flushed else "empty",
                    face="#fde2e2" if flushed else "#eeeeee", edge="#b3261e" if flushed else "#999999",
                    color="#b3261e" if flushed else "#666666", weight="bold")
        if v.get("id_ex_valid", 1):
            bus_box(ax, a, b, LANE_Y["EX  (execute)"], instr_at(prog, v["id_ex_pc"]))
        else:
            ex_flushed = flushed or prev_id_flushed
            bus_box(ax, a, b, LANE_Y["EX  (execute)"], "flushed" if ex_flushed else "bubble",
                    face="#fde2e2" if ex_flushed else "#eeeeee", edge="#b3261e" if ex_flushed else "#999999",
                    color="#b3261e" if ex_flushed else "#555555", weight="bold")
        prev_id_flushed = flushed and not v.get("if_id_valid", 1)
        prev_redirect = bool(v.get("redirect", 0))
    bit_wave(ax, cycles, "stall", LANE_Y["stall"], "#d9822b")
    bit_wave(ax, cycles, "redirect", LANE_Y["redirect"], "#2b5d9b")

    ax.set_yticks([LANE_Y[n] for n in LANES])
    ax.set_yticklabels(LANES, family="monospace", fontsize=9.5)
    ax.set_xticks([a for (a, _, _) in cycles] + [t1])
    ax.set_xticklabels([f"{x:g}" for x in [a for (a, _, _) in cycles] + [t1]], fontsize=8.5)
    ax.set_xlabel("simulation time (ns)  -  one box = one clock cycle", fontsize=9)
    for spine in ("top", "right", "left"):
        ax.spines[spine].set_visible(False)
    ax.tick_params(axis="y", length=0)
    ax.grid(axis="x", color="#dddddd", lw=0.8)
    ax.set_title(title, fontsize=12, weight="bold", loc="left")
    # small labels just under a lane, e.g. "PC held"
    for (idx, lane, text, color, *span) in marks:
        a = cycles[idx][0]
        b = cycles[idx + (span[0] if span else 1) - 1][1]
        ax.text((a + b) / 2, LANE_Y[lane] - 0.5, text, ha="center", va="center",
                fontsize=8, color=color, style="italic")
    for i, n in enumerate(notes):
        fig.text(0.1, 0.125 - 0.042 * i, n, fontsize=9.5, va="center", color="#222222")
    fig.savefig(out_path, facecolor="white")
    plt.close(fig)
    print(f"wrote {os.path.relpath(out_path, ROOT)}")


def window(cycles, center_idx, before, after):
    return cycles[max(0, center_idx - before): center_idx + after + 1]


def main():
    vcd = os.path.join(ROOT, "build", "wave.vcd")
    if not os.path.exists(vcd):
        sys.exit("build/wave.vcd not found - run:  python scripts/run.py wave hazard_test")
    prog = load_program(os.path.join(ROOT, "tests", "hex", "hazard_test.hex"))
    cycles = read_cycles(vcd)
    out_dir = os.path.join(ROOT, "docs")
    os.makedirs(out_dir, exist_ok=True)

    stall_idx = [i for i, c in enumerate(cycles) if c[2].get("stall")]
    redirect_idx = [i for i, c in enumerate(cycles) if c[2].get("redirect")]

    # ---- picture 1: the first load-use stall ----
    i = stall_idx[0]
    a, b, v = cycles[i]
    load, user = instr_at(prog, v["id_ex_pc"]), disasm(v["if_id_instr"])
    draw(window(cycles, i, 2, 4), prog,
         "Load-use stall: the pipeline freezes for one cycle",
         [f"1. '{user}' (in ID) needs the value that '{load}' (in EX) only gets from memory in the next stage.",
          "2. stall = 1: the PC and the ID stage hold still for one cycle, and an empty bubble goes into EX instead.",
          f"3. Next cycle the loaded value exists, and it is forwarded straight into '{user}' in EX (no more waiting)."],
         [(a, b, "#d9822b", "stall")],
         [(2, "IF  (pc)", "same PC twice = frozen", "#b0601a", 2),
          (4, "EX  (execute)", "loaded value forwarded in", "#2b5d9b")],
         os.path.join(out_dir, "waveform_load_use_stall.png"))

    # ---- picture 2: load -> jalr (stall, then jump + flush) ----
    r = redirect_idx[0]
    s = max(x for x in stall_idx if x < r)
    sa, sb, _ = cycles[s]
    ra_, rb, rv = cycles[r]
    jump = instr_at(prog, rv["id_ex_pc"])
    target = cycles[r + 1][2]["pc"]
    win_start = max(0, s - 1)
    draw(window(cycles, s, 1, (r - s) + 3), prog,
         "Load -> jump: stall for the address, then jump and flush the wrong path",
         [f"1. '{jump}' jumps to an address that the load right before it is still reading: stall 1 cycle.",
          f"2. The jump is decided in EX (redirect = 1), and the PC moves to the target 0x{target:x}.",
          "3. The 2 instructions fetched behind the jump were on the wrong path, so both are flushed."],
         [(sa, sb, "#d9822b", "stall"), (ra_, rb, "#2b5d9b", "redirect")],
         [(s - win_start, "IF  (pc)", "same PC twice = frozen", "#b0601a", 2),
          (r - win_start, "EX  (execute)", "jump decided here", "#2b5d9b"),
          (r + 1 - win_start, "IF  (pc)", "jump target", "#2b5d9b")],
         os.path.join(out_dir, "waveform_jalr_flush.png"))


if __name__ == "__main__":
    main()
