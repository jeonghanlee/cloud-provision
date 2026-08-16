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

Next session entry point: no Milestone work remains. Backlog M2.1 remains Deferred pending separate owner authorization for EtherCAT runtime acceptance.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Image workflow adoption | M1.1 | Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md` | Milestone | Complete | No | D1, D2, D3 | Verify that the ioc-runner workflow produces independent run-specific golden pairs through shared naming, copy, and record code on real supported hosts; [M1.1 detail](#m11). |
| M3 VM lifecycle policy | M3.1 | Review VM readiness and shutdown wait budgets | Milestone | Complete | No | D4 | Commit `986d410` records and verifies the shared policy; GitHub issue #19 is closed; [M3.1 detail](#m31). |
| M3 VM lifecycle policy | M3.2 | Reuse VM stop behavior in the ioc-runner bake | Milestone | Complete | No | D4, G1 | Commit `986d410` routes the bake through the shared public stop path; GitHub issue #11 is closed; [M3.2 detail](#m32). |
| M4 Rocky golden validation | M4.1 | Validate the Rocky 8 golden after the sudoers fix | Milestone | Complete | No | G2, D5 | Owner retired the obsolete 2026-06-03 target without claiming T1 passed; current-image validation moved to `epics-ioc-runner` #146; [M4.1 detail](#m41). |
| M5 Dynamic Ansible inventory | M5.1 | Replace fixed Ansible host inventory with VM-derived inventory | Milestone | Complete | No |  | Commits `c1f657b` and `50925d4` deliver the host-free inventory workflow; T1 and T2 passed, and GitHub issue #31 is closed; [M5.1 detail](#m51). |
| External gate | G1 | Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance | External gate | Complete | No |  | Owner accepts a measured shutdown policy for the bake and provisioner paths; [G1 detail](#g1). |
| External gate | G2 | Run downstream validation on the 2026-06-03 Rocky 8 golden image | External gate | Complete | No | D5 | Owner retired the exact historical target after the image workflow superseded it; no validation pass is claimed; [G2 detail](#g2). |

### Decisions

| ID | Decision | Source |
| --- | --- | --- |
| D1 | Image structure is settled by `docs/IMAGE_WORKFLOW.md`: a copy at every step so nothing upstream is held, identity carried by a file name and a creation record that must agree, the naming rule defined in one place, and build VMs fresh by construction. | User direction, 2026-08-01 |
| D2 | New development moves to branches: `master` takes no direct implementation work from this generation onward, and the annotated tag `pre-image-workflow` marks the last state built that way. | User direction, 2026-08-01 |
| D3 | GitHub issue #30 owns ioc-runner acceptance of the copy-based image workflow. Shared code delivered in commit `304291b` also integrates EtherCAT, but actual EtherCAT bake and consumer validation is deferred to Backlog M2.1 and does not block M1.1. The earlier claim that the old EtherCAT rows were M2.1 and M2.2 was incorrect; the prior-generation EtherCAT rows were M1.7 and M1.8. | Owner direction, 2026-08-13 |
| D4 | Centralize the VM wait settings with validated execution-time overrides. Use six IP polls at 10-second intervals, six SSH probes at 10-second intervals with a 5-second connection timeout, sixty-one cloud-init polls at 30-second intervals, and twelve shutdown polls at 5-second intervals. The ioc-runner bake uses the same public 60-second shutdown path instead of a separate 120-second loop. | Owner selection of option 1, 2026-08-14 |
| D5 | Retire G2 and M4.1 without claiming M4.1 / T1 passed because their exact 2026-06-03 fixed-name golden target is obsolete after issue #30. Carry the remaining current-image downstream verification in `epics-ioc-runner` issue #146, independent of this milestone and issue #4 closure. | Owner selection of the Backlog carry-forward and repository boundary, 2026-08-16 |

### Milestone Details

<a id="m11"></a>
#### M1.1 - Adopt the image workflow recorded in `docs/IMAGE_WORKFLOW.md`

Origin: 579a8f3 / M1.1
Identity History: 2026-08-13: EtherCAT runtime acceptance split to Backlog M2.1; shared implementation evidence remains here.
GitHub Issue: #30 - https://github.com/jeonghanlee/cloud-provision/issues/30
Status: Complete

##### Summary

Implement GitHub issue #30 against the structure recorded in `docs/IMAGE_WORKFLOW.md`. The issue removes two root causes: qcow2 backing chains that made runtime disks retain published images, and stable-name existence checks that treated an existing domain or file as proof of ownership. Commit `304291b` contains the shared workflow base; commit `fcf206b` supplies run-specific Ansible inventory, paired cleanup, and the restored 20 GiB VM disk size. Local and runtime acceptance are complete and owner-accepted, and GitHub issue #30 is closed.

##### Scope

- Create VM runtime disks as independent full copies so no VM disk retains an upstream image.
- Preserve the configured 20 GiB VM disk size after making each independent copy.
- Publish each ioc-runner bake under a run-specific immutable image name through the shared image workflow.
- Centralize ioc-runner build VM names, image names, disk paths, and run identifiers.
- Write a creation record for each produced ioc-runner golden image and VM disk.
- Remove a VM disk and its creation record together during cleanup.
- Add each run-specific ioc-runner build VM to the required Ansible groups without a maintained exact-name host row.
- Select only the newest valid ioc-runner image-plus-record pair for stable-name consumers.
- Reject missing or mismatched ioc-runner golden creation records before VM definition or start.
- Keep `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, `docs/IMAGE_WORKFLOW.md`, and `docs/VIRSH_CLI.md` aligned with the delivered workflow.

