import json
import pathlib
import struct
import subprocess
import sys
import tempfile


binary = str(pathlib.Path(sys.argv[1]).resolve())


def cint(value):
    return struct.pack('b', value) if -127 <= value <= 127 else b'\x80' + struct.pack('<i', value)


def wz_string(value):
    raw = value.encode('ascii')
    length = struct.pack('b', -len(raw)) if len(raw) < 128 else b'\x80' + struct.pack('<I', len(raw))
    return length + bytes(byte ^ ((0xaa + index) & 255) for index, byte in enumerate(raw))


def image(value):
    return (b'\x73' + wz_string('Property') + b'\0\0' + cint(1)
            + b'\0' + wz_string('skeleton') + b'\x08\0' + wz_string(value))


def read_nx(path):
    data = path.read_bytes()
    magic = data[:4]
    assert magic in (b'PKG4', b'PKG5'), magic
    count, nodes = struct.unpack_from('<IQ', data, 4)
    string_count, strings = struct.unpack_from('<IQ', data, 16)
    assert count == 2 and string_count >= 2
    _, _, _, kind, string_id = struct.unpack_from('<IIHHI', data, nodes + 20)
    assert kind == 3
    offset = struct.unpack_from('<Q', data, strings + string_id * 8)[0]
    prefix = '<I' if magic == b'PKG5' else '<H'
    length = struct.unpack_from(prefix, data, offset)[0]
    value = data[offset + struct.calcsize(prefix):offset + struct.calcsize(prefix) + length]
    return magic, value


with tempfile.TemporaryDirectory() as folder:
    root = pathlib.Path(folder)
    for length in (128, 65535, 65536, 131072):
        value = json.dumps({'skeleton': 'x' * (length - 15)}, separators=(',', ':'))
        assert len(value) == length
        source = root / f'{length}.img'
        source.write_bytes(image(value))
        result = subprocess.run([binary, '--client', str(source)], capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        magic, restored = read_nx(source.with_suffix('.nx'))
        assert magic == (b'PKG4' if len(value) <= 65535 else b'PKG5')
        assert restored == value.encode('ascii')
        assert json.loads(restored) == json.loads(value)
print('PASS: PKG4 and PKG5 string round trip at 128, 65535, 65536 and 131072 bytes')
