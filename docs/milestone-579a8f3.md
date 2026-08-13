# Work Register

## Scope

This document tracks unfinished work carried into the master reset generation identified by prior-state commit `579a8f3`.

**Out of scope:** Completed work and the prior generation's full record remain reachable from the History commit and are not repeated here.

Release line: master
Milestone index: 579a8f3
Canonical path: `docs/milestone-579a8f3.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: run the Rocky 8 and Debian 13 ioc-runner bake entry points on a supported Libvirt/KVM host, inspect each image, manifest, and creation-record pair for an independent qcow2 with no backing file, then boot fresh ioc-runner consumers and confirm that each selects the matching valid pair.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Image workflow adoption | M1.1 | Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md` | Milestone | In progress | No | D1, D2, D3 | Verify that the ioc-runner workflow produces independent run-specific golden pairs through shared naming, copy, and record code on real supported hosts; [M1.1 detail](#m11). |
| M3 VM lifecycle policy | M3.1 | Review VM readiness and shutdown wait budgets | Milestone | Not started | Yes |  | Treat all readiness and shutdown budgets as one documented and verified policy; [M3.1 detail](#m31). |
| M3 VM lifecycle policy | M3.2 | Reuse VM stop behavior in the ioc-runner bake | Milestone | Blocked | No | M3.1, G1 | Decide and verify the shared or explicitly separate shutdown path after M3.1 and G1 complete; [M3.2 detail](#m32). |
| M4 Rocky golden validation | M4.1 | Validate the Rocky 8 golden after the sudoers fix | Milestone | Blocked | No | G2 | Run downstream validation against the real Rocky 8 golden after G2 completes; [M4.1 detail](#m41). |
| External gate | G1 | Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance | External gate | Open | No |  | Owner accepts a measured shutdown policy for the bake and provisioner paths; [G1 detail](#g1). |
| External gate | G2 | Run downstream validation on the 2026-06-03 Rocky 8 golden image | External gate | Open | No |  | The real Rocky 8 golden and downstream validation environment produce recorded results; [G2 detail](#g2). |

### Decisions

| ID | Decision | Source |
| --- | --- | --- |
| D1 | Image structure is settled by `docs/IMAGE_WORKFLOW.md`: a copy at every step so nothing upstream is held, identity carried by a file name and a creation record that must agree, the naming rule defined in one place, and build VMs fresh by construction. | User direction, 2026-08-01 |
| D2 | New development moves to branches: `master` takes no direct implementation work from this generation onward, and the annotated tag `pre-image-workflow` marks the last state built that way. | User direction, 2026-08-01 |
| D3 | GitHub issue #30 owns ioc-runner acceptance of the copy-based image workflow. Shared code delivered in commit `304291b` also integrates EtherCAT, but actual EtherCAT bake and consumer validation is deferred to Backlog M2.1 and does not block M1.1. The earlier claim that the old EtherCAT rows were M2.1 and M2.2 was incorrect; the prior-generation EtherCAT rows were M1.7 and M1.8. | Owner direction, 2026-08-13 |

### Milestone Details

<a id="m11"></a>
#### M1.1 - Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`

Origin: 579a8f3 / M1.1
Identity History: 2026-08-13: EtherCAT runtime acceptance split to Backlog M2.1; shared implementation evidence remains here.
GitHub Issue: #30 - https://github.com/jeonghanlee/cloud-provision/issues/30
Status: In progress

##### Summary

Implement GitHub issue #30 against the structure recorded in `docs/IMAGE_WORKFLOW.md`. The issue removes two root causes: qcow2 backing chains that made runtime disks retain published images, and stable-name existence checks that treated an existing domain or file as proof of ownership. Commit `304291b` contains the local implementation. M1.1 remains In progress because real ioc-runner bake and consumer acceptance has not run on supported Libvirt/KVM hosts.

##### Scope

- Create VM runtime disks as independent full copies so no VM disk retains an upstream image.
- Publish each ioc-runner bake under a run-specific immutable image name through the shared image workflow.
- Centralize ioc-runner build VM names, image names, disk paths, and run identifiers.
- Write a creation record for each produced ioc-runner golden image and VM disk.
- Select only the newest valid ioc-runner image-plus-record pair for stable-name consumers.
- Reject missing or mismatched ioc-runner golden creation records before VM definition or start.
- Keep `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, and `docs/IMAGE_WORKFLOW.md` aligned with the delivered workflow.

Out of scope: Actual EtherCAT bake and consumer validation is tracked as Backlog M2.1. Wait budgets (#19), stop behavior (#11), Rocky 8 downstream validation (#4), disk-space policy, and elapsed-time policy remain separate work.

##### Completion Criteria

- The public VM-creation path makes a full source-image copy and the resulting qcow2 has no backing file.
- Real Rocky 8 and Debian 13 ioc-runner bakes produce run-specific image, manifest, and creation-record pairs through the shared workflow.
- Build VM names, golden image names, and VM disk paths come from centralized workflow functions.
- Stable-name ioc-runner consumers select the newest valid image-plus-record pair and reject missing or mismatched records.
- Each produced ioc-runner golden image name and its creation record agree on run identifier and artifact identity.
- Fresh Rocky 8 and Debian 13 ioc-runner consumers select the exact verified golden pair.
- Archive split, in-use path guards, forced publish, flatten refresh, and stable VM-name ownership are not required by the active path.
- Maintained documentation describes the same workflow implemented by the scripts.

##### Dependencies And Decisions

- D1
- D2
- D3

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner direction in current session, 2026-08-12
Implementation Authorization: Owner direction in current session, 2026-08-12
Superseded Plan Artifacts: none

1. Implement shared run identifiers, naming, paths, independent-copy handling, creation records, and pair validation.
2. Route the ioc-runner bake and consumer scripts through the shared functions.
3. Replace stable single-image refresh with run-specific published artifacts and latest-valid-pair selection.
4. Verify the public paths locally with only external command boundaries replaced.
5. Align the maintained image-workflow documentation with the shipped paths.
6. Run real Rocky 8 and Debian 13 ioc-runner bakes on a supported Libvirt/KVM host.
7. Inspect each output pair and no-backing state, boot fresh ioc-runner consumers, and record the runtime evidence.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | Local integration | Run `make check-cloud-init-status` and the ioc-runner portions of `make check-bake` through the public script entry points with only external command boundaries replaced | Repository checkout containing the delivered workflow | Independent copies have no backing file; ioc-runner bakes use centralized names and creation records; consumers reject missing or mismatched records |
| M1.1 / T2 | Runtime acceptance | Run the Rocky 8 and Debian 13 ioc-runner bake entry points, inspect outputs with `qemu-img info --output=json`, then boot fresh ioc-runner consumers | Supported Libvirt/KVM bake hosts with supported OS inputs | Each bake produces an independent matching image, manifest, and creation record, and each consumer selects the exact verified pair |
| M1.1 / T3 | Documentation | Run the repository documentation checks and compare the architecture and runbook commands with the shipped paths | Repository checkout containing the delivered workflow | The architecture and runbook describe the same paths, names, records, and checks |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | 2026-08-13 | Local checkout; real shipped scripts and fixtures with only virsh, ssh, ansible-playbook, qemu-img, virt-install, and clock or host-key boundaries replaced | Local public-path contract passed: `make check-cloud-init-status` 87/87; the M1.1 portions of `make check-bake` passed fresh-input 7/7 and ioc-runner provenance 62/62. The checks verified independent copies, unique names, matching creation records, pair rejection, and invalid run-ID rejection. A real Libvirt/KVM bake remains to be run. | `tests/check-cloud-init-status.bash`, `tests/check-iocrunner-bake-provenance.bash` |
| M1.1 / T3 | 2026-08-13 | Local checkout | `make check-docs` passed 51/51. `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, and `docs/IMAGE_WORKFLOW.md` describe the centralized naming, unique-image, creation-record, and shared-copy paths. | `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, `docs/IMAGE_WORKFLOW.md`, `configure/RULES_BAKE` |

##### Closure Evidence

- none

##### GitHub Projection

Title: Adopt the image workflow
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-13; issue updated 2026-08-13T08:02:59Z

<a id="m31"></a>
#### M3.1 - Review VM readiness and shutdown wait budgets

Origin: 579a8f3 / M3.1
Identity History: none
GitHub Issue: #19 - https://github.com/jeonghanlee/cloud-provision/issues/19
Status: Not started

##### Summary

Review the VM readiness and shutdown wait budgets as one policy. The current evidence shows that the `cloud-init` budget ended a healthy production bake before the build VM finished.

##### Scope

- Review IP discovery, SSH readiness, `cloud-init` completion, and domain shutdown budgets together.
- Record the measurements and the policy decision.
- Reconcile the runbook and script limits after the policy is decided.

Out of scope: Changing `cloud-init` status parsing, SSH readiness semantics, VM naming, image selection, or libvirt lifecycle behavior.

##### Completion Criteria

- The four wait budgets are documented together with the measurements that justify them: IP discovery at 3 x 10s, SSH readiness at 6 x 10s, `cloud-init` completion at 20 x 30s, and domain shutdown at 12 x 5s in `do_stop` versus 24 x 5s in the bake.
- The runbook's diagnosis guidance and the script limits agree.
- Verification covers timeout and eventual-success behavior through the public script path, replacing only external command boundaries where isolation is required.
- The measured basis answers G1's shutdown allowance question.

Observed 2026-07-31 during a production bake: the `cloud-init` budget expired while the build VM was healthy and still working. `cloud-init status --long` reported `status: running`, `Running in stage: modules-final`, and `errors: []`; `systemctl --failed` listed nothing; and `dnf` had logged `Total download size: 97 M`. The budget, not the boot, ended the run.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Measure the four wait paths on real supported VM environments.
2. Decide the policy and record the owner acceptance.
3. Update the implementation and runbook where the policy changes behavior.
4. Verify timeout and eventual-success behavior through the public paths.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.1 / T1 | Runtime policy | Measure the real readiness and shutdown paths, then exercise timeout and eventual-success cases | Supported Rocky 8 and Debian 13 VM environments | The recorded policy matches observed behavior and the public paths report the intended result |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.1 / T1 | 2026-07-31 | Production bake on host `Neutron` | Observed the `cloud-init` budget expire while the VM remained healthy and active; the full policy has not yet been decided | GitHub issue #19 evidence and prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |

##### Closure Evidence

- none

##### GitHub Projection

Title: Review VM readiness retry durations
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-12; issue updated 2026-07-31T09:37:09Z

<a id="m32"></a>
#### M3.2 - Reuse VM stop behavior in the ioc-runner bake

Origin: 579a8f3 / M3.2
Identity History: none
GitHub Issue: #11 - https://github.com/jeonghanlee/cloud-provision/issues/11
Status: Blocked

##### Summary

Decide whether the ioc-runner bake should reuse the shared VM stop behavior or retain a separate parameterized path. The shutdown budget must be decided before the implementation path is selected.

##### Scope

- Decide the required shutdown allowance.
- Share the shipped stop path or document and test an explicitly separate path.
- Cover successful shutdown, timeout, and unexpected domain state.

Out of scope: Changing the image flattening or cleanup sequence.

##### Completion Criteria

- The required bake timeout is decided.
- The selected shared or separate paths cover successful shutdown, timeout, and unexpected state.
- Resume as Not started when M3.1 and G1 are Complete.

##### Dependencies And Decisions

- M3.1
- G1

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Use M3.1 and G1 to establish the shutdown policy.
2. Select the shared or explicitly separate implementation path.
3. Add or update the public-path checks for all required shutdown states.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.2 / T1 | Runtime behavior | Exercise successful shutdown, timeout, and unexpected domain state through the shipped bake and VM lifecycle paths | Supported VM environments with controlled domain states | The selected path applies one documented policy and reports each state correctly |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.2 / T1 | 2026-08-06 canonicalization evidence | As recorded in the prior generation | Not rerun during reset; blocked by M3.1 and G1 | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |

##### Closure Evidence

- Blocked by M3.1 and G1. Restore status to Not started when both dependencies are Complete.

##### GitHub Projection

Title: Reuse VM stop behavior in the iocrunner bake
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-12; issue updated 2026-07-23T08:37:27Z

<a id="m41"></a>
#### M4.1 - Validate the Rocky 8 golden after the sudoers fix

Origin: 579a8f3 / M4.1
Identity History: none
GitHub Issue: #4 - https://github.com/jeonghanlee/cloud-provision/issues/4
Status: Blocked

##### Summary

Validate the Rocky 8 golden after the sudoers fix. This is an external runtime verification and cannot be closed by repository changes alone.

##### Scope

- Boot the real `rocky8-iocrunner.server` path from the 2026-06-03 Rocky 8 golden.
- Run the downstream system-infrastructure and system-lifecycle checks.
- Record the commands and observed results before closure.

Out of scope: Rebuilding the golden image unless runtime verification identifies a new defect.

##### Completion Criteria

- The real `rocky8-iocrunner.server` path passes the downstream system-infrastructure and system-lifecycle checks, with commands and results recorded.
- Resume as Not started when G2 completes.

##### Dependencies And Decisions

- G2

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Obtain the real Rocky 8 golden and downstream validation environment.
2. Run the shipped consumer path and downstream checks without replacing the provisioning path.
3. Record the commands and observed results.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.1 / T1 | External runtime | Boot the shipped Rocky 8 consumer and run the downstream system-infrastructure and system-lifecycle checks | Real Rocky 8 golden and downstream ioc-runner validation environment | The consumer and both downstream check groups pass, with evidence recorded |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.1 / T1 | 2026-08-06 canonicalization evidence | As recorded in the prior generation | Not rerun during reset; blocked by G2 | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |

##### Closure Evidence

- Blocked by G2. Restore status to Not started when G2 is Complete.

##### GitHub Projection

Title: Validate the Rocky 8 iocrunner golden after the sudoers ordering fix
Labels: none
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: none
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-12; issue updated 2026-07-23T08:36:44Z

<a id="g1"></a>
#### G1 - Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance

Origin: 579a8f3 / G1
GitHub Issue: none
Status: Open

##### Summary

Confirm whether the ioc-runner bake requires a separate 120-second shutdown allowance. This external gate affects M3.2.

##### Affected Work

- M3.2

##### Completion Criteria

- The bake waits 24 x 5s while `do_stop` waits 12 x 5s.
- M3.1 provides the measured basis for the difference.
- The owner accepts the resulting shutdown policy.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-08-06 canonicalization evidence | Open; not rerun during reset | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |

##### Closure Evidence

- none; the external condition remains open.

<a id="g2"></a>
#### G2 - Run downstream validation on the 2026-06-03 Rocky 8 golden image

Origin: 579a8f3 / G2
GitHub Issue: none
Status: Open

##### Summary

Run downstream validation on the 2026-06-03 Rocky 8 golden image. This external gate affects M4.1.

##### Affected Work

- M4.1

##### Completion Criteria

- The real golden image, `rocky8-iocrunner.server`, and downstream ioc-runner validation environment are available.
- The downstream system-infrastructure and system-lifecycle checks run against that VM.
- Commands and observed results are recorded before the gate closes.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-08-06 canonicalization evidence | Open; not rerun during reset | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |

##### Closure Evidence

- none; the external condition remains open.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M2 Deferred EtherCAT acceptance | M2.1 | Validate EtherCAT use of the shared image workflow | Verification | Deferred | No | D3 | Run the shipped EtherCAT bake and consumer on supported Libvirt/KVM, inspect the image, manifest, and creation-record pair, and confirm actual consumer selection; [M2.1 detail](#m21). |

### Backlog Details

<a id="m21"></a>
#### M2.1 - Validate EtherCAT use of the shared image workflow

Origin: 2026-08-13 split from 579a8f3 / M1.1; carries prior-state M1.7 and M1.8 from commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0`.
Identity History: 2026-08-13: split from M1.1; carries runtime acceptance that followed prior-generation M1.7 and M1.8.
GitHub Issue: none
Status: Deferred

##### Summary

Commit `304291b` integrates the EtherCAT bake and consumer with the shared naming, copy, creation-record, and pair-validation code used by ioc-runner. Local contract checks pass, but no actual EtherCAT bake or fresh consumer selection has been observed on supported Libvirt/KVM in this generation. Owner direction defers that runtime acceptance so it does not block M1.1.

##### Scope

- Run the shipped Debian 13 EtherCAT bake on supported Libvirt/KVM.
- Inspect the produced image, manifest, and creation record for matching identity and no backing file.
- Boot a fresh `debian13-ethercat` consumer and confirm that it selects the exact valid pair.
- Record the runtime evidence in this detail section.

Out of scope: Changes to the shared image workflow unless runtime verification exposes a defect. Ioc-runner acceptance remains owned by M1.1.

##### Completion Criteria

- A real EtherCAT bake completes through the shipped entry point.
- The produced image has no backing file.
- The image, manifest, and creation record agree on run identifier and artifact identity.
- A fresh EtherCAT consumer selects the exact verified pair.
- The observed paths, identifiers, and selection evidence are recorded here.

##### Dependencies And Decisions

- D3
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
| M2.1 / T1 | Local contract | Run the EtherCAT portion of `make check-bake` through the public script entry points with only external command boundaries replaced | Repository checkout containing the delivered workflow | Shared names, creation records, pair validation, and failure handling remain internally consistent |
| M2.1 / T2 | Runtime acceptance | Run the shipped EtherCAT bake and a fresh consumer, then inspect the output pair and qcow2 metadata | Supported Libvirt/KVM host with EtherCAT bake prerequisites | The bake produces an independent valid pair and the consumer selects that exact pair |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2.1 / T1 | 2026-08-13 | Local checkout; public entry points with external command boundaries replaced | The EtherCAT workflow portion of `make check-bake` completed all 8 checks. This does not satisfy runtime acceptance. | `tests/check-ethercat-bake-workflow.bash` |

##### Closure Evidence

- Deferred by owner direction on 2026-08-13. Runtime acceptance has not run.

## Assignment History

| Date | Work | Change | Evidence |
| --- | --- | --- | --- |
| 2026-08-13 | M2.1 | Split EtherCAT runtime acceptance from Current M1.1 into Backlog. Shared implementation evidence remains with M1.1. | Owner direction; prior-generation M1.7 and M1.8 in history commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0`. |

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-12 | 579a8f322c6ee3997c6e6ae2581b9a0477666ef0 |