Out of scope: Actual EtherCAT bake and consumer validation is tracked as Backlog M2.1. Full replacement of maintained fixed-name Ansible inventory is tracked as M5.1 and #31. Wait budgets (#19), stop behavior (#11), Rocky 8 downstream validation (#4), general disk-space policy beyond restoring the existing 20 GiB VM disk size, and elapsed-time policy remain separate work.

##### Completion Criteria

- The public VM-creation path makes a full source-image copy and the resulting qcow2 has no backing file.
- The public VM-creation path resizes each independent VM disk to the configured 20 GiB capacity.
- Real Rocky 8 and Debian 13 ioc-runner bakes produce run-specific image, manifest, and creation-record pairs through the shared workflow.
- Both final bake manifests record exact clean 40-character `cloud-provision` and `ansible-provision` commit identities without a `-dirty` suffix.
- Build VM names, golden image names, and VM disk paths come from centralized workflow functions.
- Run-specific ioc-runner build VMs reach the required Ansible plays without a maintained exact-name inventory row.
- Cleanup removes each VM disk, matching creation record, and seed ISO together.
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
Plan Acceptance: Owner direction in current sessions, 2026-08-12 and 2026-08-13
Implementation Authorization: Owner direction in current sessions, 2026-08-12 and 2026-08-13
Superseded Plan Artifacts: none

