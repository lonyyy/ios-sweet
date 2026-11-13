#!/usr/bin/env python3
"""Extrait la charge utile d'un conteneur Apple IM4P (DER), décompressée si LZFSE (bvx2).
Usage : im4p-extract.py IN.im4p OUT"""
import ctypes, sys

def tlv(b, i):
    tag = b[i]; n = b[i + 1]; i += 2
    if n & 0x80:
        k = n & 0x7f; n = int.from_bytes(b[i:i + k], 'big'); i += k
    return tag, i, n

def payload(d):
    tag, i, n = tlv(d, 0); assert tag == 0x30, "pas un IM4P"
    fields, end = [], i + n
    while i < end:
        t, j, m = tlv(d, i); fields.append((t, d[j:j + m])); i = j + m
    assert fields[0][1] == b'IM4P' and fields[3][0] == 0x04
    return fields[1][1].decode(), fields[3][1]

def lzfse(src, cap=64 << 20):
    lib = ctypes.CDLL('/usr/lib/libcompression.dylib')
    f = lib.compression_decode_buffer
    f.restype = ctypes.c_size_t
    f.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
    dst = ctypes.create_string_buffer(cap)
    n = f(dst, cap, src, len(src), None, 0x801)   # COMPRESSION_LZFSE
    assert n > 0, "échec LZFSE"
    return dst.raw[:n]

if __name__ == '__main__':
    kind, data = payload(open(sys.argv[1], 'rb').read())
    if data[:4] == b'bvx2':
        data = lzfse(data)
    open(sys.argv[2], 'wb').write(data)
    print(f"{sys.argv[2]} : type {kind}, {len(data)} octets")
