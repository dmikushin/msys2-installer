#!/usr/bin/bash
# Installs the product packages bundled by mkinstaller, with the target's own
# pacman, so that their install scriptlets and alpm hooks run natively.
# The installer runs it once after unpacking, from a login shell (which has
# already initialised the pacman keyring through /etc/post-install).
#
# Next to this script:
#   bundle.txt    package files in /var/cache/pacman/pkg, one per line
#   explicit.txt  package names the product asked for; the rest are dependencies
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cachedir=/var/cache/pacman/pkg

mapfile -t files < <(sed "s|^|$cachedir/|" "$here/bundle.txt")
mapfile -t explicit < "$here/explicit.txt"

if [ "${#files[@]}" -gt 0 ]; then
  pacman -U --noconfirm --needed "${files[@]}"
fi

mapfile -t names < <(pacman -Qq -p "${files[@]}")
mapfile -t deps < <(printf '%s\n' "${names[@]}" | grep -vxF -f "$here/explicit.txt" || true)
if [ "${#deps[@]}" -gt 0 ]; then
  pacman -D --asdeps "${deps[@]}" > /dev/null
fi
if [ "${#explicit[@]}" -gt 0 ]; then
  pacman -D --asexplicit "${explicit[@]}" > /dev/null
fi