1. Implement shared run identifiers, naming, paths, independent-copy handling, creation records, and pair validation.
2. Restore the configured 20 GiB capacity after each independent VM disk copy.
3. Route the ioc-runner bake and consumer scripts through the shared functions.
4. Supply each run-specific ioc-runner build VM to the existing Ansible groups through a temporary inventory source.
5. Remove each VM disk and its creation record together during cleanup.
6. Replace stable single-image refresh with run-specific published artifacts and latest-valid-pair selection.
7. Verify the public paths locally with only external command boundaries replaced.
8. Align the maintained image-workflow documentation with the shipped paths.
9. Commit the accepted implementation before runtime acceptance, then confirm the `cloud-provision` and `ansible-provision` working trees are clean and capture their exact 40-character HEAD identities.
10. Remove the retained failed Debian 13 build run, run the Debian 13 bake, inspect its output pair, no-backing state, and 20 GiB capacity, then boot a fresh Debian 13 consumer.
11. Reconfirm both repository trees are clean, run the Rocky 8 bake, inspect its output pair, no-backing state, and 20 GiB capacity, then boot a fresh Rocky 8 consumer.
12. Confirm both manifests record the captured clean repository identities and record the final runtime evidence.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | Local integration | Run `make check-cloud-init-status` and the ioc-runner portions of `make check-bake` through the public script entry points with only external command boundaries replaced | Repository checkout containing the delivered workflow | Independent copies have no backing file and retain the configured 20 GiB capacity; ioc-runner bakes use centralized names, temporary inventory, and creation records; cleanup removes VM disk pairs; consumers reject missing or mismatched records |
| M1.1 / T2 | Runtime acceptance | After the implementation commit, confirm both repository trees are clean; run the Debian 13 bake and consumer checks; reconfirm clean trees; run the Rocky 8 bake and consumer checks; inspect both outputs with `qemu-img info --output=json` | Supported Libvirt/KVM bake hosts with supported OS inputs and clean committed `cloud-provision` and `ansible-provision` trees | Each bake produces an independent 20 GiB image with no backing file, a matching manifest and creation record with exact clean 40-character repository identities, and a consumer that selects the exact verified pair |
| M1.1 / T3 | Documentation | Run the repository documentation checks and compare the architecture, image workflow, runbook, and CLI commands with the shipped paths | Repository checkout containing the delivered workflow | The maintained documents describe independent copies, 20 GiB virtual capacity, names, records, and checks without recommending a backing chain |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | 2026-08-13 | Local checkout; real shipped scripts and fixtures with only virsh, ssh, ansible-playbook, qemu-img, virt-install, and clock or host-key boundaries replaced; real cleanup rerun on host `top` | Local public-path contract passed: `make check-cloud-init-status` 91/91; the M1.1 portions of `make check-bake` passed fresh-input 7/7 and ioc-runner provenance 77/77. The checks verified independent copies, the restored 20 GiB VM disk resize, unique names, matching creation records, temporary inventory membership and removal, cleanup of VM disk pairs, pair rejection, and invalid run-ID rejection. The first real cleanup of run `20260813T195453Z-1dbbd75082f9` left the disk creation record after removing the domain, disk, seed, and DHCP entry. After the cleanup fix, the same public command removed the orphan and no artifact for that run remained. `shellcheck -x bin/create_vm.bash tests/check-cloud-init-status.bash` and `git diff --check` also passed. | `tests/check-cloud-init-status.bash`, `tests/check-iocrunner-bake-provenance.bash`; `bin/create_vm.bash -o rocky8 -n build -d /home/jeonglee/libvirt/images -p testbed -c` with the recorded run ID |
| M1.1 / T2 | 2026-08-14 11:59 PDT | Host `top`; real Libvirt/KVM; clean `cloud-provision` commit `fcf206bc9771545b02c69608bd7f5f5a799c0621`; clean `ansible-provision` commit `5c52419bf3be795780abdc64cec7732d424fede4` | Runtime acceptance passed. Debian run `20260814T183016Z-d6ba836a6368` and Rocky run `20260814T184022Z-d83582600cba` completed all nine bake steps and passed the real in-image validator. Both published qcow2 images report `virtual-size=21474836480` and no backing file; both manifests contain the exact clean repository identities. Fresh consumer runs `20260814T183831Z-157be32edd31` and `20260814T185737Z-3e7886fd1f5e` selected the matching golden names in their creation records and reached `READY`. Each in-image manifest SHA-256 matched its published sidecar, and both consumers report `epics-ioc-runner version 1.2.3 (e357210)`. Both build VMs and their disk pairs were removed after publication; the fresh consumers remain running. | `make bake.debian13`; `iocrunner-debian13-20260814T183016Z-d6ba836a6368.qcow2` and sidecars; `make debian13-iocrunner.server`; manifest SHA-256 `ef57b6d01885ffd282349fd9919f7add2461b1c27ee3932b6755becf768e162c`; `make bake.rocky8`; `iocrunner-rocky8-20260814T184022Z-d83582600cba.qcow2` and sidecars; `make rocky8-iocrunner.server`; manifest SHA-256 `d2d6f88832e5e6799c79aaa8c5e4aa686d843da9ded0196134502be5a28cf519` |
| M1.1 / T3 | 2026-08-14 | Local checkout; reader-seat command check using the cached Debian 13 upstream image and real `qemu-img` in a temporary directory | `make check-docs` passed 51/51. The maintained workflow documents describe centralized naming, unique images, creation records, independent copies, and the 20 GiB virtual-capacity step; the CLI reference no longer recommends a backing-chain command. Running its independent `convert`, `resize 20G`, and JSON `info` sequence produced qcow2 with `virtual-size=21474836480` and no `backing-filename`. This result checks the documented command sequence; M1.1 / T2 records final Libvirt/KVM runtime acceptance. | `docs/ARCHITECTURE.md`, `docs/RUNBOOK_BAKE.md`, `docs/IMAGE_WORKFLOW.md`, `docs/VIRSH_CLI.md`, `configure/RULES_BAKE` |

##### Closure Evidence

- Deliverable and M1.1 / T1 through T3 verification are complete. The owner accepted the final third-person review evidence in the current session on 2026-08-14. GitHub issue #30 was observed closed at 2026-08-14T19:40:43Z.

##### GitHub Projection

Title: Adopt the image workflow
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-14; issue updated 2026-08-14T19:40:43Z

<a id="m31"></a>
#### M3.1 - Review VM readiness and shutdown wait budgets

Origin: 579a8f3 / M3.1
Identity History: none
GitHub Issue: #19 - https://github.com/jeonghanlee/cloud-provision/issues/19
Status: Complete

##### Summary

Commit `986d410` implements the D4 wait policy, records it in the architecture and runbook, and verifies timeout, eventual-success, override, and invalid-input behavior. GitHub issue #19 is closed.

##### Scope

- Review IP discovery, SSH readiness, `cloud-init` completion, and domain shutdown budgets together.
- Record the measurements and the policy decision.
- Reconcile the runbook and script limits after the policy is decided.

