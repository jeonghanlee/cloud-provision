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

Next session entry point: run the two delivered bake entry points on a supported Libvirt/KVM host, inspect the produced image pairs, add the deferred EtherCAT consumer-selection check, then close M1.1 if the runtime and external gates pass.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Image workflow adoption | M1.1 | Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md` | Milestone | In progress | No | D1, D2 | Implement the copy-based image workflow, shared bake path, single naming rule, and matching creation record pair; [M1.1 detail](#m11). |
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
| D3 | GitHub issue #30 is the owning scope for image workflow adoption. EtherCAT image structure and build-VM creation work formerly split into M2.1 and M2.2 are absorbed into M1.1 rather than tracked as separate work. | Owner direction based on issue #30, 2026-08-12 |

### Milestone Details

<a id="m11"></a>
#### M1.1 - Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`

Origin: 579a8f3 / M1.1
Identity History: none
GitHub Issue: #30 - https://github.com/jeonghanlee/cloud-provision/issues/30
Status: In progress

##### Summary

Implement GitHub issue #30 against the structure recorded in `docs/IMAGE_WORKFLOW.md`. The issue removes the two roots that caused most of the earlier image work: the backing chain and the assumption that an existing name proves ownership. This is the first implementation item in the reset generation and is not complete because the design document or the issue body alone is not implementation evidence.

##### Scope

- Use a copy at every image step so no VM disk holds an upstream image.
- Produce both ioc-runner and EtherCAT bake families through one shared path.
- Define image names in one place with the run timestamp and hash.
- Write a creation record beside every produced image and require the name and record to agree.
- Include the EtherCAT image structure and build-VM creation behavior formerly tracked by M2.1 and M2.2.
- After implementation and verification, align `docs/ARCHITECTURE.md` and `docs/RUNBOOK_BAKE.md` with the delivered workflow.

Out of scope: Wait budgets (#19), stop behavior (#11), and Rocky 8 downstream validation (#4) remain separate work. The disk cost of full copies and the time cost of purpose work running per VM instead of once per bake remain deferred by owner direction.

##### Completion Criteria

- A VM disk is a copy rather than an overlay, and no image produced by the workflow appears in another image's backing chain.
- Both bakes produce images through one shared path.
- Names come from one rule and carry the run timestamp and hash.
- Every produced image has a matching creation record, and a check rejects a missing or mismatched pair.
- The archive split, in-use guard, symlink ban, forced publish, flattening, and name-existence ownership assumptions are not required as separate mechanisms under this workflow.
- `docs/ARCHITECTURE.md` and `docs/RUNBOOK_BAKE.md` describe the delivered image paths, names, records, and verification commands.

##### Dependencies And Decisions

- D1
- D2

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner direction in current session, 2026-08-12
Implementation Authorization: Owner direction in current session, 2026-08-12
Superseded Plan Artifacts: none

1. Implement the shared copy, naming, and creation-record path for the shipped ioc-runner and EtherCAT bake entry points.
2. Add checks for the copy chain and matching image and creation-record pair.
3. Run the real bake paths and record the observed results.
4. Update `docs/ARCHITECTURE.md` and `docs/RUNBOOK_BAKE.md` to match the verified workflow.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | Integration | Run the shipped ioc-runner and EtherCAT bake paths and inspect the produced copy chain, names, and creation records | Libvirt/KVM bake host with supported OS inputs | Both paths use the shared workflow and every image has a matching creation record |
| M1.1 / T2 | Documentation | Run the repository documentation checks and compare the architecture and runbook commands with the verified bake outputs | Repository checkout containing the delivered workflow | The architecture and runbook describe the same paths, names, records, and checks |

##### Deferred Verification

- EtherCAT consumer selection through `create_vm.bash -o debian13-ethercat` is deferred by owner direction on 2026-08-13. The current verification covers EtherCAT bake completion and its image and creation-record pair; add the consumer-selection check before M1.1 closure.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | 2026-08-13 | Local checkout; real shipped scripts and fixtures with only virsh, ssh, ansible-playbook, qemu-img, virt-install, and clock or host-key boundaries replaced | Local public-path contract passed: `make check-cloud-init-status` 87/87, `make check-bake` passed fresh-input 7/7, ioc-runner provenance 62/62, and EtherCAT workflow 8/8. The checks produced unique names and matching creation records for both bake entry points, rejected missing and mismatched pairs, and rejected an invalid run ID. A real Libvirt/KVM bake remains to be run. | `tests/check-cloud-init-status.bash`, `tests/check-iocrunner-bake-provenance.bash`, `tests/check-ethercat-bake-workflow.bash` |
| M1.1 / T2 | 2026-08-13 | Local checkout | `make check-docs` passed 51/51; `git diff --check` and shellcheck for the changed scripts and tests passed. `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, and `docs/IMAGE_WORKFLOW.md` now describe the same centralized naming, unique image, creation-record, and shared-copy paths. | `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, `docs/IMAGE_WORKFLOW.md`, `configure/RULES_BAKE` |

##### Closure Evidence

- none

##### GitHub Projection

Title: Adopt the image workflow
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-12; issue updated 2026-08-02T05:59:41Z

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

No unassigned work is recorded in this generation.

### Backlog Details

No backlog details.

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-12 | 579a8f322c6ee3997c6e6ae2581b9a0477666ef0 |
