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

### External identifiers

`P008` and `M.7` are not identifiers of this repository and have no row here.
They belong to the `EPICS-env` 1.3.0 release cycle: `P008` is the
improvement-recording step of its release verification plan, and `M.7` is the
M7 release gate recorded in
[EPICS-env `docs/milestone-1.3.0.md`](https://github.com/jeonghanlee/EPICS-env/blob/release-1.3.0/docs/milestone-1.3.0.md),
whose `M7.T3` requires full-environment install verification on real VMs. Earlier
revisions of `docs/RUNBOOK_BAKE.md` used both names without defining them; they
no longer appear outside this note.

## Now / Next (2026-07-31)

```
In progress (🔄):  none
Done (✅):  M1.1 · M1.2 · M1.3 · M2.1 · M2.2 · M2.3 · M2.4 · M2.5 · M3.1 · M4.5 · M5.1 · M5.2 · M5.3

Next entry points:
  ▶ ready now:   M1.4 · M3.2 · M3.4 · M4.1 · M4.2 · M4.3 · M4.4
  planned order: M3.2 on a dedicated branch

External wait:  M1.5 ← G1 · M3.3 ← G2 · M5.4 ← G3
Operator action: run the Rocky 8 downstream validation recorded by G1; run the production ioc-runner bake acceptance recorded by G3
Backlog forwarding: M4.1 · M4.2 · M4.3 · M4.4 split from M3.1 out-of-scope policy work; M4.5 split from M3.1 test-boundary review.
Review session archive: host `Neutron`, `/data/gitsrc/cloud-provision/work/review_sessions/20260723_233903_m3_2_vm_naming_defaults`.

Next session entry point: create a dedicated branch for M3.2 from `master`, then implement `plan20260723_234700` for issue #7.
```

Tally: 23 tasks - ✅ 13 · 🔄 0 · ⬜ 7 · 🔒 3 / ready(▶) 7 · external gates 3 (G1 · G2 · G3)

## Groups (L1)

| Group | Name | Progress | Status | Next |
| :-- | :-- | :-- | :-- | :-- |
| M1 | Golden image lifecycle | 3/5 | ⬜ | ▶ M1.4 |
| M2 | VM provisioning configuration | 5/5 | ✅ | |
| M3 | Shared behavior consistency | 1/4 | ⬜ | ▶ M3.2 · M3.4 |
| M4 | Explicit policy follow-ups | 1/5 | ⬜ | ▶ M4.1 · M4.2 · M4.3 · M4.4 |
| M5 | ioc-runner bake provenance | 3/4 | 🔒 | |

## Tasks (L2)

The `Group` cell is written once per group; continuation rows are blank.

| Group | ID | Task | Status | Next | Deps | Done when / Evidence |
| :-- | :-- | :-- | :-- | :-: | :-- | :-- |
| M1 Golden image lifecycle | M1.1 | Refresh the Rocky 8 golden image | ✅ | | | `make bake.rocky8` completed on 2026-06-03. The resulting 20 GiB qcow2 reported 4.43 GiB disk use and `corrupt: false`. |
| | M1.2 | Check the current Debian 13 golden image | ✅ | | | The shipped setup path reported 8/8 and system-infrastructure validation reported 41/41; the prior `acl` and `logrotate` omissions were not observed. |
| | M1.3 | Retire the 2026-05-13 Rocky 8 sudoers defect | ✅ | | | Superseded by M1.1, whose bake applied the `ansible-provision` sudoers `includedir` ordering change. |
| | M1.4 | [Preserve pinned golden images across rebakes (#2)](https://github.com/jeonghanlee/cloud-provision/issues/2) | ⬜ | ▶ | | Rebakes use new filenames, pinned images remain until downstream pins advance, and the retention rule is documented. |
| | M1.5 | [Validate the Rocky 8 golden after the sudoers fix (#4)](https://github.com/jeonghanlee/cloud-provision/issues/4) | 🔒 | | ← G1 | The real `rocky8-iocrunner.server` path passes the downstream system-infrastructure and system-lifecycle checks, with commands and results recorded. Resume as ⬜ when G1 completes. |
| M2 VM provisioning configuration | M2.1 | [Pass `EPICS_ENV_RAM` to per-VM recreate targets (#3)](https://github.com/jeonghanlee/cloud-provision/issues/3) | ✅ | | | Commit `7286a6b` passes `EPICS_ENV_RAM` explicitly to generated EPICS-env per-VM targets, passed V001 V002 V003 V004, and has accepted implementation review with final handoff `hand20260723_135020`. |
| | M2.2 | [Synchronize the documented default VM memory (#13)](https://github.com/jeonghanlee/cloud-provision/issues/13) | ✅ | | ← M2.1 | Commit `47c7162` makes `README.md`, executable help, and the default passed to `virt-install` agree on 4096 MB; GitHub #13 is closed. |
| | M2.3 | [Install `qemu-utils` explicitly on Debian hosts (#5)](https://github.com/jeonghanlee/cloud-provision/issues/5) | ✅ | | | Commit `3da8726` adds `qemu-utils` to the Debian package list. On 2026-07-23, disposable Debian 13 VM `m2qemu-debian13-m23qemu` verified `APT::Install-Recommends "false";`, `qemu-img` absent before setup, `make setup` exit 0, `qemu-img` present afterward, and `make check-tools` exit 0. |
| | M2.4 | [List every supported OS type in `create_vm.bash` help (#8)](https://github.com/jeonghanlee/cloud-provision/issues/8) | ✅ | | | Commit `f7bac56` lists all 11 supported `OS_TYPE` values in executable help and README, adds `make check-vm-help`, and closed GitHub #8. |
| | M2.5 | [Centralize the required `libvirt` group (#9)](https://github.com/jeonghanlee/cloud-provision/issues/9) | ✅ | | | Commit `e94c85d` defines `REQUIRED_GROUP := libvirt`, passes it through setup, VM, EPICS-env, and bake Make paths, adds `make check-required-group`, received Reviewer 1 implementation acceptance, and closed GitHub #9. |
| M3 Shared behavior consistency | M3.1 | [Centralize cloud-init completion parsing (#6)](https://github.com/jeonghanlee/cloud-provision/issues/6) | ✅ | | | Commit `2e7a512` makes both public script paths use `parse_cloud_init_status`. Local verification passed `make check-cloud-init-status` 8/8, `shellcheck bin/create_vm.bash tests/check-cloud-init-status.bash`, `git diff --check`, and `REQUIRED_GROUP=$(id -gn) make check-vm-help`; three-lane implementation re-review accepted. Fast rejection coverage for the normal readiness path moved to M4.5. The 8/8 count is the observation of 2026-07-23; the same target now also carries the M4.5 readiness cases, so later runs report a higher total. |
| | M3.2 | [Keep VM naming defaults consistent across provision and bake paths (#7)](https://github.com/jeonghanlee/cloud-provision/issues/7) | ⬜ | ▶ | | `plan20260723_234700` is approved for a shared resolver command, but implementation is intentionally deferred off `master`; create a dedicated branch before editing. Local review-session archive is on host `Neutron`. |
| | M3.3 | [Reuse VM stop behavior in the ioc-runner bake (#11)](https://github.com/jeonghanlee/cloud-provision/issues/11) | 🔒 | | ← G2 | The required bake timeout is decided; the shared or explicitly separate paths cover successful shutdown, timeout, and unexpected state. Resume as ⬜ when G2 completes. |
| | M3.4 | [Make concurrent `create_vm.bash` runs seed-safe (#22)](https://github.com/jeonghanlee/cloud-provision/issues/22) | ⬜ | ▶ | | Two concurrent runs for different OS types both reach `READY` with working `vmadmin` SSH; each seed ISO carries exactly one `local-hostname` equal to its own VM name; a failed `genisoimage` step exits non-zero instead of reporting `[OK]`; serial behavior and timings unchanged. |
| M4 Explicit policy follow-ups | M4.1 | [Define the SSH readiness policy for VM lifecycle checks (#17)](https://github.com/jeonghanlee/cloud-provision/issues/17) | ⬜ | ▶ | | The repository defines what SSH readiness means and verifies accepted and rejected cases through the public script path. |
| | M4.2 | [Review VM readiness retry durations (#19)](https://github.com/jeonghanlee/cloud-provision/issues/19) | ⬜ | ▶ | | IP discovery, SSH readiness, and `cloud-init` completion retry budgets are documented and verified against the selected policy. |
| | M4.3 | [Clarify libvirt lifecycle behavior across VM actions (#20)](https://github.com/jeonghanlee/cloud-provision/issues/20) | ⬜ | ▶ | | Status, provision, stop, and cleanup behavior is defined for running, shut off, undefined, and unexpected domain states. |
| | M4.4 | [Clarify image selection behavior across provision and bake paths (#18)](https://github.com/jeonghanlee/cloud-provision/issues/18) | ⬜ | ▶ | | Provision and bake paths document and verify expected image choice for representative OS types and variants. |
| | M4.5 | [Add fast public-path coverage for cloud-init readiness rejection (#21)](https://github.com/jeonghanlee/cloud-provision/issues/21) | ✅ | | ← D8 | `tests/check-cloud-init-status.bash` adds two readiness rejection cases that drive the real `wait_for_vm` chain through the shut-off restart branch, replacing only `virsh`, `ssh`, and `sleep`; no production line changed. The retry assertion reads the attempt count from the run instead of pinning the budget, so M4.2 may revise it freely. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-cloud-init-status` exited 0 with 18/18. Teeth confirmed by mutation: removing the `sleep` call from `wait_for_cloud_init` dropped it to 14/18 with exit 2, and the production file was restored to its committed state afterward. |
| M5 ioc-runner bake provenance | M5.1 | Validate ioc-runner bake provenance before publication | ✅ | | | Commit `c4ba7fd` makes the ioc-runner bake fresh-input only, records and validates the manifest before publication, and publishes the image and its sidecar as an atomic pair. Adds `bin/validate_iocrunner_bake.bash`, `tests/check-fresh-bake-inputs.bash`, and `tests/check-iocrunner-bake-provenance.bash` behind `make check-bake`. On 2026-07-30, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-bake` at `67c1829` exited 0 with 7/7 fresh-input and 17/17 provenance checks. |
| | M5.2 | Separate VM provisioning targets from bake selector families | ✅ | | ← M5.1 | Commit `b972dc0` separates provisionable OS types, default Make targets, ioc-runner bake inputs, and EtherCAT bake inputs in `README.md`, `docs/ARCHITECTURE.md`, and `docs/RUNBOOK_BAKE.md`. On 2026-07-30, host `Neutron`, `make help.bake` at `67c1829` exited 0 and listed the ioc-runner, validation, and EtherCAT target families separately. |
| | M5.3 | Document the post-bake acceptance checks | ✅ | | ← M5.2 | Commit `67c1829` documents the fixed post-bake SSH command contract, stale host-key removal for fresh deterministic-IP consumers, and diagnosis steps for slow `cloud-init`, Rocky `dnf`, and Debian `apt`/`dpkg` phases in `docs/RUNBOOK_BAKE.md`. On 2026-07-30, host `Neutron`, `git diff --check 67c1829~1 67c1829` exited 0 over the commit's own diff. The documented procedure itself is exercised only by the G3 production bake acceptance. |
| | M5.4 | [Accept the production ioc-runner bake for Rocky 8 and Debian 13 (#23)](https://github.com/jeonghanlee/cloud-provision/issues/23) | 🔒 | | ← G3 | The Rocky 8 and Debian 13 ioc-runner bakes run from the current `origin/master`, fresh `rocky8-iocrunner.server` and `debian13-iocrunner.server` consumers boot, and each recorded manifest matches its running system. Procedure is in `docs/RUNBOOK_BAKE.md`. Resume as ⬜ when G3 completes. |

## External gates (G)

| G | What | Blocks | Status | Evidence |
| :-- | :-- | :-- | :-- | :-- |
| G1 | Run downstream validation on the 2026-06-03 Rocky 8 golden image | M1.5 | Open | Requires the real golden image, `rocky8-iocrunner.server`, and the downstream ioc-runner validation environment. |
| G2 | Confirm whether the ioc-runner bake requires its 120-second shutdown allowance | M3.3 | Open | Owner decision required before the bake can share the provisioner's 60-second stop behavior. |
| G3 | Run the production ioc-runner bake acceptance for Rocky 8 and Debian 13 | M5.4 | Open | Requires the production bake host, network access for the real package phases, and fresh `rocky8-iocrunner.server` and `debian13-iocrunner.server` consumers. The offline contract checks under `make check-bake` do not substitute for it. The `EPICS-env` 1.3.0 M7 release gate consumes this acceptance: its `M7.T3` requires full-environment install verification on real VMs, and its release verification plan provisions those VMs through this repository's Make targets. See External identifiers above. |

## Decisions (D)

| D | Content | Decided in |
| :-- | :-- | :-- |
| D1 | Use `Nimbus - Cloud Provisioning Reliability` as the current non-versioned reliability milestone. | [GitHub milestone 1](https://github.com/jeonghanlee/cloud-provision/milestone/1), 2026-07-23 |
| D2 | Organize the register as three workstream groups with `M<group>.<task>` identifiers and retain completed golden-image history in M1. | Work Register consolidation, 2026-07-23 |
| D3 | Track all four M3.1 out-of-scope policy areas as separate GitHub issues and keep M3.1 limited to `cloud-init status` completion parsing. | User direction, 2026-07-23 |
| D4 | Keep the M3.1 test boundary limited to `virsh` and `ssh`; forward fast normal-readiness rejection coverage to M4.5. | User direction, 2026-07-23 |
| D5 | M3.2 resolver plan is approved, but implementation must not proceed directly on `master` because other repositories consume it; the local review-session archive is on host `Neutron`. | User direction, 2026-07-23 |
| D6 | Track the 2026-07-29 bake provenance commits as their own group M5 rather than under M3 or M4, because they own image publication integrity rather than shared runtime behavior or provisioning policy. | User direction, 2026-07-30 |
| D7 | Command-based runbooks carry no milestone, issue, plan, or review identifier and no current project state, so every procedure stays executable from the page alone at any point in the project's life. Tracking documents may point at a runbook; a runbook never points back. Written out in `docs/RUNBOOK_BAKE.md` under Runbook rules. | User direction, 2026-07-30 |
| D8 | Extend the D4 boundary for the M4.5 readiness cases only: `tests/check-cloud-init-status.bash` also replaces `sleep`, the clock boundary, so the readiness retry budget runs without wall-clock cost. No production line changes. D4 stands unchanged for every other purpose. | User direction, 2026-07-31 |

## Conventions

- The register is written in English; status markers use the emoji set above.
- One task row is one deliverable plus its verification.
- `Progress` is done/total tasks in the group. Group status and the ready set
  derive from task status and dependency arrows.
- GitHub controls issue membership and open/closed state. This register controls
  workstream grouping, dependency edges, decisions, and the next-session handoff.
