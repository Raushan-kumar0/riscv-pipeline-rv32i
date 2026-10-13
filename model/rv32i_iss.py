"""
rv32i_iss.py - a tiny instruction-set simulator (ISS) for RV32I.

It runs one instruction at a time with no pipeline at all, so it is easy to
trust. The random tests run the same program here and on the Verilog core and
compare the final registers and memory: any difference means the pipeline
did something wrong (a forwarding, stall or flush bug, for example).

Memory map matches the RTL simulation:
  instruction memory : 16 KB, word index = addr[13:2]
  data memory        : 16 KB, byte address wraps at 16 KB
  TOHOST             : a store to 0x3FFC ends the program
"""

MASK = 0xFFFFFFFF
TOHOST = 0x3FFC
MEM_BYTES = 16 * 1024
NOP = 0x00000013


def sext(value, bits):
    """Sign-extend a 'bits'-wide value to a Python int."""
    sign = 1 << (bits - 1)
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & sign else value


def to_signed(v):
    return sext(v, 32)


class RV32I:
    def __init__(self, program_words):
        self.imem = list(program_words)
        self.mem = bytearray(MEM_BYTES)
        self.x = [0] * 32
        self.pc = 0
        self.instret = 0

    # ---------------- memory helpers ----------------
    def _load(self, addr, size, signed):
        addr %= MEM_BYTES
        val = int.from_bytes(self.mem[addr:addr + size], "little")
        return sext(val, size * 8) & MASK if signed else val

    def _store(self, addr, size, val):
        addr %= MEM_BYTES
        self.mem[addr:addr + size] = (val & ((1 << (size * 8)) - 1)).to_bytes(size, "little")

    def word(self, addr):
        return self._load(addr, 4, False)

    def _fetch(self):
        idx = (self.pc >> 2) % (MEM_BYTES // 4)
        return self.imem[idx] if idx < len(self.imem) else NOP

    def _wr(self, rd, val):
        if rd != 0:
            self.x[rd] = val & MASK

    # ---------------- one instruction ----------------
    def step(self):
        """Execute one instruction. Returns the TOHOST code if the program ended."""
        ins = self._fetch()
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 0x7
        rs1 = (ins >> 15) & 0x1F
        rs2 = (ins >> 20) & 0x1F
        f7 = (ins >> 25) & 0x7F
        a, b = self.x[rs1], self.x[rs2]

        imm_i = sext(ins >> 20, 12)
        imm_s = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
        imm_b = sext((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                     (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        imm_u = ins & 0xFFFFF000
        imm_j = sext((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                     (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)

        next_pc = (self.pc + 4) & MASK
        tohost = None

        if op == 0x33 or op == 0x13:                       # ALU (R or I)
            y = b if op == 0x33 else imm_i & MASK
            shamt = y & 0x1F
            alt = (f7 & 0x20) != 0
            if f3 == 0:
                r = (a - y) if (op == 0x33 and alt) else (a + y)
            elif f3 == 1:
                r = a << shamt
            elif f3 == 2:
                r = int(to_signed(a) < to_signed(y))
            elif f3 == 3:
                r = int(a < y)
            elif f3 == 4:
                r = a ^ y
            elif f3 == 5:
                r = (to_signed(a) >> shamt) if alt else (a >> shamt)
            elif f3 == 6:
                r = a | y
            else:
                r = a & y
            self._wr(rd, r)
        elif op == 0x03:                                   # loads
            addr = (a + imm_i) & MASK
            size, signed = {0: (1, True), 1: (2, True), 2: (4, False),
                            4: (1, False), 5: (2, False)}[f3]
            self._wr(rd, self._load(addr, size, signed))
        elif op == 0x23:                                   # stores
            addr = (a + imm_s) & MASK
            size = {0: 1, 1: 2, 2: 4}[f3]
            if (addr & ~3) == TOHOST:
                tohost = b
            self._store(addr, size, b)
        elif op == 0x63:                                   # branches
            sa, sb = to_signed(a), to_signed(b)
            taken = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb,
                     6: a < b, 7: a >= b}.get(f3, False)
            if taken:
                next_pc = (self.pc + imm_b) & MASK
        elif op == 0x6F:                                   # JAL
            self._wr(rd, self.pc + 4)
            next_pc = (self.pc + imm_j) & MASK
        elif op == 0x67:                                   # JALR
            target = (a + imm_i) & MASK & ~1
            self._wr(rd, self.pc + 4)
            next_pc = target
        elif op == 0x37:                                   # LUI
            self._wr(rd, imm_u)
        elif op == 0x17:                                   # AUIPC
            self._wr(rd, self.pc + imm_u)
        # anything else behaves as a NOP (same as the RTL decoder)

        self.pc = next_pc
        self.instret += 1
        return tohost

    def run(self, max_steps=1_000_000):
        for _ in range(max_steps):
            code = self.step()
            if code is not None:
                return code
        raise RuntimeError("ISS: program did not finish (no TOHOST store)")


def load_hex(path):
    with open(path) as f:
        return [int(line, 16) for line in f if line.strip()]


if __name__ == "__main__":
    import sys
    sim = RV32I(load_hex(sys.argv[1]))
    code = sim.run()
    print(f"TOHOST code = {code}  instret = {sim.instret}")
    for i in range(0, 32, 4):
        print("  ".join(f"x{j:<2}={sim.x[j]:08x}" for j in range(i, i + 4)))
