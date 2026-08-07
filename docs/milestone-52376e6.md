# Work Register

Release line: master
Milestone index: 52376e6
Canonical path: `docs/milestone-52376e6.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: plan M8.1 - the first buildable step of `docs/IMAGE_WORKFLOW.md`. Create a branch before any implementation, per D12.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Golden image lifecycle | M1.1 | Refresh the Rocky 8 golden image | Milestone | Complete | No |  | See [M1.1 detail](#m11) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.2 | Check the current Debian 13 golden image | Milestone | Complete | No |  | See [M1.2 detail](#m12) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.3 | Retire the 2026-05-13 Rocky 8 sudoers defect | Milestone | Complete | No |  | See [M1.3 detail](#m13) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.4 | Preserve pinned golden images across rebakes | Milestone | Complete | No | M1.6 | See [M1.4 detail](#m14) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.5 | Validate the Rocky 8 golden after the sudoers fix | Milestone | Blocked | No | G1 | See [M1.5 detail](#m15) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.6 | Separate the bake archive from the VM working images | Milestone | Complete | No |  | See [M1.6 detail](#m16) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.7 | Bring the EtherCAT bake onto the shared image structure | Milestone | Deferred | No | M8.1 | See [M1.7 detail](#m17) for the migrated done-when rule and evidence. |
| M1 Golden image lifecycle | M1.8 | Bring the EtherCAT bake onto the shared VM creation path | Milestone | Not started | No | M8.1 | See [M1.8 detail](#m18) for the migrated done-when rule and evidence. |
| M2 VM provisioning configuration | M2.1 | Pass `EPICS_ENV_RAM` to per-VM recreate targets | Milestone | Complete | No |  | See [M2.1 detail](#m21) for the migrated done-when rule and evidence. |
| M2 VM provisioning configuration | M2.2 | Synchronize the documented default VM memory | Milestone | Complete | No | M2.1 | See [M2.2 detail](#m22) for the migrated done-when rule and evidence. |
| M2 VM provisioning configuration | M2.3 | Install `qemu-utils` explicitly on Debian hosts | Milestone | Complete | No |  | See [M2.3 detail](#m23) for the migrated done-when rule and evidence. |
| M2 VM provisioning configuration | M2.4 | List every supported OS type in `create_vm.bash` help | Milestone | Complete | No |  | See [M2.4 detail](#m24) for the migrated done-when rule and evidence. |
| M2 VM provisioning configuration | M2.5 | Centralize the required `libvirt` group | Milestone | Complete | No |  | See [M2.5 detail](#m25) for the migrated done-when rule and evidence. |
| M3 Shared behavior consistency | M3.1 | Centralize cloud-init completion parsing | Milestone | Complete | No |  | See [M3.1 detail](#m31) for the migrated done-when rule and evidence. |
| M3 Shared behavior consistency | M3.2 | Keep VM naming defaults consistent across provision and bake paths | Milestone | Complete | No | D11 | See [M3.2 detail](#m32) for the migrated done-when rule and evidence. |
| M3 Shared behavior consistency | M3.3 | Reuse VM stop behavior in the ioc-runner bake | Milestone | Blocked | No | M4.2, G2 | See [M3.3 detail](#m33) for the migrated done-when rule and evidence. |
| M3 Shared behavior consistency | M3.4 | Make concurrent `create_vm.bash` runs seed-safe | Milestone | Complete | No |  | See [M3.4 detail](#m34) for the migrated done-when rule and evidence. |
| M3 Shared behavior consistency | M3.5 | A node ID outside the known set gives every OS type the same IP and MAC | Milestone | Complete | No |  | See [M3.5 detail](#m35) for the migrated done-when rule and evidence. |
| M4 Explicit policy follow-ups | M4.1 | Define the SSH readiness policy for VM lifecycle checks | Milestone | Complete | No |  | See [M4.1 detail](#m41) for the migrated done-when rule and evidence. |
| M4 Explicit policy follow-ups | M4.2 | Review VM readiness and shutdown wait budgets | Milestone | Not started | Yes |  | See [M4.2 detail](#m42) for the migrated done-when rule and evidence. |
| M4 Explicit policy follow-ups | M4.3 | Clarify libvirt lifecycle behavior across VM actions | Milestone | Complete | No |  | See [M4.3 detail](#m43) for the migrated done-when rule and evidence. |
| M4 Explicit policy follow-ups | M4.4 | Clarify image selection behavior across provision and bake paths | Milestone | Complete | No |  | See [M4.4 detail](#m44) for the migrated done-when rule and evidence. |
| M4 Explicit policy follow-ups | M4.5 | Add fast public-path coverage for cloud-init readiness rejection | Milestone | Complete | No | D8 | See [M4.5 detail](#m45) for the migrated done-when rule and evidence. |
| M5 ioc-runner bake provenance | M5.1 | Validate ioc-runner bake provenance before publication | Milestone | Complete | No |  | See [M5.1 detail](#m51) for the migrated done-when rule and evidence. |
| M5 ioc-runner bake provenance | M5.2 | Separate VM provisioning targets from bake selector families | Milestone | Complete | No | M5.1 | See [M5.2 detail](#m52) for the migrated done-when rule and evidence. |
| M5 ioc-runner bake provenance | M5.3 | Document the post-bake acceptance checks | Milestone | Complete | No | M5.2 | See [M5.3 detail](#m53) for the migrated done-when rule and evidence. |
| M5 ioc-runner bake provenance | M5.4 | Accept the production ioc-runner bake for Rocky 8 and Debian 13 | Milestone | Complete | No | G3 | See [M5.4 detail](#m54) for the migrated done-when rule and evidence. |
| M5 ioc-runner bake provenance | M5.5 | Accept the requested ioc-runner version field and pass a selector through the bake | Milestone | Complete | No |  | See [M5.5 detail](#m55) for the migrated done-when rule and evidence. |
| M6 Unattended bake execution | M6.1 | Bake refuses to start its configuration step when launched without a terminal | Milestone | Complete | No |  | See [M6.1 detail](#m61) for the migrated done-when rule and evidence. |
| M6 Unattended bake execution | M6.2 | Bake publish step stalls when the previous golden changed owner | Milestone | Complete | No |  | See [M6.2 detail](#m62) for the migrated done-when rule and evidence. |
| M6 Unattended bake execution | M6.3 | A failed bake names no way to clean up after itself | Milestone | Complete | No |  | See [M6.3 detail](#m63) for the migrated done-when rule and evidence. |
| M6 Unattended bake execution | M6.4 | A helper's `trap -` uninstalls the bake's own exit handler | Milestone | Complete | No |  | See [M6.4 detail](#m64) for the migrated done-when rule and evidence. |
| M6 Unattended bake execution | M6.5 | Refresh-only claims a build VM it never created | Milestone | Complete | No | M6.3, M6.4 | See [M6.5 detail](#m65) for the migrated done-when rule and evidence. |
| M7 Record integrity | M7.1 | Pin every cited source coordinate to the tree it was read from | Milestone | Complete | No |  | See [M7.1 detail](#m71) for the migrated done-when rule and evidence. |
| M8 Image workflow adoption | M8.1 | Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md` | Milestone | Not started | Yes | D11 | See [M8.1 detail](#m81) for the migrated done-when rule and evidence. |
| External gate | G1 | Run downstream validation on the 2026-06-03 Rocky 8 golden image | External gate | Open | No |  | See [G1 detail](#g1) for the migrated condition and evidence. |
| External gate | G2 | Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance | External gate | Open | No |  | See [G2 detail](#g2) for the migrated condition and evidence. |
| External gate | G3 | Run the production ioc-runner bake acceptance for Rocky 8 and Debian 13 | External gate | Complete | No |  | See [G3 detail](#g3) for the migrated condition and evidence. |

### Decisions

| ID | Decision | Source |
| --- | --- | --- |
| D1 | Use `Nimbus - Cloud Provisioning Reliability` as the current non-versioned reliability milestone. | [GitHub milestone 1](https://github.com/jeonghanlee/cloud-provision/milestone/1), 2026-07-23 |
| D2 | Organize the register as three workstream groups with `M<group>.<task>` identifiers and retain completed golden-image history in M1. | Work Register consolidation, 2026-07-23 |
| D3 | Track all four M3.1 out-of-scope policy areas as separate GitHub issues and keep M3.1 limited to `cloud-init status` completion parsing. | User direction, 2026-07-23 |
| D4 | Keep the M3.1 test boundary limited to `virsh` and `ssh`; forward fast normal-readiness rejection coverage to M4.5. | User direction, 2026-07-23 |
| D5 | M3.2 resolver plan is approved, but implementation must not proceed directly on `master` because other repositories consume it; the local review-session archive is on host `Neutron`. | User direction, 2026-07-23 |
| D6 | Track the 2026-07-29 bake provenance commits as their own group M5 rather than under M3 or M4, because they own image publication integrity rather than shared runtime behavior or provisioning policy. | User direction, 2026-07-30 |
| D7 | Command-based runbooks carry no milestone, issue, plan, or review identifier and no current project state, so every procedure stays executable from the page alone at any point in the project's life. Tracking documents may point at a runbook; a runbook never points back. Written out in `docs/RUNBOOK_BAKE.md` under Runbook rules. | User direction, 2026-07-30 |
| D8 | Extend the D4 boundary for the M4.5 readiness cases only: `tests/check-cloud-init-status.bash` also replaces `sleep`, the clock boundary, so the readiness retry budget runs without wall-clock cost. No production line changes. D4 stands unchanged for every other purpose. | User direction, 2026-07-31 |
| D9 | Golden images split into an archive of versioned entries that no VM backs onto and one working copy per platform that consumers use. The archive gets its own directory for discipline rather than correctness; entries are named from the manifest's own `bake_date`; the current and previous entry are retained; upstream base images are excluded because they are re-fetchable. Recorded in `docs/ARCHITECTURE.md` section 16. | User direction, 2026-07-31 |
| D10 | Every source coordinate a document cites carries the commit it was read from: `` `<path>:<line>[-<line>]@<hash>` ``. A bare `file:line` is refused, because it silently stops being true the next time a line is inserted above it, and a bare `:<line>` with no file is refused because only the prose around it says which file is meant. The hash is the tree the writer actually read - the commit that introduced the sentence for a historical statement, `HEAD` for a statement about the code now, which becomes a historical statement on its own the moment the code moves. Enforced by `make check-docs`. | User direction, 2026-08-01 |
| D11 | Image structure is settled by `docs/IMAGE_WORKFLOW.md`: a copy at every step so nothing upstream is held, identity carried by a file name and a creation record that must agree, the naming rule defined in one place, and build VMs fresh by construction. It supersedes the archive layout, the fresh-input enforcement, and the resolver plan rather than extending them; M8.1 is where it is built. | User direction, 2026-08-01 |
| D12 | New development moves to branches: `master` takes no direct implementation work from here on, and the annotated tag `pre-image-workflow` marks the last state built that way. | User direction, 2026-08-01 |

### Source Notes

- Legacy source: `docs/milestone.md`, committed at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`; it remains in place as historical evidence and is no longer the active register.
- The legacy register used GitHub-authoritative issue membership and issue state, while its own grouping, dependencies, decisions, and handoff text remained repository-owned.
- The legacy C-ID map is preserved here for historical lookup: C1 -> M2.3 (#5), C2 -> M3.1 (#6), C3 -> M3.2 (#7), C4 -> M2.4 (#8), C5 -> M2.5 (#9), and C6 -> M3.3 (#11).
- GitHub issue #1 predates this register and has no row.
- `P008` and `M.7` belong to the `EPICS-env` 1.3.0 release cycle, not this repository; the legacy register's external reference is retained in the source file.
- The legacy register named M4.1 through M4.5 as backlog forwarding, but all five rows were assigned in its task table; the canonical Backlog is therefore empty.
- M1.7 is normalized from legacy Not started to canonical Deferred because its preserved evidence records an explicit owner deferral dated 2026-07-31.

### Milestone Details

<a id="m11"></a>
#### M1.1 - Refresh the Rocky 8 golden image

Origin: 52376e6 / M1.1
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Refresh the Rocky 8 golden image. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Refresh the Rocky 8 golden image.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `make bake.rocky8` completed on 2026-06-03. The resulting 20 GiB qcow2 reported 4.43 GiB disk use and `corrupt: false`.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Refresh the Rocky 8 golden image
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m12"></a>
#### M1.2 - Check the current Debian 13 golden image

Origin: 52376e6 / M1.2
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Check the current Debian 13 golden image. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Check the current Debian 13 golden image.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- The shipped setup path reported 8/8 and system-infrastructure validation reported 41/41; the prior `acl` and `logrotate` omissions were not observed.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.2 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.2 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Check the current Debian 13 golden image
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m13"></a>
#### M1.3 - Retire the 2026-05-13 Rocky 8 sudoers defect

Origin: 52376e6 / M1.3
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Retire the 2026-05-13 Rocky 8 sudoers defect. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Retire the 2026-05-13 Rocky 8 sudoers defect.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Superseded by M1.1, whose bake applied the `ansible-provision` sudoers `includedir` ordering change.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.3 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.3 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Retire the 2026-05-13 Rocky 8 sudoers defect
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m14"></a>
#### M1.4 - Preserve pinned golden images across rebakes

Origin: 52376e6 / M1.4
Identity History: none
GitHub Issue: #2 - https://github.com/jeonghanlee/cloud-provision/issues/2
Status: Complete

##### Summary

Preserve pinned golden images across rebakes. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Preserve pinned golden images across rebakes.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Rebakes use new filenames, pinned images remain until downstream pins advance, and the retention rule is documented. Delivered with M1.6: rebakes land under `iocrunner-<os>-<bake_date>.qcow2` in the archive rather than overwriting in place, so an image a downstream gate pins survives the next bake. Retention keeps the current and previous entry and reports the rest as surplus without deleting, per the issue's own acceptance that the policy line is the deliverable. Documented in `docs/ARCHITECTURE.md` section 16. Same evidence and session as M1.6.

##### Dependencies And Decisions

- M1.6

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.4 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.4 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Preserve pinned golden images across rebakes
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m15"></a>
#### M1.5 - Validate the Rocky 8 golden after the sudoers fix

Origin: 52376e6 / M1.5
Identity History: none
GitHub Issue: #4 - https://github.com/jeonghanlee/cloud-provision/issues/4
Status: Blocked

##### Summary

Validate the Rocky 8 golden after the sudoers fix. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Validate the Rocky 8 golden after the sudoers fix.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- The real `rocky8-iocrunner.server` path passes the downstream system-infrastructure and system-lifecycle checks, with commands and results recorded. Resume as ⬜ when G1 completes.

##### Dependencies And Decisions

- G1

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.5 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.5 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- Blocked by G1. Restore the executable status recorded in the legacy register when every external gate is Complete.

##### GitHub Projection

Title: Validate the Rocky 8 golden after the sudoers fix
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m16"></a>
#### M1.6 - Separate the bake archive from the VM working images

Origin: 52376e6 / M1.6
Identity History: none
GitHub Issue: #25 - https://github.com/jeonghanlee/cloud-provision/issues/25
Status: Complete

##### Summary

Separate the bake archive from the VM working images. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Separate the bake archive from the VM working images.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- A bake run after a full consumer create-and-destroy cycle publishes without a manual `chown`, without an overwrite prompt, and without touching a file the baking account does not own; the published golden never appears in any domain's backing chain. One directory currently serves two roles: the bake writes the golden there and every consumer backs onto it there, so libvirt `dynamic_ownership` claims it on consumer start and never restores it after a `.clean` teardown. Carries three deferred items recorded on #25 - the EtherCAT publish step at `bin/bake_ethercat_image.bash:206-207@77fd36e`, which still uses plain `mv`; the backing-chain scan in `protect_output_consumers` at `bin/bake_iocrunner_image.bash:95@77fd36e`, which must follow the working copy; Archive at `${IMAGE_DIR}/../archive` holds every published pair under a name taken from the manifest's own `bake_date`; nothing backs onto an entry, so libvirt never claims one. `refresh_working_copy` copies a chosen entry to the working copy at today's unchanged path and name - a real file, guarded by an explicit symlink check - and `protect_output_consumers` moved from publish to refresh, because nothing backs onto an archive entry and a guard there could never fire. `make bake.<os>` publishes then refreshes, so it ends where it always did; `make refresh.<os>` and `-R <entry>` roll a platform back. Provisioning refuses a missing working copy and names the refresh target rather than refreshing implicitly. Retention reports the current and previous entry as kept and the rest as surplus, deleting nothing. Documented in `docs/ARCHITECTURE.md` section 16; `docs/DESIGN_IMAGE_LAYOUT.md` was folded in and removed. On 2026-07-31, host `Neutron`, `make check-bake` exited 0 with 24/24, up from 20, and `make check-cloud-init-status` 63/63. Teeth confirmed by two mutations: publishing back into the image directory failed the archive-entry and sidecar assertions, and making the working copy a symlink failed the real-file assertion. A retention listing defect was caught and fixed before commit - an empty archive reported one nameless entry because `printf` with no arguments emits a blank line. A real bake ran on 2026-08-01, host `Neutron`, and produced the layout for the first time: `/data/libvirt/archive/iocrunner-rocky8-20260801T073406Z.qcow2` with its sidecar, and `/data/libvirt/images/iocrunner-rocky8.qcow2` as a real-file working copy, both owned by the baking account. That run also surfaced a first-transition case this row had not anticipated. A golden published before the split is backed onto directly by its consumers, so the in-use guard at `bin/bake_iocrunner_image.bash:138@e8318b6` refuses the very bake that would create the split - the layout cannot bootstrap while any consumer defined from the pre-split golden still exists, running or shut off, because the guard scans `virsh list --all`. Removing the consumer with its `.clean` target cleared it, and the consumer was recreated from the new working copy afterward. The refusal is correct and no change is proposed; recorded so the next operator meeting it does not read it as a defect. Session `work/review_sessions/20260731_092657_m1_6_m1_4_image_layout`. The EtherCAT publish step is not included and is carried by M1.7; the base images are excluded by design because they are re-fetchable.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.6 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.6 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Separate the bake archive from the VM working images
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m17"></a>
#### M1.7 - Bring the EtherCAT bake onto the shared image structure

Origin: 52376e6 / M1.7
Identity History: none
GitHub Issue: none
Status: Deferred

##### Summary

Bring the EtherCAT bake onto the shared image structure. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


The legacy register used `Not started`; this status is normalized to `Deferred` because the preserved evidence records an owner deferral on 2026-07-31.

##### Scope

- Deliverable: Bring the EtherCAT bake onto the shared image structure.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Follow-up to M8.1, not superseded by it: the target changed from the archive layout to the structure M8.1 builds, but the work - EtherCAT publishing like the ioc-runner bake instead of its own way - is the same and still needed. Cannot start before M8.1 lands, because the structure to join does not exist yet. `bin/bake_ethercat_image.bash:222-223@c177daa` still publishes with a plain `mv` directly into the image directory, so the two bakes now have different layouts. Deferred by owner direction on 2026-07-31 until the ioc-runner layout has settled in real use. The shape to reach is `docs/ARCHITECTURE.md` section 16; whether the shared archive and refresh logic is extracted into one file both bakes use, or copied, is open and was explicitly not decided.

##### Dependencies And Decisions

- M8.1

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.7 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.7 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- Owner deferral is recorded under Completion Criteria; no closure evidence is claimed.

##### GitHub Projection

Title: Bring the EtherCAT bake onto the shared image structure
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m18"></a>
#### M1.8 - Bring the EtherCAT bake onto the shared VM creation path

Origin: 52376e6 / M1.8
Identity History: none
GitHub Issue: none
Status: Not started

##### Summary

Bring the EtherCAT bake onto the shared VM creation path. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Bring the EtherCAT bake onto the shared VM creation path.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Follow-up to M8.1, not superseded by it. Unique names make VM reuse impossible only for the paths M8.1 converts; the EtherCAT bake has to be moved onto that path for the guarantee to reach it, and until then it keeps reusing whatever VM stands. The fix is no longer `-F` but joining the shared creation path. The two bakes call the same `bin/create_vm.bash` on opposite assumptions. The ioc-runner bake passes `-F` at `bin/bake_iocrunner_image.bash:535@f7bceca`, so `require_fresh_input` at `bin/create_vm.bash:418-436@f7bceca` refuses when a domain of that name is already defined or its disk still exists. The EtherCAT bake omits `-F` at `bin/bake_ethercat_image.bash:132@f7bceca`, and its comment at `bin/bake_ethercat_image.bash:129@f7bceca` states the opposite intent outright - "create_vm.bash is idempotent - handles not-defined / shut off / running". Consequence: an EtherCAT bake can run on a VM a previous bake left behind, already provisioned and already de-proxied, and still stamp `/etc/ethercat-bake.manifest` at `bin/bake_ethercat_image.bash:152@f7bceca` and publish it as a sidecar at `bin/bake_ethercat_image.bash:223@f7bceca`. The manifest then describes a build nobody made from a fresh base. This is the state M5.1 removed from the ioc-runner bake, which is why the divergence reads as drift rather than as a decision: neither side records a reason for differing. Found 2026-08-01 by a coherence sweep, not by a failure; no EtherCAT bake is known to have produced a wrong manifest this way. Not verified by running: the claim above rests on reading the three files, and `make check-bake` covers the ioc-runner bake only. Done when both bakes agree on whether a build VM may be reused, the choice is written down for whichever way it goes, and a check covers the EtherCAT side. Related to M1.7, which is the other half of the same repository having grown one bake at a time; kept separate because that row is about the archive layout and this one about build inputs.

##### Dependencies And Decisions

- M8.1

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.8 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.8 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- none

##### GitHub Projection

Title: Bring the EtherCAT bake onto the shared VM creation path
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m21"></a>
#### M2.1 - Pass `EPICS_ENV_RAM` to per-VM recreate targets

Origin: 52376e6 / M2.1
Identity History: none
GitHub Issue: #3 - https://github.com/jeonghanlee/cloud-provision/issues/3
Status: Complete

##### Summary

Pass `EPICS_ENV_RAM` to per-VM recreate targets. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Pass `EPICS_ENV_RAM` to per-VM recreate targets.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `7286a6b` passes `EPICS_ENV_RAM` explicitly to generated EPICS-env per-VM targets, passed V001 V002 V003 V004, and has accepted implementation review with final handoff `hand20260723_135020`.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Pass `EPICS_ENV_RAM` to per-VM recreate targets
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m22"></a>
#### M2.2 - Synchronize the documented default VM memory

Origin: 52376e6 / M2.2
Identity History: none
GitHub Issue: #13 - https://github.com/jeonghanlee/cloud-provision/issues/13
Status: Complete

##### Summary

Synchronize the documented default VM memory. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Synchronize the documented default VM memory.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `47c7162` makes `README.md`, executable help, and the default passed to `virt-install` agree on 4096 MB; GitHub #13 is closed.

##### Dependencies And Decisions

- M2.1

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2.2 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2.2 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Synchronize the documented default VM memory
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m23"></a>
#### M2.3 - Install `qemu-utils` explicitly on Debian hosts

Origin: 52376e6 / M2.3
Identity History: none
GitHub Issue: #5 - https://github.com/jeonghanlee/cloud-provision/issues/5
Status: Complete

##### Summary

Install `qemu-utils` explicitly on Debian hosts. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Install `qemu-utils` explicitly on Debian hosts.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `3da8726` adds `qemu-utils` to the Debian package list. On 2026-07-23, disposable Debian 13 VM `m2qemu-debian13-m23qemu` verified `APT::Install-Recommends "false";`, `qemu-img` absent before setup, `make setup` exit 0, `qemu-img` present afterward, and `make check-tools` exit 0.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2.3 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2.3 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Install `qemu-utils` explicitly on Debian hosts
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m24"></a>
#### M2.4 - List every supported OS type in `create_vm.bash` help

Origin: 52376e6 / M2.4
Identity History: none
GitHub Issue: #8 - https://github.com/jeonghanlee/cloud-provision/issues/8
Status: Complete

##### Summary

List every supported OS type in `create_vm.bash` help. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: List every supported OS type in `create_vm.bash` help.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `f7bac56` lists all 11 supported `OS_TYPE` values in executable help and README, adds `make check-vm-help`, and closed GitHub #8.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2.4 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2.4 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: List every supported OS type in `create_vm.bash` help
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m25"></a>
#### M2.5 - Centralize the required `libvirt` group

Origin: 52376e6 / M2.5
Identity History: none
GitHub Issue: #9 - https://github.com/jeonghanlee/cloud-provision/issues/9
Status: Complete

##### Summary

Centralize the required `libvirt` group. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Centralize the required `libvirt` group.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `e94c85d` defines `REQUIRED_GROUP := libvirt`, passes it through setup, VM, EPICS-env, and bake Make paths, adds `make check-required-group`, received Reviewer 1 implementation acceptance, and closed GitHub #9.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2.5 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2.5 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Centralize the required `libvirt` group
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m31"></a>
#### M3.1 - Centralize cloud-init completion parsing

Origin: 52376e6 / M3.1
Identity History: none
GitHub Issue: #6 - https://github.com/jeonghanlee/cloud-provision/issues/6
Status: Complete

##### Summary

Centralize cloud-init completion parsing. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Centralize cloud-init completion parsing.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `2e7a512` makes both public script paths use `parse_cloud_init_status`. Local verification passed `make check-cloud-init-status` 8/8, `shellcheck bin/create_vm.bash tests/check-cloud-init-status.bash`, `git diff --check`, and `REQUIRED_GROUP=$(id -gn) make check-vm-help`; three-lane implementation re-review accepted. Fast rejection coverage for the normal readiness path moved to M4.5. The 8/8 count is the observation of 2026-07-23; the same target now also carries the M4.5 readiness cases, so later runs report a higher total.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Centralize cloud-init completion parsing
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m32"></a>
#### M3.2 - Keep VM naming defaults consistent across provision and bake paths

Origin: 52376e6 / M3.2
Identity History: none
GitHub Issue: #7 - https://github.com/jeonghanlee/cloud-provision/issues/7
Status: Complete

##### Summary

Keep VM naming defaults consistent across provision and bake paths. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Keep VM naming defaults consistent across provision and bake paths.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Retired 2026-08-01, not delivered: #7 closed as not planned. The defect it named - `VM_NAME` and the disk paths computed separately by `bin/create_vm.bash` and each bake - is real and unfixed, and is carried by M8.1, whose acceptance requires names to come from one place. What is retired is this row's plan, not its finding: `plan20260723_234700` would have extracted a resolver from the current naming rule, and M8.1 replaces that rule outright, so extracting it first would build something the new one discards. D5's dedicated-branch condition retires with the plan it guarded. `plan20260723_234700` is approved for a shared resolver command, but implementation is intentionally deferred off `master`; create a dedicated branch before editing. Local review-session archive is on host `Neutron`.

##### Dependencies And Decisions

- D11

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.2 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.2 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- Owner-approved retirement is recorded in the preserved legacy evidence under Completion Criteria. No new closure verification was run during canonicalization.

##### GitHub Projection

Title: Keep VM naming defaults consistent across provision and bake paths
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m33"></a>
#### M3.3 - Reuse VM stop behavior in the ioc-runner bake

Origin: 52376e6 / M3.3
Identity History: none
GitHub Issue: #11 - https://github.com/jeonghanlee/cloud-provision/issues/11
Status: Blocked

##### Summary

Reuse VM stop behavior in the ioc-runner bake. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Reuse VM stop behavior in the ioc-runner bake.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- The required bake timeout is decided; the shared or explicitly separate paths cover successful shutdown, timeout, and unexpected state. M4.2 settles the shutdown budget first, so only the code decision - share `do_stop` or keep a parameterized path - remains here. Resume as ⬜ when M4.2 and G2 complete.

##### Dependencies And Decisions

- M4.2
- G2

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.3 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.3 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- Blocked by M4.2, G2. Restore the executable status recorded in the legacy register when every external gate is Complete.

##### GitHub Projection

Title: Reuse VM stop behavior in the ioc-runner bake
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m34"></a>
#### M3.4 - Make concurrent `create_vm.bash` runs seed-safe

Origin: 52376e6 / M3.4
Identity History: none
GitHub Issue: #22 - https://github.com/jeonghanlee/cloud-provision/issues/22
Status: Complete

##### Summary

Make concurrent `create_vm.bash` runs seed-safe. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Make concurrent `create_vm.bash` runs seed-safe.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Two concurrent runs for different OS types both reach `READY` with working `vmadmin` SSH; each seed ISO carries exactly one `local-hostname` equal to its own VM name; a failed `genisoimage` step exits non-zero instead of reporting `[OK]`; serial behavior and timings unchanged. Held rather than produced: the shared staging path #22 named was already gone. `c4ba7fd` moved staging to `${IMAGE_DIR}/${VM_NAME}.seed_staging` on 2026-07-29 as a one-line change with no comment, because the old path sat inside the repository and `bin/bake_iocrunner_image.bash:78@0d8ea2f` counts untracked files when recording provenance - every bake would have stamped `cloud-provision <sha>-dirty`. The race disappeared as a side effect nobody reasoned about, which is why nothing recorded or tested it. This row adds the holding. `genisoimage` no longer discards its failure reason: the output is captured and replayed only on failure, because the tool writes statistics to stderr even when it succeeds; the staging directory is left in place on failure so the inputs that caused it survive. Verified on real VMs, 2026-07-31, host `Neutron`: `testbed-rocky8-server` and `testbed-debian13-server` provisioned concurrently both reached `READY` inside three minutes, `vmadmin` SSH worked on both and each reported its own hostname, and each seed ISO read back exactly one `local-hostname` equal to its own VM name with distinct `instance-id` values. Both VMs were removed afterwards. Offline: `make check-cloud-init-status` exited 0 with 73/73, up from 63. Teeth confirmed by mutation - moving staging back inside the repository failed `stages outside the repository`, and discarding the failure reason failed `names the reason`; the first mutation also left `.seed_staging/` in the working tree, demonstrating the provenance contamination directly. Found while verifying: the node-ID address collision, registered as M3.5. Session `work/review_sessions/20260731_152147_m3_4_seed_race`.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.4 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.4 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Make concurrent `create_vm.bash` runs seed-safe
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m35"></a>
#### M3.5 - A node ID outside the known set gives every OS type the same IP and MAC

Origin: 52376e6 / M3.5
Identity History: none
GitHub Issue: #27 - https://github.com/jeonghanlee/cloud-provision/issues/27
Status: Complete

##### Summary

A node ID outside the known set gives every OS type the same IP and MAC. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: A node ID outside the known set gives every OS type the same IP and MAC.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Two VMs of different OS types created with the same unknown node ID receive different addresses and different MACs; `server`, `node1`, and `node2` keep today's values; a check covers the fallback mapping without provisioning. Observed 2026-07-31 while verifying M3.4: `-n probe` reported `192.168.122.241` for `rocky8`, `debian13`, and `epics-env-rocky8` alike, because the per-OS base is applied only on the known-node-ID branch while the fallback hashes `NODE_ID` alone into both the address and the MAC. The M3.4 verification used `-n server` and so did not hit it. The fallback mapping now hashes `${OS_TYPE}/${NODE_ID}` rather than the node ID alone, so an address identifies a VM. The range moved from 200-254 to 160-254: 160-199 sits between the highest per-OS block and the old window and nothing else uses it, so widening cost nothing and roughly halves the collision rate. A fixed range still collides, so `register_dhcp` now names it - the address, the VM holding it, and the node ID that produced it - instead of letting libvirt's generic duplicate-entry error stand as the explanation. Verified 2026-07-31, host `Neutron`: all eleven OS types with `-n probe` receive eleven distinct addresses, where the committed version gave `192.168.122.241` to every one of them; and `server`, `node1`, `node2` were compared against the committed script through the header path and are byte-identical (150/151/152, 50/51/52, 70/71/72). `make check-cloud-init-status` exited 0 with 77/77, up from 73. Teeth confirmed by mutation: hashing the node ID alone failed the distinctness assertion, and shifting a known base failed the two fixed-value assertions. Correction recorded on the issue: the original body claimed the second run overwrites the first's reservation. It does not - `register_dhcp` deletes only its own exact triple, and libvirt refuses the duplicate add, which was confirmed directly with two throwaway entries on an unused address. The second run aborts loudly rather than corrupting anything, which lowers the severity but not the reason to fix it. Follow-up, `ca3290c`: the guard this row added was itself defective and shipped untested. It matched the address with an awk regex, so `192.168.122.10` read as held by the entry for `192.168.122.101` and a VM whose address was free was refused - worse than the collision it was added to name, because it blocked correct work rather than merely failing to explain a failure. Found when it stopped a routine provisioning run. The address is now compared as a whole quoted field, pinned by three cases including one that asserts the run reached registration at all; the first version of the negative case passed without ever getting there. The lesson recorded: this row's own verification covered the address mapping and not the guard, on the assumption that something which only ever refuses is safe to ship untested.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.5 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.5 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: A node ID outside the known set gives every OS type the same IP and MAC
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m41"></a>
#### M4.1 - Define the SSH readiness policy for VM lifecycle checks

Origin: 52376e6 / M4.1
Identity History: none
GitHub Issue: #17 - https://github.com/jeonghanlee/cloud-provision/issues/17
Status: Complete

##### Summary

Define the SSH readiness policy for VM lifecycle checks. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Define the SSH readiness policy for VM lifecycle checks.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `docs/ARCHITECTURE.md` section 13 states the contract: readiness is a non-interactive, key-only login as `vmadmin` that reaches remote command execution. The four literal `ssh -o` call sites in `bin/create_vm.bash` are replaced by one `SSH_USER`, `SSH_PROBE_OPTIONS`, and `ssh_probe`; no literal option list remains. A changed host key is no longer counted as "not available": `ssh_probe` returns a distinct code, `wait_for_ssh` stops instead of spending its budget, and the operator gets the `ssh-keygen -R` repair for that address. Retry budgets untouched, per #19. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-cloud-init-status` exited 0 with 26/26; `shellcheck` clean. Teeth confirmed by mutation: removing the distinct return code dropped it to 23/26 with exit 2, including `expected 0, got 5` on the budget assertion. Session `work/review_sessions/20260731_034737_m4_1_ssh_readiness_policy`. Surfaced but not done: whether the provisioner should refresh `known_hosts` itself, as the bake scripts do - deliberately excluded because it writes to the operator's trust store and accepts a changed identity unseen.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Define the SSH readiness policy for VM lifecycle checks
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m42"></a>
#### M4.2 - Review VM readiness and shutdown wait budgets

Origin: 52376e6 / M4.2
Identity History: none
GitHub Issue: #19 - https://github.com/jeonghanlee/cloud-provision/issues/19
Status: Not started

##### Summary

Review VM readiness and shutdown wait budgets. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Review VM readiness and shutdown wait budgets.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- All four wait budgets are treated as one policy, documented, and verified: IP discovery (`bin/create_vm.bash:827@c177daa`, 3 x 10s), SSH readiness (`bin/create_vm.bash:868@c177daa`, 6 x 10s), `cloud-init` completion (`bin/create_vm.bash:909@c177daa`, 20 x 30s), and domain shutdown (`do_stop` at `bin/create_vm.bash:373@c177daa`, 12 x 5s, against the bake's own 24 x 5s at `bin/bake_iocrunner_image.bash:614@c177daa`). The measured basis this produces is what lets the owner answer G2; M4.2 itself is not blocked by G2. Observed 2026-07-31 during a production bake, recorded on issue #19: the `cloud-init` budget of 20 attempts at 30 seconds expired while the build VM was healthy and still working - `cloud-init status --long` reported `status: running`, `Running in stage: modules-final`, `errors: []`, `systemctl --failed` listed nothing, and `dnf` had just logged `Total download size: 97 M`. The bake stopped at Step 1 and left a half-provisioned VM that the next attempt must clean up first. The budget, not the boot, ended the run.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.2 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.2 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- none

##### GitHub Projection

Title: Review VM readiness and shutdown wait budgets
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m43"></a>
#### M4.3 - Clarify libvirt lifecycle behavior across VM actions

Origin: 52376e6 / M4.3
Identity History: none
GitHub Issue: #20 - https://github.com/jeonghanlee/cloud-provision/issues/20
Status: Complete

##### Summary

Clarify libvirt lifecycle behavior across VM actions. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Clarify libvirt lifecycle behavior across VM actions.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `docs/ARCHITECTURE.md` section 14 states the policy as one action-by-state table - four actions by five states - because four separate descriptions would reproduce the drift the policy exists to prevent. Three rules are recorded with it: an unexpected state is never resolved by waiting, so every read-or-start action refuses and points at cleanup; cleanup stays state-blind and always returns 0 because idempotent removal reaches the same end state from anywhere and a pre-check would only race; and `unavailable` is not `not defined`. That last one was a real defect - `virsh domstate` fails identically for an absent domain and an unreachable libvirt, so a libvirt outage told the operator to provision a VM that might already exist and let `-S` exit 0 for a question nobody answered. `get_domain_state` now asks the connection separately, and provision refuses before creating anything. The distinction stops at reporting; no retry or reconnect was added, per #19. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-cloud-init-status` exited 0 with 53/53, up from 26; `shellcheck` clean. Teeth confirmed by mutation: collapsing `unavailable` back into `not defined` failed four outage assertions, and the provision case then ran on to attempt a real base-image download - which is what the guard prevents. `do_stop`'s budget untouched, per G2. Session `work/review_sessions/20260731_035600_m4_3_libvirt_lifecycle`.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.3 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.3 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Clarify libvirt lifecycle behavior across VM actions
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m44"></a>
#### M4.4 - Clarify image selection behavior across provision and bake paths

Origin: 52376e6 / M4.4
Identity History: none
GitHub Issue: #18 - https://github.com/jeonghanlee/cloud-provision/issues/18
Status: Complete

##### Summary

Clarify image selection behavior across provision and bake paths. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Clarify image selection behavior across provision and bake paths.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `docs/ARCHITECTURE.md` section 15 records the mapping by class rather than by file name - upstream moving, upstream pinned, and baked locally - because whether an image can be obtained again is the operationally important fact. `-s` and the provision header now print the selected image and its class, so selection is visible before a run does anything. Fixed a defect that could destroy hours of work: `verify_base_image` deleted the base image whenever `qemu-img info` did not report qcow2, before checking whether a download URL existed, so an unusable `iocrunner-*.qcow2` was removed with no way to fetch it back. The delete is gone entirely, the inspection now uses `--force-share` like `bin/bake_iocrunner_image.bash:85@6e67d02`, and the failure reason is reported instead of discarded. The bake output name and the consumer input name are asserted as a pair. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-cloud-init-status` exited 0 with 63/63. Teeth confirmed by mutation, and the first attempt failed that check: restoring the delete left 62/62 green because the case never reached `verify_base_image`, so the case was rewritten to force the fresh-provision path and to assert the refusal reason rather than a name the header also prints; the mutation then failed with `base image was deleted`. The locking route into the defect was not reproduced - no domain was running on this host. Session `work/review_sessions/20260731_091810_m4_4_image_selection`.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.4 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.4 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Clarify image selection behavior across provision and bake paths
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m45"></a>
#### M4.5 - Add fast public-path coverage for cloud-init readiness rejection

Origin: 52376e6 / M4.5
Identity History: none
GitHub Issue: #21 - https://github.com/jeonghanlee/cloud-provision/issues/21
Status: Complete

##### Summary

Add fast public-path coverage for cloud-init readiness rejection. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Add fast public-path coverage for cloud-init readiness rejection.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `tests/check-cloud-init-status.bash` adds two readiness rejection cases that drive the real `wait_for_vm` chain through the shut-off restart branch, replacing only `virsh`, `ssh`, and `sleep`; no production line changed. The retry assertion reads the attempt count from the run instead of pinning the budget, so M4.2 may revise it freely. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-cloud-init-status` exited 0 with 18/18. Teeth confirmed by mutation: removing the `sleep` call from `wait_for_cloud_init` dropped it to 14/18 with exit 2, and the production file was restored to its committed state afterward.

##### Dependencies And Decisions

- D8

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.5 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.5 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Add fast public-path coverage for cloud-init readiness rejection
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m51"></a>
#### M5.1 - Validate ioc-runner bake provenance before publication

Origin: 52376e6 / M5.1
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Validate ioc-runner bake provenance before publication. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Validate ioc-runner bake provenance before publication.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `c4ba7fd` makes the ioc-runner bake fresh-input only, records and validates the manifest before publication, and publishes the image and its sidecar as an atomic pair. Adds `bin/validate_iocrunner_bake.bash`, `tests/check-fresh-bake-inputs.bash`, and `tests/check-iocrunner-bake-provenance.bash` behind `make check-bake`. On 2026-07-30, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-bake` at `67c1829` exited 0 with 7/7 fresh-input and 17/17 provenance checks. Those checks verified the atomic-pair claim only where the invoking user owned the target; every fixture created its own destination. M6.2 carries the case that crosses that boundary.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M5.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Validate ioc-runner bake provenance before publication
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m52"></a>
#### M5.2 - Separate VM provisioning targets from bake selector families

Origin: 52376e6 / M5.2
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Separate VM provisioning targets from bake selector families. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Separate VM provisioning targets from bake selector families.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `b972dc0` separates provisionable OS types, default Make targets, ioc-runner bake inputs, and EtherCAT bake inputs in `README.md`, `docs/ARCHITECTURE.md`, and `docs/RUNBOOK_BAKE.md`. On 2026-07-30, host `Neutron`, `make help.bake` at `67c1829` exited 0 and listed the ioc-runner, validation, and EtherCAT target families separately.

##### Dependencies And Decisions

- M5.1

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5.2 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M5.2 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Separate VM provisioning targets from bake selector families
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m53"></a>
#### M5.3 - Document the post-bake acceptance checks

Origin: 52376e6 / M5.3
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Document the post-bake acceptance checks. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Document the post-bake acceptance checks.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Commit `67c1829` documents the fixed post-bake SSH command contract, stale host-key removal for fresh deterministic-IP consumers, and diagnosis steps for slow `cloud-init`, Rocky `dnf`, and Debian `apt`/`dpkg` phases in `docs/RUNBOOK_BAKE.md`. On 2026-07-30, host `Neutron`, `git diff --check 67c1829~1 67c1829` exited 0 over the commit's own diff. The documented procedure itself is exercised only by the G3 production bake acceptance.

##### Dependencies And Decisions

- M5.2

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5.3 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M5.3 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Document the post-bake acceptance checks
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m54"></a>
#### M5.4 - Accept the production ioc-runner bake for Rocky 8 and Debian 13

Origin: 52376e6 / M5.4
Identity History: none
GitHub Issue: #23 - https://github.com/jeonghanlee/cloud-provision/issues/23
Status: Complete

##### Summary

Accept the production ioc-runner bake for Rocky 8 and Debian 13. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Accept the production ioc-runner bake for Rocky 8 and Debian 13.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- The Rocky 8 and Debian 13 ioc-runner bakes run from the current `origin/master`, fresh `rocky8-iocrunner.server` and `debian13-iocrunner.server` consumers boot, and each recorded manifest matches its running system. Procedure is in `docs/RUNBOOK_BAKE.md`. Accepted 2026-08-01 on host `Neutron` when G3 completed; the evidence, including the six-field record and the two consumer boots, is recorded in the G3 row rather than duplicated here.

##### Dependencies And Decisions

- G3

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5.4 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M5.4 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Accept the production ioc-runner bake for Rocky 8 and Debian 13
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m55"></a>
#### M5.5 - Accept the requested ioc-runner version field and pass a selector through the bake

Origin: 52376e6 / M5.5
Identity History: none
GitHub Issue: #26 - https://github.com/jeonghanlee/cloud-provision/issues/26
Status: Complete

##### Summary

Accept the requested ioc-runner version field and pass a selector through the bake. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Accept the requested ioc-runner version field and pass a selector through the bake.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- A bake with no selector writes the unchanged six-field `app_ioc_runner` record and passes validation; a bake with a selector produces an image whose `ioc-runner -V` reports that ref's commit, writes both `commit=` and `requested=`, and passes validation; a nonexistent ref fails by name during the Ansible run and publishes nothing; and `requested=` on any of the other four application records is rejected. `ansible-provision` already landed its half in `75f16c3` and `ca2a9de`. `bin/validate_iocrunner_bake.bash` accepts one optional trailing `requested=<ref>` on `app_ioc_runner` only, checked for shape - present, non-empty, no whitespace - and deliberately not tied to `tag` or `state`, because a requested ref is caller intent while the tag is whatever points at the resolved commit. The other four application records still take exactly six fields. `bin/bake_iocrunner_image.bash` gains `-r <ref>`, validated against `^[A-Za-z0-9._/-]+$` before the image directory is even checked, and passed as `-e ioc_runner_version=` to the `site.yml` play only; this is the first `--extra-vars` use in the repository and the narrow placement is deliberate, since `04_nfs_sim.yml` and `07_test_users.yml` have nothing to do with the runner version. An unset selector leaves both the invocation and the record byte-identical to before. Documented in `docs/ARCHITECTURE.md` and `docs/RUNBOOK_BAKE.md`. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-bake` exited 0 with 43/43, up from 24; `shellcheck` clean. A single-reviewer gate found the bake half untested and two silent-acceptance defects, all three fixed before commit: `-r` with an empty value was treated as unset, so `-r "${VAR}"` against an unset variable produced an unpinned bake with no warning, and `-r` given with `-R` was discarded because refresh exits before Ansible runs; both are now refused. A new promotion mode `publish-pinned` records every `ansible-playbook` invocation and asserts the selector reaches `site.yml` and no other play, and that an unset selector adds no extra vars at all. Teeth confirmed by mutation, four of them: accepting a trailing field on any record failed the non-runner rejection; dropping the shape check failed the empty, whitespace, and second-field rejections; putting the selector on every play failed both the no-other-play and the unset-selector assertions; and never passing it failed the site.yml assertion. A third review round examined the documentation and found that the archive split had left three stale passages describing the pre-archive layout, two of which this work sat directly beneath; the repair was delegated to a separate agent under a written charter, and that agent found the third passage itself - the charter had said two - plus the missing `ARCHIVE_DIR` row in the bake Inputs table, declining to fix either as outside its charter. A three-lane convergence accepted its edits, settled the remaining two, and recorded two process lessons: a charter must give the symptom and the search rather than a count, and no check in this repository can see documentation becoming false - every suite passes either way. A final adversarial pass then found one more silent acceptance: `-r -k` swallowed the next flag as the ref and the character class accepted the dash-led value, so the bake proceeded pinned to `-k`; refused now, with guard tests that assert the named refusal because their first version stayed green over the removed guard - the bake failed anyway on a nonexistent directory. Sessions `work/review_sessions/20260731_181624_m5_5_docs_convergence`. The pinned-bake half of the acceptance - an image whose `ioc-runner -V` reports the requested tag's commit - needs a real bake and is not covered here. Original context: until this landed, `ioc_runner_version` had to stay empty in real bakes, and an earlier revision of this row recorded the pre-implementation code state; that reading was left in place after the work landed and is superseded here. Verified against the code 2026-08-01: `parse_app_record` at `bin/validate_iocrunner_bake.bash:93-97@1c8eb7d` accepts the optional `requested=<ref>`; `bin/bake_iocrunner_image.bash:346@1c8eb7d` takes `-r` and `bin/bake_iocrunner_image.bash:536@1c8eb7d` passes `-e ioc_runner_version=` to `site.yml` alone, while the calls at `bin/bake_iocrunner_image.bash:538@1c8eb7d`, `bin/bake_iocrunner_image.bash:545@1c8eb7d`, and `bin/bake_iocrunner_image.bash:551@1c8eb7d` pass only `-i` and `--limit`. The `ansible-provision` half reads the variable at `roles/app_ioc_runner/tasks/main.yml:10@0082a56`, fails by name on an unknown ref at `roles/app_ioc_runner/tasks/main.yml:27@0082a56`, and records the field through `roles/bake_provenance/files/record-iocrunner-source.bash:167@0082a56` and `roles/bake_provenance/files/record-iocrunner-source.bash:217@0082a56`. Both sides are in place; what no check in either repository observes is the join between them - the fake `ansible-playbook` in `tests/check-iocrunner-bake-provenance.bash` records the argument and stops, so that a pinned bake yields an image whose `ioc-runner -V` reports the requested commit rests on a real bake. That bake ran on 2026-08-01, host `Neutron`: `bin/bake_iocrunner_image.bash -o rocky8 -r 1.2.2` completed 10/10 and published a manifest recording `commit=fd14875df5fdbfcb362d194e81bf74c1de960daa state=clean-tagged tag=1.2.2 requested=1.2.2`, where `fd14875d` is the commit `refs/tags/1.2.2` resolves to upstream. A fresh `testbed-rocky8-iocrunner.server` booted from that image reports `epics-ioc-runner version 1.2.2 (fd14875)`, and its in-image `/etc/iocrunner-bake.manifest` is byte-identical to the published sidecar record. The join is observed; `ansible-provision` `M.13/T.2` and `T.3` are satisfied by the same run.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5.5 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M5.5 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Accept the requested ioc-runner version field and pass a selector through the bake
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m61"></a>
#### M6.1 - Bake refuses to start its configuration step when launched without a terminal

Origin: 52376e6 / M6.1
Identity History: none
GitHub Issue: #24 - https://github.com/jeonghanlee/cloud-provision/issues/24
Status: Complete

##### Summary

Bake refuses to start its configuration step when launched without a terminal. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Bake refuses to start its configuration step when launched without a terminal.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Root cause was ssh connection multiplexing, not the absence of a terminal. The operator's `ssh_config` shares a master under `Host *` with a ten-minute persist and names the socket from the address; these VMs are destroyed and recreated at fixed addresses, so a socket outlived the VM it was made for, the next connection found a master whose connection was dead, and the accepts-then-breaks fallback left the caller's stdin and stderr non-blocking. `ansible-playbook` at step 4 then refused with `Ansible requires blocking IO on stdin/stdout/stderr`. Fixed in `c75a39a`: every ssh this repository makes to a testbed VM carries `-o ControlMaster=no -o ControlPath=none` - the readiness contract, both bake scripts, and the runbook commands agents copy verbatim; `ssh-keyscan` is excluded because it accepts no `-o` and never reaches the mux client path. Accepted 2026-08-01 on host `Neutron` by a real bake launched in exactly the form that used to fail, `setsid nohup bin/bake_iocrunner_image.bash -o rocky8 -r 1.2.2 < /dev/null`: step 4 entered `site.yml` and the run completed 10/10, publishing a validated pair. Diagnosis was delegated to a separate agent; its controls with the stock script were a removed master giving a clean run and a stale master reproducing the non-blocking fd0. An earlier end-to-end control of mine was inconclusive - the mutated run also came back clean - and was reported as such rather than as verification. Original done-when: a bake launched detached either completes or fails for a reason that belongs to the bake. Reproduced twice on 2026-07-31 with `nohup` and with `setsid nohup ... < /dev/null`; the then-working form was `setsid script -qec "make bake" /dev/null`, no longer required.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M6.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M6.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Bake refuses to start its configuration step when launched without a terminal
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m62"></a>
#### M6.2 - Bake publish step stalls when the previous golden changed owner

Origin: 52376e6 / M6.2
Identity History: none
GitHub Issue: #24 - https://github.com/jeonghanlee/cloud-provision/issues/24
Status: Complete

##### Summary

Bake publish step stalls when the previous golden changed owner. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Bake publish step stalls when the previous golden changed owner.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- Both publish renames at `bin/bake_iocrunner_image.bash:425@88f7a02` and `bin/bake_iocrunner_image.bash:427@88f7a02` now use `mv -f --`, matching the in-VM manifest writes at `bin/bake_iocrunner_image.bash:182@88f7a02` and `bin/bake_iocrunner_image.bash:211@88f7a02`. A pre-publish writability assertion was reviewed and rejected: `mv` needs write permission on the image directory, not on the destination file, so asserting target writability would abort bakes that succeed. `tests/check-iocrunner-bake-provenance.bash` gains promotion mode `publish-unwritable`, the first case that drives a completed publication; it sets the prior golden to mode 0444 and runs the bake under a pseudo-terminal, because without one `mv` overwrites silently and the case would pin nothing. On 2026-07-31, host `Neutron`, `REQUIRED_GROUP=$(id -gn) make check-bake` exited 0 with 20/20. Teeth confirmed by mutation: removing `-f` from `bin/bake_iocrunner_image.bash:425@88f7a02` dropped it to 18/20 with exit 2, failing on `bake exited 1` and `image or sidecar was not replaced`; the earlier non-terminal form of the same case passed 20/20 under that mutation and was discarded as false assurance. Pattern audit: the EtherCAT bake shares the same assumption at `bin/bake_ethercat_image.bash:206-207@77fd36e` and is deferred to the archive separation in #25 by owner direction. Session `work/review_sessions/20260731_024614_m6_2_publish_overwrite` on host `Neutron`. Original done-when: the publish step either overwrites the previous golden pair without prompting, or fails with a named error that identifies the ownership repair; behavior no longer depends on whether a terminal is attached. Observed 2026-07-31: a bake driven under `script -qec` sat 43 minutes at Step 9/10 on the `mv` overwrite prompt. `bin/bake_iocrunner_image.bash:417@f681616` and `bin/bake_iocrunner_image.bash:419@f681616` use `mv --` without `-f`, while the in-VM manifest writes at `bin/bake_iocrunner_image.bash:182@f681616` and `bin/bake_iocrunner_image.bash:211@f681616` already use `mv -f --`. The previous golden had changed owner to `libvirt-qemu` when consumer VMs started; libvirt `dynamic_ownership` claims the backing chain and its `remember_owner` restore does not run when a consumer is removed by the `.clean` target instead of a graceful stop. Without a terminal `mv` cannot prompt and silently overwrites, which is why earlier bakes passed unnoticed - so the M6.1 remedy is what exposes this. Confirmed on the real path 2026-08-01, host `Neutron`: the previous golden was owned by `libvirt-qemu` and stayed so after its consumer was removed, and the 2026-08-01 rocky8 bake published over it without stalling, leaving the pair owned by the baking account.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M6.2 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M6.2 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Bake publish step stalls when the previous golden changed owner
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m63"></a>
#### M6.3 - A failed bake names no way to clean up after itself

Origin: 52376e6 / M6.3
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

A failed bake names no way to clean up after itself. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: A failed bake names no way to clean up after itself.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `docs/RUNBOOK_BAKE.md` "Failed bake mid-way" tells the reader to "run the printed cleanup command", and nothing is printed. A bake that fails inside a playbook dies through `set -e` with the Ansible `PLAY RECAP` as its last output; the `EXIT` trap at `bin/bake_iocrunner_image.bash:437@e8318b6` runs `cleanup_output_temps`, which removes temporary files and says nothing. Observed 2026-08-01 on host `Neutron` while checking that a nonexistent selector fails by name: the run refused correctly with `app_ioc_runner: requested ioc_runner_version not found: 9.9.9-nonexistent`, published nothing, and left `testbed-debian13-server` running and half-provisioned exactly as the runbook describes - but with no instruction on screen. This matters because the runbook is read by agents more than by operators, and an agent cannot find a command that was never emitted. Done when a bake that fails after the build VM exists prints the clean-restart command for that VM, a bake that fails before the build VM exists prints nothing, `-k` on a successful bake is unaffected, and a test pins each of those three and is confirmed by mutation to fail when the message is removed. The runbook wording is corrected in the same change. Owner direction 2026-08-01 chose emitting the message over rewording the runbook, because the runbook's readers work from the log. Done 2026-08-01: `report_build_vm_on_failure` at `bin/bake_iocrunner_image.bash:85@9cd4f3c` runs from the existing `EXIT` trap and asks libvirt whether the domain exists rather than tracking a flag, so a run that dies before Step 1 stays silent instead of naming a VM that was never created. `tests/check-iocrunner-bake-provenance.bash` goes 51 to 75; `make check-bake` exits 0 at 75/75, `shellcheck` clean. Two of the three assertions have teeth: removing the message call drops the suite to 57/75 on the two failing modes, and removing the domain query drops it to 63/75 on a new `in-use-refusal` case. That case exists because the first version of the no-VM assertion was hollow - it hung on the `-r` guard refusals, which happen at `bin/bake_iocrunner_image.bash:396-412@9cd4f3c`, before the trap is installed at `bin/bake_iocrunner_image.bash:457@9cd4f3c`, so they stayed silent however the trap was written. The in-use refusal is the one failure that lands between the two, and it is the refusal a real bake met twice this day. The third assertion, that a successful bake prints nothing, is pinned by NO test and is recorded as such: removing the `rc` check leaves all 75 green, because `refresh_working_copy` clears the `EXIT` trap before a successful run ends. A `publish-clean` promotion mode was added to rule out the pseudo-terminal as the cause and did not change the result. The cause is M6.4. Related: M6.5 completes the reasoning this row started. Asking libvirt instead of tracking a flag was chosen here so a run dying before Step 1 would not name a VM it never created; the same question - is this domain ours - has a second half that was missed, and M6.5 supplies it.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M6.3 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M6.3 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: A failed bake names no way to clean up after itself
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m64"></a>
#### M6.4 - A helper's `trap -` uninstalls the bake's own exit handler

Origin: 52376e6 / M6.4
Identity History: none
GitHub Issue: #28 - https://github.com/jeonghanlee/cloud-provision/issues/28
Status: Complete

##### Summary

A helper's `trap -` uninstalls the bake's own exit handler. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: A helper's `trap -` uninstalls the bake's own exit handler.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `refresh_working_copy` sets its own `EXIT` trap at `bin/bake_iocrunner_image.bash:195@9cd4f3c` and clears it with `trap - EXIT HUP INT TERM` at `bin/bake_iocrunner_image.bash:200@9cd4f3c`. `trap -` restores the default rather than the previous handler, so `cleanup_output_temps`, installed at `bin/bake_iocrunner_image.bash:457@9cd4f3c`, is gone from that moment on. The helper runs at `bin/bake_iocrunner_image.bash:626@9cd4f3c` at the end of a successful bake and at `bin/bake_iocrunner_image.bash:495@9cd4f3c` in `-R` refresh-only mode. Consequence: a bake that fails after Step 9's refresh prints no clean-restart guidance, because that guidance runs from the same handler. An earlier revision of this row and of #28 also claimed the run would leave `OUTPUT_TEMP` and `SIDECAR_TEMP` behind; that is wrong and withdrawn, because `bin/bake_iocrunner_image.bash:616-619@9cd4f3c` move both into the archive and clear their flags before `refresh_working_copy` is reached. No temporary-file leak occurs on any path examined. What remains is the shape rather than a present cost: the handler is silently uninstalled partway through every successful run, so anything added to it later is disarmed from Step 9 onward with nothing saying so. The two other `trap -` pairs at `bin/bake_iocrunner_image.bash:277-291@9cd4f3c` and `bin/bake_iocrunner_image.bash:311-320@9cd4f3c` are harmless because they run before `bin/bake_iocrunner_image.bash:457@9cd4f3c` installs anything. Found 2026-08-01 while pinning M6.3, from a mutation that survived: removing the `rc` check in `report_build_vm_on_failure` left all 75 checks green, because on a successful run the handler is no longer installed to be reached. Not a regression from M6.3 - the temp-cleanup exposure predates it. Done when the bake's exit handler survives every helper and a successful bake still has it installed when it exits. Delivered 2026-08-01: `refresh_working_copy` registers its two `.refresh.tmp` paths in `REFRESH_IMAGE_TEMP` and `REFRESH_SIDECAR_TEMP`, cleared individually after each `mv` so a half-done refresh never deletes the file it just moved, and `cleanup_output_temps` removes them. The local trap and its `trap -` are gone. Signals still reach the handler through `bin/bake_iocrunner_image.bash:481@c177daa`. Effect measured: removing the `rc` check in `report_build_vm_on_failure` now drops the suite to 72/75 on all three successful-publish cases, where before the fix the same mutation left 75/75. That mutation is the proof the handler is installed at exit; it also gave M6.3's third assertion the teeth it lacked. Reintroducing `trap -` is NOT caught by any check, and cannot be with this harness: the only step after the refresh is `do_cleanup`, which swallows every virsh failure by design at `bin/create_vm.bash:349@c177daa` and `bin/create_vm.bash:353@c177daa`, so no failure can be placed past that point. A `late-failure` promotion mode was written to try and was withdrawn when the bake completed anyway. The earlier acceptance wording here required such a test and is withdrawn with it. Second scope reduction, recorded rather than quietly dropped: with `do_cleanup` unfailable, the only reachable late failure is `report_archive_retention`, so the consequence this row opened with is close to unreachable in practice. The row is kept because the handler's lifetime is now correct for whatever is added to it next, which was always the durable part. Carried by `c177daa`, whose message names only #29 because the two fixes touch the same function and landed together; that is why this row and #28 stayed open after the code was already in. Closed 2026-08-01 against the three acceptance criteria read one at a time: the handler survives every helper, since the only `trap -` pairs left are `bin/bake_iocrunner_image.bash:314@c177daa` and `bin/bake_iocrunner_image.bash:343@c177daa`, both ahead of the install at `bin/bake_iocrunner_image.bash:480@c177daa`; a successful bake still holds it at exit, measured on the current tree rather than inherited - `REQUIRED_GROUP=$(id -gn) make check-bake` exits 0 at 76/76, and replacing the `rc` check at `bin/bake_iocrunner_image.bash:90@c177daa` with a value no exit status can take drops it to 73/76 with exit 2, failing exactly `publish-clean`, `publish-unwritable`, and `publish-pinned` "prints no failure guidance on success"; and `docs/RUNBOOK_BAKE.md` "Failed bake mid-way" gave up the limitation it recorded, replaced by the one silence that is real - a refresh-only run prints nothing, because it boots nothing and any VM of that name is an earlier run's. The line numbers cited above and in #28 are the pre-`c177daa` file; the function moved when the temps became globals. Scope was separated from M6.3 by owner direction 2026-08-01: the missing message and the vanishing handler have different causes, and the handler owes a temp-cleanup promise that needs its own check. Related: M6.5, found the same day in the same function. Both are the handler firing where it should not - this row because it stops firing partway through a run, M6.5 because it fires about a VM that is not this run's.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M6.4 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M6.4 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: A helper's `trap -` uninstalls the bake's own exit handler
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m65"></a>
#### M6.5 - Refresh-only claims a build VM it never created

Origin: 52376e6 / M6.5
Identity History: none
GitHub Issue: #29 - https://github.com/jeonghanlee/cloud-provision/issues/29
Status: Complete

##### Summary

Refresh-only claims a build VM it never created. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Refresh-only claims a build VM it never created.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- `-R` refreshes the working copy from an archive entry and boots nothing, but `report_build_vm_on_failure` asked only whether a domain of the build VM's name exists. After a `-k` bake, or one that failed and left its VM standing, that domain belongs to an earlier run. Observed 2026-08-01 on host `Neutron`: a build VM was created by hand, `-R` was refused at the in-use guard, and the run named that VM as left for inspection and printed the command to delete it. Following that instruction would have destroyed a VM the run had nothing to do with - the same class of wrong-but-confident refusal as the prefix-matching DHCP guard in `ca3290c` (M3.5). Fixed by refusing the report when `REFRESH_ONLY` is true. The same run, unchanged otherwise, printed nothing afterward while the VM stayed up. `tests/check-iocrunner-bake-provenance.bash` goes 75 to 76 with a case that plants a domain state file and runs `-R` against a missing entry; removing the guard drops it to 75/76. Surfaced by M6.4 rather than caused by it: before that fix, `refresh_working_copy` cleared the `EXIT` trap, so `-R` said nothing whatever happened. Relation to M6.3: that row chose to ask libvirt instead of tracking a flag, so a run dying before Step 1 would not name a VM it never created. Existing was taken as sufficient; ours is the half that was missing. This row is the same question asked from the other side.

##### Dependencies And Decisions

- M6.3
- M6.4

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M6.5 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M6.5 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Refresh-only claims a build VM it never created
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m71"></a>
#### M7.1 - Pin every cited source coordinate to the tree it was read from

Origin: 52376e6 / M7.1
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Pin every cited source coordinate to the tree it was read from. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Pin every cited source coordinate to the tree it was read from.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- A bare `file:line` in a document rots silently: one inserted line shifts every coordinate below it, and no suite here can see a document become false - they all pass either way. Measured 2026-08-01, host `Neutron`: ten of the sixteen fully-qualified citations in this register pointed at unrelated lines, and every one of them had been correct when written. `bin/bake_iocrunner_image.bash:437@e8318b6` is `trap cleanup_output_temps EXIT`, and line 437 of the same file at `c177daa` is blank; the same three commits of 2026-08-01 that added `SSH_OPTIONS`, `report_build_vm_on_failure`, and the refresh temporaries pushed everything below them down. Owner direction, 2026-08-01: pin the coordinate to the commit it was read from rather than chase it. `bin/bake_iocrunner_image.bash:95@77fd36e` cannot drift, because the tree it names is immutable, so the failure is removed rather than alarmed on - and a historical row keeps saying what was true when written instead of being falsified by a later edit. Each of the 45 coordinates was recovered by finding the commit that introduced its sentence and confirming the line at that tree; none of the ten was wrong at its own tree. `tests/check-doc-refs.bash` behind `make check-docs` then refuses an unpinned coordinate, a bare `:NNN` that names no file, a hash absent from this repository, a path absent from that tree, and a line past its end; 45/45, exit 0. Teeth confirmed by five mutations, each dying with its own reason: dropping a hash 43/44, a nonexistent commit `no such commit in this repository`, line 99999 `past end of file (1035 lines at c177daa)`, a coordinate stripped of its file name 43/44, and an absent path `path absent from c177daa`. Recorded limit, in the check's own header: it cannot judge whether the cited line says what the prose claims - a coordinate aimed at the wrong line of the right file at the right tree passes and always will. The pin makes a coordinate reproducible, not true. `ansible-provision` paths are cited with its own hashes but are not resolvable from here and are left unchecked.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M7.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M7.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this work Complete. Its source evidence is preserved under Completion Criteria; no new closure verification was run during canonicalization.

##### GitHub Projection

Title: Pin every cited source coordinate to the tree it was read from
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="m81"></a>
#### M8.1 - Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`

Origin: 52376e6 / M8.1
Identity History: none
GitHub Issue: #30 - https://github.com/jeonghanlee/cloud-provision/issues/30
Status: Not started

##### Summary

Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`. This detail preserves the legacy register's scope and evidence without claiming a rerun during canonicalization.

Source: `docs/milestone.md` at prior-state commit `52376e6b5eedcab9afbb8e9a815770032a0289e0`.


##### Scope

- Deliverable: Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`.
- Scope, exclusions, and conditions stated in the legacy evidence are preserved under Completion Criteria.

Out of scope: No separate out-of-scope field was present in the legacy register.

##### Completion Criteria

- The workflow settled 2026-08-01 replaces the structure that produced most of this milestone's image work, so this row is where that structure is actually built. Two roots are removed rather than guarded. First, the backing chain: every VM disk is a copy, so nothing upstream of it is ever held, and the devices built to survive that holding become unnecessary - the archive and working-copy split, the in-use guard, `mv -f` on publish, the symlink ban, and the flatten step. Second, existence taken for ownership: every image we make carries a unique name and a creation record beside it, and the pair agreeing is what makes it valid, so "does a domain of this name exist" is never again asked in place of "did this run make it". Supersedes on landing, none closed before then because none of it is built: M1.4 (#2), M1.6 (#25), M1.7, M1.8, M3.2 (#7), M6.2 (#24), M6.3, M6.4 (#28), M6.5 (#29). Untouched by it: M4.2 (#19), M3.3 (#11), M1.5 (#4) - wait budgets, stop behavior, and downstream validation are timing and operations, not image structure. Done when a VM disk is a copy rather than an overlay, both bakes produce images through one shared path, names come from one place and carry the run's timestamp and hash, every image we make has its creation record, and a check pins the pair rule. Deferred by owner direction to a later round: the disk cost of full copies and the time cost of purpose work running per VM instead of once per bake.

##### Dependencies And Decisions

- D11

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. No separate implementation plan field was present in the legacy register; use the migrated Scope and Completion Criteria as the source for any future plan update.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M8.1 / T1 | Source evidence | Preserve the legacy completion and evidence text; do not treat canonicalization as a rerun | As recorded in the legacy register | Preserve the source result without adding a new verification claim |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M8.1 / T1 | As recorded in legacy register | As recorded or not specified | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- none

##### GitHub Projection

Title: Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`
Labels: not recorded in the legacy register; live labels not compared
GitHub Milestone: Nimbus - Cloud Provisioning Reliability; live assignment not compared
Observed State: not compared during canonicalization
Observed Labels: not compared during canonicalization
Observed Milestone: not compared during canonicalization
Last Compared: never

<a id="g1"></a>
#### G1 - Run downstream validation on the 2026-06-03 Rocky 8 golden image

Origin: 52376e6 / G1
GitHub Issue: none
Status: Open

##### Summary

Run downstream validation on the 2026-06-03 Rocky 8 golden image. This detail preserves the legacy gate condition and evidence without claiming a rerun during canonicalization.

Affected work:
- M1.5

##### Completion Criteria

- Requires the real golden image, `rocky8-iocrunner.server`, and the downstream ioc-runner validation environment.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| As recorded in legacy register | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- none; the external condition remains open.

<a id="g2"></a>
#### G2 - Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance

Origin: 52376e6 / G2
GitHub Issue: none
Status: Open

##### Summary

Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance. This detail preserves the legacy gate condition and evidence without claiming a rerun during canonicalization.

Affected work:
- M3.3

##### Completion Criteria

- The bake waits 24 x 5s at `bin/bake_iocrunner_image.bash:614@c177daa`; `do_stop` waits 12 x 5s at `bin/create_vm.bash:373@c177daa`. No record explains where 120 seconds came from, so the two cannot simply be merged. M4.2 produces the measured basis and proposes a value; this gate completes when the owner accepts it. It blocks M3.3 only - M4.2 is the work that answers it.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| As recorded in legacy register | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- none; the external condition remains open.

<a id="g3"></a>
#### G3 - Run the production ioc-runner bake acceptance for Rocky 8 and Debian 13

Origin: 52376e6 / G3
GitHub Issue: none
Status: Complete

##### Summary

Run the production ioc-runner bake acceptance for Rocky 8 and Debian 13. This detail preserves the legacy gate condition and evidence without claiming a rerun during canonicalization.

Affected work:
- M5.4

##### Completion Criteria

- Accepted 2026-08-01 on host `Neutron`. `bin/bake_iocrunner_image.bash -o rocky8` and `-o debian13` each completed 10/10 with no selector, publishing an image and sidecar pair whose `app_ioc_runner` record is the unchanged six-field form - `commit=85b6d904d9a2283833f2c2be274e1567beb47d2e state=clean-untagged tag=-`, no `requested=` field. Fresh `rocky8-iocrunner.server` and `debian13-iocrunner.server` consumers booted from those images at `192.168.122.150` and `192.168.122.50`, and each in-image `/etc/iocrunner-bake.manifest` matches its published sidecar record. Both repositories were at `origin/master` for all shipped code; the only local difference was register text in this file. Pinned runs preceded these and are recorded under M5.5; they were re-run unpinned deliberately, because a pinned golden carries `requested=` into every VM derived from it and the `EPICS-env` release gate consumes this image. Worth recording for whoever reads a version string: `ioc-runner -V` reports `1.2.2` for both the pinned and the unpinned image, because the runner's version string has not moved past its last tag - only `commit` distinguishes them, which is why the manifest records `commit`, `tag`, and `requested` separately. Logs: `work/bake-{rocky8,debian13}-prod.log`. Original conditions: requires the production bake host, network access for the real package phases, and fresh `rocky8-iocrunner.server` and `debian13-iocrunner.server` consumers. The offline contract checks under `make check-bake` do not substitute for it. The `EPICS-env` 1.3.0 M7 release gate consumes this acceptance: its `M7.T3` requires full-environment install verification on real VMs, and its release verification plan provisions those VMs through this repository's Make targets. See External identifiers above.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| As recorded in legacy register | Preserved from legacy register; not rerun on 2026-08-06 | Completion Criteria above; source `docs/milestone.md` at `52376e6b5eedcab9afbb8e9a815770032a0289e0` |

##### Closure Evidence

- The legacy register marked this gate Complete. Its source evidence is preserved under Completion Criteria; no new gate verification was run during canonicalization.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |

No unassigned work is recorded in the legacy register.

### Backlog Details

No backlog details.

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-06 (canonicalization) | 52376e6b5eedcab9afbb8e9a815770032a0289e0 |
