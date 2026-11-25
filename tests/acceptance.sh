#!/usr/bin/env bash
# Acceptance test of mkinstaller with the examples/hello product, in wine:
#   1. build acme-hello 1.0.0 and 1.1.0, publish 1.0.0 to the update channel
#   2. mkinstaller builds the installer, fetching the channel with the licence key
#   3. the installer runs unattended in a fresh wine prefix, with the licence key
#   4. checks: install path, branded launcher/shortcuts, packages, scriptlets
#   5. publish 1.1.0; pacman -Syu in the installation must pull it over git+ssh
#   6. without the licence key the channel must refuse the update
#
#   tests/acceptance.sh [--remote URL --licence KEY --publisher KEY --known-hosts FILE]
# Without --remote, a local sshd (tests/channel-fixture.sh) plays GitHub.
# Environment: WINE (default: wine), WORK (default: ~/scratch/mkinstaller-accept).
set -euo pipefail

src=$(cd "$(dirname "$0")/.." && pwd)
WINE=${WINE:-wine}
WORK=${WORK:-$HOME/scratch/mkinstaller-accept}
remote= licence= publisher= known_hosts=
while [ $# -gt 0 ]; do
  case "$1" in
    --remote) remote=$2; shift 2 ;;
    --licence) licence=$(realpath "$2"); shift 2 ;;
    --publisher) publisher=$(realpath "$2"); shift 2 ;;
    --known-hosts) known_hosts=$(realpath "$2"); shift 2 ;;
    *) echo "$0: unknown argument $1" >&2; exit 2 ;;
  esac
done

pass=0 fail=0
check() {  # check <description> <command...>
  local what=$1; shift
  if "$@"; then echo "PASS $what"; pass=$((pass + 1)); else echo "FAIL $what"; fail=$((fail + 1)); fi
}
step() { echo; echo "=== $*"; }

mkdir -p "$WORK"
log=$WORK/logs
mkdir -p "$log"

step "channel"
if [ -z "$remote" ]; then
  remote=$("$src/tests/channel-fixture.sh" start "$WORK/fixture")
  licence=$WORK/fixture/licence.key publisher=$WORK/fixture/publisher.key known_hosts=$WORK/fixture/known_hosts
  trap '"$src/tests/channel-fixture.sh" stop "$WORK/fixture"' EXIT
fi
echo "remote=$remote"

step "product packages"
rm -rf "$WORK/pkg" "$WORK/repo-1.0.0" "$WORK/repo-1.1.0"
for v in 1.0.0 1.1.0; do
  mkdir -p "$WORK/pkg/$v" "$WORK/repo-$v"
  cp "$src/examples/hello/pkg/"* "$WORK/pkg/$v/"
  (cd "$WORK/pkg/$v" && HELLO_VERSION=$v PKGDEST="$WORK/repo-$v" makepkg --nodeps --noconfirm > "$log/makepkg-$v.log" 2>&1)
done
ls "$WORK"/repo-*/

step "product config"
prod=$WORK/product
rm -rf "$prod"
cp -r "$src/examples/hello" "$prod"
rm -rf "$prod/pkg"
python3 - "$prod/product.toml" "$remote" "$licence" "${known_hosts:-}" <<'EOF'
import re, sys
path, remote, licence, known_hosts = sys.argv[1:]
s = open(path).read()
s = re.sub(r'^remote = .*$', f'remote = "{remote}"', s, flags=re.M)
s = re.sub(r'^build_key = .*$', f'build_key = "{licence}"', s, flags=re.M)
if known_hosts:
    s = re.sub(r'^# known_hosts = .*$', f'known_hosts = "{known_hosts}"', s, flags=re.M)
open(path, "w").write(s)
EOF
grep -E '^(remote|build_key|known_hosts) =' "$prod/product.toml"

step "publish 1.0.0"
"$src/mkinstaller" publish "$prod/product.toml" "$WORK/repo-1.0.0" v1.0.0 \
  --push-key "$publisher" ${known_hosts:+--known-hosts "$known_hosts"} 2>&1 | tee "$log/publish-1.0.0.log" | tail -3

step "build installer"
"$src/mkinstaller" build "$prod/product.toml" --wine "$WINE" 2>&1 | tee "$log/build.log" | tail -5
setup=$prod/out/acme-hello-1.0.0-setup.exe
check "installer exists" test -s "$setup"

