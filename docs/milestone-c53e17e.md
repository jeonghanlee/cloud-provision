# Work Register

This document tracks unfinished work carried into the master reset generation
identified by prior-state commit `c53e17e`.

Release line: master
Milestone index: c53e17e
Canonical path: `docs/milestone-c53e17e.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: M2, M3, and M9 are Complete and issues #33, #34, and #36 are closed. M5, M6, M7, and M8 are assigned to the Milestone and Ready; M5 (package-parity guard against the P_common set) needs plan acceptance and implementation authority before editing. Keep M1.1 EtherCAT deferred in the Backlog and run no EtherCAT test or runtime action.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Proxy lifecycle | M2 | Remove every injected proxy artifact before publishing golden images | Milestone | Complete | No | D009-D017, M3, G2 | M3 completes the exact IOC proxy set, both real IOC producer-consumer gates pass, the separately authorized ioc-runner existing-artifact audit completes, and issue #34 is observed closed; [M2 detail](#m2). |
| Proxy lifecycle | M3 | Complete proxy injection for non-interactive Ansible and pip | Milestone | Complete | No | D009-D010, D013, D016, D018 | The shared contract owns the exact Debian 8, Ubuntu 8, and Rocky 7 final artifacts, local IOC-only verification passes, and two real IOC producer-consumer gates pass; [M3 detail](#m3). |
| Proxy lifecycle | G1 | Deliver the consumer behavior required by the two IOC real gates | External gate | Complete | No |  | Retired by D016 because issue #33 is now owned directly by M3; no delivery result is claimed; [G1 detail](#g1). |
| Proxy lifecycle | G2 | Authorize and complete the ioc-runner existing-artifact audit | External gate | Complete | No |  | A separate value-safe audit plan is accepted, authorized, and executed for M2 / T13; [G2 detail](#g2). |
| Image audit | M9 | Preserve the IOC runner existing-image audit as a tracked tool | Milestone | Complete | No | G2 | The tracked entry point, runbook, and real existing-image verification satisfy issue #36; [M9 detail](#m9). |
| Proxy ordering follow-up | M5 | Guard package-set parity between the retired cloud-init packages and post-apply install | Milestone | Not started | Yes | D018, D020 | A check fails when a former cloud-init `packages:` entry is not installed by post-apply provisioning; [M5 detail](#m5). |
| Proxy ordering follow-up | M6 | Document and guard the base-image locale assumption | Milestone | Not started | Yes | D018 | The runbook and ADR record that locale-gen depends on base-image locale support, and a guard catches its absence; [M6 detail](#m6). |
| Proxy ordering follow-up | M7 | Record the package-install ordering in the proxy ADR and runbook | Milestone | Not started | Yes | D018 | The proxy ADR and RUNBOOK_BAKE state packages install post-apply via Ansible, not cloud-init; [M7 detail](#m7). |
| Image and node model redesign | M8 | Redesign the image and node model around pipeline roles and retire the testbed concept | Milestone | Not started | Yes | D018, D019 | Replace the testbed concept with a role-based base, builder, golden-family, verify, bare, and source-build model grounded in the actual ansible-provision usage, absorbing the testbed-to-bare piece; [M8 detail](#m8). |

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D009 | One production contract owns the current profile, APT, DNF, and system Git proxy artifacts and renders the create-VM seed from the validated proxy URL. | 2026-08-20 |
| D010 | Both bake callers execute the same privileged terminal seal, whose complete preflight and value-free clean verification must pass before stop or publication. | 2026-08-20 |
| D011 | An independent value-free fixture and tests must exercise the shipped producer and both shipped bake callers with only outer command, SSH transport, and filesystem-root boundaries replaced. | 2026-08-20 |
| D012 | The accepted M2 implementation plan registers issue #34 only; issue #33 behavior and the existing-artifact audit remain external gates rather than implementation work in M2. | 2026-08-20 |
| D013 | Documentation states only verified scope. | 2026-08-20 |
| D014 | Reading, auditing, quarantining, replacing, or deleting an existing artifact requires a separate plan and authorization. | 2026-08-20 |
| D015 | EtherCAT real-bake verification and EtherCAT image audit are owned by Backlog M1.1 and issue #35 and do not block M2 or issue #34 closure. | 2026-08-20 |
| D016 | Issue #33 is assigned directly to M3. M2 depends on M3 instead of G1, while D012 remains the historical boundary of the accepted M2 implementation plan. | 2026-08-20 |
| D017 | Dedicated EtherCAT test surfaces are removed from the current graph without changing production EtherCAT behavior; this supersedes only the current EtherCAT test portion of D011, preserves its `47aeede` result as history, and assigns restoration and update from `733edf0beca51a59ca44782ec3958b00a8fc8bc3` to Backlog M1.1 after M3. | 2026-08-20 |
| D018 | Under proxy injection, `create_vm` removes the cloud-init `packages:` directive so packages install after the proxy apply through Ansible; the cloud-init package module runs in the config stage before the runcmd apply and cannot use the proxy. This supersedes the accepted M3 plan assumption that apply-before-Ansible was the only ordering constraint and preserves that plan acceptance as history. It also opens the testbed, package-parity, locale, and documentation follow-ups recorded in the Backlog. | 2026-08-21 |
| D019 | Backlog M4 (testbed-to-bare) is consolidated into Backlog M8 rather than executed separately. Both retire the server=1/node=2 concept and edit the same `create_vm` prefix and node handling, so a narrow M4 pass would rework the surface M8 rewrites. M8 absorbs the bare-node piece and its D018 dependency; the earlier decision to keep M4 at its own narrow scope is preserved as history. | 2026-08-22 |
| D020 | The M5 package-parity guard is keyed by base OS type, one expected-coverage list per OS template (debian13, rocky8, rocky10, ubuntu24, ubuntu26), owned inside cloud-provision rather than read from ansible-provision. Each list is the P_common set defined in `docs/IMAGE_WORKFLOW.md` (Operator definition): the packages that must be present on that base OS regardless of provisioning role. The guard compares the former cloud-init packages against that definition, not against what any single post-apply path installs today. Locale support is part of P_common (the `locales` package on the debian family), so the guard keeps the `locales` entry; M6 owns only the base-image locale assumption. The list is named by OS type only; naming it as the `bare` role belongs to M8. | 2026-08-22 |

### Assignment History

| Work Identity | From Section | To Section | Target Commit | Authority Moved At |
| --- | --- | --- | --- | --- |
| c53e17e / M5 | Backlog | Milestone | this synchronization commit | this synchronization commit |
| c53e17e / M6 | Backlog | Milestone | this synchronization commit | this synchronization commit |
| c53e17e / M7 | Backlog | Milestone | this synchronization commit | this synchronization commit |
| c53e17e / M8 | Backlog | Milestone | this synchronization commit | this synchronization commit |

### Milestone Details

<a id="m2"></a>
#### M2 - Remove every injected proxy artifact before publishing golden images

Origin: c53e17e / M2
Identity History: none
GitHub Issue: [#34](https://github.com/jeonghanlee/cloud-provision/issues/34)
Status: Complete

##### Summary

Commit `47aeede` established the original four-surface proxy contract and terminal seals. M3 now owns the issue #33 expansion to the exact IOC final set, while M2 remains responsible for the real IOC producer-consumer gates and the separately authorized existing-artifact audit.

##### Scope

- Add the shared current profile, APT, DNF, and system Git proxy artifact contract.
- Render that contract through the real `create_vm.bash` seed path.
- Execute the same terminal seal in both shipped bake callers before stop and publication.
- Add independent exact-set, shipped-path, failure-mutation, documentation, and deferred real-gate evidence.

Out of scope: implementing issue #33 inside the accepted M2 plan because M3 owns that work; Ansible repository changes; `-F`; existing-artifact inspection or remediation without G2; EtherCAT test execution, real-bake verification, and image audit tracked by M1.1 and issue #35.

##### Completion Criteria

- The producer, both bake callers, and the independent fixture agree on the exact current artifact set.
- Each bake validates and extracts its manifest, runs the shared seal as the last guest command, stops the exact VM, and publishes only its exact stopped disk.
- M2 / T1 through M2 / T10 pass through the specified local and review paths.
- M3 completes and M2 / T11 and M2 / T12 pass through supported Libvirt/KVM with exact producer-consumer record binding.
- G2 completes and M2 / T13 records the separately authorized value-safe ioc-runner audit result.

##### Dependencies And Decisions

- D009-D017
- D012 remains the historical boundary of the accepted M2 plan; D016 assigns issue #33 implementation to M3 without rewriting that plan.
- M3 and G2 are Complete; M2 / T11 through M2 / T13 pass through their real authorized paths.
- Issue #34 was reconciled and observed closed on 2026-08-22, satisfying the final M2 closure condition.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: `plan20260820_025428`, accepted 2026-08-20
Implementation Authorization: `auth20260820_075556`
Superseded Plan Artifacts: `plan20260820_005505`, `plan20260820_013544`, `plan20260820_023853`

1. Implement P001 through P010 from `plan20260820_025428` without expanding the approved boundary.
2. Run V001 through V010 and record only observed local results.
3. Obtain the required implementation cross-check before any commit request.
4. Keep V012, V013, and V015 pending until their named external gates and separate authority exist; V014 belongs to M1.1 and issue #35.

The accepted plan above remains historical. D016 and D017 do not add issue #33 or current EtherCAT test work to it; M3 has its own development plan and M1.1 owns future EtherCAT test restoration.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M2 / T1 | Syntax | Run V002 with `bash -n` on the shared contract, producer, both bakes, and four public tests | Local checkout | Every named Bash file parses |
| M2 / T2 | Static analysis | Run V003 with ShellCheck warning severity and inspect the full output | Local checkout | Exit 0 and no unreviewed warning |
| M2 / T3 | Producer contract | Run V004 with `make check-proxy-injection` | Local checkout; shipped producer with outer boundaries replaced | Debian, Ubuntu, and Rocky emit the exact applicable set; no-input and ambiguity paths remain correct |
| M2 / T4 | Joined lifecycle | Run the current `make check-proxy-lifecycle` | Local checkout; shipped producer and IOC bake caller | Full fixture and production tuples agree; applicable IOC inventory, dispatch, seal-call, and seed omissions fail before stop or publication |
| M2 / T5 | IOC bake | Run V006 with `make check-bake-provenance` | Local checkout; shipped IOC bake with outer boundaries replaced | Seal bytes execute as the last guest command and every failure blocks publication |
| M2 / T6 | Historical EtherCAT local gate | Preserve the observed result at commit `47aeede`; do not run an EtherCAT test in the current graph | Historical checkout only | The prior local result remains evidence for the code at `47aeede`, not current coverage |
| M2 / T7 | IOC-only offline aggregate | Run the current `make check-bake` only after its direct dependency graph contains fresh-input, IOC provenance, and IOC lifecycle leaves | Local checkout | Exactly the three IOC-only aggregate leaves pass; no EtherCAT test command runs |
| M2 / T8 | Documentation | Run V009 with `make check-docs` | Local checkout | ADR, architecture, runbook, and repository Markdown checks pass |
| M2 / T9 | Diff hygiene | Run V010 with `git diff --check` | Local checkout | Exit 0 |
| M2 / T10 | Implementation cross-check | A fresh Reviewer runs V002 through V010 and checks P001 through P010 | Final uncommitted implementation | No blocking finding before a commit request |
| M2 / T11 | Debian IOC real gate | Run V012 through the exact public Debian IOC bake and fresh consumer paths | Supported Libvirt/KVM after M3 | Consumer record source equals the just-published producer basename before clean verification |
| M2 / T12 | Rocky IOC real gate | Run V013 through the exact public Rocky IOC bake and fresh consumer paths | Supported Libvirt/KVM after M3 | Consumer record source equals the just-published producer basename before clean verification |
| M2 / T13 | Existing ioc-runner artifact audit | Run V015 only from its separate accepted and authorized value-safe plan | Separately authorized audit environment after G2 | Record the observed ioc-runner artifact result without exposing values |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M2 / T1 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; approved uncommitted implementation | Pass | V002 `bash -n` exited 0 for all eight named Bash files |
| M2 / T1 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` with the corrected uncommitted M3 implementation | Pass | M3 V001 `bash -n` exited 0 for all six named Bash files |
| M2 / T2 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; approved uncommitted implementation | Pass | V003 ShellCheck exited 0 with empty inspected output |
| M2 / T2 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` with the corrected uncommitted M3 implementation | Pass | M3 V002 `shellcheck -S warning` exited 0 with empty inspected output for all six named Bash files |
| M2 / T3 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped producer with outer boundaries replaced | Pass | V004 `make check-proxy-injection`: 63/63 passed, including full fixture-to-production tuple comparison for Debian, Ubuntu, and Rocky |
| M2 / T3 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; shipped producer and staged contract with outer boundaries replaced | Pass | M3 V003 `make check-proxy-injection`: 123/123 passed, including exact 8/8/7 tuples, fail-closed roots and commands, shared-file newline rejection, and 15 hostile-environment apply, rollback, and seal assertions |
| M2 / T4 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped producer and both shipped bake callers | Pass | V005 `make check-proxy-lifecycle`: 26/26 passed, including file/stdin operand rejection, three fixture tuple mutations, six applicable inventory omissions, dispatch and seal-call omissions, and seed-argument omission |
| M2 / T4 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; shipped producer and IOC bake caller with outer boundaries replaced | Pass | M3 V005 `make check-proxy-lifecycle`: 35/35 passed, including exactly 15 IOC inventory omissions and no EtherCAT test |
| M2 / T5 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5`; shipped IOC bake with outer boundaries replaced | Pass | V006 `make check-bake-provenance`: 86/86 passed |
| M2 / T5 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; shipped IOC bake with outer boundaries replaced | Pass | M3 V004 `make check-bake-provenance`: 107/107 passed, including Debian and Rocky seal, byte and metadata restoration, and misplaced Rocky sshd block rejection |
| M2 / T6 | 2026-08-20 09:52:08 PDT | Historical implementation delivered in `47aeede`; shipped EtherCAT bake with outer boundaries replaced | Pass | Historical V007 `make check-bake-ethercat-workflow`: 11/11 passed; D017 removes this command from the current graph |
| M2 / T7 | 2026-08-20 09:52:08 PDT | Historical implementation delivered in `47aeede`; former offline aggregate | Pass | Historical V008 included 7/7, 86/86, 11/11, and 26/26; its EtherCAT 11/11 portion is not current coverage |
| M2 / T7 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; current IOC-only aggregate after D017 | Pass | M3 V007 `make check-bake`: fresh-input 7/7, IOC provenance 107/107, and IOC lifecycle 35/35 passed; graph inspection found only the three IOC leaves and no direct EtherCAT test reference |
| M2 / T8 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5` | Pass | V009 `make check-docs`: 3/3 passed |
| M2 / T8 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` with updated durable documents | Pass | M3 V008 `make help.bake` exited 0 and `make check-docs` passed 3/3 |
| M2 / T9 | 2026-08-20 09:52:08 PDT | Local checkout at `2b746d5` | Pass | V010 `git diff --check` exited 0 |
| M2 / T9 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` with the corrected uncommitted M3 implementation | Pass | M3 V009 `git diff --check` exited 0; three selected production and generic EtherCAT files matched `733edf0`; five user-data template hashes remained unchanged |
| M2 / T10 | 2026-08-20 10:03:44 PDT | Fresh Reviewer `codex_gpt5_signal`; final uncommitted implementation in `hand20260820_095313` | Pass | V011 accepted with zero blocking findings and zero required decisions in `work/review_sessions/20260819_235119_proxy-lifecycle/reviews/fup20260820_100344_codex_gpt5_signal_on_hand20260820_095313.md` |
| M2 / T10 | 2026-08-20 18:32:23 PDT | Fresh implementation Reviewer on the corrected combined proxy lifecycle | Pass | M3 V010 resolved the root-environment finding and accepted P001-P010 with zero blocking findings and zero required decisions |
| M2 / T11 | 2026-08-22 16:29:38 PDT | Supported Libvirt/KVM host at `18a1667`; new Debian bake and fresh consumer | Pass | The exact public Debian IOC bake completed all 10 steps, terminal proxy seal and provenance validation passed, and `iocrunner-debian13-20260822T231755Z-610a9cd3f35f.qcow2` was published; its fresh consumer creation record selected that exact basename and reached READY before consumer cleanup |
| M2 / T12 | 2026-08-22 16:33:53 PDT | Supported Libvirt/KVM host at `18a1667`; new Rocky bake and fresh consumer | Pass | The exact public Rocky IOC bake completed all 10 steps, terminal proxy seal and provenance validation passed, and `iocrunner-rocky8-20260822T232958Z-6ee4986b0420.qcow2` was published; its fresh consumer creation record selected that exact basename and reached READY before consumer cleanup |
| M2 / T13 | 2026-08-22 18:16 PDT | Supported Libvirt/KVM host; read-only libguestfs 1.54.1 against the approved image directory | Pass | The accepted `plan20260822_g2_guestfish_audit` checked five image/manifest pairs: qcow2 metadata and integrity passed, one guest root was inspected per image, and the guestfish-backed contract check returned clean for Debian 2 and Rocky 3; no host mount or NBD connection remained, no guest command ran, and no proxy value or guest file content was emitted |

##### Closure Evidence

- Fresh M3 implementation review on 2026-08-20 resolved the fixed-PATH and restrictive-umask finding after the real hostile-environment apply, rollback, and seal regression passed; the corrected combined proxy lifecycle has zero blocking findings and zero required decisions.
- Fresh review `fup20260820_100344` accepted the F007-F009 corrections with zero blocking findings and zero required decisions; local V002-V010 and M2 / T10 now pass.
- Prior reviews remain historical evidence: `fup20260820_093345` failed on F007-F009, `fup20260820_085945` accepted the preceding correction, and `fup20260820_083901` recorded the earlier failed cross-check.
- D015 moved EtherCAT real-bake verification and EtherCAT image audit to Backlog M1.1 and issue #35 on 2026-08-20 without removing the shared contract or local shipped-path coverage delivered in 47aeede.
- D016 replaced G1 with M3 on 2026-08-20 without claiming that issue #33 had been delivered.
- D017 preserved the local EtherCAT results only as historical evidence at `47aeede` and assigned future test restoration to M1.1.
- G2 completed on 2026-08-22 under `plan20260822_g2_guestfish_audit`; M2 / T13 passed for five existing IOC runner images without remediation or value exposure.
- Issue #34 body was reconciled to the completed criteria, the final result comment was recorded, and the issue was observed closed at 2026-08-22 21:47 PDT.

##### GitHub Projection

Title: Remove every injected proxy artifact before publishing golden images
Labels: bug
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: bug
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-22 21:47 PDT; remote issue observed closed
Projection State: reconciled; completed body, close comment, and closed state observed

<a id="m3"></a>
#### M3 - Complete proxy injection for non-interactive Ansible and pip

Origin: c53e17e / M3
Identity History: none
GitHub Issue: [#33](https://github.com/jeonghanlee/cloud-provision/issues/33)
Status: Complete

##### Summary

The shipped VM seed does not yet place every proxy artifact needed by non-interactive Ansible, sudo, SSH, pip, and system tools under the shared apply-and-seal lifecycle. M3 extends one production contract to the exact Debian 8, Ubuntu 8, and Rocky 7 final sets, verifies both supported IOC families through public shipped paths, and removes dedicated EtherCAT tests from the current graph without changing production EtherCAT behavior.

##### Scope

- Make `/etc/os-release` parsing and test-root command selection fail closed without falling back to host guest commands.
- Extend the shared inventory, renderer, apply mode, seal mode, and remnant verifier to the exact 8/8/7 final artifact set and required ownership and modes.
- Keep the existing OS user-data templates unchanged and perform one controlled structural merge after SSH-key substitution.
- Require exactly one top-level `write_files` and one top-level `runcmd`, stage the byte-identical contract and validated input, and run privileged apply before Ansible while preserving locale commands.
- Exercise the real shipped producer and IOC bake caller with only outer command, SSH transport, network, image, and filesystem boundaries replaced.
- Run two normal IOC seal cases and exactly 15 one-at-a-time public IOC inventory omissions: eight Debian and seven Rocky.
- Remove only the dedicated EtherCAT test file and its direct Make, lifecycle, and runbook references; retain production and generic EtherCAT surfaces unchanged.
- Update the proxy lifecycle ADR, canonical milestone evidence, and complete issue projections after repository verification.

Out of scope: changes to `ansible-provision`; production EtherCAT behavior; generic EtherCAT selector or inventory tests; any EtherCAT test command, real bake, or image audit; reading or changing existing images; proxy values; unrelated cleanup or wording; commits and pushes; GitHub mutation under repository implementation authority.

##### Completion Criteria

- The shipped contract accepts a regular `/etc/os-release` or safe relative link inside the selected root and rejects every named invalid identity or root case with nonzero status.
- The production inventory and independent fixture agree on exactly 8 Debian rows, 8 Ubuntu rows, and 7 Rocky rows, including path, owner, group, mode, ownership form, marker, cleanup, and remnant rules.
- Apply completes full-set preflight, candidate rendering, sudo and effective sshd validation, fixed-order installation, and sshd reload; seal completes cleanup preflight, reverse removal, transient cleanup, value-free remnant verification, and the supported cloud-init clean operation.
- Generated user-data has one structural `write_files`, one structural `runcmd`, byte-identical staged contract content, validated input, preserved locale commands, and apply before Ansible.
- Local shipped-path checks pass for the producer, IOC bake, two normal IOC seal cases, and exactly 15 public IOC inventory omissions without executing EtherCAT tests.
- The dedicated EtherCAT test surfaces are absent, their restoration record is in M1.1, and the selected production and generic EtherCAT files remain unchanged from `733edf0beca51a59ca44782ec3958b00a8fc8bc3`.
- A fresh implementation cross-check reports no blocking finding.
- One real Debian IOC bake and fresh consumer and one real Rocky IOC bake and fresh consumer pass on supported Libvirt/KVM through cloud-init, non-interactive SSH, sudo, Ansible, pip, package manager, system Git, terminal seal, publication, and exact pair selection.
- Issue #33 is reconciled from this canonical detail and observed closed, or Closure Evidence records an explicit dated exception.

##### Dependencies And Decisions

- D009-D010, D013, D016
- D017 controls the EtherCAT test boundary but is not an execution dependency for M3.
- M3 and G2 are independent.
- Repository implementation is authorized by `auth20260820_165043` for accepted plan `plan20260820_163327`.
- GitHub issue mutation requires separate Issue delegation after complete drafts and a fresh metadata preflight.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: `plan20260820_163327`, accepted 2026-08-20
Implementation Authorization: `auth20260820_165043`
Superseded Plan Artifacts: none

1. P001 accepts the named M3 plan in this register and changes M3 to In progress at the first authorized repository edit.
2. P002 corrects fail-closed OS identity parsing and test-root guest-command isolation.
3. P003 implements the exact shared inventory, render, apply, seal, metadata, and transient-file contract.
4. P004 performs the controlled generated user-data merge while leaving all OS templates unchanged.
5. P005 expands the independent fixture and public producer coverage.
6. P006 parameterizes the public IOC bake harness and adds two normal and exactly 15 omission cases through real shipped code.
7. P007 removes only the dedicated EtherCAT test surfaces and preserves the restoration baseline in M1.1.
8. P008 promotes D001-D004 and D008 into the proxy lifecycle ADR and updates applicable runbook and index text.
9. P009 runs local IOC-only verification, records only observed results, and prepares full canonical projections and local issue drafts for #33, #34, and #35.
10. P010 obtains a fresh implementation cross-check and writes the execution handoff; commits and GitHub edits remain separately authorized actions.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M3 / T1 | Syntax | Run V001 with `bash -n` on every modified Bash file | Local checkout | Every named Bash file parses |
| M3 / T2 | Static analysis | Run V002 with `shellcheck -S warning` on every modified Bash file and inspect the complete output | Local checkout | Exit 0 and no unreviewed warning |
| M3 / T3 | Producer and contract | Run V003 with `make check-proxy-injection` | Local checkout; real shipped producer and contract with outer boundaries replaced | Parser and root failures return nonzero; Debian, Ubuntu, and Rocky generated user-data and exact artifact sets pass |
| M3 / T4 | IOC bake | Run V004 with `make check-bake-provenance` | Local checkout; real copied IOC bake and streamed contract with outer boundaries replaced | Debian and Rocky normal seal paths block every failure before conversion or publication |
| M3 / T5 | IOC lifecycle omissions | Run V005 with `make check-proxy-lifecycle` | Local checkout; real producer, IOC bake, and contract | Fixture tuples agree and exactly 15 one-at-a-time omissions fail with identity, no seal completion, and zero conversion or publication |
| M3 / T6 | Fresh input guards | Run V006 with `make check-bake-fresh-inputs` | Local checkout | Existing fresh-input guards remain correct |
| M3 / T7 | IOC-only aggregate | Confirm the direct graph has exactly fresh-input, IOC provenance, and IOC lifecycle leaves, then run V007 with `make check-bake` | Local checkout | Every IOC-only leaf passes and no EtherCAT test command runs |
| M3 / T8 | Documentation | Run V008 with `make help.bake` and `make check-docs` | Local checkout | Help and durable documentation describe the current IOC-only test graph and deferred EtherCAT tests |
| M3 / T9 | Diff and preservation | Run V009 with `git diff --check`, compare selected production and generic EtherCAT files with `733edf0`, and inspect the narrow allowed diffs in `configure/RULES_BAKE` and `bin/create_vm.bash` | Local checkout | No whitespace error, production EtherCAT behavior is unchanged, and only the accepted direct test surfaces differ |
| M3 / T10 | Implementation cross-check | A fresh Reviewer checks P001-P010 and reruns V001-V009 through the real shipped paths | Final uncommitted implementation | No blocking finding before a commit request |
| M3 / T11 | Issue projection preflight | Run V011 after local verification: derive complete #33, #34, and #35 drafts from their canonical details, compare live metadata read-only, and audit every issue reference | Local checkout and GitHub read-only access | Drafts are self-contained, metadata is verified, real gates remain pending, and no GitHub mutation occurs |
| M3 / T12 | Debian IOC real gate | Run V012 through the exact public Debian IOC bake and fresh consumer paths | Supported Libvirt/KVM | The no-direct-route flow completes and the consumer selects the exact just-published pair |
| M3 / T13 | Rocky IOC real gate | Run V013 through the exact public Rocky IOC bake and fresh consumer paths | Supported Libvirt/KVM | The no-direct-route flow completes and the consumer selects the exact just-published pair |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M3 / T1 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` with the corrected uncommitted implementation | Pass | V001 `bash -n` exited 0 for all six named Bash files |
| M3 / T2 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` with the corrected uncommitted implementation | Pass | V002 `shellcheck -S warning` exited 0 with empty inspected output for all six named Bash files |
| M3 / T3 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; real shipped producer and staged contract with outer boundaries replaced | Pass | V003 `make check-proxy-injection`: 123/123 passed, including exact 8/8/7 tuples, structural merge, fail-closed roots and commands, shared-file newline rejection, and 15 hostile-environment apply, rollback, and seal assertions |
| M3 / T4 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; real shipped IOC bake and streamed contract with outer boundaries replaced | Pass | V004 `make check-bake-provenance`: 107/107 passed, including normal Debian and Rocky seal, exact shared-file restoration, and misplaced Rocky sshd block rejection before publication |
| M3 / T5 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; real producer, IOC bake, contract, and independent fixture | Pass | V005 `make check-proxy-lifecycle`: 35/35 passed; exactly 15 IOC inventory omissions failed before seal completion and publication; no EtherCAT test ran |
| M3 / T6 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0` | Pass | V006 `make check-bake-fresh-inputs`: 7/7 passed |
| M3 / T7 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; IOC-only aggregate | Pass | V007 dependency inspection found only fresh-input, IOC provenance, and IOC lifecycle leaves; `make check-bake` passed 7/7, 107/107, and 35/35 without an EtherCAT test command |
| M3 / T8 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; updated ADR and runbook | Pass | V008 `make help.bake` exited 0 and `make check-docs` passed 3/3 |
| M3 / T9 | 2026-08-20 18:32:23 PDT | Local checkout at `733edf0`; production EtherCAT preservation boundary | Pass | V009 `git diff --check` exited 0; `bin/bake_ethercat_image.bash` and two generic tests matched `733edf0`; five user-data template hashes matched their baselines; the narrow diff contained only the accepted shared merge and direct test removal |
| M3 / T10 | 2026-08-20 18:32:23 PDT | Fresh Reviewer on the corrected final uncommitted implementation | Pass | V010 resolved the root-environment finding and accepted P001-P010 with zero blocking findings and zero required decisions |
| M3 / T11 | 2026-08-20 18:39:18 PDT | Local checkout and GitHub read-only access | Pass | V011 produced self-contained #33, #34, and #35 bodies, verified open state, `bug`, milestone 1, and assignee `jeonghanlee`, and found only the planned #35 title difference |
| M3 / T12 | 2026-08-21 | Supported Libvirt/KVM | Pass | V012 Debian real gate passed after the R1 fix (create_vm drops the cloud-init `packages:` directive when the proxy is injected, so packages install post-apply through the applied proxy): the bake completed all 10 steps and published `iocrunner-debian13-20260821T085423Z-d97faafeb045`, and a fresh `debian13-iocrunner.server` consumer reached READY selecting that exact pair |
| M3 / T13 | 2026-08-21 | Supported Libvirt/KVM | Pass | V013 Rocky real gate passed under the same R1 fix (dnf packages install post-apply via Ansible over the proxy): the bake completed all 10 steps and published `iocrunner-rocky8-20260821T155443Z-9b788064edba`, and a fresh `rocky8-iocrunner.server` consumer reached READY selecting that exact pair |

