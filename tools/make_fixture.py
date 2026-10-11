#!/usr/bin/env python3
"""Deterministic SYNTHETIC level.dat fixture (little-endian NBT, 8-byte header).
This is built from the format as documented by the community; it is NOT a real
Minecraft world file, so passing tests only prove self-consistency."""
import json, os, struct

def s(x):
    b = x.encode(); return struct.pack('<H', len(b)) + b
def tag(t, name, payload): return bytes([t]) + s(name) + payload
def i32(v): return struct.pack('<i', v)
def i64(v): return struct.pack('<q', v)

def build():
    body = b''
    body += tag(8, 'LevelName', s('Fixture World \u0645\u0631\u062d\u0628\u0627'))
    body += tag(3, 'GameType', i32(1))
    body += tag(3, 'Difficulty', i32(2))
    body += tag(3, 'SpawnX', i32(-12)) + tag(3, 'SpawnY', i32(64)) + tag(3, 'SpawnZ', i32(300))
    body += tag(4, 'RandomSeed', i64(-1234567890123))
    body += tag(4, 'LastPlayed', i64(1700000000))
    body += tag(3, 'StorageVersion', i32(10))
    body += tag(3, 'NetworkVersion', i32(800))
    body += tag(9, 'lastOpenedWithVersion', bytes([3]) + i32(5) + b''.join(i32(x) for x in (1, 26, 0, 0, 0)))
    body += tag(1, 'hasBeenLoadedInCreative', bytes([1]))
    body += tag(5, 'rainLevel', struct.pack('<f', 0.5))
    body += tag(10, 'experiments', tag(1, 'cavesAndCliffs', bytes([0])) + b'\x00')
    body += tag(11, 'UnknownIntArray', i32(2) + i32(7) + i32(-7))
    payload = bytes([10]) + s('') + body + b'\x00'
    return struct.pack('<II', 10, len(payload)) + payload

def parse_check(data):
    """Independent mini-reader to confirm the fixture is well-formed."""
    ver, n = struct.unpack_from('<II', data); assert n == len(data) - 8
    pos = 8
    def rs():
        nonlocal pos
        (l,) = struct.unpack_from('<H', data, pos); pos += 2
        v = data[pos:pos+l].decode(); pos += l; return v
    def payload(t):
        nonlocal pos
        sizes = {1:1,2:2,3:4,4:8,5:4,6:8}
        if t in sizes:
            fmt = {1:'<b',2:'<h',3:'<i',4:'<q',5:'<f',6:'<d'}[t]
            v = struct.unpack_from(fmt, data, pos)[0]; pos += sizes[t]; return v
        if t == 8: return rs()
        if t == 11:
            (c,) = struct.unpack_from('<i', data, pos); pos += 4
            v = list(struct.unpack_from('<%di' % c, data, pos)); pos += 4*c; return v
        if t == 9:
            et = data[pos]; pos += 1; (c,) = struct.unpack_from('<i', data, pos); pos += 4
            return [payload(et) for _ in range(c)]
        if t == 10: return comp()
        raise ValueError(t)
    def comp():
        nonlocal pos
        d = {}
        while True:
            t = data[pos]; pos += 1
            if t == 0: return d
            k = rs()
            d[k] = payload(t)
    assert data[pos] == 10; pos += 1; rs()
    r = comp(); assert pos == len(data); return ver, r

if __name__ == '__main__':
    here = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures')
    os.makedirs(here, exist_ok=True)
    data = build()
    ver, doc = parse_check(data)
    open(os.path.join(here, 'level.dat'), 'wb').write(data)
    json.dump({'headerVersion': ver, 'LevelName': doc['LevelName'], 'GameType': 1,
               'SpawnX': -12, 'RandomSeed': -1234567890123, 'keyCount': len(doc)},
              open(os.path.join(here, 'level.expected.json'), 'w'), ensure_ascii=False)
    print('fixture OK:', len(data), 'bytes;', sorted(doc))
