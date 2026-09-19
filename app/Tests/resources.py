"""Reject damaged PNG resources, including files that still expose valid dimensions."""
from pathlib import Path
import struct
import sys
import zlib


def validate_png(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'{path}: invalid PNG signature'
    offset = 8
    compressed = bytearray()
    ended = False
    while offset < len(data):
        assert offset + 12 <= len(data), f'{path}: truncated chunk header'
        length = struct.unpack_from('>I', data, offset)[0]
        end = offset + 12 + length
        assert end <= len(data), f'{path}: truncated chunk payload'
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        expected = struct.unpack_from('>I', data, end - 4)[0]
        assert zlib.crc32(kind + payload) == expected, f'{path}: corrupt {kind!r} chunk'
        if kind == b'IDAT':
            compressed.extend(payload)
        offset = end
        if kind == b'IEND':
            assert length == 0 and offset == len(data), f'{path}: invalid PNG ending'
            ended = True
            break
    assert ended and compressed, f'{path}: missing image data or IEND'
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(compressed)
    assert pixels and decoder.eof and not decoder.unused_data, f'{path}: incomplete image stream'
    print(f'PASS: Complete PNG with valid checksums: {path.name}')


if __name__ == '__main__':
    paths = [Path(p) for p in sys.argv[1:]] or sorted((Path(__file__).resolve().parents[1] / 'Resources').glob('*.png'))
    assert paths, 'No PNG resources found'
    for path in paths:
        validate_png(path)
