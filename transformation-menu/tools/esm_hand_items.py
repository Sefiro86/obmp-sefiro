# "Hand-held" items from the game plugins: weapons (WEAP, bows included), shields (ARMO with the shield slot) and torches
# (carriable LIGH). As a creature the character must be unarmed: with a weapon or torch in hand the game asks for
# animations (one-handed, two-handed, bow, torch) that creatures lack and the body stays frozen (deer, 2026-11-17).
# Full runtime IDs: the plugin's index in Plugins.txt in the high byte. New records of a plugin = high byte equal
# to the number of its masters; those with a lower high byte override master records and are skipped.
# Usage: python -I esm_hand_items.py   (prints the counts)
import os
import struct
import zlib

DATA = r"E:\SteamLibrary\steamapps\common\Oblivion Remastered\OblivionRemastered\Content\Dev\ObvData\Data"
COMPRESSED = 0x00040000
SHIELD = 0x2000          # biped slot 13
CARRIED = 0x2            # LIGH: "Can be carried"


def subrecords(body):
    p, out = 0, {}
    while p + 6 <= len(body):
        st = body[p:p + 4]
        ss = struct.unpack_from("<H", body, p + 4)[0]
        out.setdefault(st, body[p + 6:p + 6 + ss])
        p += 6 + ss
    return out


def walk(data, off, end, want, out):
    while off < end:
        typ = data[off:off + 4]
        size = struct.unpack_from("<I", data, off + 4)[0]
        if typ == b"GRUP":
            walk(data, off + 20, off + size, want, out)
            off += size
            continue
        flags, form = struct.unpack_from("<II", data, off + 8)
        body = data[off + 20:off + 20 + size]
        off += 20 + size
        if typ not in want:
            continue
        if flags & COMPRESSED:
            body = zlib.decompress(body[4:])
        out.append((typ, form, subrecords(body)))


def masters_and_records(path, want):
    with open(path, "rb") as f:
        data = f.read()
    hdr_size = struct.unpack_from("<I", data, 4)[0]
    hdr = subrecords(data[20:20 + hdr_size])
    # there can be more than one MAST: count them by walking the header
    masters, p, h = 0, 0, data[20:20 + hdr_size]
    while p + 6 <= len(h):
        if h[p:p + 4] == b"MAST":
            masters += 1
        p += 6 + struct.unpack_from("<H", h, p + 4)[0]
    out = []
    walk(data, 20 + hdr_size, len(data), want, out)
    return masters, out


def load_order():
    names = []
    with open(os.path.join(DATA, "Plugins.txt"), encoding="latin-1") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and os.path.exists(os.path.join(DATA, line)):
                names.append(line)
    return names


def hand_items():
    """{full runtime id: "weapon"|"shield"|"torch"}"""
    result = {}
    for index, name in enumerate(load_order()):
        masters, recs = masters_and_records(os.path.join(DATA, name), {b"WEAP", b"ARMO", b"LIGH"})
        for typ, form, sub in recs:
            if form >> 24 != masters:
                continue   # override of a master's record
            kind = None
            if typ == b"WEAP":
                kind = "weapon"
            elif typ == b"ARMO":
                b = sub.get(b"BMDT")
                if b and len(b) >= 2 and struct.unpack_from("<H", b, 0)[0] & SHIELD:
                    kind = "shield"
            elif typ == b"LIGH":
                d = sub.get(b"DATA")
                if d and len(d) >= 16 and struct.unpack_from("<I", d, 12)[0] & CARRIED:
                    kind = "torch"
            if kind:
                result[(index << 24) | (form & 0xFFFFFF)] = kind
    return result


if __name__ == "__main__":
    print("order:", ", ".join(f"{i:02X} {n}" for i, n in enumerate(load_order())))
    items = hand_items()
    from collections import Counter
    print(Counter(items.values()))
    for fid in (0x000229B5, 0x00000C0C, 0x000352C1, 0x00023923, 0x0000C0F4):
        print(hex(fid), items.get(fid))
