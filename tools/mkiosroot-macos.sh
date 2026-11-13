#!/bin/bash
# Variante macOS de tools/mkiosroot.sh (Linux) : même disque iOS, mêmes ajouts,
# mais macOS monte les images APFS de l'IPSW nativement (pas d'apfs-fuse) et
# crée le HFS+ avec hdiutil. Gardée séparée de la version Linux car les outils
# de montage/formatage n'ont rien en commun. Applique aussi sweet-root-tweaks.py.
#
#   sudo tools/mkiosroot-macos.sh OS.dmg SYSTEMOS.dmg APPOS.dmg OUT [SIZE]   (SIZE défaut 16g)
#
# Produit OUT.sparseimage (HFS+ journalisé, sensible à la casse, volume iOSRoot).
set -euo pipefail

[[ $# -ge 4 ]] || { sed -n '2,9p' "$0"; exit 2; }
[[ $EUID == 0 ]] || { echo "À lancer avec sudo (propriétaires root/_logd/mobile à conserver)." >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
os=$1 sysos=$2 appos=$3 out=$4 size=${5:-16g}
[[ ! -e $out.sparseimage ]] || { echo "refuse d'écraser $out.sparseimage" >&2; exit 1; }
RSYNC=/opt/homebrew/bin/rsync
[[ -x $RSYNC ]] || { echo "rsync GNU requis : brew install rsync" >&2; exit 1; }

work=$(mktemp -d /private/tmp/iosroot.XXXXXX)
mounts=()
cleanup() {
	for m in "${mounts[@]}"; do hdiutil detach -quiet "$m" 2>/dev/null || hdiutil detach -force -quiet "$m" 2>/dev/null || true; done
	rmdir "$work"/* "$work" 2>/dev/null || true
}
trap cleanup EXIT

# Images de l'IPSW : l'OS est un UDIF, les cryptex sont de l'APFS brut.
attach_ro() {
	mkdir "$work/$2"
	hdiutil attach -quiet -nobrowse -readonly -noverify -noautofsck -owners on -mountpoint "$work/$2" "$1" 2>/dev/null ||
		hdiutil attach -quiet -nobrowse -readonly -noverify -noautofsck -owners on -mountpoint "$work/$2" \
			-imagekey diskimage-class=CRawDiskImage "$1"
	mounts+=("$work/$2")
}
attach_ro "$os" os
attach_ro "$sysos" sysos
attach_ro "$appos" appos

hdiutil create -quiet -size "$size" -type SPARSE -fs "Case-sensitive Journaled HFS+" -volname iOSRoot "$out"
mkdir "$work/root"
hdiutil attach -quiet -nobrowse -owners on -mountpoint "$work/root" "$out.sparseimage"
mounts=("$work/root" "${mounts[@]}")
root=$work/root
mdutil -i off "$root" >/dev/null 2>&1 || true

copy() {
	echo "copie $1 -> ${2#"$root"}"
	mkdir -p "$2"
	# Lecture via le VFS : les fichiers compressés APFS sont décompressés, et sans -X
	# les attributs de compression ne suivent pas (XNU/HFS n'en a pas besoin).
	"$RSYNC" -aH --numeric-ids "$1/" "$2/"
}
copy "$work/os" "$root"
copy "$work/sysos" "$root/private/preboot/Cryptexes/OS"
copy "$work/appos" "$root/private/preboot/Cryptexes/App"

# Cache partagé là où dyld le cherche (ignition_level=1) : liens physiques.
dsc=private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
mkdir -p "$root/System/Library/Caches/com.apple.dyld"
for f in "$root/$dsc"/*; do ln "$f" "$root/System/Library/Caches/com.apple.dyld/${f##*/}"; done

# Fichiers des cryptex sans équivalent dans l'OS : liés à leur chemin racine.
for c in OS App; do
	(cd "$root/private/preboot/Cryptexes/$c" && find . ! -type d ! -path './System/Library/Caches/com.apple.dyld/*') |
	while IFS= read -r f; do
		f=${f#./}
		if [[ ! -e $root/$f && ! -L $root/$f ]]; then
			mkdir -p "$root/$(dirname "$f")"
			ln "$root/private/preboot/Cryptexes/$c/$f" "$root/$f"
		fi
	done
done

# Magasins de logd (créés à la restauration sur un vrai appareil) : _logd = 272.
db=$root/private/var/db
install -d -o 272 -g 272 -m 0751 "$db/diagnostics"
install -d -o 272 -g 272 -m 0755 "$db/uuidtext" "$db/diagnostics/timesync"
for d in diagnostics uuidtext diagnostics/timesync; do install -o 272 -g 272 -m 0644 /dev/null "$db/$d/.migrated"; done

# Keybag système en clair pour l'AppleKeyStore intégré (pas de code).
install -d -m 0700 -o 0 -g 0 "$root/private/var/keybags"
kb=$work/systembag.kb
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' > "$kb"
install -m 0600 -o 0 -g 0 "$kb" "$root/private/var/keybags/systembag.kb"
rm -f "$kb"

python3 -I "$here/sweet-root-tweaks.py" "$root"

# Traces de macOS à ne pas laisser dans la racine iOS.
rm -rf "$root/.fseventsd" "$root/.Spotlight-V100" "$root/.Trashes"
df -h "$root"
hdiutil detach -quiet "$root"
mounts=("${mounts[@]:1}")
dev=$(hdiutil attach -nomount -nobrowse "$out.sparseimage" | awk 'NR==1{print $1}')
fsck_hfs -fy "$dev" || true
fsck_hfs -fn "$dev"
hdiutil detach -quiet "$dev"
echo "OK : $out.sparseimage"