##### Closure Evidence

- Local V001-V011 pass. V012 first failed on supported Libvirt/KVM because the cloud-init `packages:` module installs before the runcmd proxy apply, so the golden bake could not fetch packages in the no-direct-route topology. The R1 fix makes `create_vm` drop the `packages:` directive whenever the proxy is injected, deferring package installation to post-apply Ansible over the applied proxy. Both real gates then passed end-to-end: V012 (Debian) and V013 (Rocky) each baked through all 10 steps, published the golden pair, and had a fresh consumer select that exact pair. The fix and test landed in commit `fbd9fb3`; the milestone record landed in `bbee888`. Issue #33 was observed closed on 2026-08-21, satisfying the last completion criterion, so M3 is Complete.

##### GitHub Projection

Title: Complete proxy injection for non-interactive Ansible and pip
Labels: bug
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: bug
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-21; issue closed with the completion comment
Projection State: reconciled; issue #33 observed closed on 2026-08-21

<a id="g1"></a>
#### G1 - Deliver the consumer behavior required by the two IOC real gates

Origin: c53e17e / G1
GitHub Issue: none
Status: Complete

##### Summary

D016 retires this external-gate identity because issue #33 is now registered directly as M3. The original delivery condition did not run, and this retirement makes no claim that the consumer behavior exists.

