# Work Register

This document tracks unfinished work carried into the master reset generation
identified by prior-state commit `c53e17e`.

Release line: master
Milestone index: c53e17e
Canonical path: `docs/milestone-c53e17e.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: Open `docs/milestone-c53e17e.md`, obtain owner authorization, and execute the Deferred EtherCAT runtime acceptance in Backlog M1.1.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |

No assigned work remains in this generation.

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
