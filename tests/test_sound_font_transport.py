"""Run against a built converter: python tests/test_sound_font_transport.py <binary>.
No font installation or network required. Tests the actual IMG parser and NX writer.
"""
import pathlib
import struct
import subprocess
import sys
import tempfile

BINARY = str(pathlib.Path(sys.argv[1]).resolve())
try:
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
except ImportError:  # Windows
    pass

def ci(n):
    return struct.pack('b', n) if -127 <= n <= 127 else b'\x80' + struct.pack('<i', n)

def ws(s):
    b = s.encode('ascii')
    return ci(-len(b)) + bytes(c ^ ((0xaa + i) & 255) for i, c in enumerate(b))

def body(payload, header, length=None):
    return b'\x73' + ws('Sound_DX8') + b'\0' + ci(len(payload) if length is None else length) + ci(0) + header + payload

def image(properties):
    result = b'\x73' + ws('Property') + b'\0\0' + ci(len(properties))
    for name, data in properties:
        result += b'\0' + ws(name) + b'\x09' + struct.pack('<I', len(data)) + data
    return result

def read_audio(path):
    b = path.read_bytes()
    count, nodes = struct.unpack_from('<IQ', b, 4)
    _, strings = struct.unpack_from('<IQ', b, 16)
    _, audios = struct.unpack_from('<IQ', b, 40)
    result = {}
    for i in range(count):
        name, _, _, kind, idx, length = struct.unpack_from('<IIHHII', b, nodes + 20 * i)
        if kind != 6:
            continue
        pos = struct.unpack_from('<Q', b, strings + name * 8)[0]
        size = struct.unpack_from('<H', b, pos)[0]
        text = b[pos + 2:pos + 2 + size].decode()
        pos = struct.unpack_from('<Q', b, audios + idx * 8)[0]
        result[text] = b[pos:pos + length]
    return result

# Minimal, fully bounded SFNT transport fixture: one table and four data bytes.
font = bytes.fromhex('000100000001001000000000') + struct.pack('>4sIII', b'test', 0, 28, 4) + b'FONT'
prefix = bytes.fromhex('0283eb36e44f52ce119f530020af0ba7708beb36e44f52ce119f530020af0ba7700001819f580556c3ce11bf0100aa0055595a')
header70 = prefix + b'\x12' + struct.pack('<HHIIHHH', 1, 1, len(font), len(font), 1, 8, 0)
header82 = prefix + b'\x1e' + struct.pack('<HHIIHHH', 0x55, 1, 22050, 16000, 1, 0, 12) + bytes(12)
audio = b'\xff\xfb' + bytes(range(120))
with tempfile.TemporaryDirectory() as folder:
    root = pathlib.Path(folder)
    def run(name, data, ok=True):
        source = root / (name + '.img')
        source.write_bytes(data)
        result = subprocess.run([BINARY, '--client', str(source)], capture_output=True)
        assert (result.returncode == 0) == ok, (name, result.returncode, result.stdout, result.stderr)
        return source.with_suffix('.nx')
    path = run('mixed', image([('FONT_70', body(font, header70)), ('SOUND', body(audio, header82)), ('FONT_82', body(font, header82))]))
    values = read_audio(path)
    assert values == {'FONT_70': font, 'FONT_82': font, 'SOUND': header82 + audio}, values
    # Last property must work with an exact end-of-file, rather than reading 12 bytes beyond.
    assert read_audio(run('last', image([('FONT', body(font, header70))]))) == {'FONT': font}
    run('negative', image([('FONT', body(font, header70, -1))]), False)
    run('excess_payload', image([('FONT', body(font, header70, 100000))]), False)
    run('truncated_extended', image([('FONT', body(font, header70))])[:-1], False)
print('PASS: actual IMG -> NX writer: font70, font82, mixed ordinary audio, exact EOF, negative/oversize/truncated rejected')
