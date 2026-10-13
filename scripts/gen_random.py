"""
gen_random.py - random instruction generator (RIG) for the RV32I core.

Builds a random but always-terminating program:
  1. prologue : x2 = 0x1000 (data base pointer), every other register = random
  2. body     : N random instructions - ALU, loads, stores, forward branches,
                forward jumps, AUIPC+JALR pairs
  3. epilogue : store 1 to TOHOST (ends the simulation)

A small register pool is used on purpose: with only ~10 registers, almost
every instruction depends on a recent one, which hammers the forwarding,
stall and flush logic - exactly where pipeline bugs hide.

Only forward branches/jumps are generated, so the program can never loop.
Loads/stores stay inside 0x1000-0x17FF (the region the testbench dumps).
"""
import random

POOL = [1, 3, 4, 5, 6, 7, 8, 9, 10, 11]      # destination/source registers (x2 is reserved)
BASE_REG = 2
BASE_ADDR = 0x1000
TOHOST = 0x3FFC


# ------------------------------------------------------------------ encoders
def r_type(f7, rs2, rs1, f3, rd):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33


def i_type(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(imm, rs2, rs1, f3):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23


def b_type(imm, rs2, rs1, f3):
    imm &= 0x1FFF
    return ((((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) |
            (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63)


def u_type(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def j_type(imm, rd):
    imm &= 0x1FFFFF
    return ((((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) |
            (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F)


def li(rd, val):
    """lui + addi pair that loads any 32-bit constant."""
    val &= 0xFFFFFFFF
    lo = val & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((val - lo) >> 12) & 0xFFFFF
    return [(u_type(hi, rd, 0x37), f"lui x{rd}, 0x{hi:x}"),
            (i_type(lo, rd, 0, rd, 0x13), f"addi x{rd}, x{rd}, {lo}")]


R_OPS = [("add", 0, 0x00), ("sub", 0, 0x20), ("sll", 1, 0x00), ("slt", 2, 0x00),
         ("sltu", 3, 0x00), ("xor", 4, 0x00), ("srl", 5, 0x00), ("sra", 5, 0x20),
         ("or", 6, 0x00), ("and", 7, 0x00)]
I_OPS = [("addi", 0), ("slti", 2), ("sltiu", 3), ("xori", 4), ("ori", 6), ("andi", 7)]
SH_OPS = [("slli", 1, 0x00), ("srli", 5, 0x00), ("srai", 5, 0x20)]
LOADS = [("lb", 0, 1), ("lh", 1, 2), ("lw", 2, 4), ("lbu", 4, 1), ("lhu", 5, 2)]
STORES = [("sb", 0, 1), ("sh", 1, 2), ("sw", 2, 4)]
BRANCHES = [("beq", 0), ("bne", 1), ("blt", 4), ("bge", 5), ("bltu", 6), ("bgeu", 7)]


def gen_program(seed, length=300):
    """Return a list of (machine_word, assembly_text) tuples."""
    rng = random.Random(seed)
    prog = []

    def rd():
        return 0 if rng.random() < 0.05 else rng.choice(POOL)     # x0 sometimes, to test it stays 0

    def rs():
        r = rng.random()
        return 0 if r < 0.05 else BASE_REG if r < 0.10 else rng.choice(POOL)

    # ---- prologue ----
    prog += li(BASE_REG, BASE_ADDR)
    for r in range(1, 32):
        if r != BASE_REG:
            prog += li(r, rng.getrandbits(32))

    # ---- body ----
    kinds = ["r", "i", "shift", "load", "store", "branch", "jal", "jalr", "lui", "auipc"]
    weights = [26, 16, 8, 15, 12, 12, 3, 3, 3, 2]
    body = []
    targets = set()        # body indexes that some branch/jump lands on
    while len(body) < length:
        left = length - len(body)                  # slots still available for jump targets
        k = rng.choices(kinds, weights)[0]
        if k == "r":
            name, f3, f7 = rng.choice(R_OPS)
            d, s1, s2 = rd(), rs(), rs()
            body.append((r_type(f7, s2, s1, f3, d), f"{name} x{d}, x{s1}, x{s2}"))
        elif k == "i":
            name, f3 = rng.choice(I_OPS)
            d, s1, imm = rd(), rs(), rng.randint(-2048, 2047)
            body.append((i_type(imm, s1, f3, d, 0x13), f"{name} x{d}, x{s1}, {imm}"))
        elif k == "shift":
            name, f3, f7 = rng.choice(SH_OPS)
            d, s1, sh = rd(), rs(), rng.randint(0, 31)
            body.append((i_type((f7 << 5) | sh, s1, f3, d, 0x13), f"{name} x{d}, x{s1}, {sh}"))
        elif k == "load":
            name, f3, size = rng.choice(LOADS)
            d = rng.choice(POOL)                   # never overwrite the base pointer
            off = rng.randrange(0, 0x800, size)
            body.append((i_type(off, BASE_REG, f3, d, 0x03), f"{name} x{d}, {off}(x{BASE_REG})"))
        elif k == "store":
            name, f3, size = rng.choice(STORES)
            s2 = rs()
            off = rng.randrange(0, 0x800, size)
            body.append((s_type(off, s2, BASE_REG, f3), f"{name} x{s2}, {off}(x{BASE_REG})"))
        elif k == "branch" and left >= 2:
            name, f3 = rng.choice(BRANCHES)
            s1, s2 = rs(), rs()
            skip = rng.randint(1, min(3, left - 1))
            off = (skip + 1) * 4
            targets.add(len(body) + skip + 1)
            body.append((b_type(off, s2, s1, f3), f"{name} x{s1}, x{s2}, .+{off}"))
        elif k == "jal" and left >= 2:
            d = rd()
            skip = rng.randint(1, min(3, left - 1))
            off = (skip + 1) * 4
            targets.add(len(body) + skip + 1)
            body.append((j_type(off, d), f"jal x{d}, .+{off}"))
        elif k == "jalr" and left >= 3 and (len(body) + 1) not in targets:
            # auipc rt, 0 ; jalr rd, 12(rt)  -> jumps over exactly one instruction.
            # Nothing may jump straight onto the jalr (rt would be stale), hence the check.
            rt, d = rng.choice(POOL), rd()
            targets.add(len(body) + 3)
            body.append((u_type(0, rt, 0x17), f"auipc x{rt}, 0"))
            body.append((i_type(12, rt, 0, d, 0x67), f"jalr x{d}, 12(x{rt})"))
        elif k == "lui":
            d, imm = rd(), rng.getrandbits(20)
            body.append((u_type(imm, d, 0x37), f"lui x{d}, 0x{imm:x}"))
        elif k == "auipc":
            d, imm = rd(), rng.getrandbits(20)
            body.append((u_type(imm, d, 0x17), f"auipc x{d}, 0x{imm:x}"))
    prog += body

    # ---- epilogue: PASS ----
    prog += li(5, 1)
    prog += li(6, TOHOST)
    prog.append((s_type(0, 5, 6, 2), "sw x5, 0(x6)"))
    prog.append((j_type(0, 0), "jal x0, .+0"))
    return prog


def write_hex(prog, path):
    with open(path, "w") as f:
        for word, _ in prog:
            f.write(f"{word:08x}\n")


def write_asm(prog, path):
    with open(path, "w") as f:
        f.write("    .section .text.init\n    .globl _start\n_start:\n")
        for _, text in prog:
            f.write(f"    {text}\n")


if __name__ == "__main__":
    import sys
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    p = gen_program(seed)
    write_hex(p, f"random_{seed}.hex")
    write_asm(p, f"random_{seed}.S")
    print(f"wrote random_{seed}.hex / .S ({len(p)} instructions)")
