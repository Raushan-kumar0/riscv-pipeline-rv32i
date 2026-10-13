"""rv32i_disasm.py - tiny RV32I disassembler (used to label waveform plots)."""
ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
       "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]


def _sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def disasm(ins):
    if ins == 0x00000013:
        return "nop"
    op, rd, f3 = ins & 0x7F, (ins >> 7) & 0x1F, (ins >> 12) & 7
    rs1, rs2, f7 = (ins >> 15) & 0x1F, (ins >> 20) & 0x1F, ins >> 25
    d, s1, s2 = ABI[rd], ABI[rs1], ABI[rs2]
    imm_i = _sext(ins >> 20, 12)
    if op == 0x33:
        names = {0: "sub" if f7 & 0x20 else "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor",
                 5: "sra" if f7 & 0x20 else "srl", 6: "or", 7: "and"}
        return f"{names[f3]} {d},{s1},{s2}"
    if op == 0x13:
        if f3 in (1, 5):
            name = "slli" if f3 == 1 else ("srai" if f7 & 0x20 else "srli")
            return f"{name} {d},{s1},{rs2}"
        names = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
        if f3 == 0 and rs1 == 0:
            return f"li {d},{imm_i}"
        return f"{names[f3]} {d},{s1},{imm_i}"
    if op == 0x03:
        return f"{ {0:'lb',1:'lh',2:'lw',4:'lbu',5:'lhu'}.get(f3,'l?') } {d},{imm_i}({s1})"
    if op == 0x23:
        imm = _sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
        return f"{ {0:'sb',1:'sh',2:'sw'}.get(f3,'s?') } {s2},{imm}({s1})"
    if op == 0x63:
        imm = _sext((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                    (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        name = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}.get(f3, "b?")
        return f"{name} {s1},{s2},{imm:+d}"
    if op == 0x6F:
        imm = _sext((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                    (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
        return f"j {imm:+d}" if rd == 0 else f"jal {d},{imm:+d}"
    if op == 0x67:
        if rd == 0 and rs1 == 1 and imm_i == 0:
            return "ret"
        return f"jalr {d},{imm_i}({s1})"
    if op == 0x37:
        return f"lui {d},0x{ins >> 12:x}"
    if op == 0x17:
        return f"auipc {d},0x{ins >> 12:x}"
    return f".word 0x{ins:08x}"
