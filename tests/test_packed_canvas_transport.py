"""Actual IMG -> NX packed texture transport. Run with the built converter path."""
import pathlib
import re
import struct
import subprocess
import sys
import tempfile
import zlib

BINARY = str(pathlib.Path(sys.argv[1]).resolve())
try:
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
except ImportError:
    pass

def ci(n):
    return struct.pack('b', n) if -127 <= n <= 127 else b'\x80' + struct.pack('<i', n)

KEY = bytes(65536)
def ws(s):
    b = s.encode('ascii')
    return ci(-len(b)) + bytes(c ^ ((0xaa + i) & 255) ^ KEY[i] for i, c in enumerate(b))
def properties(items):
    return ci(len(items)) + b''.join(b'\0' + ws(name) + bytes([kind]) + data for name, kind, data in items)
def extended(data):
    return struct.pack('<I', len(data)) + data

def canvas(raw, pages=1, fmt=2562, encrypted=False, child_name='origin', declared=None, fmt2=0, legacy=False, link=None, origin=(7, 9), extra_items=()):
    origin = b'\x73' + ws('Shape2D#Vector2D') + ci(origin[0]) + ci(origin[1])
    items = [(child_name, 9, extended(origin))]
    if link: items.append((link, 8, b'\0' + ws('atlas')))
    props = properties(items + list(extra_items))
    compressed = zlib.compress(raw)
    if legacy:
        stream = zlib.compressobj()
        compressed = stream.compress(raw) + stream.flush(zlib.Z_SYNC_FLUSH) + b'\x07'
    if encrypted:
        blocks = [compressed[i:i + 13] for i in range(0, len(compressed), 13)]
        compressed = b''.join(struct.pack('<I', len(b)) + bytes(x ^ KEY[i] for i, x in enumerate(b)) for b in blocks)
    return (b'\x73' + ws('Canvas') + b'\0\x01\0\0' + props + ci(4) + ci(4) + ci(fmt) + ci(fmt2) +
            struct.pack('<II', pages, len(compressed) + 1 if declared is None else declared) + b'\0' + compressed)

def image(data):
    return b'\x73' + ws('Property') + b'\0\0' + properties([('atlas', 9, extended(data))])

def lz4(block, expected):
    out = bytearray()
    pos = 0
    while pos < len(block):
        token = block[pos]
        pos += 1
        literal = token >> 4
        if literal == 15:
            while True:
                n = block[pos]; pos += 1; literal += n
                if n != 255: break
        assert pos + literal <= len(block)
        out += block[pos:pos + literal]; pos += literal
        if pos == len(block): break
        offset = struct.unpack_from('<H', block, pos)[0]; pos += 2
        assert 0 < offset <= len(out)
        match = (token & 15) + 4
        if (token & 15) == 15:
            while True:
                n = block[pos]; pos += 1; match += n
                if n != 255: break
        for _ in range(match): out.append(out[-offset])
    assert len(out) == expected
    return bytes(out)

def read(path, wanted='atlas', origin=(7, 9)):
    b = path.read_bytes()
    count, nodes = struct.unpack_from('<IQ', b, 4)
    _, strings = struct.unpack_from('<IQ', b, 16)
    raw_count, raws = struct.unpack_from('<IQ', b, 52)
    entries = []
    for i in range(count):
        name, children, n, kind, value, length = struct.unpack_from('<IIHHII', b, nodes + 20 * i)
        off = struct.unpack_from('<Q', b, strings + name * 8)[0]
        size = struct.unpack_from('<H', b, off)[0]
        entries.append((b[off + 2:off + 2 + size].decode(), children, n, kind, value, length))
    root = entries[0]
    atlas = root
    for part in wanted.split('/'):
        atlas = next(x for x in entries[atlas[1]:atlas[1] + atlas[2]] if x[0] == part)
    assert atlas[3] == 5
    children = entries[atlas[1]:atlas[1] + atlas[2]]
    entry = next(x for x in children if x[0] == 'origin')
    assert entry[3:] == (4, *origin)
    packed = next((x for x in children if x[0] == '__nx_texture'), None)
    if packed is None: return None
    assert packed[3] == 8 and packed[4] < raw_count
    offset = struct.unpack_from('<Q', b, raws + packed[4] * 8)[0]
    raw = b[offset:offset + packed[5]]
    magic, version, size, w, h, fmt, pages, codec = struct.unpack_from('<8I', raw)
    assert (magic, version, size, w, h, fmt, codec) == (0x58544350, 1, 32, 4, 4, 2562, 1)
    result = bytearray()
    for i in range(pages):
        pos, n = struct.unpack_from('<II', raw, 32 + i * 8)
        result += lz4(raw[pos:pos + n], w * h * 4)
    return bytes(result)