Out of scope: Changing `cloud-init` status parsing, SSH readiness semantics, VM naming, image selection, or libvirt lifecycle behavior.

##### Completion Criteria

- The four wait policies are documented together with the measurements that justify them: IP discovery at six polls with 10-second intervals, SSH readiness at six probes with 10-second intervals and a 5-second connection timeout, `cloud-init` completion at sixty-one polls with 30-second intervals, and domain shutdown at twelve polls with 5-second intervals through one shared path.
- The runbook's diagnosis guidance and the script limits agree.
- Verification covers timeout and eventual-success behavior through the public script path, replacing only external command boundaries where isolation is required.
- The measured basis answers G1's shutdown allowance question.

Observed 2026-07-31 during a production bake: the `cloud-init` budget expired while the build VM was healthy and still working. `cloud-init status --long` reported `status: running`, `Running in stage: modules-final`, and `errors: []`; `systemctl --failed` listed nothing; and `dnf` had logged `Total download size: 97 M`. The budget, not the boot, ended the run.

Pre-change code inspection on 2026-08-14 confirmed that the readiness values are poll counts rather than exact elapsed-time budgets. IP discovery made three polls with two 10-second sleeps. SSH made six probes with five 10-second sleeps and each probe could spend up to the configured 5-second connection timeout. Cloud-init made twenty polls with nineteen 30-second sleeps. The shutdown paths slept before every poll, so their twelve and twenty-four 5-second waits were actual 60-second and 120-second limits.

##### Dependencies And Decisions

- D4

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner approved the isolated measurement plan and selected D4 option 1 in the current session, 2026-08-14
Implementation Authorization: Owner authorized the accepted measurement and D4 implementation plan in the current session, 2026-08-14
Superseded Plan Artifacts: none

1. Confirm that isolated `m31-rocky8-test` and `m31-debian13-test` DHCP VM names do not collide with existing domains.
2. Provision both isolated VMs through the shipped public path and record IP discovery, SSH readiness, and cloud-init completion timings without replacing an internal function.
3. Stop both isolated VMs through the shipped public stop path, record graceful-shutdown timings, and clean only the two isolated domains and their artifacts.
4. Analyze the measurements and propose the intended budgets. Do not change production values until the owner accepts the policy decision.
5. Implement D4, update the runbook, and verify timeout and eventual-success behavior through the public paths.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.1 / T1 | Runtime policy | Measure the real readiness and shutdown paths, then exercise timeout and eventual-success cases | Supported Rocky 8 and Debian 13 VM environments | The recorded policy matches observed behavior and the public paths report the intended result |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.1 / T1 | 2026-07-31 | Production bake on host `Neutron` | Observed the `cloud-init` budget expire while the VM remained healthy and active; the full policy has not yet been decided | GitHub issue #19 evidence and prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |
| M3.1 / T1 | 2026-08-14 17:10 PDT | Host `top`; real Libvirt/KVM; isolated `m31-rocky8-test` and `m31-debian13-test` DHCP VMs; shipped `bin/create_vm.bash` provision, stop, and cleanup paths with an outer UTC timestamp recorder | Both provisioning runs reached `READY` and both public stop runs succeeded. Rocky 8 obtained an address on the third DHCP poll after about 21 seconds, passed SSH on the first probe, and reported cloud-init complete on the third status poll 61 seconds after the first status check. Debian 13 obtained an address on the second DHCP poll after about 10 seconds, passed SSH on the first probe, and reported cloud-init complete on the third status poll 61 seconds after the first status check. Each VM reached `shut off` on the first 5-second stop poll. Cleanup removed both isolated domains, disk pairs, and seed ISOs; no matching domain, file, or DHCP reservation remained. This base-image sample does not replace the prior package-installing bake observation. | `bin/create_vm.bash -o <os> -n test -d /home/jeonglee/libvirt/images -p m31 -F`; the same command with `-S` and `-c`; UTC observation window 2026-08-15T00:06:19Z through 2026-08-15T00:10:11Z |
| M3.1 / T1 | 2026-08-15 01:31 PDT | Local checkout; shipped `bin/create_vm.bash` with only outer `virsh`, `ssh`, and `sleep` boundaries controlled by the repository fixture | The default timeout and last-attempt success cases passed for IP discovery, SSH, cloud-init, and shutdown. Execution-time overrides reached the public path. All nine settings rejected zero, and representative negative and non-integer values were rejected before a VM action. | `make check-cloud-init-status`: 151/151; `bash -n`: pass; `shellcheck -S warning`: pass; plain `shellcheck`: two existing SC1091 information items for dynamic `source` paths; `git diff --check`: pass |