##### Completion Criteria

- D016 registers issue #33 as M3 and replaces the M2 dependency on G1 with a dependency on M3.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-08-20 | Complete | Retired by D016; the original delivery and verification condition did not run |

##### Closure Evidence

- 2026-08-20: D016 registered issue #33 as M3 and retired G1. The original condition did not run, and no delivery or verification result is claimed.

<a id="g2"></a>
#### G2 - Authorize and complete the ioc-runner existing-artifact audit

Origin: c53e17e / G2
GitHub Issue: none
Status: Complete

##### Summary

The separately planned and authorized value-safe audit determined the state of the existing ioc-runner artifacts. All five selected images passed, and no remediation was authorized or performed.

##### Scope

Audit existing published `iocrunner-*.qcow2` artifacts and matching `.manifest` sidecars under the approved image directory using read-only metadata checks, read-only libguestfs root inspection, and a guestfish-backed verifier pinned to the shipped proxy contract inventory and marker/key rules.

Out of scope: new bakes; EtherCAT artifacts; guest execution; proxy values or guest file contents; remediation, quarantine, deletion, replacement, and credential rotation.

##### Completion Criteria

- The named value-safe audit plan is accepted and separately authorized.
- Every selected existing ioc-runner artifact passes the read-only metadata, guest-root inspection, and value-free proxy-clean checks.
- Audit resources are removed, no host mount or NBD connection remains, no guest command runs, and the observed aggregate is recorded as M2 / T13 without exposing values.