with tempfile.TemporaryDirectory() as folder:
    root = pathlib.Path(folder)
    def run(name, data, ok=True):
        p = root / (name + '.img'); p.write_bytes(data)
        result = subprocess.run([BINARY, str(p), '-c', '--threads', '1'], capture_output=True)
        assert (result.returncode == 0) == ok, (name, result.stdout, result.stderr)
        return p.with_suffix('.nx')
    for pages in [0, 1, 2, 20]:
        raw = b''.join(struct.pack('<I', (i * 101 + 3) & 0xffffffff) for i in range(16 * max(1, pages)))
        assert read(run('pages' + str(pages), image(canvas(raw, pages)))) == raw
    raw = b''.join(struct.pack('<I', i * 1023 + 1) for i in range(32))
    assert read(run('split-format', image(canvas(raw, 2, fmt=2, fmt2=10)))) == raw
    assert read(run('legacy-complete', image(canvas(raw, 2, legacy=True)))) == raw
    assert read(run('list-bms', image(canvas(raw, 2, encrypted=True)))) == raw
    keys = pathlib.Path(__file__).resolve().parents[1].joinpath('Keys.cpp').read_text()
    section = keys.split('key_gms[65536] = {', 1)[1].split('};', 1)[0]
    KEY = bytes(int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', section))
    assert read(run('list-gms', image(canvas(raw, 2, encrypted=True)))) == raw
    KEY = bytes(65536)
    assert read(run('ordinary', image(canvas(bytes(64), 0, 2)))) is None
    for link in ['source', '_inlink', '_outlink']:
        items = [('atlas', 9, extended(canvas(raw, 2))),
                 ('alias', 9, extended(canvas(bytes(64), 0, fmt=2, link=link, origin=(11, 13))))]
        path = run('link-' + link, b'\x73' + ws('Property') + b'\0\0' + properties(items))
        assert read(path, 'alias', (11, 13)) == raw
        # A link must replace the packed companion as well as the legacy bitmap.
        items[1] = ('alias', 9, extended(canvas(bytes(128), 2, link=link, origin=(11, 13))))
        path = run('replace-' + link, b'\x73' + ws('Property') + b'\0\0' + properties(items))
        assert read(path, 'alias', (11, 13)) == raw
        items[0] = ('atlas', 9, extended(canvas(bytes(64), 0, fmt=2)))
        path = run('legacy-target-' + link, b'\x73' + ws('Property') + b'\0\0' + properties(items))
        assert read(path, 'alias', (11, 13)) is None
    items = [('atlas', 9, extended(canvas(raw, 2))),
             ('alias', 9, extended(b'\x73' + ws('UOL') + b'\0\0' + ws('atlas')))]
    group = b'\x73' + ws('Property') + b'\0\0' + properties(items)
    # UOL is resolved within a non-root image/property boundary by this converter.
    wrapped = b'\x73' + ws('Property') + b'\0\0' + properties([('group', 9, extended(group))])
    path = run('uol', wrapped)
    assert read(path, 'group/alias') == raw
    nested = canvas(raw, 2, extra_items=[('nested', 9, extended(canvas(bytes(128), 2)))])
    path = run('nested', image(nested))
    assert read(path, 'atlas/nested') == bytes(128)
    run('missing-page', image(canvas(bytes(64), 2)), False)
    run('legacy-missing-page', image(canvas(bytes(64), 2, legacy=True)), False)
    run('legacy-extra-page', image(canvas(bytes(128), 1, legacy=True)), False)
    checksum = bytearray(image(canvas(bytes(64), 1))); checksum[-1] ^= 1
    run('bad-checksum', bytes(checksum), False)
    run('extra-page', image(canvas(bytes(128), 1)), False)
    run('truncated', image(canvas(bytes(128), 2))[:-1], False)
    run('bad-length', image(canvas(bytes(64), declared=100000)), False)
    run('collision', image(canvas(bytes(64), child_name='__nx_texture')), False)
print('PASS actual converter: 10-bit bits, 1/2/20 pages, origin, BMS/GMS encrypted blocks, legacy and malformed data')