##### Closure Evidence

- Complete on 2026-08-15. Commit `986d410` is present on `origin/feature/image-workflow`; third-person and second-person findings were corrected; GitHub issue #19 was observed closed at 2026-08-15T08:44:52Z.

##### GitHub Projection

Title: Review VM readiness retry durations
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-15; issue updated 2026-08-15T08:44:52Z

<a id="m32"></a>
#### M3.2 - Reuse VM stop behavior in the ioc-runner bake

Origin: 579a8f3 / M3.2
Identity History: none
GitHub Issue: #11 - https://github.com/jeonghanlee/cloud-provision/issues/11
Status: Complete

##### Summary

Commit `986d410` routes ioc-runner publication through `create_vm.bash -S` with the same validated shutdown settings used by ordinary VM operations. GitHub issue #11 is closed.

##### Scope

- Apply the D4 shutdown allowance.
- Share the shipped public stop path.
- Cover successful shutdown, timeout, and unexpected domain state.

Out of scope: Changing the image flattening or cleanup sequence.

##### Completion Criteria

- The required bake timeout is recorded in D4.
- The bake invokes the shipped public stop path.
- The shared path covers successful shutdown, timeout, and unexpected state.

##### Dependencies And Decisions

- D4
- G1

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner selection of D4 option 1 in the current session, 2026-08-14
Implementation Authorization: Owner authorized the selected implementation in the current session, 2026-08-14
Superseded Plan Artifacts: none

1. Use D4 and G1 as the accepted shutdown policy.
2. Call `create_vm.bash -S` from the ioc-runner publication step.
3. Verify bake wiring and the shared public path's successful shutdown, timeout, and unexpected-state behavior.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3.2 / T1 | Runtime behavior | Exercise successful shutdown, timeout, and unexpected domain state through the shipped bake and VM lifecycle paths | Shipped scripts with controlled outer `virsh`, `ssh`, and `sleep` boundaries, plus M3.1 real stop measurements | The selected path applies one documented policy and reports each state correctly |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3.2 / T1 | 2026-08-06 canonicalization evidence | As recorded in the prior generation | Not rerun during reset; blocked by M3.1 and G1 | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |
| M3.2 / T1 | 2026-08-15 01:31 PDT | Local checkout; shipped ioc-runner bake and VM lifecycle scripts with controlled outer command boundaries; M3.1 real shutdown measurements | Three successful publication cases called the public `create_vm.bash -S` path and passed a 7-second execution override to it. The shared lifecycle test covered first-poll and last-poll success, timeout, and unexpected state. | `make check-bake`: 7/7 fresh-input, 83/83 ioc-runner provenance and publication, 8/8 EtherCAT regression; `make check-cloud-init-status`: 151/151; `make check-docs`: 51/51 |

##### Closure Evidence

- Complete on 2026-08-15. Commit `986d410` is present on `origin/feature/image-workflow`; third-person and second-person findings were corrected; GitHub issue #11 was observed closed at 2026-08-15T08:44:56Z.

##### GitHub Projection

Title: Reuse VM stop behavior in the iocrunner bake
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-15; issue updated 2026-08-15T08:44:56Z

<a id="m41"></a>
#### M4.1 - Validate the Rocky 8 golden after the sudoers fix

Origin: 579a8f3 / M4.1
Identity History: none
GitHub Issue: #4 - https://github.com/jeonghanlee/cloud-provision/issues/4
Status: Complete

##### Summary

The original work targeted the fixed-name Rocky golden rebuilt on 2026-06-03. Issue #30 replaced that image workflow and produced a newer run-specific Rocky image and fresh consumer, so the owner retired this exact historical target. M4.1 / T1 was not rerun and is not recorded as passed; current-image downstream validation is carried by `epics-ioc-runner` issue #146.

##### Scope

- Boot the real `rocky8-iocrunner.server` path from the 2026-06-03 Rocky 8 golden.
- Run the downstream system-infrastructure and system-lifecycle checks.
- Record the commands and observed results before closure.

Out of scope: Rebuilding the golden image unless runtime verification identifies a new defect.

##### Completion Criteria

- Owner-approved retirement records that the exact 2026-06-03 target is obsolete and waives its unrun T1 without calling it Pass.
- Current-image downstream verification is independently tracked in `epics-ioc-runner` issue #146.

##### Dependencies And Decisions

- G2
- D5

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner selected local completion with an explicit exception for the open issue state, 2026-08-16; issue #4 was subsequently observed closed.
Implementation Authorization: Owner authorized the canonical milestone update, 2026-08-16.
Superseded Plan Artifacts: The original three-step runtime plan below was retired by D5.