##### Dependencies And Decisions

- D014 requires a separate plan and authorization for existing-artifact inspection or remediation.
- This audit uses a read-only libguestfs inspection path and does not authorize remediation.

##### Implementation Plan

Plan ID: `plan20260822_g2_guestfish_audit`
Plan Status: accepted
Plan Acceptance: owner selected the guestfish method in chat on 2026-08-22
Implementation Authorization: owner direction and approval in chat on 2026-08-22
Superseded Plan Artifacts: `work/plan-g2-iocrunner-audit.md`, plan20260822_171920_g2_iocrunner_audit

1. Enumerate regular, non-symlink `iocrunner-*.qcow2` files and require one matching `.manifest` sidecar per image.
2. Run read-only `qemu-img info` and `qemu-img check`; reject backing files, malformed metadata, or nonzero check errors.
3. Open one image at a time through the read-only libguestfs appliance and let `guestfish` inspect the guest root without a host `mount` or NBD connection.
4. Run a guestfish-backed value-safe proxy-clean verifier over the shipped contract inventory, retaining only exit status and the value-free result line.
5. Close the libguestfs appliance, remove temporary state, and verify no host mount, NBD connection, or audit residue remains.
6. Record the aggregate by OS and artifact count as M2 / T13 without emitting filenames, proxy values, or guest file contents.