step "install in a fresh wine prefix"
export WINEPREFIX=$WORK/wineprefix WINEDEBUG=-all
# No host integration: winemenubuilder would put the shortcuts into the host desktop menus.
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
rm -rf "$WINEPREFIX"
"$WINE" wineboot -i > "$log/wineboot.log" 2>&1
users=$WINEPREFIX/drive_c/users/$USER
# Keep Desktop & co inside the prefix instead of symlinks to the host's folders.
for d in "$users"/*; do
  if [ -L "$d" ]; then rm "$d"; mkdir "$d"; fi
done
cp "$licence" "$WORK/licence.key"
(cd "$log" && "$WINE" "$setup" install --confirm-command --accept-messages --accept-licenses \
  LicenseKeyFile="Z:${WORK//\//\\}\\licence.key" > "$log/install.log" 2>&1) || true

root=$WINEPREFIX/drive_c/AcmeHello
wbash() { (cd "$root" && "$WINE" usr/bin/bash.exe --login -c "$1" < /dev/null 2>> "$log/wbash.err"); }
check "installed into C:/AcmeHello" test -f "$root/usr/bin/msys-2.0.dll"
check "branded launcher exe" test -f "$root/acme-hello.exe"
check "launcher ini selects UCRT64 and the product" grep -qx 'MSYS2_PRODUCT=acme-hello' "$root/acme-hello.ini"
check "launcher icon" cmp -s "$root/acme-hello.ico" "$src/examples/hello/assets/acme.ico"
check "launcher title is the product terminal" grep -qa "Acme Hello Terminal" <(strings -el "$root/acme-hello.exe")
desktop_lnk=$users/Desktop/"Acme Hello Terminal.lnk"
check "desktop shortcut 'Acme Hello Terminal'" test -f "$desktop_lnk"
check "desktop shortcut targets acme-hello.exe" grep -qa 'acme-hello.exe' <(strings -a "$desktop_lnk"; strings -el "$desktop_lnk")
check "start menu shortcut" test -n "$(find "$WINEPREFIX/drive_c" -path '*Start Menu*' -name 'Acme Hello Terminal.lnk' -print -quit)"
check "uninstaller" test -f "$root/uninstall.exe"
check "licence key installed" cmp -s "$root/etc/pacman.d/git-xfer/acme.key" "$licence"
check "product repo in pacman.conf" grep -qx '\[acme\]' "$root/etc/pacman.conf"

q=$(wbash 'pacman -Q acme-hello tree' || true)
echo "$q"
check "acme-hello 1.0.0 installed by pacman" grep -qx 'acme-hello 1.0.0-1' <<< "$q"
check "dependency tree installed" grep -q '^tree ' <<< "$q"
check "git and openssh for the update channel" test -f "$root/usr/bin/git.exe" -a -f "$root/usr/bin/ssh.exe"
check "tree marked as dependency" grep -qi 'as a dependency' <<< "$(wbash 'pacman -Qi tree | grep "Install Reason"')"
check "scriptlet ran natively" grep -qx '1.0.0-1' "$root/etc/acme-hello.scriptlet"
check "acme-hello runs" grep -qx 'Acme Hello 1.0.0' <<< "$(wbash 'acme-hello')"

step "publish 1.1.0 and update with pacman"
"$src/mkinstaller" publish "$prod/product.toml" "$WORK/repo-1.1.0" v1.1.0 \
  --push-key "$publisher" ${known_hosts:+--known-hosts "$known_hosts"} 2>&1 | tee "$log/publish-1.1.0.log" | tail -1
# Product update only: a full -Syu would also pull whatever MSYS2 released
# since the base archive, which makes the test depend on the day it runs.
wbash 'pacman -Sy --noconfirm 2>&1 && pacman -Qu 2>&1' > "$log/update-check.log" || true
check "pacman -Qu offers acme-hello 1.1.0 from the channel" grep -q '^acme-hello 1.0.0-1 -> 1.1.0-1' "$log/update-check.log"
wbash 'pacman -S --noconfirm acme-hello 2>&1' > "$log/update.log" || true
check "pacman updated acme-hello to 1.1.0 over git+ssh" grep -qx 'acme-hello 1.1.0-1' <<< "$(wbash 'pacman -Q acme-hello')"
check "upgrade scriptlet ran" grep -qx '1.1.0-1' "$root/etc/acme-hello.scriptlet"
check "acme-hello 1.1.0 runs" grep -qx 'Acme Hello 1.1.0' <<< "$(wbash 'acme-hello')"

step "no licence, no updates"
mv "$root/etc/pacman.d/git-xfer/acme.key" "$WORK/acme.key.removed"
wbash 'pacman -Sy 2>&1' > "$log/nolicence.log" && nolic=0 || nolic=$?
cat "$log/nolicence.log" | tail -3
check "pacman -Sy fails without the licence key" test "$nolic" -ne 0
check "failure names the missing licence key" grep -q 'licence key /etc/pacman.d/git-xfer/acme.key' "$log/nolicence.log"
mv "$WORK/acme.key.removed" "$root/etc/pacman.d/git-xfer/acme.key"

echo
echo "total=$((pass + fail)) passed=$pass failed=$fail logs=$log"
[ "$fail" -eq 0 ]