1. Record owner-approved retirement of the obsolete 2026-06-03 target.
2. Preserve M4.1 / T1 as not run and make no downstream pass claim for the issue #30 image.
3. Record `epics-ioc-runner` issue #146 as the independent owner of current-image downstream validation.
4. Observe issue #4 closed and update the milestone status and next session entry point.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M4.1 / T1 | External runtime | Boot the shipped Rocky 8 consumer and run the downstream system-infrastructure and system-lifecycle checks | Real Rocky 8 golden and downstream ioc-runner validation environment | The consumer and both downstream check groups pass, with evidence recorded |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M4.1 / T1 | 2026-08-06 canonicalization evidence | As recorded in the prior generation | Not rerun during reset; blocked by G2 | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |
| M4.1 / T1 | 2026-08-16 owner retirement | Retired 2026-06-03 target | Not run; waived by D5, not passed | Issue #30 superseded the fixed-name workflow; remaining current-image verification moved to `epics-ioc-runner` issue #146 |

##### Closure Evidence

- Complete by owner-approved retirement on 2026-08-16 under D5; M4.1 / T1 remains explicitly not run.
- `ansible-provision` commit `141400bbad33b236cef24e58485dc48c255fa499` enforces the sudoers include directive as the final active directive.
- Durable `epics-ioc-runner` commit `60de0cf10d5d549712f146d293d13a7adc795740` records a 2026-08-12 real six-suite gate on fresh Rocky and Debian consumers. Rocky reported `SUITES OK (6 blocks, 614 checks, na=12)`; the recorded system-infrastructure S05 include-order checks and the real system-lifecycle S29 non-IOC sudo denial check passed. This predates issue #30 and supports retirement context only.
- Issue #30 accepted the current image workflow on Rocky run `20260814T184022Z-d83582600cba` with clean `cloud-provision` commit `fcf206bc9771545b02c69608bd7f5f5a799c0621`, clean `ansible-provision` commit `5c52419bf3be795780abdc64cec7732d424fede4`, installed runner `e357210`, valid provenance, and a fresh consumer that reached `READY`. It did not run the downstream suites.
- The unrun current-image check is owned by `epics-ioc-runner` issue #146 and does not block this retirement.

##### GitHub Projection

Title: Validate the Rocky 8 iocrunner golden after the sudoers ordering fix
Labels: none
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: none
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-16; issue closed and updated 2026-08-16T08:11:30Z

<a id="m51"></a>
#### M5.1 - Replace fixed Ansible host inventory with VM-derived inventory

Origin: 579a8f3 / M5.1
Identity History: none
GitHub Issue: #31 - https://github.com/jeonghanlee/cloud-provision/issues/31
Status: Complete

##### Summary

Replace hand-maintained per-VM host entries with inventory derived from the VM identity and address resolved by the provisioning path. Commits `c1f657b` in cloud-provision and `50925d4` in ansible-provision use one shared generator for ordinary VMs, ioc-runner consumers and build VMs, EtherCAT consumers and build VMs, and EPICS-env build VMs. The maintained inventory contains only group relationships, and its Make entry points require a generated runtime host source unless a complete site-owned inventory is supplied.

Local group checks cover all supported selectors and roles. Real acceptance configured a fresh arbitrary-name Debian 13 VM, ran the Debian 13 EPICS-env build playbook, and completed a fresh run-specific Rocky 8 ioc-runner bake. Actual EtherCAT bake and consumer validation remains deferred to Backlog M2.1 under D3 and is not part of M5.1 closure.

##### Scope

- Derive each Ansible host entry from the actual VM name, address, OS selector, and intended role groups.
- Cover ordinary VMs, ioc-runner consumers, EtherCAT consumers and build VMs, EPICS-env build VMs, and run-specific ioc-runner bake VMs.
- Preserve the intended `all_nodes`, `ioc_nodes`, `nfs_sim_nodes`, `ethercat_nodes`, `ethercat_build`, and `epics_env_build` group selection without requiring an exact host name in a maintained inventory file.
- Remove script, test, and maintained-document assumptions that a supported VM must already have a fixed inventory row.

Out of scope: Image artifact naming, qcow2 selection, DHCP and MAC allocation policy, Ansible role behavior, and the actual EtherCAT bake and consumer validation owned by Backlog M2.1.

##### Completion Criteria