##### Test Plan

| Label | Layer | Method | Expected Result |
| --- | --- | --- | --- |
| M2 / T13-a | Inventory | Enumerate existing IOC runner qcow2 and manifest pairs from the approved directory | Every selected qcow2 has one matching regular sidecar |
| M2 / T13-b | Image metadata | Run read-only `qemu-img info` and `qemu-img check` for each selected image | No backing file and zero check errors |
| M2 / T13-c | Guest root and proxy state | Inspect one guest root through read-only libguestfs and run the guestfish-backed proxy-clean verifier | One inspected root per image and `clean=true` for every image |
| M2 / T13-d | Resource cleanup | Close libguestfs, remove temporary state, and recheck host state | No host mount, NBD connection, or audit residue remains |

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-08-22 18:16 PDT | Pass | `plan20260822_g2_guestfish_audit` completed for five image/manifest pairs: Debian 2 and Rocky 3 passed qcow2 metadata and integrity, single-root inspection, value-safe proxy-clean verification, and residue checks without host mount, NBD, guest command execution, remediation, or value exposure |

##### Closure Evidence

- 2026-08-22: The accepted and authorized guestfish audit completed with `images=5 debian=2 rocky=3 passed=5 failed=0 residue=clean`.
- M9 and issue #36 preserve the verifier at `bin/audit_iocrunner_images.bash`; M9 / T4 owns verification through that tracked entry point and does not replace the historical G2 result.

<a id="m9"></a>
#### M9 - Preserve the IOC runner existing-image audit as a tracked tool

