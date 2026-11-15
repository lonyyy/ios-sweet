#!/bin/bash
# Copie la racine iPadOS et lui réapplique sweet-root-tweaks.py (applis supprimables dans
# /Applications, démons en boucle retirés), sans repartir de l'IPSW.
#
#   sudo tools/ipados-refresh-root.sh SOURCE.sparseimage SORTIE.sparseimage
set -euo pipefail
[[ $EUID == 0 ]] || { echo "À lancer avec sudo (propriétaires des fichiers iOS à conserver)." >&2; exit 1; }
src=$1 out=$2
here=$(cd "$(dirname "$0")" && pwd)
[[ ! -e $out ]] || { echo "refuse d'écraser $out" >&2; exit 1; }
cp "$src" "$out"
mnt=$(mktemp -d /private/tmp/iosroot.XXXXXX)
hdiutil attach -quiet -nobrowse -owners on -mountpoint "$mnt" "$out"
trap 'hdiutil detach -quiet "$mnt" 2>/dev/null || true' EXIT
python3 -I "$here/sweet-root-tweaks.py" "$mnt"
rm -rf "$mnt/.fseventsd" "$mnt/.Spotlight-V100" "$mnt/.Trashes"
hdiutil detach -quiet "$mnt"; trap - EXIT
dev=$(hdiutil attach -nomount -nobrowse "$out" | awk 'NR==1{print $1}')
fsck_hfs -fy "$dev" || true
fsck_hfs -fn "$dev"
hdiutil detach -quiet "$dev"
sync
echo "OK : $out"
