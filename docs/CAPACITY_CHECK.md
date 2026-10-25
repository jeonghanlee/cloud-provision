# Host capacity check

`bin/check_capacity.bash` decides whether a planned set of guests fits the
host. A caller runs it before starting a retained guest or creating a new one
and acts only on its exit status.

## Interface

```bash
bin/check_capacity.bash [options] status
bin/check_capacity.bash [options] start <domain>...
bin/check_capacity.bash [options] create
```

| Action | Planned set |
| --- | --- |
| `status` | The running guests only; reports the headroom |
| `start` | The running guests plus the named shut-off guests |
| `create` | The running guests plus `-N` new guests of `-m` MB memory and `-z` disk size |

| Option | Meaning | Default |
| --- | --- | --- |
| `-d <dir>` | Image store directory | Directory of the first target disk, else `~/libvirt/images` |
| `-N <count>` | New guests for `create` | `1` |
| `-m <mb>` | Memory of each new guest | `4096` |
| `-z <size>` | Disk size of each new guest, with an `M`, `G`, or `T` suffix | `20G` |
| `-D` | Also count the planned growth of every other defined guest | Off |
| `-q` | Print only the final capacity line | Off |

## Measurement

| Input | Source |
| --- | --- |
| Total and available memory | `MemTotal` and `MemAvailable` of `/proc/meminfo` |
| Total and available image store bytes | `df` on the image store directory |
| Guest state and memory allowance | `virsh dominfo` (`State`, `Max memory`) |
| Resident memory of a running guest | `virsh dommemstat` (`rss`); an unavailable value counts as zero |
| Disks of a guest | `virsh domblklist --details`, device `disk` only |
| Virtual and allocated size of a disk | `qemu-img info --output=json`, top-level `virtual-size` and `actual-size` |

## Demand

- **Memory.** A guest to start or create adds its allowance plus the host
  overhead. A running guest adds the part of its allowance plus overhead that
  its resident memory has not yet reached, never below zero.
- **Disk.** Every planned disk adds its growth, the virtual size less the
  allocated size, never below zero. A created guest adds its full disk size
  and the size of its new files. A guest named by `start` that already runs
  is counted once, as a running guest.

The available memory and the available image store bytes already include the
current usage, so existing allocation is not subtracted again.

## Decision

The planned set fits when both remainders stay at or above their margins:

| Resource | Remainder | Margin |
| --- | --- | --- |
| Memory | Available memory less the memory demand | 10 percent of total memory |
| Disk | Available image store bytes less the disk demand | 5 percent of the image store total |

Policy values are read from the environment, so an owner-recorded margin
replaces the default:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CAPACITY_MEM_OVERHEAD_MB` | `1024` | Host memory overhead per guest |
| `CAPACITY_NEW_FILES_MB` | `1` | Disk space of the new files of a created guest |
| `CAPACITY_MEM_MARGIN_PCT` | `10` | Memory that must stay available |
| `CAPACITY_DISK_MARGIN_PCT` | `5` | Image store space that must stay free |
| `CAPACITY_LIBVIRT_URI` | `qemu:///system` | Hypervisor connection |

## Result

The report lists the memory and the disk figures in GiB and ends with one
machine-readable line.

| Exit status | Final line | Meaning |
| --- | --- | --- |
| `0` | `capacity=FIT` | Both resources stay above their margins |
| `1` | `capacity=NOFIT reason=memory`, `disk`, or `memory,disk` | At least one resource falls below its margin |
| `2` | No capacity line; message on standard error | The decision could not be made |

Status `2` covers every failure to measure or to read the input: an unknown
domain, a guest that is neither running nor shut off, a missing disk image,
unreadable `df` or `meminfo` output, and invalid options or policy values. A
caller treats any status other than `0` as no start, so a failed measurement
never leads to a start.

## Verification

```bash
make check-capacity
```

The suite runs the real script against real qcow2 images and the real
`qemu-img`. It replaces only the hypervisor and host-measurement boundaries
(`virsh`, `df`, and the meminfo file) and checks the demand figures, both
margin boundaries, the failure statuses, and the option validation.
