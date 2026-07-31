# Design: Image Archive and Working Copy

**Status: accepted, not implemented.** This document records a design agreed on
2026-07-31 for M1.6 (issue #25) and M1.4 (issue #2). Nothing here describes the
repository as it stands today; `docs/ARCHITECTURE.md` does that. When this design
lands, its content moves into `ARCHITECTURE.md` and this file is removed.

## Why one design for two issues

Both issues decide where golden images live and under what name. Deciding them
apart would produce two layouts.

- **#25** — one directory serves two roles. The bake publishes the golden there,
  and every consumer backs onto it there. libvirt's `dynamic_ownership` claims
  the whole backing chain when a domain starts, and the restore half runs only
  on a graceful shutdown, so a `.clean` teardown leaves the golden owned by
  `libvirt-qemu`. The next bake then overwrites a file the baking account does
  not own.
- **#2** — a rebake overwrites `iocrunner-<os>.qcow2` in place. A downstream
  release gate that is pinned to the previous environment loses the image its
  pin refers to.

One archive holding versioned entries, plus one working copy per platform,
satisfies both: the archive is where retention lives, and the working copy is
where libvirt is allowed to do what it does.

## Layout

```
/data/libvirt/archive/iocrunner-rocky8-20260729T060708Z.qcow2
/data/libvirt/archive/iocrunner-rocky8-20260729T060708Z.qcow2.manifest
/data/libvirt/images/iocrunner-rocky8.qcow2          <- consumers back onto this
/data/libvirt/images/testbed-rocky8-iocrunner-server.qcow2
/data/libvirt/images/testbed-rocky8-iocrunner-server-seed.iso
```

The bake publishes into `archive/`. A separate refresh step copies a chosen
archive entry to the working copy in `images/`. Per-VM overlay disks and seed
ISOs stay with the working copy.

## The rules that make it work

### The working copy is a real file, never a symlink

A symlink at the position consumers back onto would resolve through to the
archive entry, and libvirt would chown that — the exact outcome the archive
exists to prevent, on the copy meant to be permanent. The working copy is
produced by copy or by a fresh `qemu-img convert`.

This says nothing about symlinks elsewhere on the path. `~/libvirt ->
/data/libvirt` exists because the root filesystem is 224G at 85% while `/data`
is 2.9T at 24%, and it is unaffected: resolution ends at a real file, and
libvirt chowns per file rather than per directory. Observed on this host —
`iocrunner-rocky8.qcow2` is owned by `libvirt-qemu` while its sidecar manifest
beside it is still owned by the invoking user.

### The working copy keeps today's path and name

Every existing per-VM overlay records an absolute backing path. Renaming the
consumer-visible artifact would strand every existing consumer. The archive is
the new thing; what consumers already resolve does not move.

This is also why no other repository needs a coordinated change. `con`'s release
gate and `EPICS-env`'s M7.T3 both see an unchanged consumer-visible artifact. A
later drift toward renaming it would be a cross-repository change and must be
recognized as one.

### The archive gets its own directory, for discipline rather than correctness

A single directory would have worked. libvirt claims files that appear in a
started domain's backing chain, not directory neighbours, and the repository's
only glob over the image directory — `bin/bake_iocrunner_image.bash:121` — reads
each file's backing file, so flat archive entries can neither match nor produce
a false positive. No code in this repository deletes by glob there.

Separation is chosen because it makes pointing a consumer at an archive entry
hard, and because the image directory already holds 57G of mixed content. It is
a judgment, not a necessity, and is recorded as such so a later reader does not
believe the alternative was impossible.

### The backing-chain guard moves from publish to refresh

`protect_output_consumers` today refuses to publish while a consumer backs onto
the output image. After the split, the bake publishes into an archive nothing
backs onto, so the guard as placed could never fire again while still reading as
protection.

The property worth protecting does not disappear: replacing a working copy while
a consumer runs still pulls the floor out from under it. The scan moves to the
refresh step. Publishing to the archive needs no such guard.

### Provisioning refuses when the working copy is absent

Refresh is an explicit operator step with its own target. Provisioning does not
refresh implicitly, because silent staleness would hand an operator the previous
environment with nothing reported — worse than an error, since the run looks
correct.

### Archive entries are named from the bake timestamp

`iocrunner-<os>-<bake_date>.qcow2`, taking `bake_date` from the value the bake
already stamps into the manifest, in compact form: `20260729T060708Z`.

The manifest already carries the full identity — `bake_date`, the
`cloud-provision` and `ansible-provision` commits, the EPICS versions, the base
image digest, and each application's commit. The file name does not duplicate
that; it distinguishes and orders. Taking the name from the value the bake
already records means the name and the contents cannot disagree, and a plain
listing shows which entry is current and which is previous.

A source hash was rejected because the manifest holds several and choosing one
leaves the others able to change without changing the name, and because hashes
do not order. A serial was rejected because it carries no information.

### Retention keeps the current and the previous entry

Two is the smallest depth that makes a rollback possible at all. Older entries
are removed only after the record below shows nothing pins them.

Retention is manual, per #2, but "keep until the pin advances" is unenforceable
if nobody can see which entry a pin claims. The archive carries a readable
record of what pins each retained entry. Automation is not required; a readable
record is.

### Upstream base images stay where they are

`debian-13-genericcloud-amd64-daily.qcow2` and the other downloadable bases
migrate ownership by the same mechanism, and they are excluded from this split
deliberately: they are re-fetchable, and commit `6e67d02` removed the delete that
made losing one costly. Including them would widen the change without serving
either issue's acceptance criterion.

## Interaction with work already landed

Commit `6e67d02` added a check asserting that the bake output name and the
consumer input name are one pair. After this design lands the bake publishes a
versioned archive name, so the pair to assert becomes the refresh target against
the consumer selection. The check follows the change; it is not dropped.

## What this design does not settle

The refresh step's own interface — target name, whether it takes an explicit
archive entry or defaults to the newest — is left to the implementation plan.
