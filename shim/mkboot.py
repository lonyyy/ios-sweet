#!/usr/bin/env python3
"""Reconstruit un boot.img v2 à partir de la sauvegarde stock : même en-tête,
même ramdisk, même dtb ; seul le noyau est remplacé par notre shim.
Usage : mkboot.py <boot_stock.img> <Image> <sortie.img> [--ramdisk payload.bin]
Avec --ramdisk, le ramdisk stock est remplacé (payload XNU pour le shim)."""
import hashlib, struct, sys

stock, image, out = sys.argv[1:4]
new_ramdisk = open(sys.argv[5], 'rb').read() if sys.argv[4:5] == ['--ramdisk'] else None
b = open(stock, 'rb').read()
assert b[:8] == b'ANDROID!' and struct.unpack_from('<I', b, 40)[0] == 2
ks, rs, ss, page = (struct.unpack_from('<I', b, o)[0] for o in (8, 16, 24, 36))
dtb_size = struct.unpack_from('<I', b, 1648)[0]
align = lambda n: (n + page - 1) // page * page
off = page
kernel_old = b[off:off + ks]; off += align(ks)
ramdisk = b[off:off + rs];    off += align(rs)
second = b[off:off + ss];     off += align(ss)
dtb = b[off:off + dtb_size]
if new_ramdisk is not None:
    ramdisk = new_ramdisk
assert dtb[:4] == b'\xd0\x0d\xfe\xed', "dtb introuvable"

kernel = open(image, 'rb').read()
hdr = bytearray(b[:1660])
struct.pack_into('<I', hdr, 8, len(kernel))
struct.pack_into('<I', hdr, 16, len(ramdisk))
sha = hashlib.sha1()
for blob in (kernel, ramdisk, second, b'', dtb):   # ordre mkbootimg v2
    sha.update(blob); sha.update(struct.pack('<I', len(blob)))
hdr[576:608] = sha.digest().ljust(32, b'\0')

pad = lambda x: x + b'\0' * (align(len(x)) - len(x))
img = pad(bytes(hdr)) + pad(kernel) + pad(ramdisk) + pad(second) + pad(dtb)
open(out, 'wb').write(img)
print(f"{out}: {len(img)} octets (shim {len(kernel)}, ramdisk {len(ramdisk)}, dtb {dtb_size})")