Origin: c53e17e / M9
Identity History: none
GitHub Issue: [#36](https://github.com/jeonghanlee/cloud-provision/issues/36)
Status: Complete

##### Summary

The successful existing-image audit currently depends on an ignored work script. Preserve its read-only guestfish path as a tracked cloud-provision operator tool so the audit can be repeated without reconstructing the code.

##### Scope

- Add `bin/audit_iocrunner_images.bash` as the supported entry point.
- Resolve the repository root from the installed script path instead of a workstation-specific checkout path.
- Accept `-d <image_dir>` with `/data/libvirt/images` as the default.
- Retain read-only qcow2 metadata checks, guestfish root inspection, and the value-free proxy artifact checks pinned to the shipped proxy contract.
- Document privileges, required commands and packages, usage, output, and failure behavior in `docs/RUNBOOK_BAKE.md`.
- Update the G2 record to reference the tracked entry point.

Out of scope: proxy remediation, quarantine, deletion, replacement, or credential rotation; EtherCAT images; arbitrary qcow2 images outside the supported IOC runner Debian 13 and Rocky 8 naming contract; changes to proxy apply or seal behavior; printing proxy values, guest file contents, or per-image identifiers.

##### Completion Criteria

- The tracked script contains no workstation-specific checkout path.
- `-h` documents the interface and `-d` selects an absolute image directory.
- Every image is opened read-only without a host mount, NBD attachment, or guest command execution.
- Contract drift, unsupported image names, missing, symbolic-link, or empty sidecars, image corruption, ambiguous roots, proxy artifacts, and cleanup failures stop the audit.
- Output remains limited to value-free failure stages and aggregate counts.
- The runbook names the required packages and provides copy-safe commands.
- M9 / T1 through M9 / T4 pass through the tracked entry point and documented path.

##### Dependencies And Decisions

- G2 is Complete and its 2026-08-22 read-only result establishes the behavior to preserve, but it does not verify the new tracked entry point.
- This work is related to issue #34 and does not expand its proxy lifecycle contract.
- Issue #36 was created with label `enhancement`, milestone `Nimbus - Cloud Provisioning Reliability`, and assignee `jeonghanlee` before implementation began.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner approved the `bin/` and `docs/RUNBOOK_BAKE.md` locations on 2026-08-22
Implementation Authorization: owner directed issue-first implementation on 2026-08-22
Superseded Plan Artifacts: none

1. Promote the accepted guestfish audit into `bin/` and replace only the workstation-specific configuration with the documented command interface.
2. Add runbook instructions and package requirements.
3. Update the G2 path and issue #36 projection metadata.
4. Run all planned checks and record only observed results.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M9 / T1 | Syntax and static analysis | Run `bash -n` and `shellcheck -S warning` on the tracked script | Local checkout | Exit 0 with no unreviewed warning |
| M9 / T2 | Command interface | Run the shipped help and invalid-argument paths | Local checkout | Help is complete and invalid input fails before image access |
| M9 / T3 | Documentation | Run `make check-docs` and `git diff --check` | Local checkout | Documentation checks pass and no whitespace error is present |
| M9 / T4 | Existing images | Run the tracked script with root privileges against the approved image directory | Supported Libvirt/KVM host | Every selected IOC runner image and manifest pair passes with `residue=clean` |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M9 / T1 | 2026-08-22 19:24 PDT | Local checkout; tracked `bin/audit_iocrunner_images.bash` | Pass | `bash -n` and `shellcheck -S warning` each exited 0; ShellCheck output was empty |
| M9 / T2 | 2026-08-22 19:24 PDT | Local checkout; tracked command interface | Pass | `-h` exited 0 with the documented default and options; unknown option, missing `-d` value, and extra argument each exited 1 with `stage=usage` before image access |
| M9 / T3 | 2026-08-22 19:24 PDT | Local checkout; tracked runbook and canonical record | Pass | `make check-docs` passed 3/3 and `git diff --check` exited 0 |
| M9 / T4 | 2026-08-22 PDT | Supported Libvirt/KVM host; tracked `bin/audit_iocrunner_images.bash` at `ad2d7a9` with root privileges against the approved image directory | Pass | All five selected images passed (`debian=2`, `rocky=3`, `failed=0`) and cleanup reported `residue=clean`; recorded in the issue #36 closing comment |

##### Closure Evidence

- The tracked script, runbook, and canonical projection are implemented in `ad2d7a9`.
- M9 / T1 through M9 / T4 pass; T4 ran the tracked entry point against the real image directory.
- Issue #36 was observed closed on 2026-08-23 05:09:36 UTC after every completion criterion was satisfied.

##### GitHub Projection

Title: Preserve the IOC runner image audit as a tracked tool
Labels: enhancement
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-22 22:15:49 PDT; remote closed 2026-08-23 05:09:36 UTC
Projection State: reconciled; remote closed with the M9 / T4 result in its closing comment

<a id="m5"></a>
#### M5 - Guard package-set parity between the retired cloud-init packages and post-apply install

Origin: c53e17e / M5
Identity History: none
GitHub Issue: none
Status: Not started

##### Summary

D018 moved package installation from the cloud-init `packages:` module to post-apply Ansible. The two lists must stay equivalent or a package silently disappears from the golden image. Add a guard that keeps them in agreement.

##### Scope

- Enumerate the packages each of the five OS templates (`templates/user-data.<os>`) installs through cloud-init `packages:`, including `locales`.
- Keep one expected-coverage list per base OS type inside this repository, seeded from the P_common set in `docs/IMAGE_WORKFLOW.md` (Operator definition), with package names spelled per OS (D020).
- Fail a check when a former cloud-init package is absent from its OS list, naming the missing package.
- Run the check in the offline test graph.

Out of scope: changing the package sets themselves; proxy contract behavior; the base-image locale assumption (M6); naming the list as the `bare` role (M8); closing any coverage gap the check reveals, which is decided from the observed T4 result.

##### Completion Criteria

- A check fails when a former cloud-init `packages:` entry is not installed by post-apply provisioning.
- The check runs in the offline test graph.
- The check reads the shipped templates through the real shipped check path; the divergence test drives the same check through fixture templates, never a modified shipped template.

##### Dependencies And Decisions

- D018 and D020
- Coupling to M8: the lists are keyed by the current `create_vm` OS types and the post-apply paths are today's inventory roles (`generate_ansible_inventory.bash`). When M8 renames OS types or roles, the list keys are re-pointed; the guard itself is not redesigned.
- Post-apply paths per OS today: `rocky8` and `debian13` through `base_os` (`pkg_base` + `pkg_standard`) for ioc-node, nfs-sim-node, and ioc-runner-build; `debian13` additionally through the ethercat roles; all five through `epics_env_build` plus the `pkg_automation` per-OS package file.
- No single post-apply path installs the whole P_common set (the intersection across paths is only git and autoconf), so the list is seeded from the P_common definition, not from the paths.
- Open planning finding: with the list seeded from the definition, every shipped template entry is already in its list, so T4 passes and the guard verifies only that templates stay within the P_common definition; it does not detect a package that ansible-provision fails to install. Whether M5 keeps that narrower purpose or compares against the actual ansible-provision install set is decided after M8 puts P_common in place. M8 runs first.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Add `tests/fixtures/expected-post-apply-packages/<os>.txt` for the five OS types, seeded from the P_common set in `docs/IMAGE_WORKFLOW.md` (Operator definition). Names are identical across families except the two in the definition's family table (ssl-dev, g++); the rocky lists omit the locale items, which the definition assigns to the debian family only.
2. Add `tests/check-package-parity.bash`: extract the `packages:` block of each template and fail naming any entry absent from that OS list. The check runs one direction only: every template entry must be in the list; the list may hold more. Accept the template directory and list directory as arguments so fixtures can drive the real check.
3. Add `check-package-parity` to `configure/RULES_BAKE` (`.PHONY`, help line) and to the `check-bake` aggregate.
4. Run T1 through T4 and record observed results; present any revealed coverage gap as a decision, not as a silent list edit.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M5 / T1 | Syntax and static analysis | Run `bash -n` and `shellcheck -S warning` on the new check | Local checkout | Exit 0 and no unreviewed warning |
| M5 / T2 | Covered fixture | Drive the shipped check with a fixture template whose packages all appear in its list | Local checkout; real check, fixture input | Exit 0 |
| M5 / T3 | Divergence fixture | Drive the shipped check with a fixture template carrying a package absent from its list | Local checkout; real check, fixture input | Nonzero exit naming that package |
| M5 / T4 | Shipped templates | Run `make check-package-parity` against the five shipped templates and lists | Local checkout | Every template entry is in its OS list; the exact missing packages per OS otherwise |

##### Verification Results

None observed.

##### Closure Evidence

None.

<a id="m6"></a>
#### M6 - Document and guard the base-image locale assumption

Origin: c53e17e / M6
Identity History: none
GitHub Issue: none
Status: Not started

##### Summary

Under proxy injection the `packages:` strip means the runcmd locale commands rely on the base image already shipping locale support (Debian ships `locales`; Rocky ships glibc langpacks). This assumption is now load-bearing and undocumented, and breaks silently if a base image drops it.

##### Scope

- Document in the runbook and ADR that locale generation depends on base-image locale support.
- Add a guard that catches a base image missing the required locale support.

Out of scope: changing locale selection; proxy contract behavior.

##### Completion Criteria

- The runbook and ADR record the base-image locale dependency.
- A guard fails when the base image lacks the required locale support.

##### Dependencies And Decisions

- D018

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

##### Test Plan

To be defined at planning.

##### Verification Results

None observed.

##### Closure Evidence

None.

<a id="m7"></a>
#### M7 - Record the package-install ordering in the proxy ADR and runbook

Origin: c53e17e / M7
Identity History: none
GitHub Issue: none
Status: Not started

##### Summary

D018 changed how packages reach the golden image. The durable proxy ADR and RUNBOOK_BAKE should state the ordering rationale so the design is not re-derived from the code.

##### Scope

- Record in the proxy ADR and RUNBOOK_BAKE that under proxy injection packages install after the proxy apply through Ansible, not through the cloud-init package module; without proxy injection the cloud-init baseline installs them at first boot (the hand-off subset defined in `docs/IMAGE_WORKFLOW.md`, Operator definition).
- State the reason: the cloud-init package module runs before the runcmd apply and cannot use the proxy.

Out of scope: proxy contract behavior; changing the install mechanism.

##### Completion Criteria

- The proxy ADR and RUNBOOK_BAKE describe the post-apply package-install ordering and its reason.
- The text references D018.

##### Dependencies And Decisions

- D018

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

##### Test Plan

To be defined at planning.

##### Verification Results

None observed.

##### Closure Evidence

None.

<a id="m8"></a>
#### M8 - Redesign the image and node model around pipeline roles and retire the testbed concept

Origin: c53e17e / M8
Identity History: none
GitHub Issue: none; ansible-provision side tracked by [jeonghanlee/ansible-provision#17](https://github.com/jeonghanlee/ansible-provision/issues/17)
Status: Not started

##### Summary

The testbed concept conflates three things: the NAT environment name, the default VM prefix, and the plain base-node role. The `debian13`/`rocky8` node is really the shared start of three uses: a builder that bakes a golden image, an un-provisioned node in the lab, and a standalone provisioning target. Redesign the image and node model around explicit pipeline roles, grounded in the actual ansible-provision usage and standard golden-image practice.

Under D018 the proxy-injection merge drops the cloud-init `packages:` directive for every VM, so a plain `testbed` VM that runs no post-apply Ansible now installs no packages. The absorbed bare-node piece (D019) makes the `bare` species a package-minimal base image any test can boot and retires the server=1/node=2 concept as part of this redesign.

##### Scope

- Retire the testbed concept and the server=1/node=2 cluster numbering.
- Implement the image model defined in `docs/IMAGE_WORKFLOW.md` (Operator definition): vacua, operators, and species, with `bare` as the common ancestor species.
- Decide the two concepts that document does not define because they belong to image life, not to species: builder (the ephemeral bake VM) and verify (the fresh-boot consumer); and settle the golden flavor and latest-pointer convention recorded in that document's Open decisions.
- Reflect the model in `create_vm` OS types, prefixes, the runbooks, and the operator definition in `docs/IMAGE_WORKFLOW.md`; the ADR set in `docs/decisions/` stays as it is.
- Decide a name for the NAT environment that currently reads testbed, coordinated with the ansible-provision trust-posture wording.

Out of scope: implementing before an accepted plan and authority; proxy contract behavior.

##### Completion Criteria

- The species in `docs/IMAGE_WORKFLOW.md` are buildable on every vacuum the definition assigns them, and the builder and verify concepts are documented.
- `create_vm` and the durable documentation reflect the model and the testbed term is retired.
- The golden flavor and latest-pointer convention is defined.
- The `bare` species boots as a package-minimal base image with no test-specific assumptions, and no test depends on the retired server=1/node=2 concept.

##### Dependencies And Decisions

- D018 and D019
- The ansible-provision changes (P_common role, vacuum-wide inventory groups, one owner for the EPICS development package list) are part of this work unit and are tracked here; jeonghanlee/ansible-provision#17 is the pointer on that repository.
- Absorbs the former Backlog M4 testbed-to-bare piece (D019); its bare node is defined here as one species of the surrounding model.
- Informed by standard golden-image pipeline practice (builder, golden, and fresh-boot consumer stages; image families; bake heavy and stable, keep cloud-init light) and the ansible-provision usage map.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

Both repositories work on the `m8-operator-model` branch and merge to master when M8 closes. The ansible-provision side is rewritten from the operator definition; existing ansible code is not preserved. The rewrite is total: one role per operator named as the definition's Role column, one playbook per operator under `playbooks/operators/`, one assembly per species under `playbooks/species/`, and the numbered playbooks, `site.yml`, `base_os`, and `pkg_standard` retire. Every variable in today's `group_vars/all.yml` moves to the `defaults/` of the operator role that consumes it; only values consumed by more than one operator (for example `epics_ioc_engineers`) stay in `group_vars/all.yml`, and the existing site-override precedence is unchanged. Every numbered step closes with a third-person review before the next; steps 8 and 9 and every operator-definition edit add a second-person pass; a joint two-repository review precedes the merges.

1. ansible-provision: write `roles/common` new, implementing P_common exactly as the operator definition states it: the package halves with the per-family names, the debian-family locale items, and the configuration content (chrony, sudoers includedir, rocky EPEL/PowerTools and `secure_path`). The package list is authored in the role with the pkg_automation per-OS lists as the reference baseline, not read from that repository.
2. ansible-provision: rebuild the inventory as five vacuum groups (`debian13`, `rocky8`, `rocky10`, `ubuntu24`, `ubuntu26`) under a `vacua` parent plus the species groups in underscore form (`iocrunner`, `iocrunner_nfs`, `epics_dev`, `nfs_sim`, `rtbase`, `ethercat`), with `group_vars` for the three new vacua; the inventory file renames from `testbed.ini` to `lab.ini`.
3. ansible-provision: rewrite the playbook layer one playbook per operator, plus one assembly playbook per species that imports its operator playbooks in the definition's order; the EPICS operators carry their configuration content (P_epics the rocky firewalld EPICS ports, P_epics-build Python and pip). Update the repository README command examples and its `testbed` trust wording (README, `docs/STANDALONE.md`, the `ansible.cfg` inventory path) to `lab`, and keep its `tests/` checks passing. Regenerate the ansible-provision make targets (`configure/RULES_ANSIBLE`) for the operator and species playbooks, retiring the `<pb>.<os>.<node>` forms. The cloud-provision callers that hardcode playbook names (`bin/bake_iocrunner_image.bash` with `site.yml`, `04_nfs_sim`, and `07_test_users`, which now publishes the iocrunner and iocrunner-nfs species as separate golden flavors selected by a flavor flag defaulting to iocrunner; `bin/bake_ethercat_image.bash` with `05_ethercat_base`; `bin/run_epics_env_build.bash`, whose default playbook retires with the rewrite) move to the new species assemblies in the same step.
4. ansible-provision: the EPICS development package list follows the pkg_automation `epics` lists as the reference baseline; `pkg_standard` retires with the rewrite.
5. cloud-provision: rework `create_vm` OS types to `<vacuum>` and `<vacuum>-<species>`, rename `epics-env-<os>` to `<os>-epics-dev`, add the `<vacuum>-iocrunner-nfs` consumer type for the second golden flavor, redefine the IP bases as a vacuum-by-species table, retire the server/node numbering, and replace the `testbed` default prefix with `lab`; add the plain `rocky10`, `ubuntu24`, and `ubuntu26` bare types that do not exist yet, and update every other reader of the old names and of the retired `-n server` interface: `configure/CONFIG_SITE`, `bin/run_epics_env_build.bash`, `bin/bake_ethercat_image.bash`, `tests/check-proxy-injection.bash`, `bin/audit_iocrunner_images.bash` (whose kind and platform cases widen with the golden flavors and the new vacua), and the cloud-init and inventory tests.
6. cloud-provision: rewrite `generate_ansible_inventory.bash` to accept species names on every vacuum the definition assigns and emit hosts into both their vacuum group and their species group; a bare host's group is its vacuum group alone, since bare has no separate species group.
7. cloud-provision: regenerate the make targets in `configure/RULES_VM`, `RULES_EPICS_ENV`, and `RULES_BAKE` for the new names and drop the `.server`/`.node1` forms.
8. cloud-provision: update `README.md`, `ARCHITECTURE.md`, `RUNBOOK_BAKE.md`, `RUNBOOK_ANSIBLE_INVENTORY.md`, and `VIRSH_CLI.md` to the definition's terms and rename the NAT environment to `lab`.
9. Settle the golden-naming Open decision by deciding whether the existing `image_workflow_select_latest_image` selection becomes the defined convention, reflect it in the bake publish names, and document builder and verify in the image-life sections of `docs/IMAGE_WORKFLOW.md`.
10. Keep the operator definition current as the implementation lands: the Role column tracks the delivered role names and each settled Open decisions row is removed in the change that settles it.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M8 / T1 | Syntax and static analysis | Run `bash -n` and `shellcheck -S warning` on every changed Bash file in both repositories and `ansible-playbook --syntax-check` on every rewritten playbook | Local checkouts | Exit 0 and no unreviewed warning |
| M8 / T2 | Offline contract checks | Run `make check-bake`, `make check-proxy-injection`, `make check-runtime-inventory`, and `make check-docs` in cloud-provision and the ansible-provision `tests/` checks, updated for the new names | Local checkouts | Every check passes against the new model |
| M8 / T3 | Inventory matrix | Drive the shipped `generate_ansible_inventory.bash` with every vacuum-species pair the definition assigns | Local checkout; real generator | Every assigned pair is accepted; bare pairs land in the vacuum group alone, and every other pair lands in both its vacuum and species groups |
| M8 / T4 | P_common on every vacuum | Boot one fresh VM per vacuum and apply only the bare assembly (`playbooks/species/bare.yml`) with a generated host inventory and `ansible-playbook` | Supported Libvirt/KVM | Every must-have and nice-to-have package is installed, the configuration content is in place, and the debian family generates `en_US.UTF-8` |
| M8 / T5 | Golden regression | Run the debian13 and rocky8 iocrunner bakes, one iocrunner-nfs bake, and fresh consumers through the shipped entry points | Supported Libvirt/KVM | Every bake publishes its flavor and every consumer selects the exact just-published pair |
| M8 / T6 | Source-build vacuum | Run one epics-dev build through `bin/run_epics_env_build.bash` on a vacuum outside the former core pair | Supported Libvirt/KVM | The build completes on the new inventory structure |

##### Verification Results

None observed.

##### Closure Evidence

None.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Deferred EtherCAT acceptance | M1.1 | Validate EtherCAT use of the shared image workflow and proxy seal | Carry-forward | Deferred | No | D014-D015, D017, M3 | After M3, restore and update the deferred EtherCAT test surfaces from `733edf0`, then run the real bake, consumer, proxy-clean check, and separately authorized image audit; [M1.1 detail](#m11). |

### Backlog Details

<a id="m11"></a>
#### M1.1 - Validate EtherCAT use of the shared image workflow and proxy seal

Origin: c53e17e / M1.1
Identity History: none
GitHub Issue: [#35](https://github.com/jeonghanlee/cloud-provision/issues/35)
Status: Deferred

##### Summary

Commit `304291b` integrates the EtherCAT bake and consumer with the shared naming, copy, creation-record, and pair-validation code used by ioc-runner. Commit `47aeede` adds the shared proxy artifact contract, the terminal EtherCAT seal, and historical local EtherCAT coverage. D017 removes only the dedicated EtherCAT test surfaces from the current graph and records `733edf0` as their restoration baseline after M3; production EtherCAT behavior remains unchanged. No actual EtherCAT bake, fresh consumer selection, value-redacting proxy check, or existing EtherCAT image audit has been observed on supported Libvirt/KVM in this generation.

##### Scope

- After M3 completes, restore and update the deferred dedicated EtherCAT test surfaces from the recorded `733edf0` baseline.
- Apply the same SIGPIPE-safe IP-resolution fix already made in the IOC bake to the EtherCAT bake, whose VM-address `awk` still exits on first match while `create_vm -s` is writing and can abort the bake with exit 141 under `set -o pipefail`.
- Run the shipped Debian 13 EtherCAT bake on supported Libvirt/KVM.
- Inspect the produced image, manifest, and creation record for matching identity and no backing file.
- Boot a fresh `debian13-ethercat` consumer and confirm that it selects the exact valid pair produced by the bake.
- Run a value-redacting verifier against the exact produced image and confirm that no shared-contract proxy artifact remains.
- Audit current EtherCAT working and archived images under a separate accepted and authorized value-safe plan.
- Quarantine or replace every affected EtherCAT image and record any required credential rotation outside the repository and GitHub.
- Record the runtime evidence in this detail section.
- Verify the EtherCAT bake still installs its packages after the proxy-injection `packages:` strip (D018), since the EtherCAT bake shares the same `create_vm` merge; if it does not install them through a post-apply path, restore that coverage.

Out of scope: Changes to the shared image workflow or proxy contract unless runtime verification exposes a defect; ioc-runner runtime verification and ioc-runner image audit owned by M2 and issue #34; publishing any proxy endpoint or credential.

##### Completion Criteria

- A real EtherCAT bake completes through the shipped entry point.
- The produced image has no backing file.
- The image, manifest, and creation record agree on run identifier and artifact identity.
- A fresh EtherCAT consumer selects the exact verified pair.
- A value-redacting verifier reports no shared-contract proxy artifact in the exact produced image.
- Existing EtherCAT working and archived images are audited without emitting proxy values.
- Every affected EtherCAT image is replaced or quarantined.
- Any required credential rotation is recorded externally without placing the credential in GitHub or the repository.
- The observed paths, identifiers, and selection evidence are recorded here.
- The deferred EtherCAT test surfaces are restored and updated for the post-M3 shared contract before any EtherCAT test command runs.

##### Dependencies And Decisions

- D014-D015, D017, and M3
- M3 must complete before the deferred EtherCAT tests are restored or run.
- Supported Libvirt/KVM host with the EtherCAT bake prerequisites
- Separate plan and authorization before any existing EtherCAT image is read or remediated

##### Deferred Test Restoration Record

Restoration baseline: `733edf0beca51a59ca44782ec3958b00a8fc8bc3`

| Surface | Baseline Blob | Recorded Location |
| --- | --- | --- |
| `tests/check-ethercat-bake-workflow.bash` | `2b1cf56c7f65116dac9854878d9604ad0d035c05` | lines 1-473 |
| `tests/check-proxy-lifecycle.bash` | `97d5dfa83f9fd4c9ad4550656b25588608d719eb` | lines 169-170, 201-206, 221-225, and 245-247 |
| `configure/RULES_BAKE` | `55a3cef3bbda8752b981437bc2789a8a7d508101` | lines 26-27, 33, 41-42, and 55 |
| `docs/RUNBOOK_BAKE.md` | `b4588fedf492f57c54221c40271908dc0795dfd5` | lines 348-366 |

The future M1.1 plan must restore these surfaces as source material and update them for the then-current shared contract. It must not overwrite later IOC work with the baseline bytes.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Wait for M3 to complete and obtain a separate accepted and authorized M1.1 plan.
2. Restore the deferred test surfaces from `733edf0` as source material, update them for the current shared contract, and verify their direct graph before running them.
3. Confirm the supported host prerequisites and available source golden pair.
4. Run the shipped EtherCAT bake entry point.
5. Inspect the produced image, manifest, creation record, no-backing state, and value-redacting proxy-clean result.
6. Boot a fresh `debian13-ethercat` consumer and confirm exact pair selection.
7. Obtain a separate accepted and authorized value-safe plan before auditing existing EtherCAT images.
8. Quarantine or replace any affected image and record any external credential action without storing proxy values.
9. Record the evidence and close the work unit if all criteria pass.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | Historical local contract | Preserve the observed `47aeede` result; do not run an EtherCAT test in the current M3 graph | Historical checkout only | The prior local result remains evidence for `47aeede`, not current coverage |
| M1.1 / T2 | Runtime acceptance | Run the shipped EtherCAT bake and a fresh consumer, then inspect the exact output pair, qcow2 metadata, creation record, and value-redacting proxy-clean result | Supported Libvirt/KVM host with EtherCAT bake prerequisites | The bake produces an independent valid pair, the verifier reports no contract proxy artifact, and the consumer selects that exact pair |
| M1.1 / T3 | Existing-image audit | Run only from a separate accepted and authorized value-safe audit plan | Separately authorized audit environment | Existing EtherCAT images are classified without emitting values and every affected image is replaced or quarantined |
| M1.1 / T4 | Deferred test restoration | Restore the recorded surfaces from `733edf0`, update them for the post-M3 contract, and run them only under the future accepted M1.1 plan | Repository checkout after M3 | Dedicated EtherCAT tests cover the then-current contract without reverting IOC work |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.1 / T1 | 2026-08-20 11:38 PDT | Commit `47aeede`; shipped EtherCAT and joined lifecycle paths with only outer boundaries replaced | Pass | `make check-bake-ethercat-workflow` passed 11/11 and `make check-proxy-lifecycle` passed 26/26; this does not satisfy real runtime acceptance or existing-image audit |
| M1.1 / T2 | Not run | Supported Libvirt/KVM host with EtherCAT bake prerequisites | Pending | Exact real bake, fresh consumer, and value-redacting proxy-clean result |
| M1.1 / T3 | Not run | Separately authorized audit environment | Pending | Separate value-safe EtherCAT audit plan |
| M1.1 / T4 | Not run | Repository checkout after M3 | Pending | Restore and update the recorded test surfaces from `733edf0` |

##### Closure Evidence

- Deferred by owner direction on 2026-08-13 and retained separately on 2026-08-20. Real runtime acceptance and existing-image audit have not run.
- The prior local EtherCAT contract result remains pinned at `tests/check-ethercat-bake-workflow.bash:237-239@c53e17e`; M1.1 / T1 records the later 47aeede rerun.
- D017 deferred the dedicated EtherCAT tests on 2026-08-20 and recorded their exact `733edf0` baseline above. No EtherCAT test ran during the M3 review or planning session.

##### GitHub Projection

Title: Validate EtherCAT use of the shared image workflow and proxy seal
Labels: bug
GitHub Milestone: Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: bug
Observed Milestone: Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-08-20 18:43:18 PDT; remote updated 2026-08-20 18:43:11 PDT
Projection State: reconciled; remote title and body match the canonical projection and the issue remains open

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-19 | c53e17eda34f5ddd7795ff61bccf63ec220a35c8 |
