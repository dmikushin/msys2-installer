# MSYS2 under wine: "Bad address" on every fork+exec

With wine 11.16 (run here) and every release up to 11.22 (same
`grow_thread_stack()` in their sources), every MSYS2 program that forks and then
execs (any external command run by bash from a pipeline, a subshell or a
`$(...)`) fails with `Bad address`. The installer's first-run step and pacman
both depend on that, so the acceptance test cannot pass on those wine versions.

## Cause

Cygwin (msys-2.0.dll) gives the forked child a stack it allocates itself
(`child_info_fork::alloc_stack`): it reserves the whole stack with
`PAGE_NOACCESS`, commits the part the parent used, and marks three pages below
it `PAGE_READWRITE | PAGE_GUARD`. Windows grows a thread stack on a guard-page
hit by committing the next page below as `PAGE_READWRITE | PAGE_GUARD`.

wine's `grow_thread_stack()` (dlls/ntdll/unix/virtual.c) instead set only the
`VPROT_COMMITTED | VPROT_GUARD` bits on the next page and kept its reserve-time
protection, `PAGE_NOACCESS`. Once the three guard pages are used up, the next
stack page is committed but inaccessible. `child_info_spawn::worker` probes a
0x11048-byte stack frame (`__chkstk_ms`), hits that page, and Cygwin turns the access
violation into `EFAULT`, which bash prints as "Bad address".

## Reproducer without Cygwin

`stackprobe.c` builds the same stack layout and probes 0x11000 bytes:

    x86_64-w64-mingw32-gcc -O1 -o stackprobe.exe stackprobe.c
    wine stackprobe.exe        # wine 11.16: dies, no STACKPROBE_OK
                               # patched wine: STACKPROBE_OK

`stackprobe.exe 0x5800` shows the faulty state: the page below the used guard
pages reports `protect=101` (PAGE_NOACCESS | PAGE_GUARD) instead of 104.

## Fix

Upstream wine fixed it in commit 17e0faed ("ntdll: Reset page protections to
zero on decommit. And make sure to always set the full protections on
commit.", 2026-11-17); it is not in any release up to 11.22.
`grow-thread-stack-rw.patch` is the minimal backport to wine 11.16: the grown
and the new guard pages get `VPROT_READ | VPROT_WRITE`. With it, both
stackprobe.exe and MSYS2's fork+exec work.

# A transaction that upgrades pacman hangs in its hooks

Reproduced with the patched wine 11.16 on a fresh MSYS2 base
(`pacman -U pacman-6.1.0-31 grep-1~3.12-1` over pacman 6.1.0-30): after
"upgrading pacman", the info-directory hook's fork fails with
`child_copy: data read copy failed ... Win32 error 998` and pacman waits
forever for the half-dead child. The same transaction without the pacman
package completes. Unverified explanation: pacman.exe was replaced on disk
while running, and the fork child is started from the new binary, whose data
layout differs from the parent's. Cygwin's remedy for replaced binaries,
`/var/run/cygfork` hardlinks, was tried and stays empty under wine. Whether
the same transaction works on real Windows was not tested.

MSYS2 updates its core packages (bash, filesystem, mintty, msys2-runtime,
pacman, pacman-mirrors) in a transaction of their own for this reason.
mkinstaller therefore refuses to bundle core packages: the product's
packages must fit the core of the base archive, or the base archive must be
newer.
