# Work Register

Repository-local canonical tracker for `Nimbus - Cloud Provisioning
Reliability` in `cloud-provision`. This register is agent-independent: every
agent and contributor reads this file instead of chat history or per-agent
memory.

Mode: GitHub-authoritative for issue membership and issue state; register-authoritative for grouping, dependencies, decisions, and handoff.

## Format

- Two levels: `M<group>` (workstream) / `M<group>.<task>` (work unit).
  Verification and evidence live in the task's Done-when column.
- Tracking IDs: **M** (work) · **G** (external gate) · **D** (decision).
- Dependencies are typed arrows: `← M..` (prior task) · `← G..` (external gate)
  · `← D..` (decision).
- Status (✅ done · 🔄 in progress · ⬜ not started · 🔒 blocked) and Next
  (▶ ready - startable now) are kept separate. A group's status and the ready
  set derive from its tasks and dependency arrows.

### Migration map

| Previous ID | Current ID | GitHub issue |
| :-- | :-- | :-- |
| C1 | M2.3 | [#5](https://github.com/jeonghanlee/cloud-provision/issues/5) |
| C2 | M3.1 | [#6](https://github.com/jeonghanlee/cloud-provision/issues/6) |
| C3 | M3.2 | [#7](https://github.com/jeonghanlee/cloud-provision/issues/7) |
| C4 | M2.4 | [#8](https://github.com/jeonghanlee/cloud-provision/issues/8) |
| C5 | M2.5 | [#9](https://github.com/jeonghanlee/cloud-provision/issues/9) |
| C6 | M3.3 | [#11](https://github.com/jeonghanlee/cloud-provision/issues/11) |

## Now / Next (2026-07-23)

```
In progress (🔄):  none
Done before Nimbus: M1.1 · M1.2 · M1.3

Next entry points:
  ▶ ready now:   M2.3 · M1.4 · M2.1 · M2.4 · M2.5 · M3.1 · M3.2
  planned order: M2.1 → M2.2

External wait:  M1.5 ← G1 · M3.3 ← G2
Operator action: run the Rocky 8 downstream validation recorded by G1

Next session entry point: redefine M2.3 in issue #5 from `bin/setup_host.bash` and `configure/RULES_SETUP`, deciding whether post-install verification belongs in the same task before implementation planning.
```

Tally: 13 tasks - ✅ 3 · 🔄 0 · ⬜ 7 · 🔒 3 / ready(▶) 7 · external gates 2 (G1 · G2)

## Groups (L1)

| Group | Name | Progress | Status | Next |
| :-- | :-- | :-- | :-- | :-- |
| M1 | Golden image lifecycle | 3/5 | ⬜ | ▶ M1.4 |
| M2 | VM provisioning configuration | 0/5 | ⬜ | ▶ M2.3 |
| M3 | Shared behavior consistency | 0/3 | ⬜ | ▶ M3.1 |

## Tasks (L2)

The `Group` cell is written once per group; continuation rows are blank.

| Group | ID | Task | Status | Next | Deps | Done when / Evidence |
| :-- | :-- | :-- | :-- | :-: | :-- | :-- |
| M1 Golden image lifecycle | M1.1 | Refresh the Rocky 8 golden image | ✅ | | | `make bake.rocky8` completed on 2026-06-03. The resulting 20 GiB qcow2 reported 4.43 GiB disk use and `corrupt: false`. |
| | M1.2 | Check the current Debian 13 golden image | ✅ | | | The shipped setup path reported 8/8 and system-infrastructure validation reported 41/41; the prior `acl` and `logrotate` omissions were not observed. |
| | M1.3 | Retire the 2026-05-13 Rocky 8 sudoers defect | ✅ | | | Superseded by M1.1, whose bake applied the `ansible-provision` sudoers `includedir` ordering change. |
| | M1.4 | [Preserve pinned golden images across rebakes (#2)](https://github.com/jeonghanlee/cloud-provision/issues/2) | ⬜ | ▶ | | Rebakes use new filenames, pinned images remain until downstream pins advance, and the retention rule is documented. |
| | M1.5 | [Validate the Rocky 8 golden after the sudoers fix (#4)](https://github.com/jeonghanlee/cloud-provision/issues/4) | 🔒 | | ← G1 | The real `rocky8-iocrunner.server` path passes the downstream system-infrastructure and system-lifecycle checks, with commands and results recorded. |
| M2 VM provisioning configuration | M2.1 | [Pass `EPICS_ENV_RAM` to per-VM recreate targets (#3)](https://github.com/jeonghanlee/cloud-provision/issues/3) | ⬜ | ▶ | | Per-VM recreate targets pass `EPICS_ENV_RAM` explicitly; the global VM default returns to 2048 MB after the generated and real recreate paths are verified. |
| | M2.2 | [Synchronize the documented default VM memory (#13)](https://github.com/jeonghanlee/cloud-provision/issues/13) | 🔒 | | ← M2.1 | `README.md`, executable help, and the default passed to `virt-install` agree after M2.1 establishes the final value. |
| | M2.3 | [Install `qemu-utils` explicitly on Debian hosts (#5)](https://github.com/jeonghanlee/cloud-provision/issues/5) | ⬜ | ▶ | | The real Debian host setup path installs `qemu-img` with recommended packages disabled, and `make check-tools` passes afterward. |
| | M2.4 | [List every supported OS type in `create_vm.bash` help (#8)](https://github.com/jeonghanlee/cloud-provision/issues/8) | ⬜ | ▶ | | Executable help and README list every accepted `OS_TYPE`; a repository check detects future omissions. |
| | M2.5 | [Centralize the required `libvirt` group (#9)](https://github.com/jeonghanlee/cloud-provision/issues/9) | ⬜ | ▶ | | Host setup and VM provisioning resolve membership checks and operator guidance from one maintained value; the default remains `libvirt`. |
| M3 Shared behavior consistency | M3.1 | [Centralize cloud-init completion parsing (#6)](https://github.com/jeonghanlee/cloud-provision/issues/6) | ⬜ | ▶ | | Both public script actions use one parser and agree on complete, incomplete, and malformed real command output. |
| | M3.2 | [Keep VM naming defaults consistent across provision and bake paths (#7)](https://github.com/jeonghanlee/cloud-provision/issues/7) | ⬜ | ▶ | | Both paths derive the same VM name and source disk from one maintained definition while `VM_PREFIX` and `IMAGE_DIR` overrides continue to work. |
| | M3.3 | [Reuse VM stop behavior in the iocrunner bake (#11)](https://github.com/jeonghanlee/cloud-provision/issues/11) | 🔒 | | ← G2 | The required bake timeout is decided; the shared or explicitly separate paths cover successful shutdown, timeout, and unexpected state. |

## External gates (G)

| G | What | Blocks | Status | Evidence |
| :-- | :-- | :-- | :-- | :-- |
| G1 | Run downstream validation on the 2026-06-03 Rocky 8 golden image | M1.5 | Open | Requires the real golden image, `rocky8-iocrunner.server`, and the downstream ioc-runner validation environment. |
| G2 | Confirm whether the iocrunner bake requires its 120-second shutdown allowance | M3.3 | Open | Owner decision required before the bake can share the provisioner's 60-second stop behavior. |

## Decisions (D)

| D | Content | Decided in |
| :-- | :-- | :-- |
| D1 | Use `Nimbus - Cloud Provisioning Reliability` as the current non-versioned reliability milestone. | [GitHub milestone 1](https://github.com/jeonghanlee/cloud-provision/milestone/1), 2026-07-23 |
| D2 | Organize the register as three workstream groups with `M<group>.<task>` identifiers and retain completed golden-image history in M1. | Work Register consolidation, 2026-07-23 |

## Conventions

- The register is written in English; status markers use the emoji set above.
- One task row is one deliverable plus its verification.
- `Progress` is done/total tasks in the group. Group status and the ready set
  derive from task status and dependency arrows.
- GitHub controls issue membership and open/closed state. This register controls
  workstream grouping, dependency edges, decisions, and the next-session handoff.
