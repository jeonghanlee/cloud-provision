# Work Register

## Scope

This document tracks unfinished work carried into the master reset generation identified by prior-state commit `780a25e`.

**Out of scope:** Completed work and the prior generation's full record remain reachable from the History commit and are not repeated here.

Release line: master
Milestone index: 780a25e
Canonical path: `docs/milestone-780a25e.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: No assigned milestone is Ready. Backlog M1.1 remains Deferred pending separate owner authorization for EtherCAT runtime acceptance; M1.2 and M1.3 are Complete.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Locale readiness | M1.3 | Provide `en_US.UTF-8` in Debian, Ubuntu, and Rocky cloud-init guests | Milestone | Complete | No |  | Fresh Debian 13, Ubuntu 24/26, and Rocky 8/10 guests accept the host locale without warnings and record the observed runtime results; [M1.3 detail](#m13). |

M1.3 is Complete in this generation. Completed prior-generation work and its evidence are reachable from the History commit.

### Milestone Details

<a id="m13"></a>
#### M1.3 - Provide `en_US.UTF-8` in Debian, Ubuntu, and Rocky cloud-init guests

Origin: 780a25e / M1.3
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Provide the locale requested by the host SSH environment in every supported plain cloud-init guest template. Debian and Ubuntu templates install and generate `en_US.UTF-8`; Rocky runtime acceptance confirmed that the existing image packages already provide the same locale, so no Rocky template change was required.

##### Scope

- Configure Debian 13, Ubuntu 24, Ubuntu 26, Rocky 8, and Rocky 10 plain cloud-init guests.
- Generate `en_US.UTF-8` before the guest is handed to the operator.
- Verify `locale -a`, a login shell, and cloud-init completion on fresh guests.
- Record observed runtime results for all five supported base templates.

Out of scope: modifying the existing `testbed-debian13-server` guest, changing the host locale, and changing proxy behavior.

##### Completion Criteria

- Each of the five supported base templates provisions a fresh guest without the invalid-locale warning.
- Each guest reports the `en_US` UTF-8 locale through `locale -a`.
- Each guest reaches cloud-init completion and accepts a non-interactive SSH command.
- Any Rocky template change required by runtime evidence is applied and rechecked.
- The five runtime results and cleanup state are recorded here.

##### Dependencies And Decisions

- The host can reach the five upstream base images through its runtime proxy environment.
- Owner authorization to apply the locale fix and run all five fresh guest checks was given in chat on 2026-08-19.
- Verification guests use the `locale-check` prefix and are cleaned after acceptance.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner approval in chat on 2026-08-19
Implementation Authorization: Owner authorization in chat on 2026-08-19
Superseded Plan Artifacts: none

1. Add locale package and generation commands to Debian and Ubuntu cloud-init templates.
2. Verify the public seed-generation path contains the locale configuration.
3. Provision fresh Debian 13, Ubuntu 24/26, and Rocky 8/10 guests through `bin/create_vm.bash`.
4. Check locale availability, login-shell output, cloud-init completion, and package installation.
5. Apply any Rocky template correction required by runtime evidence, re-run checks, clean the verification guests, and record results.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.3 / T1 | Local contract | Run the public seed-generation path for Debian and Ubuntu with external command boundaries replaced | Repository checkout with the delivered templates | The seed contains `locales`, `locale-gen`, and `update-locale` exactly once for each Debian-family template |
| M1.3 / T2 | Runtime acceptance | Provision and inspect a fresh Debian 13 guest | Supported Libvirt/KVM host with the host proxy environment | Package installation completes, `locale -a` contains `en_US`, and a login shell emits no invalid-locale warning |
| M1.3 / T3 | Runtime acceptance | Provision and inspect fresh Ubuntu 24 and Ubuntu 26 guests | Supported Libvirt/KVM host with the host proxy environment | Both guests satisfy the same locale and cloud-init checks |
| M1.3 / T4 | Runtime acceptance | Provision and inspect fresh Rocky 8 and Rocky 10 guests | Supported Libvirt/KVM host with the host proxy environment | Both guests satisfy the locale and cloud-init checks, or the required template correction is recorded and rechecked |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.3 / T1 | 2026-08-19 | Local checkout; public `bin/create_vm.bash` path with external boundaries replaced | Debian 13 and Ubuntu 24/26 seed generation included locale package installation, locale.gen activation, and both locale commands; the locale/proxy suite completed 36 checks | `make check-proxy-injection` |
| M1.3 / T2 | 2026-08-19 | Fresh Debian 13 `locale-check-debian13-node1` on supported Libvirt/KVM | cloud-init completed; `locales` was installed; `locale -a` contained `en_US`; `/etc/default/locale` set `LANG=en_US.UTF-8`; a forced `LC_CTYPE=en_US.UTF-8` login shell returned without the invalid-locale warning | `bin/create_vm.bash -o debian13 -n node1 -p locale-check`; SSH runtime assertions |
| M1.3 / T3 | 2026-08-19 | Fresh Ubuntu 24 `locale-check-epics-env-ubuntu24-node1` and Ubuntu 26 `locale-check-epics-env-ubuntu26-node1` on supported Libvirt/KVM | Both guests completed cloud-init; `locales` was installed; `locale -a` contained `en_US`; `/etc/default/locale` set `LANG=en_US.UTF-8`; forced login shells returned without the invalid-locale warning | `bin/create_vm.bash` with `epics-env-ubuntu24` and `epics-env-ubuntu26`, `-n node1 -p locale-check`; SSH runtime assertions |
| M1.3 / T4 | 2026-08-19 | Fresh Rocky 8 `locale-check-rocky8-node1` and Rocky 10 `locale-check-epics-env-rocky10-node1` on supported Libvirt/KVM | Both guests completed cloud-init; `locale -a` contained `en_US`; forced `LC_CTYPE=en_US.UTF-8` login shells returned without the invalid-locale warning; no Rocky template correction was required | `bin/create_vm.bash` with `rocky8` and `epics-env-rocky10`, `-n node1 -p locale-check`; SSH runtime assertions |

##### Closure Evidence

- Complete 2026-08-19. Five fresh verification guests passed the locale and login-shell checks and were removed with the `locale-check` cleanup path; the existing `testbed-debian13-server` was not modified.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 Deferred EtherCAT acceptance | M1.1 | Validate EtherCAT use of the shared image workflow | Carry-forward | Deferred | No |  | Run the shipped EtherCAT bake and consumer on supported Libvirt/KVM, inspect the image, manifest, and creation-record pair, and confirm actual consumer selection; [M1.1 detail](#m11). |
| M1 Provisioning runtime inputs | M1.2 | Inject host proxy configuration into cloud-init provisioning without storing endpoint details | Milestone | Complete | No |  | Discover zero, one, or multiple host `*proxy.sh` files, reject ambiguous discovery, copy the selected file into `/etc/profile.d/`, and configure the OS package manager and Git without recording the proxy hostname or port; fresh Debian and Rocky runtime acceptance passed; [M1.2 detail](#m12). |

### Backlog Details

<a id="m11"></a>
#### M1.1 - Validate EtherCAT use of the shared image workflow

Origin: 780a25e / M1.1
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

Out of scope: Changes to the shared image workflow unless runtime verification exposes a defect. Ioc-runner runtime acceptance is already complete and reachable from the History commit.

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
| M1.1 / T1 | 2026-08-13 | Local checkout; public entry points with external command boundaries replaced | The EtherCAT workflow portion of `make check-bake` completed all 8 checks. This does not satisfy runtime acceptance. | `tests/check-ethercat-bake-workflow.bash` |

##### Closure Evidence

- Deferred by owner direction on 2026-08-13. Runtime acceptance has not run.

<a id="m12"></a>
#### M1.2 - Inject host proxy configuration into cloud-init provisioning without storing endpoint details

Origin: 780a25e / M1.2
Identity History: none
GitHub Issue: #32
Status: Complete

##### Summary

Allow a local provisioning host to provide its proxy configuration at image or VM creation time. The repository records the discovery and injection contract, but does not contain the proxy hostname or port.

##### Scope

- Search the host `/etc/profile.d/` directory for `*proxy.sh`.
- Continue without proxy configuration when no matching file exists.
- Use exactly one matching file when present.
- Stop with an explicit error when multiple matching files exist.
- Copy the selected proxy script into the guest `/etc/profile.d/`.
- Apply the proxy values to the guest package manager configuration for APT or DNF.
- Apply the proxy values to the system Git configuration.
- Keep proxy endpoint details out of tracked source, templates, tests, and milestone records.

Out of scope: proxy credentials, proxy hostname and port, external proxy service configuration, and removal of proxy configuration from ordinary runtime VMs.

##### Completion Criteria

- A host with no matching proxy file provisions without proxy configuration.
- A host with exactly one matching proxy file copies that file into the guest.
- Debian package installation uses the injected proxy configuration.
- Rocky package installation uses the injected proxy configuration.
- Git uses the injected proxy configuration.
- Multiple matching files stop provisioning before an ambiguous configuration is used.
- Tests verify the real seed-generation path with endpoint values supplied only by test-local fixtures.
- No tracked file contains the site proxy hostname or port.

##### Dependencies And Decisions

- The host proxy file is a runtime input and is not committed.
- Tests substitute an isolated temporary directory for the host `/etc/profile.d/` source location without changing tracked files.
- The discovery contract accepts exactly zero or one matching file.
- An ambiguous set of matching files is an error.
- Proxy endpoint details remain outside the repository-owned configuration.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: Owner approval in chat on 2026-08-19
Implementation Authorization: Owner authorization in chat on 2026-08-19
Superseded Plan Artifacts: none

1. Add proxy file discovery and exact-cardinality validation to the provisioning input path.
2. Parse the selected file's proxy variables without recording endpoint details in repository files or logs.
3. Extend cloud-init seed generation to copy the selected script and configure APT or DNF and system Git.
4. Add public-path tests for absent, single, and multiple proxy files across the supported package-manager paths.
5. Run the real repository checks and confirm that endpoint values remain local to the test or host environment.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| M1.2 / T1 | Local contract | Substitute an isolated empty directory for the host `/etc/profile.d/` source location and run the public seed-generation path | Repository checkout with a test-local source-directory override | Seed generation succeeds without proxy configuration |
| M1.2 / T2 | Local contract | Substitute an isolated directory containing one proxy fixture with test-local endpoint values and run the public seed-generation path | Repository checkout with a test-local source-directory override | The guest seed contains the selected profile script and package-manager and Git configuration |
| M1.2 / T3 | Local contract | Substitute an isolated directory containing two proxy fixtures and run the public seed-generation path | Repository checkout with a test-local source-directory override | Provisioning stops with an explicit multiple-file error |
| M1.2 / T4 | Runtime acceptance | Provision Debian and Rocky guests through the shipped entry points using a host-local proxy fixture | Supported Libvirt/KVM host with a reachable site proxy | Package installation and Git access use the proxy, and the endpoint is not persisted in tracked repository files |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1.2 / T1 | 2026-08-19 | Local checkout; public `bin/create_vm.bash` path with external boundaries replaced and no proxy fixture | Debian seed generation completed without a `write_files` proxy block | `make check-proxy-injection` / no-proxy case |
| M1.2 / T2 | 2026-08-19 | Local checkout; public `bin/create_vm.bash` path with one test-local proxy fixture | Debian and Rocky seed generation copied the profile script and generated the matching APT or DNF and system Git settings without printing the endpoint | `make check-proxy-injection` / Debian and Rocky proxy cases |
| M1.2 / T3 | 2026-08-19 | Local checkout; public `bin/create_vm.bash` path with two test-local proxy fixtures | Provisioning rejected the ambiguous input before the base image download boundary | `make check-proxy-injection` / multiple-proxy case |
| M1.2 / T4 | 2026-08-19 | Supported Libvirt/KVM host; existing Debian 13 proxy runtime and fresh Rocky 8 `proxy-check-rocky8-node1` provisioned through `bin/create_vm.bash` with the host-local proxy file | Debian package installation completed with the guest profile, APT, and system Git proxy settings present. Rocky cloud-init completed; the non-empty profile content matched the host input, DNF and system Git proxy settings were present, `git` was installed, and `git ls-remote` succeeded with proxy environment variables removed so the system Git configuration was exercised. The Rocky verification guest and disk were cleaned after acceptance. | `bin/create_vm.bash -o rocky8 -n node1 -p proxy-check -d /home/jeonglee/libvirt/images -F`; SSH runtime checks |

##### Closure Evidence

- Complete 2026-08-19. Fresh Debian and Rocky runtime acceptance passed. The Rocky guest reached cloud-init completion, used the injected DNF and system Git settings, and completed direct Git access through system Git configuration. The actual site endpoint remained outside tracked files and command output. The Rocky verification guest and disk were removed; the existing `testbed-debian13-server` guest was not modified during cleanup.

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-16 | 780a25e713fb431c2a03a0c8d6b71c122ca4f36a |
