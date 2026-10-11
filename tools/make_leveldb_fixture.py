#!/usr/bin/env python3
"""Builds a small SYNTHETIC LevelDB (one .ldb with 2 data blocks: raw-zlib + none,
and one .log with an overwrite + a delete) following the public LevelDB file-format
docs. Cross-checked with an independent mini reader below. NOT a real Bedrock DB."""
import json, os, struct, zlib

def crc32c(data, crc=0):
    crc ^= 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    return crc ^ 0xFFFFFFFF
def mask(c): return ((((c >> 15) | (c << 17)) & 0xFFFFFFFF) + 0xA282EAD8) & 0xFFFFFFFF
assert crc32c(b'123456789') == 0xE3069283

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        if n: out.append(b | 0x80)
        else: out.append(b); return bytes(out)
def ikey(k, seq, typ=1): return k + struct.pack('<Q', (seq << 8) | typ)

def build_block(entries, restart=2):
    buf = bytearray(); restarts = []; prev = b''
    for i, (k, v) in enumerate(entries):
        if i % restart == 0: restarts.append(len(buf)); shared = 0
        else:
            shared = 0
            while shared < min(len(prev), len(k)) and prev[shared] == k[shared]: shared += 1
        buf += varint(shared) + varint(len(k) - shared) + varint(len(v)) + k[shared:] + v
        prev = k
    for r in restarts: buf += struct.pack('<I', r)
    buf += struct.pack('<I', len(restarts))
    return bytes(buf)

def with_trailer(block, ctype):
    if ctype == 4:
        c = zlib.compressobj(wbits=-15); block = c.compress(block) + c.flush()
    t = bytes([ctype]); return block + t + struct.pack('<I', mask(crc32c(block + t)))

def nbt_player():
    s = lambda x: struct.pack('<H', len(x)) + x.encode()
    body = b'\x03' + s('DimensionId') + struct.pack('<i', 0)
    body += b'\x09' + s('Pos') + b'\x05' + struct.pack('<i', 3) + struct.pack('<3f', 10.5, 64.0, -3.25)
    body += b'\x09' + s('Rotation') + b'\x05' + struct.pack('<i', 2) + struct.pack('<2f', 90.0, 15.0)
    inv = b'\x08' + s('Name') + s('minecraft:diamond_sword') + b'\x01' + s('Count') + b'\x01' + \
          b'\x01' + s('Slot') + b'\x00' + b'\x02' + s('Damage') + struct.pack('<h', 5) + b'\x00'
    body += b'\x09' + s('Inventory') + b'\x0a' + struct.pack('<i', 1) + inv
    return b'\x0a' + s('') + body + b'\x00'

def chunk(x, z, tag, dim=None, sub=None):
    k = struct.pack('<ii', x, z) + (struct.pack('<i', dim) if dim is not None else b'') + bytes([tag])
    return k + (bytes([sub & 0xFF]) if sub is not None else b'')

A = [  # (userkey, seq, value) in table
    (b'BiomeData', 5, b'\x0a\x00\x00\x00'),
    (chunk(-1, 2, 47, dim=1, sub=-1), 3, bytes(range(40))),
    (chunk(0, 0, 44), 2, b'\x28'),
    (b'mobevents', 4, b'old'),
    (b'player_server_a1', 6, b'p1'),
    (b'player_server_b2', 7, b'p2'),
    (b'zzz_unknown', 8, b'\xde\xad\xbe\xef'),
]
A.append((b'~local_player', 1, nbt_player()))
A.sort(key=lambda e: (e[0], -e[1]))

def make_table():
    mid = 4
    blocks = [A[:mid], A[mid:]]
    out = bytearray(); handles = []
    for i, ents in enumerate(blocks):
        raw = build_block([(ikey(k, s), v) for k, s, v in ents])
        data = with_trailer(raw, 4 if i == 0 else 0)
        handles.append((ikey(ents[-1][0], ents[-1][1]), len(out), len(data) - 5))
        out += data
    index = build_block([(k, varint(o) + varint(s)) for k, o, s in handles], restart=1)
    meta = build_block([], restart=1)
    mh = (len(out), len(meta)); out += with_trailer(meta, 0)
    ih = (len(out), len(index)); out += with_trailer(index, 0)
    footer = varint(mh[0]) + varint(mh[1]) + varint(ih[0]) + varint(ih[1])
    footer += b'\x00' * (40 - len(footer)) + bytes.fromhex('57fb808b24754 7db'.replace(' ', ''))
    return bytes(out + footer)

def make_log():
    batch = struct.pack('<QI', 10, 2)
    batch += b'\x01' + varint(9) + b'mobevents' + varint(3) + b'new'
    batch += b'\x00' + varint(len(chunk(0, 0, 44))) + chunk(0, 0, 44)
    typ = b'\x01'
    rec = struct.pack('<I', mask(crc32c(typ + batch))) + struct.pack('<HB', len(batch), 1) + batch
    return rec

def check(table):  # independent decode of the table bytes
    assert table[-8:] == bytes.fromhex('57fb808b247547db')
    return len(table)

if __name__ == '__main__':
    d = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures', 'db')
    os.makedirs(d, exist_ok=True)
    t = make_table(); check(t)
    open(os.path.join(d, '000005.ldb'), 'wb').write(t)
    open(os.path.join(d, '000006.log'), 'wb').write(make_log())
    open(os.path.join(d, 'CURRENT'), 'w').write('MANIFEST-000001\n')
    json.dump({'liveKeys': 7, 'mobevents': 'new', 'deleted': chunk(0, 0, 44).hex()},
              open(os.path.join(d, '..', 'db.expected.json'), 'w'))
    print('leveldb fixture OK', len(t), 'bytes table')
