# Work Register

This document tracks unfinished work carried into the master reset generation
identified by prior-state commit `c53e17e`.

Release line: master
Milestone index: c53e17e
Canonical path: `docs/milestone-c53e17e.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: Complete the separately planned issue #33 prerequisite recorded as G1; then restore M2 as In progress and run M2 / T11 through M2 / T13 (V012-V014) on supported Libvirt/KVM. Keep M2 / T14 (V015) gated on U002 and a separate accepted and authorized audit plan.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Proxy lifecycle | M2 | Remove every injected proxy artifact before publishing golden images | Milestone | Blocked | No | D009-D014, G1 | The current four-surface producer contract, both terminal bake seals, local shipped-path checks, three real producer-consumer gates, and the separately authorized existing-artifact audit complete; [M2 detail](#m2). |
| Proxy lifecycle | G1 | Deliver the consumer behavior required by the three real gates | External gate | Open | No |  | The separately scoped issue #33 behavior required by M2 / T11 through M2 / T13 is delivered and verified; [G1 detail](#g1). |
| Proxy lifecycle | G2 | Authorize and complete the existing-artifact audit | External gate | Open | No |  | A separate value-safe audit plan is accepted, authorized, and executed for M2 / T14; [G2 detail](#g2). |

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D009 | One production contract owns the current profile, APT, DNF, and system Git proxy artifacts and renders the create-VM seed from the validated proxy URL. | 2026-08-20 |
| D010 | Both bake callers execute the same privileged terminal seal, whose complete preflight and value-free clean verification must pass before stop or publication. | 2026-08-20 |
| D011 | An independent value-free fixture and tests must exercise the shipped producer and both shipped bake callers with only outer command, SSH transport, and filesystem-root boundaries replaced. | 2026-08-20 |
| D012 | This milestone registers issue #34 only; issue #33 behavior and the existing-artifact audit remain external gates rather than work rows in this register. | 2026-08-20 |
| D013 | Documentation states only verified scope. | 2026-08-20 |
| D014 | Reading, auditing, quarantining, replacing, or deleting an existing artifact requires a separate plan and authorization. | 2026-08-20 |

### Milestone Details

<a id="m2"></a>
#### M2 - Remove every injected proxy artifact before publishing golden images

Origin: c53e17e / M2
Identity History: none
GitHub Issue: [#34](https://github.com/jeonghanlee/cloud-provision/issues/34)
Status: Blocked

##### Summary

The current VM seed producer writes four deterministic proxy artifact surfaces, while the two bake callers remove a different historical set. M2 establishes one shared production contract, makes the real seed and both real bake callers consume it, and verifies exact producer, cleanup, and remnant-set equality without exposing values.

##### Scope

- Add the shared current profile, APT, DNF, and system Git proxy artifact contract.
- Render that contract through the real `create_vm.bash` seed path.
- Execute the same terminal seal in both shipped bake callers before stop and publication.
- Add independent exact-set, shipped-path, failure-mutation, documentation, and deferred real-gate evidence.

Out of scope: issue #33 SSH, sudo, pip, vmadmin, general-environment, and direct-route behavior; Ansible changes; `-F`; existing-artifact inspection or remediation; GitHub mutation.

##### Completion Criteria

- The producer, both bake callers, and the independent fixture agree on the exact current artifact set.
- Each bake validates and extracts its manifest, runs the shared seal as the last guest command, stops the exact VM, and publishes only its exact stopped disk.
- M2 / T1 through M2 / T10 pass through the specified local and review paths.
- G1 completes and M2 / T11 through M2 / T13 pass through supported Libvirt/KVM with exact producer-consumer record binding.
- G2 completes and M2 / T14 records the separately authorized value-safe audit result.

##### Dependencies And Decisions

- D009-D014
- G1 is Open and blocks M2 after M2 / T1 through M2 / T10 passed on 2026-08-20; resume as In progress.
- G2 will become a blocking dependency only after M2 / T11 through M2 / T13 pass; resume as In progress.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: `plan20260820_025428`, accepted 2026-08-20
Implementation Authorization: `auth20260820_075556`
Superseded Plan Artifacts: `plan20260820_005505`, `plan20260820_013544`, `plan20260820_023853`

1. Implement P001 through P010 from `plan20260820_025428` without expanding the approved boundary.
2. Run V001 through V010 and record only observed local results.
3. Obtain the required implementation cross-check before any commit request.
4. Keep V012 through V015 pending until their named external gates and separate authority exist.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2 / T1 | Syntax | Run V002 with `bash -n` on the shared contract, producer, both bakes, and four public tests | Local checkout | Every named Bash file parses |
| M2 / T2 | Static analysis | Run V003 with ShellCheck warning severity and inspect the full output | Local checkout | Exit 0 and no unreviewed warning |
| M2 / T3 | Producer contract | Run V004 with `make check-proxy-injection` | Local checkout; shipped producer with outer boundaries replaced | Debian, Ubuntu, and Rocky emit the exact applicable set; no-input and ambiguity paths remain correct |
| M2 / T4 | Joined lifecycle | Run V005 with `make check-proxy-lifecycle` | Local checkout; shipped producer and both shipped bake callers | Full fixture and production tuples agree; applicable inventory, dispatch, seal-call, and seed omissions fail before stop or publication |
| M2 / T5 | IOC bake | Run V006 with `make check-bake-provenance` | Local checkout; shipped IOC bake with outer boundaries replaced | Seal bytes execute as the last guest command and every failure blocks publication |
| M2 / T6 | EtherCAT bake | Run V007 with `make check-bake-ethercat-workflow` | Local checkout; shipped EtherCAT bake with outer boundaries replaced | The Debian-only caller meets the same terminal seal and publication contract |
| M2 / T7 | Offline aggregate | Run V008 with `make check-bake` | Local checkout | Every offline bake gate passes through shipped entry points |
| M2 / T8 | Documentation | Run V009 with `make check-docs` | Local checkout | ADR, architecture, runbook, and repository Markdown checks pass |
| M2 / T9 | Diff hygiene | Run V010 with `git diff --check` | Local checkout | Exit 0 |
| M2 / T10 | Implementation cross-check | A fresh Reviewer runs V002 through V010 and checks P001 through P010 | Final uncommitted implementation | No blocking finding before a commit request |
| M2 / T11 | Debian IOC real gate | Run V012 through the exact public Debian IOC bake and fresh consumer paths | Supported Libvirt/KVM after G1 | Consumer record source equals the just-published producer basename before clean verification |
| M2 / T12 | Rocky IOC real gate | Run V013 through the exact public Rocky IOC bake and fresh consumer paths | Supported Libvirt/KVM after G1 | Consumer record source equals the just-published producer basename before clean verification |
| M2 / T13 | Debian EtherCAT real gate | Run V014 through the exact public EtherCAT bake and fresh consumer paths | Supported Libvirt/KVM after G1 | Consumer record source equals the just-published producer basename before clean verification |
| M2 / T14 | Existing-artifact audit | Run V015 only from its separate accepted and authorized value-safe plan | Separately authorized audit environment after G2 | Record the observed existing-artifact result without exposing values |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2 / T1 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; approved uncommitted implementation | Pass | V002 `bash -n` exited 0 for all eight named Bash files |
| M2 / T2 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; approved uncommitted implementation | Pass | V003 ShellCheck exited 0 with empty inspected output |
| M2 / T3 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped producer with outer boundaries replaced | Pass | V004 `make check-proxy-injection`: 63/63 passed, including full fixture-to-production tuple comparison for Debian, Ubuntu, and Rocky |
| M2 / T4 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped producer and both shipped bake callers | Pass | V005 `make check-proxy-lifecycle`: 26/26 passed, including file/stdin operand rejection, three fixture tuple mutations, six applicable inventory omissions, dispatch and seal-call omissions, and seed-argument omission |
| M2 / T5 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped IOC bake with outer boundaries replaced | Pass | V006 `make check-bake-provenance`: 86/86 passed |
| M2 / T6 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped EtherCAT bake with outer boundaries replaced | Pass | V007 `make check-bake-ethercat-workflow`: 11/11 passed |
| M2 / T7 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped offline bake entry points | Pass | V008 `make check-bake`: 7/7, 86/86, 11/11, and 26/26 passed |
| M2 / T8 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5` | Pass | V009 `make check-docs`: 3/3 passed |
| M2 / T9 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5` | Pass | V010 `git diff --check` exited 0 |
| M2 / T10 | 2026-08-20 10:03:44 PDT | Fresh Reviewer `codex_gpt5_signal`; final uncommitted implementation in `hand20260820_095313` | Pass | V011 accepted with zero blocking findings and zero required decisions in `work/review_sessions/20260819_235119_proxy-lifecycle/reviews/fup20260820_100344_codex_gpt5_signal_on_hand20260820_095313.md` |
| M2 / T11 | Not run | Supported Libvirt/KVM after G1 | Pending | Exact public Debian IOC bake and consumer |
| M2 / T12 | Not run | Supported Libvirt/KVM after G1 | Pending | Exact public Rocky IOC bake and consumer |
| M2 / T13 | Not run | Supported Libvirt/KVM after G1 | Pending | Exact public Debian EtherCAT bake and consumer |
| M2 / T14 | Not run | Separately authorized audit environment after G2 | Pending | Separate value-safe audit plan |

##### Closure Evidence

- Fresh review `fup20260820_100344` accepted the F007-F009 corrections with zero blocking findings and zero required decisions; local V002-V010 and M2 / T10 now pass.
- Prior reviews remain historical evidence: `fup20260820_093345` failed on F007-F009, `fup20260820_085945` accepted the preceding correction, and `fup20260820_083901` recorded the earlier failed cross-check.
- Issue #34 remains open until every completion criterion and external gate is satisfied.

##### GitHub Projection

Title: Remove every injected proxy artifact before publishing golden images
Labels: bug
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: bug
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-20 08:00:40 PDT; remote updated 2026-08-19 23:23:35 PDT

<a id="g1"></a>
#### G1 - Deliver the consumer behavior required by the three real gates

Origin: c53e17e / G1
GitHub Issue: none
Status: Open

##### Summary

Issue #34 M2 / T11 through M2 / T13 require separately scoped consumer behavior before the three real paths can run. This gate records only that external prerequisite and does not register issue #33 as work in this document.

##### Completion Criteria

- The separate issue #33 implementation is delivered and verified for the exact consumer paths required by M2 / T11 through M2 / T13.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| Not run | Pending | Separate issue #33 plan, authorization, delivery, and verification |

##### Closure Evidence

- None.

<a id="g2"></a>
#### G2 - Authorize and complete the existing-artifact audit

Origin: c53e17e / G2
GitHub Issue: none
Status: Open

##### Summary

Issue #34 cannot close until a separately planned and authorized value-safe audit determines the state of existing artifacts. This gate grants no permission to inspect or remediate them.

##### Completion Criteria

- A named value-safe audit plan is accepted, separately authorized, executed, and recorded as M2 / T14.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| Not run | Pending | Separate audit plan and authorization |

##### Closure Evidence

- None.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Deferred EtherCAT acceptance | M1.1 | Validate EtherCAT use of the shared image workflow | Carry-forward | Deferred | No |  | Run the shipped EtherCAT bake and consumer on supported Libvirt/KVM, inspect the image, manifest, and creation-record pair, and confirm actual consumer selection; [M1.1 detail](#m11). |

### Backlog Details

<a id="m11"></a>
#### M1.1 - Validate EtherCAT use of the shared image workflow

Origin: c53e17e / M1.1
Identity History: none
GitHub Issue: none
Status: Deferred

##### Summary

Commit `304291b` integrates the EtherCAT bake and consumer with the shared naming, copy, creation-record, and pair-validation code used by ioc-runner. Local contract checks pass, but no actual EtherCAT bake or fresh consumer selection has been observed on supported Libvirt/KVM in this generation. Owner direction defers that runtime acceptance so it does not block the ioc-runner image-workflow acceptance.

##### Scope

- Run the shipped Debian 13 EtherCAT bake on supported Libvirt/KVM.
- Inspect the produced image, manifest, and creation record for matching identity and no backing file.
- Boot a fresh `debian13-ethercat` consumer and confirm that it selects the exact valid pair.
- Record the runtime evidence in this detail section.

Out of scope: Changes to the shared image workflow unless runtime verification exposes a defect. Ioc-runner runtime acceptance is already complete and reachable from the prior-state commit recorded in History.

##### Completion Criteria

- A real EtherCAT bake completes through the shipped entry point.
- The produced image has no backing file.
- The image, manifest, and creation record agree on run identifier and artifact identity.
- A fresh EtherCAT consumer selects the exact verified pair.
- The observed paths, identifiers, and selection evidence are recorded here.

##### Dependencies And Decisions

- Supported Libvirt/KVM host with the EtherCAT bake prerequisites

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Confirm the supported host prerequisites and available source golden pair.
2. Run the shipped EtherCAT bake entry point.
3. Inspect the produced image, manifest, creation record, and no-backing state.
4. Boot a fresh `debian13-ethercat` consumer and confirm exact pair selection.
5. Record the evidence and close the work unit if all criteria pass.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | Local contract | Run the EtherCAT portion of `make check-bake` through the public script entry points with only external command boundaries replaced | Repository checkout containing the delivered workflow | Shared names, creation records, pair validation, and failure handling remain internally consistent |
| M1.1 / T2 | Runtime acceptance | Run the shipped EtherCAT bake and a fresh consumer, then inspect the output pair and qcow2 metadata | Supported Libvirt/KVM host with EtherCAT bake prerequisites | The bake produces an independent valid pair and the consumer selects that exact pair |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | 2026-08-13 | Local checkout; public entry points with external command boundaries replaced | The EtherCAT workflow portion of `make check-bake` completed all 8 checks. This does not satisfy runtime acceptance. | `tests/check-ethercat-bake-workflow.bash:237-239@c53e17e` |

##### Closure Evidence

- Deferred by owner direction on 2026-08-13. Runtime acceptance has not run.

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-19 | c53e17eda34f5ddd7795ff61bccf63ec220a35c8 |
