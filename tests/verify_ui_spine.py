import hashlib
import json
import mmap
import pathlib
import struct
import sys


expected_source = 'bd218752b8901383c58d1e374f4795527c74e1df8067bae381f0c960bfc04831'
expected = {
    '330/skeleton.json': (151072, 'f31181a295adf2b3'),
    '430/skeleton.json': (80194, 'd3958e35cf99f439'),
    '2200/skeleton.json': (103589, '7c3f9d2f0e0f7d4e'),
    '2300/skeleton.json': (201744, '1dc3f6266559b531'),
    '2400/skeleton.json': (96651, '26b4ff66a85b0fa4'),
    '2700/skeleton.json': (158455, 'b241d5faa83f3ec8'),
    '3600/skeleton.json': (109277, 'fecb9f7188664b24'),
    '5100/skeleton.json': (84301, '34a566deffd09656'),
    '6300/skeleton.json': (124623, 'bedbfbf5667f9bd5'),
    '6400/skeleton.json': (77992, 'e37fe81cce25a36d'),
    '6500/skeleton.json': (179970, '5643a08a2a5416a3'),
    '15100/skeleton.json': (128742, '1a2bd17bf7d616fc'),
    '15200/skeleton.json': (69037, '842bfd1d2d7e2f62'),
    '15400/skeleton.json': (114663, 'eef77b71de403f6b'),
    '16200/skeleton.json': (155107, '39d5926883efc1fa'),
    '16400/skeleton.json': (88113, '54bd6a6872ccba5d'),
    '17200/Lynn.json': (515357, '4d3d73c813ddda73'),
    '17500/moxuan.json': (1008135, '048c6f2881b2adf0'),
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def fnv64(data):
    value = 0xcbf29ce484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    return f'{value:016x}'


source = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
assert sha256(source) == expected_source
with output.open('rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
    assert data[:4] == b'PKG5'
    node_count, node_table = struct.unpack_from('<IQ', data, 4)
    string_count, string_table = struct.unpack_from('<IQ', data, 16)

    def get_string(identifier):
        assert identifier < string_count
        position = struct.unpack_from('<Q', data, string_table + identifier * 8)[0]
        length = struct.unpack_from('<I', data, position)[0]
        assert position + 4 + length <= len(data)
        return data[position + 4:position + 4 + length]

    def get_node(identifier):
        assert identifier < node_count
        return struct.unpack_from('<IIHHI', data, node_table + identifier * 20)

    def child(parent, name):
        _, first, count, _, _ = get_node(parent)
        for identifier in range(first, first + count):
            if get_string(get_node(identifier)[0]) == name.encode():
                return identifier
        raise AssertionError(name)

    base = 0
    for part in ('Login.img', 'ClassSelect', 'back', '1'):
        base = child(base, part)
    for path, (length, digest) in expected.items():
        identifier = base
        for part in path.split('/'):
            identifier = child(identifier, part)
        _, _, _, kind, string_id = get_node(identifier)
        assert kind == 3, path
        value = get_string(string_id)
        assert len(value) == length and fnv64(value.replace(b'\n', b' ')) == digest, path
        assert isinstance(json.loads(value), dict), path
        print(f'PASS {path} {length} {digest}')
print(f'SOURCE SHA-256 {sha256(source)}')
print(f'OUTPUT SHA-256 {sha256(output)}')
