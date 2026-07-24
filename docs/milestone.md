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
Done before Nimbus: M1.1 · M1.2 · M1.3 · M2.1 · M2.2 · M2.3 · M2.4 · M2.5 · M3.1

Next entry points:
  ▶ ready now:   M1.4 · M3.2 · M4.1 · M4.2 · M4.3 · M4.4 · M4.5
  planned order: M3.2 on a dedicated branch

External wait:  M1.5 ← G1 · M3.3 ← G2
Operator action: run the Rocky 8 downstream validation recorded by G1
Backlog forwarding: M4.1 · M4.2 · M4.3 · M4.4 split from M3.1 out-of-scope policy work; M4.5 split from M3.1 test-boundary review.
Review session archive: host `Neutron`, `/data/gitsrc/cloud-provision/work/review_sessions/20260723_233903_m3_2_vm_naming_defaults`.

Next session entry point: create a dedicated branch for M3.2 from `master`, then implement `plan20260723_234700` for issue #7.
```

Tally: 18 tasks - ✅ 9 · 🔄 0 · ⬜ 7 · 🔒 2 / ready(▶) 7 · external gates 2 (G1 · G2)

## Groups (L1)

| Group | Name | Progress | Status | Next |
| :-- | :-- | :-- | :-- | :-- |
| M1 | Golden image lifecycle | 3/5 | ⬜ | ▶ M1.4 |
| M2 | VM provisioning configuration | 5/5 | ✅ | |
| M3 | Shared behavior consistency | 1/3 | ⬜ | ▶ M3.2 |
| M4 | Explicit policy follow-ups | 0/5 | ⬜ | ▶ M4.1 · M4.2 · M4.3 · M4.4 · M4.5 |

## Tasks (L2)

The `Group` cell is written once per group; continuation rows are blank.

| Group | ID | Task | Status | Next | Deps | Done when / Evidence |
| :-- | :-- | :-- | :-- | :-: | :-- | :-- |
| M1 Golden image lifecycle | M1.1 | Refresh the Rocky 8 golden image | ✅ | | | `make bake.rocky8` completed on 2026-06-03. The resulting 20 GiB qcow2 reported 4.43 GiB disk use and `corrupt: false`. |
| | M1.2 | Check the current Debian 13 golden image | ✅ | | | The shipped setup path reported 8/8 and system-infrastructure validation reported 41/41; the prior `acl` and `logrotate` omissions were not observed. |
| | M1.3 | Retire the 2026-05-13 Rocky 8 sudoers defect | ✅ | | | Superseded by M1.1, whose bake applied the `ansible-provision` sudoers `includedir` ordering change. |
| | M1.4 | [Preserve pinned golden images across rebakes (#2)](https://github.com/jeonghanlee/cloud-provision/issues/2) | ⬜ | ▶ | | Rebakes use new filenames, pinned images remain until downstream pins advance, and the retention rule is documented. |
| | M1.5 | [Validate the Rocky 8 golden after the sudoers fix (#4)](https://github.com/jeonghanlee/cloud-provision/issues/4) | 🔒 | | ← G1 | The real `rocky8-iocrunner.server` path passes the downstream system-infrastructure and system-lifecycle checks, with commands and results recorded. |
| M2 VM provisioning configuration | M2.1 | [Pass `EPICS_ENV_RAM` to per-VM recreate targets (#3)](https://github.com/jeonghanlee/cloud-provision/issues/3) | ✅ | | | Commit `7286a6b` passes `EPICS_ENV_RAM` explicitly to generated EPICS-env per-VM targets, passed V001 V002 V003 V004, and has accepted implementation review with final handoff `hand20260723_135020`. |
| | M2.2 | [Synchronize the documented default VM memory (#13)](https://github.com/jeonghanlee/cloud-provision/issues/13) | ✅ | | ← M2.1 | Commit `47c7162` makes `README.md`, executable help, and the default passed to `virt-install` agree on 4096 MB; GitHub #13 is closed. |
| | M2.3 | [Install `qemu-utils` explicitly on Debian hosts (#5)](https://github.com/jeonghanlee/cloud-provision/issues/5) | ✅ | | | Commit `3da8726` adds `qemu-utils` to the Debian package list. On 2026-07-23, disposable Debian 13 VM `m2qemu-debian13-m23qemu` verified `APT::Install-Recommends "false";`, `qemu-img` absent before setup, `make setup` exit 0, `qemu-img` present afterward, and `make check-tools` exit 0. |
| | M2.4 | [List every supported OS type in `create_vm.bash` help (#8)](https://github.com/jeonghanlee/cloud-provision/issues/8) | ✅ | | | Commit `f7bac56` lists all 11 supported `OS_TYPE` values in executable help and README, adds `make check-vm-help`, and closed GitHub #8. |
| | M2.5 | [Centralize the required `libvirt` group (#9)](https://github.com/jeonghanlee/cloud-provision/issues/9) | ✅ | | | Commit `e94c85d` defines `REQUIRED_GROUP := libvirt`, passes it through setup, VM, EPICS-env, and bake Make paths, adds `make check-required-group`, received Reviewer 1 implementation acceptance, and closed GitHub #9. |
| M3 Shared behavior consistency | M3.1 | [Centralize cloud-init completion parsing (#6)](https://github.com/jeonghanlee/cloud-provision/issues/6) | ✅ | | | Commit `2e7a512` makes both public script paths use `parse_cloud_init_status`. Local verification passed `make check-cloud-init-status` 8/8, `shellcheck bin/create_vm.bash tests/check-cloud-init-status.bash`, `git diff --check`, and `REQUIRED_GROUP=$(id -gn) make check-vm-help`; three-lane implementation re-review accepted. Fast rejection coverage for the normal readiness path moved to M4.5. |
| | M3.2 | [Keep VM naming defaults consistent across provision and bake paths (#7)](https://github.com/jeonghanlee/cloud-provision/issues/7) | ⬜ | ▶ | | `plan20260723_234700` is approved for a shared resolver command, but implementation is intentionally deferred off `master`; create a dedicated branch before editing. Local review-session archive is on host `Neutron`. |
| | M3.3 | [Reuse VM stop behavior in the iocrunner bake (#11)](https://github.com/jeonghanlee/cloud-provision/issues/11) | 🔒 | | ← G2 | The required bake timeout is decided; the shared or explicitly separate paths cover successful shutdown, timeout, and unexpected state. |
| M4 Explicit policy follow-ups | M4.1 | [Define the SSH readiness policy for VM lifecycle checks (#17)](https://github.com/jeonghanlee/cloud-provision/issues/17) | ⬜ | ▶ | | The repository defines what SSH readiness means and verifies accepted and rejected cases through the public script path. |
| | M4.2 | [Review VM readiness retry durations (#19)](https://github.com/jeonghanlee/cloud-provision/issues/19) | ⬜ | ▶ | | IP discovery, SSH readiness, and `cloud-init` completion retry budgets are documented and verified against the selected policy. |
| | M4.3 | [Clarify libvirt lifecycle behavior across VM actions (#20)](https://github.com/jeonghanlee/cloud-provision/issues/20) | ⬜ | ▶ | | Status, provision, stop, and cleanup behavior is defined for running, shut off, undefined, and unexpected domain states. |
| | M4.4 | [Clarify image selection behavior across provision and bake paths (#18)](https://github.com/jeonghanlee/cloud-provision/issues/18) | ⬜ | ▶ | | Provision and bake paths document and verify expected image choice for representative OS types and variants. |
| | M4.5 | [Add fast public-path coverage for cloud-init readiness rejection (#21)](https://github.com/jeonghanlee/cloud-provision/issues/21) | ⬜ | ▶ | | The normal provisioning readiness path rejects non-complete and malformed `cloud-init status` output through a fast public-path test without changing production retry behavior. |

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
| D3 | Track all four M3.1 out-of-scope policy areas as separate GitHub issues and keep M3.1 limited to `cloud-init status` completion parsing. | User direction, 2026-07-23 |
| D4 | Keep the M3.1 test boundary limited to `virsh` and `ssh`; forward fast normal-readiness rejection coverage to M4.5. | User direction, 2026-07-23 |
| D5 | M3.2 resolver plan is approved, but implementation must not proceed directly on `master` because other repositories consume it; the local review-session archive is on host `Neutron`. | User direction, 2026-07-23 |

## Conventions

- The register is written in English; status markers use the emoji set above.
- One task row is one deliverable plus its verification.
- `Progress` is done/total tasks in the group. Group status and the ready set
  derive from task status and dependency arrows.
- GitHub controls issue membership and open/closed state. This register controls
  workstream grouping, dependency edges, decisions, and the next-session handoff.
