# CLAUDE.md

Guidance for coding agents working in this repository. Read `README.md`
first: it is the user documentation and the specification of the behaviour.

## What this is

A fork of `msys2/msys2-installer` turned into `mkinstaller`, a constructor of
branded Windows installers for products shipped as pacman packages on top of
MSYS2. The fork's work lives on the branch `constructor`; `main` follows
upstream. The upstream release scripts (`make-msys2-installer`,
`create-sfx.sh`, CI) were removed on `constructor`, not adapted.

## Layout

| path | role |
| --- | --- |
| `mkinstaller` | the build tool (Python 3.11+, stdlib only): `build` and `publish` |
| `qt-ifw/` | Qt IFW template; `@...@` placeholders are filled by `mkinstaller` (`make_ifw_tree`) |
| `launcher/` | msys2-launcher sources (imported from msys2/msys2-launcher@d83aab4), patched to take the product name from a generated `product.h` |
| `runtime/pacman-git-xfer` | pacman `XferCommand` serving `git+ssh://<remote>#<ref>/<file>`; runs on the target and on the build host |
| `runtime/firstrun.sh` | runs once on the target: installs the bundled packages with the target's pacman |
| `runtime/github_known_hosts` | GitHub host keys (from `https://api.github.com/meta`) |
| `examples/hello/` | example product, used by the acceptance test |
| `tests/acceptance.sh` | end-to-end test in wine |
| `tests/channel-fixture.sh` | local sshd standing in for a GitHub repository with deploy keys |
| `tests/wine/` | wine defects that break MSYS2, reproducer and patch |

## Design decisions (do not undo without a reason that beats these)

- **Install with the target's pacman, not by unpacking on the host.** The
  host only resolves and downloads (`pacman -Sw`/`-Sp` as fake root via
  `unshare -r`); `firstrun.sh` runs `pacman -U` on the target so install
  scriptlets and alpm hooks run natively.
- **Updates are git refs, not GitHub release assets.** Release assets of a
  private repository need the REST API and a token; an SSH deploy key gives
  git access only. The owner chose git+ssh with a deploy key as licence.
  A release is a parentless commit holding a complete pacman repository,
  tagged with the release name, with the channel branch pointing at it.
- **No MSYS2 core packages in the bundle.** A transaction that replaces
  pacman hangs in the fork of its own hooks (reproduced under wine, see
  `tests/wine/README.md`). The build refuses core packages (`MSYS2_CORE`
  in `mkinstaller`) and asks for a newer base archive. An option to bundle
  base upgrades existed and was removed for this reason.
- **ssh is isolated from the user's configuration**: `ssh -F none -i <key>
  -o IdentitiesOnly=yes`, so that an agent key or a ControlMaster session
  never stands in for the licence key. Paths in `GIT_SSH_COMMAND` are shell
  quoted (`printf %q`, `shlex.quote`).

## Testing

- Every behaviour change must be checked with `tests/acceptance.sh`; it
  prints `total= passed= failed=` and keeps logs in `$WORK/logs`. A full
  run takes several minutes, most of it in wine.
- wine must carry `tests/wine/grow-thread-stack-rw.patch` (or upstream
  commit 17e0faed). With wine 11.16 to 11.22 unpatched, every MSYS2
  fork+exec fails with "Bad address" and nothing works. Check a wine build
  with `tests/wine/stackprobe.c` first; it takes seconds.
- MSYS2 under wine prints `Cygwin WARNING: Couldn't compute FAST_CWD
  pointer` on every start; it is harmless noise, filter it out when reading
  logs.
- Run wine in a prefix of its own (`WINEPREFIX=...`) and with
  `WINEDLLOVERRIDES=winemenubuilder.exe=d`, otherwise the installer's
  shortcuts land in the host desktop menus.
- Stop a hung wine run with `WINEPREFIX=<that prefix> wineserver -k`, never
  by killing processes by name.
- `pacman -Syu` in tests depends on what MSYS2 released since the base
  archive; the acceptance test updates the product package only.

## Conventions

- Error messages name the component, the operation and the cause
  (`mkinstaller: error: <config>: channel.remote must be an ssh:// URL ...`).
- Keep `README.md` (configuration table, step-by-step guide) in sync with
  every key added to or removed from `product.toml`.
- Commit messages in English, explaining why.
