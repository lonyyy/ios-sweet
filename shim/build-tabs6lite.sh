#!/bin/bash
# Tab S6 Lite (SM-P613) : compile le shim ios-sweet (avec chargeur XNU) et
# l'emballe dans un boot.img v2 construit sur la sauvegarde stock (en-tête, dtb).
# Usage : build-tabs6lite.sh [payload.bin]
set -euo pipefail
cd "$(dirname "$0")"
X=aarch64-elf-
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
SRCS="start.S shim.c console.c mmu.c fdt.c loader.c ufs.c osm.c"
mkdir -p out
for f in $SRCS; do ${X}gcc $CFLAGS -c $f -o out/${f%.*}.o; done
abs=$(${X}readelf -r out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o out/osm.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "erreur : $abs relocations absolues" >&2; exit 1; }
objs=$(for f in $SRCS; do printf 'out/%s.o ' "${f%.*}"; done)
${X}gcc $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N $objs -lgcc -o out/shim.elf
${X}objcopy -O binary out/shim.elf out/Image
size=$((16#$(${X}nm out/shim.elf | awk '$3=="_end"{print $1}')))
truncate -s "$size" out/Image
STOCK=$(ls -d ../../recon-*/backup/boot.img | tail -1)
python3 -I mkboot.py "$STOCK" out/Image out/shim-boot.img ${1:+--ramdisk "$1"}
shasum -a 256 out/shim-boot.img