- No supported VM or bake build host requires its exact name to be added to `inventory/testbed.ini` before Ansible can target it.
- Run-specific Rocky 8 and Debian 13 ioc-runner build VMs enter the correct OS, IOC, and NFS simulation groups.
- EtherCAT and EPICS-env paths enter only their intended groups.
- Checks reject missing or incorrect group membership and detect a return to fixed-name inventory dependence.
- Maintained architecture and runbook documents describe the same inventory source and group-selection behavior as the scripts.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner selected the shared generated-inventory option in the current session, 2026-08-15
Implementation Authorization: Owner authorized the selected implementation in the current session, 2026-08-15
Superseded Plan Artifacts: none

1. Add one shared generator that accepts the resolved VM name, address, OS selector, and workload role and writes the required Ansible host memberships.
2. Keep the maintained inventory as the host-free group relationship source so the existing group variables and playbook scopes continue to apply.
3. Route ordinary and consumer VM use, ioc-runner bake, EtherCAT bake, and EPICS-env build use through generated temporary host inventories.
4. Remove fixed host rows after every supported path has a generated equivalent.
5. Add local group-membership checks and run representative real VM and bake paths.
6. Align the maintained architecture and runbook with the delivered inventory model.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5.1 / T1 | Inventory contract | Generate inventory for every supported OS selector and representative standard, arbitrary, and run-specific node IDs, then inspect the merged Ansible graph | Repository checkouts with the real inventory generator and Ansible inventory parser | Every generated host appears once and belongs only to the groups required by its VM role |
| M5.1 / T2 | Runtime acceptance | Configure a fresh arbitrary-name ordinary VM, execute an EPICS-env build playbook, and complete one run-specific ioc-runner bake through their shipped entry points; retain actual EtherCAT bake and consumer acceptance in Backlog M2.1 | Supported Libvirt/KVM host | Each selected Ansible play targets the actual VM without a maintained fixed-name host row, and the run-specific bake completes and cleans its build VM |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M5.1 / T1 | 2026-08-13 | Code and inventory inspection | Not satisfied: `configure/CONFIG_SITE` defines eleven OS selectors and `create_vm.bash` accepts arbitrary node IDs, but `inventory/testbed.ini` contains only fixed host entries for a subset. | `configure/CONFIG_SITE`, `bin/create_vm.bash`, `ansible-provision/inventory/testbed.ini` |
| M5.1 / T2 | 2026-08-13 | Host `top`; real Rocky 8 ioc-runner bake | Not satisfied: Ansible rejected the valid run-specific build VM because its exact name was absent from the static inventory. | `make bake.rocky8`; run `20260813T195453Z-1dbbd75082f9` |
| M5.1 / T1 | 2026-08-15 | Local checkouts; real generator and Ansible inventory parser; filesystem, Libvirt, SSH, and Ansible command boundaries controlled only where named by each public-path check | Satisfied: all eleven OS selectors, ordinary and arbitrary names, both ioc-runner bake platforms, EtherCAT runtime and build roles, and EPICS-env core and matrix roles produced only their required direct groups. IOC hosts were reachable through both `ioc_nodes` and `all_nodes`; EPICS-env hosts were reachable through `epics_env_build`; fixed host rows were absent and rejected by the regression check. The runtime-inventory aggregate passed 65/65 plus EPICS-env 2/2, ansible-provision Make preflight passed 3/3, ioc-runner bake passed 83/83, and EtherCAT bake passed 10/10. | `make check-runtime-inventory`; `make check-bake-provenance`; `make check-bake-ethercat-workflow`; ansible-provision `make check-runtime-inventory-contract` |
| M5.1 / T2 | 2026-08-15 | Host `top`; real running VMs and shipped `create_vm.bash -s`, generator, and Ansible parser/playbook loader | Partially satisfied without changing VM contents: Rocky 8 and Debian 13 ioc-runner consumers passed domain, IP, SSH, and cloud-init readiness and each appeared as the sole target of all three `site.yml` plays through the generated inventory. The Debian 13 EPICS-env VM passed readiness and appeared as the sole `epics_env_build` target. The Rocky 8 EPICS-env VM had SSH ready but reported cloud-init `unknown`, so its public status path correctly returned nonzero. No ordinary VM play, run-specific bake, or configuration-changing play was executed in this observation. | `bin/create_vm.bash -s` piped to `bin/generate_ansible_inventory.bash --status-input`; `ansible-playbook --list-hosts` with `inventory/testbed.ini` and the generated source |
| M5.1 / T2 | 2026-08-15 02:35 PDT | Host `top`; real Libvirt/KVM; shipped VM, generator, Ansible, EPICS-env, and ioc-runner bake entry points | Satisfied for the owner-selected runtime scope. Fresh arbitrary-name VM `m51verify-debian13-m51accept` reached `READY`; generated inventory selected it for `playbooks/01_base.yml`, which completed `ok=10`, `changed=2`, `failed=0`, and cleanup left no matching domain, disk, seed ISO, or DHCP reservation. `run_epics_env_build.bash` generated the Debian 13 EPICS-env inventory and ran `playbooks/08_epics_env_build.yml` on only `testbed-epics-env-debian13-server`, completing `ok=2`, `changed=0`, `failed=0`. Rocky 8 ioc-runner bake `20260815T092848Z-e115d2581d28` completed all nine shipped steps; `site.yml` completed `ok=27`, `failed=0`, NFS simulation completed `ok=11`, `failed=0`, test users completed `ok=4`, `failed=0`, the real in-image provenance validator passed, the output image and both sidecars were published, `qemu-img check` found no errors, and the build VM and DHCP reservation were removed. Post-run checks passed inventory 65/65 plus 2/2, fresh-input 7/7, ioc-runner 83/83, EtherCAT inventory mapping 10/10, docs 51/51, and ansible-provision 3/3. Actual EtherCAT bake and consumer acceptance remains in Backlog M2.1. | `bin/create_vm.bash -F`; generated inventory with `playbooks/01_base.yml`; `bin/run_epics_env_build.bash -o epics-env-debian13`; `make bake.rocky8`; `iocrunner-rocky8-20260815T092848Z-e115d2581d28.qcow2` and sidecars; `make check-runtime-inventory check-bake check-docs`; ansible-provision `make check-runtime-inventory-contract` |

