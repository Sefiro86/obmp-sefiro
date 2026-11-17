# Creature attack damage from the TES plugin (Oblivion.esm and game plugins): CREA records, DATA subrecord.
# Oblivion DATA format (UESP, 20 bytes): type u8, combat u8, magic u8, stealth u8, soul u8, ? u8,
# health u16, ? u16, attack damage u16, 8 attributes u8. Compressed records (flag 0x00040000): u32 size + zlib.
# Command-line usage: python -I esm_creature_damage.py <file.esm> [hexadecimal formIDs...]
import struct
import sys
import zlib

COMPRESSED = 0x00040000


def walk(data, off, end, out):
    while off < end:
        typ = data[off:off + 4]
        size = struct.unpack_from("<I", data, off + 4)[0]
        if typ == b"GRUP":
            walk(data, off + 20, off + size, out)
            off += size
            continue
        flags, form = struct.unpack_from("<II", data, off + 8)
        body = data[off + 20:off + 20 + size]
        off += 20 + size
        if typ != b"CREA":
            continue
        if flags & COMPRESSED:
            body = zlib.decompress(body[4:])
        p = 0
        rec = {}
        while p + 6 <= len(body):
            st = body[p:p + 4]
            ss = struct.unpack_from("<H", body, p + 4)[0]
            rec.setdefault(st, body[p + 6:p + 6 + ss])
            p += 6 + ss
        d = rec.get(b"DATA")
        if d and len(d) >= 12:
            health = struct.unpack_from("<H", d, 6)[0]
            damage = struct.unpack_from("<H", d, 10)[0]
            name = rec.get(b"EDID", b"").rstrip(b"\0").decode("latin-1")
            out[form] = {"editorId": name, "health": health, "damage": damage, "dataSize": len(d)}


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    hdr_size = struct.unpack_from("<I", data, 4)[0]   # TES4 record at the head
    out = {}
    walk(data, 20 + hdr_size, len(data), out)
    return out


if __name__ == "__main__":
    res = read(sys.argv[1])
    print(len(res), "creatures")
    for fid in sys.argv[2:]:
        print(fid, res.get(int(fid, 16)))
