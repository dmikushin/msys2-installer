# mkinstaller: branded MSYS2 installers for commercial products

`mkinstaller` turns the MSYS2 installer into a constructor for product
installers. A product is a set of pacman packages; the installer puts a
standard MSYS2 environment into the product's own folder, installs the
product packages into it with MSYS2's own pacman, and gives the user a
product terminal. Updates come through pacman from a GitHub repository, and
the licence is the SSH key that grants read access to it.

What an installer built from `examples/hello/product.toml` does:

* installs into `C:\AcmeHello` (not `C:\msys64`), registered as "Acme Hello"
  with its own uninstaller;
* creates "Acme Hello Terminal" on the desktop and in the start menu: a mintty
  window titled "Acme Hello Terminal" with the product icon, started by
  `acme-hello.exe` (the MSYS2 launcher built with the product's name and icon);
* installs `acme-hello` and its dependencies with the target's pacman, so
  install scriptlets and hooks run as on any MSYS2 system;
* asks for the licence key file and installs it; `pacman -Syu` then fetches
  product updates over `git+ssh` with that key.

## Building an installer

    ./mkinstaller build examples/hello/product.toml

Requirements on the Linux build host: `pacman` (with `repo-add`, `pacman-key`),
`unshare` (util-linux), `bsdtar`, `7z`, `git`, `ssh`,
`x86_64-w64-mingw32-gcc`/`windres`, `wine`, `gpg`, Python 3.11+.

Steps, all on the build host:

1. Download the official MSYS2 base archive pinned in `[base]` and verify its
   sha256. The packages must not need newer MSYS2 core packages (pacman,
   bash, msys2-runtime, ...) than the archive has: the build refuses them,
   because a transaction that replaces pacman breaks the fork() of its own
   hooks; take a newer base archive instead.
2. Resolve the `[packages]` against the base's package database and download
   them with all dependencies (`pacman -Sw`, as fake root in a user
   namespace, signatures checked against the MSYS2 keyring from the archive).
   Product packages come from the update channel itself, fetched with
   `channel.build_key`, or from a local repository `channel.build_repo`.
3. Put the downloaded packages into `/var/cache/pacman/pkg` of the
   environment, add the channel to `/etc/pacman.conf`, install
   `pacman-git-xfer`, the branded launcher and the terminal profile.
4. Pack the environment and generate the Qt Installer Framework tree from
   `qt-ifw/` (config, skin, licence, licence-key page, install script).
5. Run `binarycreator.exe` (Qt IFW from MSYS2's package) under wine.

On the target, the installer unpacks the environment, copies the licence key,
runs a first login shell (keyring initialisation) and then
`/usr/share/<id>/firstrun.sh`, which installs the bundled packages with
`pacman -U` and marks dependencies as such.

## Configuration

`product.toml`; paths are relative to it. The example
`examples/hello/product.toml` uses every key.

| key | meaning |
| --- | --- |
| `product.id` | machine name `[a-z][a-z0-9-]*`: launcher, cache and file names |
| `product.name`, `version`, `publisher`, `url`, `description` | shown by the installer and in "Apps & features" |
| `install.default_dir` | default target, Qt IFW variables allowed (`@RootDir@AcmeHello`); no spaces |
| `install.start_menu_dir`, `desktop_shortcut`, `maintenance_tool` | shortcuts and uninstaller name |
| `terminal.name` | shortcut name and window title |
| `terminal.launcher` | base name of the launcher `.exe/.ini/.ico` in the target folder |
| `terminal.msystem` | `UCRT64`, `MINGW64`, `CLANG64`, `MINGW32` or `MSYS` |
| `terminal.icon` | `.ico` of the launcher and the shortcuts |
| `terminal.welcome` | line printed when the product terminal opens |
| `branding.*` | installer skin: `installer_icon`, `window_icon`, `logo`, `watermark`, `banner`, `background`, `stylesheet` (files), `wizard_style`, `title_color`, `title`, `wizard_width`, `wizard_height` |
| `license.file`, `license.name` | licence agreement page |
| `base.url`, `base.sha256` | MSYS2 base archive |
| `base.mirrors` | MSYS2 mirrors used at build time, tried in order |
| `packages.names`, `packages.lists` | packages to install; lists are files with one name per line, `#` comments |
| `channel.name` | pacman repository name of the product |
| `channel.remote` | `ssh://git@github.com/<owner>/<repo>.git` |
| `channel.ref` | branch the releases are published to (default `stable`) |
| `channel.siglevel` | pacman `SigLevel` of the repository |
| `channel.known_hosts` | host keys of the remote (default: GitHub's) |
| `channel.signing_key` | armored public key, if the packages are signed |
| `channel.build_key` / `channel.build_repo` | where the build takes the product packages from; `${VAR}` and `~` expand |
| `output.dir`, `output.name` | where the installer goes |

## Updates: pacman over git+ssh, licence = deploy key

GitHub release assets of a private repository can only be downloaded through
the REST API with a token; an SSH key grants access to git only. So a release
is a git ref: `mkinstaller publish` makes a pacman repository
(`<channel>.db`, `<channel>.files`, packages) of a directory of packages,
commits it as a parentless commit, tags it with the release name and points
the channel branch at it.

    ./mkinstaller publish product.toml dist/ v1.1.0 [--push-key KEY --known-hosts FILE]

On the target, `/etc/pacman.conf` has

    XferCommand = /usr/bin/bash /usr/bin/pacman-git-xfer %o %u
    [acme]
    Server = git+ssh://git@github.com/acme/hello-dist.git#stable

`pacman-git-xfer` (in `runtime/`) serves `git+ssh://` URLs with a shallow
fetch of the ref using the key that `/etc/pacman.d/git-xfer.conf` assigns to
the remote (`/etc/pacman.d/git-xfer/<channel>.key`, the licence), and hands
every other URL to curl. A database download triggers the fetch of the newest
release; packages are read from the same snapshot.

GitHub setup for a product:

1. a private repository, e.g. `acme/hello-dist`;
2. per customer, a read-only **deploy key**; its private half is the licence
   key file the customer gets. Removing the deploy key revokes the licence;
3. the vendor publishes with an account or deploy key that has write access.

The licence key can be given on the installer's "Licence key" page, or
unattended:

    acme-hello-1.0.0-setup.exe install --confirm-command --accept-messages --accept-licenses LicenseKeyFile=C:\path\licence.key

## Acceptance test

    WINE=/path/to/wine tests/acceptance.sh

builds the example product, installs it in a fresh wine prefix, checks path,
launcher, shortcuts, packages and scriptlets, publishes 1.1.0 and checks that
`pacman -Syu` installs it, and that without the licence key the channel
refuses. By default a local sshd (`tests/channel-fixture.sh`) with a read-only
licence key plays the GitHub repository; `--remote/--licence/--publisher`
point it at a real one.

wine releases up to 11.22 break every fork+exec of MSYS2 programs; see
`tests/wine/README.md` for the cause and the patch.