##### Closure Evidence

- Complete on 2026-08-16. Cloud-provision commit `c1f657b3d1d747b5e74cbb3857934585ab533d5c` is present on `origin/feature/image-workflow`; ansible-provision commit `50925d40c1470e8e4bc3cb7df8e157f8451a20bc` is present on `origin/master`; GitHub issue #31 has synchronized completion criteria and was observed closed at 2026-08-16T07:06:56Z.

##### GitHub Projection

Title: Replace fixed Ansible host inventory with VM-derived inventory
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-16; issue updated 2026-08-16T07:06:56Z

<a id="g1"></a>
#### G1 - Confirm whether the ioc-runner bake requires its own 120-second shutdown allowance

Origin: 579a8f3 / G1
GitHub Issue: none
Status: Complete

##### Summary

Confirm whether the ioc-runner bake requires a separate 120-second shutdown allowance. This external gate affects M3.2.

##### Affected Work

- M3.2

##### Completion Criteria

- The pre-change bake waited 24 x 5s while `do_stop` waited 12 x 5s.
- M3.1 provides the measured basis for the difference.
- The owner accepts the resulting shutdown policy.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-08-06 canonicalization evidence | Open; not rerun during reset | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |
| 2026-08-14 17:10 PDT | Rocky 8 and Debian 13 both reached `shut off` on the first 5-second public stop poll. The owner selected D4, which uses one twelve-poll, 5-second public stop path for ordinary provisioning and the ioc-runner bake. | M3.1 / T1 real Libvirt/KVM measurements; owner selection of option 1 |

##### Closure Evidence

- Complete by owner acceptance of D4 on 2026-08-14. The ioc-runner bake does not retain a separate 120-second shutdown allowance.

<a id="g2"></a>
#### G2 - Run downstream validation on the 2026-06-03 Rocky 8 golden image

Origin: 579a8f3 / G2
GitHub Issue: none
Status: Complete

##### Summary

The exact 2026-06-03 Rocky golden target was superseded by the run-specific image workflow accepted in issue #30. The owner retired this historical gate without claiming the downstream validation passed and moved the current-image check to `epics-ioc-runner` issue #146.

##### Affected Work

- M4.1

##### Completion Criteria

- D5 records owner-approved retirement of the obsolete exact target and the waived original checks.
- The independent current-image verification has an owning issue in `epics-ioc-runner`.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-08-06 canonicalization evidence | Open; not rerun during reset | Prior canonical state at commit `579a8f322c6ee3997c6e6ae2581b9a0477666ef0` |
| 2026-08-16 owner retirement | Complete by retirement; original downstream validation not run | D5; current-image verification moved to `epics-ioc-runner` issue #146 |

##### Closure Evidence

- Complete by owner-approved retirement on 2026-08-16. The exact historical target is no longer required, and no validation pass is claimed.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M2 Deferred EtherCAT acceptance | M2.1 | Validate EtherCAT use of the shared image workflow | Carry-forward | Deferred | No | D3 | Run the shipped EtherCAT bake and consumer on supported Libvirt/KVM, inspect the image, manifest, and creation-record pair, and confirm actual consumer selection; [M2.1 detail](#m21). |

### Backlog Details

<a id="m21"></a>
#### M2.1 - Validate EtherCAT use of the shared image workflow

Origin: 579a8f3 / M2.1
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
