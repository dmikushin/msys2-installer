# mkinstaller: branded MSYS2 installers for commercial products

`mkinstaller` builds Windows installers for products that ship as pacman
packages on top of [MSYS2](https://www.msys2.org). It is a fork of the
[MSYS2 installer](https://github.com/msys2/msys2-installer): the same Qt
Installer Framework installer and the same official MSYS2 base system, but
configured by one `product.toml` instead of being MSYS2 itself.

An installer built by `mkinstaller`:

* installs a standard MSYS2 environment into the product's own folder, e.g.
  `C:\AcmeHello` instead of `C:\msys64`, registered under the product's name
  with its own uninstaller;
* shows the product's skin (icons, logo, banner, colours) and licence;
* creates a branded terminal shortcut on the desktop and in the start menu:
  a mintty window with the product's title and icon, started by a launcher
  `.exe` built from MSYS2's launcher with the product's name;
* installs the product's pacman packages and their dependencies with the
  target's own pacman, so install scriptlets and hooks run as on any MSYS2
  system;
* takes a licence key file and installs it. The licence is a read-only
  GitHub deploy key: with it, pacman fetches product updates from a private
  GitHub repository over `git+ssh`; without it, the update channel refuses.

Product updates are ordinary pacman updates: the vendor runs
`mkinstaller publish`, the customer runs `pacman -Syu` (or
`pacman -Sy <package>`) in the product terminal.

## Step-by-step: setting up a product

The commands below set up a product "Acme Hello" (id `acme-hello`) with the
update channel `acme/hello-dist` on GitHub. Replace the names with yours.

### 1. Prepare the build host

The build host is Linux. On Arch Linux and derivatives (the tested setup):

    sudo pacman -S --needed pacman util-linux libarchive 7zip git openssh \
        mingw-w64-gcc mingw-w64-binutils wine gnupg python

Other distributions need the same tools: pacman 6 with `repo-add` and
`pacman-key`, `unshare`, `bsdtar`, `7z`, `x86_64-w64-mingw32-gcc` and
`-windres`, `wine`, `gpg`, Python 3.11+.

wine must be able to run MSYS2 programs. Releases up to at least 11.22 break
every fork+exec of MSYS2 programs; build wine with
`tests/wine/grow-thread-stack-rw.patch` (backport of upstream commit
17e0faed) or use a release that contains that commit. `tests/wine/README.md`
has a small reproducer (`stackprobe.c`) to check a wine build. wine is needed only to run
Qt IFW's `binarycreator.exe` and the acceptance test; the installers
themselves are for Windows.

Get the constructor:

    git clone -b constructor https://github.com/dmikushin/msys2-installer.git
    cd msys2-installer

### 2. Package the product

Each part of the product is a pacman package built for MSYS2: a `PKGBUILD`
with `arch=('any')` for scripts and data, or one built in MSYS2 for binaries.
`examples/hello/pkg/PKGBUILD` is a minimal one, with a dependency (`tree`
from MSYS2) and an install scriptlet:

    cd examples/hello/pkg
    HELLO_VERSION=1.0.0 PKGDEST=$PWD/../dist makepkg --nodeps
    cd -

Dependencies on MSYS2 packages are resolved against the MSYS2 repositories
at build time. They must not require newer MSYS2 core packages (`bash`,
`filesystem`, `mintty`, `msys2-runtime`, `pacman`, `pacman-mirrors`) than
the base archive contains; the build stops with a message if they do. Take a
newer base archive in that case.

### 3. Create the update channel on GitHub

1. Create a **private** repository for the releases, e.g. `acme/hello-dist`.
   It holds only release commits; keep the sources elsewhere.
2. Create the vendor's publishing key and add it as a deploy key **with**
   write access:

       ssh-keygen -t ed25519 -N '' -f publisher.key -C acme-hello-publisher
       gh repo deploy-key add publisher.key.pub -R acme/hello-dist -t publisher --allow-write

3. Create a build key: a read-only deploy key that the build uses to fetch
   the product packages from the channel:

       ssh-keygen -t ed25519 -N '' -f build.key -C acme-hello-build
       gh repo deploy-key add build.key.pub -R acme/hello-dist -t build

Deploy keys can also be added on GitHub under *Settings, Deploy keys*. Note
that `gh` ties the keys it adds to its authentication token: if that token
is revoked, GitHub removes those deploy keys too, and with them the
customers' licences. For licences that must outlive a token, add the keys in
the web interface or with a token that stays.

### 4. Publish the first release

    ./mkinstaller publish examples/hello/product.toml examples/hello/dist v1.0.0 \
        --push-key publisher.key

This builds a pacman repository named after `channel.name` from all packages
in the directory, commits it, tags it `v1.0.0` and points the branch
`channel.ref` (`stable`) at it. Each release replaces the branch content;
older releases stay reachable by their tags.

### 5. Write `product.toml`

Copy `examples/hello/` and edit `product.toml`; every key is explained in
[Configuration](#configuration). The parts that matter first:

    [product]
    id = "acme-hello"
    name = "Acme Hello"
    version = "1.0.0"
    publisher = "Acme Corp"

    [install]
    default_dir = "@RootDir@AcmeHello"     # no spaces

    [terminal]
    name = "Acme Hello Terminal"
    icon = "assets/acme.ico"

    [license]
    file = "LICENSE.txt"

    [packages]
    lists = ["packages.txt"]               # acme-hello, one name per line

    [channel]
    name = "acme"
    remote = "ssh://git@github.com/acme/hello-dist.git"
    build_key = "${ACME_BUILD_KEY}"

Skin images go to `[branding]`: `logo` (shown in the banner corner),
`banner` (page header), `watermark`, `background`, `installer_icon`, and
`title_color` for the page titles.

### 6. Build the installer

    ACME_BUILD_KEY=$PWD/build.key ./mkinstaller build examples/hello/product.toml

The installer is written to `examples/hello/out/acme-hello-1.0.0-setup.exe`;
the work tree is `examples/hello/_build/`, downloads are cached in
`~/.cache/mkinstaller/`. Pass `--wine /path/to/wine` to use a patched wine.

### 7. Issue a licence

Per customer, one read-only deploy key:

    ssh-keygen -t ed25519 -N '' -f customer-42.key -C acme-hello-customer-42
    gh repo deploy-key add customer-42.key.pub -R acme/hello-dist -t customer-42

Send the customer `customer-42.key` (the private half) together with the
installer. Revoke the licence by deleting the deploy key:

    gh repo deploy-key list -R acme/hello-dist
    gh repo deploy-key delete <id> -R acme/hello-dist

### 8. Install (customer)

Run the installer and choose `customer-42.key` on the *Licence key* page,
or install unattended:

    acme-hello-1.0.0-setup.exe install --confirm-command --accept-messages --accept-licenses LicenseKeyFile=C:\path\customer-42.key

Without a key the product installs too; updates stay disabled until the key
is copied to `<install dir>\etc\pacman.d\git-xfer\acme.key`.

### 9. Ship an update

Build the new package version, then publish it:

    ./mkinstaller publish examples/hello/product.toml dist-1.1.0 v1.1.0 --push-key publisher.key

The directory must contain every package of the release, not only the
changed ones: a release is a complete repository. Customers get it with
`pacman -Syu` in the product terminal. A new installer is only needed for new
customers; rebuild it when the release should be in the initial install.

### 10. Check the result

    WINE=/path/to/patched/wine tests/acceptance.sh

runs steps 2 to 9 with the example product in a fresh wine prefix and
checks the outcome (see [Acceptance test](#acceptance-test)).

## How a build works

All steps run on the build host:

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

    WINE=/path/to/wine tests/acceptance.sh [--remote URL --licence KEY --publisher KEY --known-hosts FILE]

builds the example product (versions 1.0.0 and 1.1.0), publishes 1.0.0,
builds the installer, installs it unattended with the licence key in a fresh
wine prefix and checks: install folder, launcher and its icon and title,
desktop and start-menu shortcuts, uninstaller, licence key, pacman
configuration, installed packages, dependency marking, the install
scriptlet. It then publishes 1.1.0 and checks that `pacman -Qu` offers it
and `pacman -S` installs it over git+ssh, and that without the licence key
`pacman -Sy` fails and names the missing key. The test updates only the
product package: a full `-Syu` would also pull whatever MSYS2 released since
the base archive and make the result depend on the day.

By default a local sshd (`tests/channel-fixture.sh`) plays GitHub, with a
read-only licence key and a read-write publisher key; `--remote` and the key
options run it against a real repository. Logs go to
`$WORK/logs` (default `~/scratch/mkinstaller-accept`).

`tests/wine/README.md` documents the two defects found while running MSYS2
under wine, with reproducers.
