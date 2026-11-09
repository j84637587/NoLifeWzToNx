"""Seed a valid v4 blank cache, then verify the real converter ignores it."""
import pathlib
import struct
import subprocess
import sys
import tempfile
import zlib

BINARY = str(pathlib.Path(sys.argv[1]).resolve())

def ws(text):
    data = text.encode('ascii')
    return struct.pack('b', -len(data)) + bytes(c ^ ((0xaa + i) & 255) for i, c in enumerate(data))

def cache_name(version, compressed):
    data = struct.pack('<IBBiiIiI', version, 0, 0, 4, 4, 2, 0, len(compressed)) + compressed
    first, second = 14695981039346656037, 1099511628211
    for value in data:
        first = ((first ^ value) * 1099511628211) & 0xffffffffffffffff
        second = ((second ^ value) * 14029467366897019727) & 0xffffffffffffffff
    return f'{first:016x}{second:016x}.bin'

def decode(block):
    result = bytearray()
    pos = 0
    while pos < len(block):
        token = block[pos]; pos += 1
        length = token >> 4
        if length == 15:
            while True:
                extra = block[pos]; pos += 1; length += extra
                if extra != 255: break
        result += block[pos:pos + length]; pos += length
        if pos == len(block): break
        offset = struct.unpack_from('<H', block, pos)[0]; pos += 2
        length = token & 15
        if length == 15:
            while True:
                extra = block[pos]; pos += 1; length += extra
                if extra != 255: break
        for _ in range(length + 4): result.append(result[-offset])
    return bytes(result)

def bitmap(path):
    data = path.read_bytes()
    count, table = struct.unpack_from('<IQ', data, 28)
    assert count == 1
    offset = struct.unpack_from('<Q', data, table)[0]
    size = struct.unpack_from('<I', data, offset)[0]
    return decode(data[offset + 4:offset + 4 + size])

with tempfile.TemporaryDirectory() as folder:
    root = pathlib.Path(folder)
    pixels = bytes(range(1, 65))
    compressed = zlib.compress(pixels)
    canvas = b'\x73' + ws('Canvas') + b'\0\0' + b'\x04\x04\x02\0' + struct.pack('<II', 0, len(compressed)) + b'\0' + compressed
    image = b'\x73' + ws('Property') + b'\0\0\x01\0' + ws('atlas') + b'\x09' + struct.pack('<I', len(canvas)) + canvas
    source = root / 'legacy.img'; source.write_bytes(image)
    cache = root / '.NoLifeWzToNx.cache'; cache.mkdir()
    blank = b'\xf0\x31' + bytes(64)  # Valid LZ4 literal block, valid CRC, wrong pixels.
    stale = cache / cache_name(4, compressed)
    stale.write_bytes(struct.pack('<III', 0x32434c4e, len(blank), zlib.crc32(blank)) + blank)
    def run():
        result = subprocess.run([BINARY, str(source), '-c', '--threads', '1'], capture_output=True)
        assert result.returncode == 0, (result.stdout, result.stderr)
        return result.stdout.decode(errors='replace')
    first = run()
    output = source.with_suffix('.nx')
    assert bitmap(output) == pixels, 'Old v4 blank cache was reused instead of decoding the source'
    assert 'cache hits: 0' in first
    assert stale.exists(), 'Unrelated/old cache files must not be deleted'
    assert (cache / cache_name(5, compressed)).exists(), 'New decode was not cached in v5'
    output.unlink()
    second = run()
    assert bitmap(output) == pixels and 'cache hits: 1' in second, ('Valid new cache was not reused', bitmap(output).hex(), second, [p.name for p in cache.iterdir()])
print('PASS v4 blank cache ignored, source pixels restored, v5 cache reused')
