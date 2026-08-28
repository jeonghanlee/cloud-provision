# Work Register

Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: M3 (Debian 12) code landed across the eight plan steps
and M3 / T1 passed; M3 / T2 and M3 / T3 (real provision) are blocked on M6. The
nearest actionable entry is M6 (define and create the `lab` libvirt network in
the host setup path): its plan is accepted, so implementation can begin once
authorized - completing it unblocks M3's real-path verification. M2 (the `P_proxy` precondition) awaits its
ansible-provision `proxy` role and is not yet Ready; M5 (the driver extra-vars
passthrough, issue #38) is open; EtherCAT validation stays Deferred in the
Backlog.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Operator model | M1 | Split the operator definition into its own normative document and add the realization-mode and produced-artifact framing | Milestone | Complete | No |  | `docs/OPERATOR_MODEL.md` carries the operator, species, and vacua definitions verbatim, `docs/IMAGE_WORKFLOW.md` points to it, and the realization-mode axis and produced-artifact node are added; committed as `e260630`; [M1 detail](#m1). |
| Operator model | M2 | Add the P_proxy precondition, landing with its ansible-provision proxy role | Milestone | Not started | No | M1 | `docs/OPERATOR_MODEL.md` defines `P_proxy` (optional, unconditionally-first precondition) and the matching ansible-provision `proxy` role exists so definition and implementation land together; the `iocserver` species already landed; [M2 detail](#m2). |
| OS coverage | M3 | Support Debian 12 as a sixth vacuum, bare and epics-dev | Milestone | In progress | Yes | M1 | Debian 12 is wired as a vacuum (definition, template, package source, guard) and as the `debian12-epics-dev` variant, a real bare provision installs P_common, and the epics-dev variant builds layers 1+2; [M3 detail](#m3). |
| Driver ergonomics | M5 | Add an extra-vars (ANSIBLE_OPTS) passthrough to the epics-dev build driver | Milestone | Not started | Yes |  | `bin/run_epics_env_build.bash` forwards extra-vars so the build flavor (e.g. gz) is selectable from the driver, not only via the ansible-provision make target; [M5 detail](#m5). Refs #38. |
| Host setup | M6 | Define and create the `lab` libvirt network in the host setup path | Milestone | Not started | Yes |  | `bin/setup_host.bash` defines and activates the `lab` network (192.168.123.0/24) from a shipped definition when absent, so a host with only the libvirt `default` network can provision lab vacua; unblocks M3 / T2 and M3 / T3; [M6 detail](#m6). |

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D1 | Reading, auditing, quarantining, replacing, or deleting an existing guest, disk, image, archive, or sidecar requires a separate accepted plan and explicit authorization. | 2026-08-20 |

### Assignment History

None this generation.

### Milestone Details

<a id="m1"></a>
#### M1 - Split the operator definition into its own normative document

Origin: 1 / M1
Identity History: none
Status: Complete

##### Summary

The operator, species, and vacua definitions were the normative core of
`docs/IMAGE_WORKFLOW.md`, but they sat under the non-normative physics-reading
shorthand and read as image-naming prose, so other repositories and sessions
could not find them. This milestone moves them, unchanged, into
`docs/OPERATOR_MODEL.md` as the single normative source, leaves a pointer in
`IMAGE_WORKFLOW.md`, and adds two framings that stop the three realizations from
drifting: a realization-mode axis (Golden cloud image, Live server, Instant
container) and a produced-artifact node naming the EPICS-env-distribution and
its `epics-dev` build environment.

##### Scope

- Create `docs/OPERATOR_MODEL.md` and carry the Vacua, Operators, Commutation,
  Species, and valid-unnamed-product tables verbatim from `IMAGE_WORKFLOW.md`.
- Add a Notation section, the realization-mode axis, and a Produced-artifacts
  section (distribution producer `epics-dev`, build mechanisms local make and
  ansible, consumer `P_epics`); defer run-purpose classification to the
  `epics-env-pipeline` skill.
- Replace the operator-definition section in `IMAGE_WORKFLOW.md` with a pointer
  and align its header.

Out of scope: the `P_proxy` precondition (M2) and the `iocserver` species;
internal site modules; any change to the operator or species definitions
themselves.

##### Completion Criteria

- Every operator-definition table row from the pre-split `IMAGE_WORKFLOW.md`
  appears verbatim in `OPERATOR_MODEL.md`.
- `IMAGE_WORKFLOW.md` carries no operator-definition body, only a pointer, and
  no repository link targets a removed sub-anchor.
- The added sections reference only defined operators and species.

##### Dependencies And Decisions

- None.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner-directed during the session
Implementation Authorization: committed as `e260630`
Superseded Plan Artifacts: none

##### Test Plan

| Check | Method |
| --- | --- |
| M1 / T1 | Every operator-definition table row of `origin/master:docs/IMAGE_WORKFLOW.md` is found verbatim in `OPERATOR_MODEL.md`. |
| M1 / T2 | No tracked Markdown links a removed sub-anchor (`#operators`, `#vacua`, `#species`). |
| M1 / T3 | The P_common cell and family-name text match the current single-source (`configure/pcommon-packages`) form. |
| M1 / T4 | The realization-mode and produced-artifact sections name no undefined operator or species. |

##### Verification Results

| Check | Date | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| M1 / T1 | 2026-08-27 | Local checkout at `e260630` | Pass | Row-by-row grep of the origin operator-definition section against `OPERATOR_MODEL.md` reported 0 mismatches. |
| M1 / T2 | 2026-08-27 | Local checkout at `e260630` | Pass | Repo-wide grep for the removed sub-anchors returned none. |
| M1 / T3 | 2026-08-27 | Local checkout at `e260630` | Pass | The carried P_common cell and family sentence equal the post-single-source upstream text. |
| M1 / T4 | 2026-08-27 | Local checkout at `e260630` | Pass | No `P_proxy` or `iocserver` token remains outside the Status deferral note. |

##### Closure Evidence

Committed as `e260630` on 2026-08-27. Deliverable, completion criteria, and the
four local checks are satisfied; the milestone has no external gate.

<a id="m2"></a>
#### M2 - Add the P_proxy precondition

Origin: 2 / M2
Identity History: none
Status: Not started

##### Summary

The `iocserver` species (`iocrunner` without `P_testusers`) landed in the SOT
with the operator-model document, matching the ansible-provision `iocserver`
species playbook. What remains for M2 is the `P_proxy` precondition, held out
because it lands with its `proxy` role in ansible-provision. The full draft is
preserved in `work/operator-model-pending-B.md`.

##### Scope

- Add `P_proxy` as an optional precondition: not a member of any species
  product, and when present applied unconditionally first, before P_common and
  before every fetch. Record the single authority `bin/proxy_contract.bash`, the
  ADR-defined artifact inventory, and the per-realization fate (Golden seals it,
  Live and Instant keep it).
- Restore the realization proxy-fate column and the from-vacuum walkthrough
  removed for M1, now that the proxy notation exists.
- Land the matching ansible-provision `proxy` role in the same change set.

Out of scope: internal site modules; any Debian 12 work (M3); the `iocserver`
species (already landed).

##### Completion Criteria

- `docs/OPERATOR_MODEL.md` defines `P_proxy` as above.
- The ansible-provision `proxy` role exists and its name matches the document.
- The one-to-one map between the definition and the role holds.

##### Dependencies And Decisions

- M1 (the document must exist first).
- Coordinated with ansible-provision; the definition and the `proxy` role land
  together.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

##### Test Plan

| Check | Method |
| --- | --- |
| M2 / T1 | The `P_proxy` artifact inventory in the document matches `ADR-20260820`. |
| M2 / T2 | The ansible-provision `proxy` role applies the artifact set through `bin/proxy_contract.bash`. |

##### Verification Results

Pending.

<a id="m3"></a>
#### M3 - Support Debian 12 as a sixth vacuum

Origin: 3 / M3
Identity History: none
Status: In progress

##### Summary

A Linux support request adds Debian 12 (bookworm) to the supported OS matrix.
Today the vacua are debian13, rocky8, rocky10, ubuntu24, and ubuntu26; Debian 12
becomes the sixth, in the debian family. It mirrors debian13 wiring, and the
`debian12-epics-dev` source-build variant is included so Debian 12 can carry the
layers 1+2 EPICS build like the other vacua.

##### Scope

- Bare vacuum: add `debian12` (debian family) everywhere a vacuum is wired -
  `docs/OPERATOR_MODEL.md` (Vacua and a `bare_debian12` species), the P_common
  single source `configure/pcommon-packages` (`family:` map), a
  `templates/user-data.debian12` cloud-init template mirroring debian13, the
  `configure/CONFIG_SITE` `OS_TYPES`, the `bin/create_vm.bash` base-image branch
  (bookworm GenericCloud), the `bin/generate_ansible_inventory.bash` bare vacuum
  list, and the package-parity guard coverage.
- Source-build variant: add `debian12-epics-dev` to `CONFIG_SITE` `OS_TYPES`, the
  `create_vm.bash` epics-dev branch and IP-base declaration and mapping
  (`DEBIAN12_IP_BASE`, `DEBIAN12_EPICS_DEV_IP_BASE`), and the
  `bin/run_epics_env_build.bash` epics-dev allowlist.

Out of scope: internal site modules; the `P_proxy` work (M2);
changes to EPICS-env itself (its Debian 12 support already exists in CI).

##### Completion Criteria

- The vacua definition and `bare_debian12` species list debian12.
- `make check-package-parity` covers debian12 and passes.
- A real Debian 12 bare provision installs the P_common set.
- `make debian12-epics-dev.main` provisions and `run_epics_env_build.bash -o
  debian12-epics-dev` builds layers 1+2 on it.

##### Dependencies And Decisions

- M1 (the vacua definition lives in the new document).
- EPICS-env Debian 12 support (present in its CI) for the epics-dev build check.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner-accepted 2026-08-27 after plan, third-person, and second-person review
Implementation Authorization: owner-authorized 2026-08-28
Superseded Plan Artifacts: none

1. `configure/pcommon-packages`: add `debian12=debian` to the `family:` line.
2. `bin/create_vm.bash`: add the `debian12` base-image case - `BASE_IMAGE_NAME`
   `debian-12-genericcloud-amd64.qcow2` and `BASE_URL`
   `https://cloud.debian.org/images/cloud/bookworm/latest/${BASE_IMAGE_NAME}`
   (Debian 12 is stable, so `bookworm/latest`, not the `trixie/daily` path
   debian13 uses), mirroring the debian13 case's other fields (`OS_VARIANT`,
   `VM_BOOT_FIRMWARE=uefi`) - and the `debian12-epics-dev` case mirroring
   `debian13-epics-dev`; declare `DEBIAN12_IP_BASE=15` and
   `DEBIAN12_EPICS_DEV_IP_BASE=45` in the IP-base declare block and add both to
   the IP-base case; update the help and header vacua lists.
3. `configure/CONFIG_SITE`: add `debian12` and `debian12-epics-dev` to
   `OS_TYPES`.
4. `templates/user-data.debian12`: mirror `user-data.debian13`, keeping the
   debian-family locale self-check as the last runcmd entry.
5. `bin/generate_ansible_inventory.bash`: add `debian12` to the bare vacuum
   selector list.
6. `bin/run_epics_env_build.bash`: add `debian12-epics-dev` to the epics-dev
   allowlist.
7. `docs/OPERATOR_MODEL.md`: add the `debian12 | debian` vacuum row and the
   `bare_debian12 = P_common |0_debian12⟩` species row (unicode ket, as the
   existing species rows use).
8. package-parity guard: no new fixture is needed - the guard derives the
   debian12 expected set from the `family:` map and checks the production
   `templates/user-data.debian12` (step 4). Confirm `make check-package-parity`
   passes; the `tests/fixtures/package-parity/` sets test the parser, not each OS.

##### Test Plan

| Check | Method |
| --- | --- |
| M3 / T1 | `make check-package-parity` passes with debian12 covered. |
| M3 / T2 | A real Debian 12 bare provision (`make debian12.main`) installs the P_common must-have and core-utility sets. |
| M3 / T3 | `make debian12-epics-dev.main` provisions and `run_epics_env_build.bash -o debian12-epics-dev` builds layers 1+2. |

##### Verification Results

- T1: pass. `make check-package-parity` reports 6 checked, 6 passed, with
  debian12 covered.
- T2, T3: blocked on M6 - the real bare provision and the epics-dev layers 1+2
  build have not been run. This host carries only the `default` network
  (192.168.122.0/24); `create_vm.bash` targets the `lab` network
  (192.168.123.0/24), which no path defines yet (M6). The provision needs either
  the lab host or M6's setup path.
- T2/T3 base-image pre-check: pass. The `debian-12-genericcloud-amd64.qcow2`
  URL (`cloud.debian.org/.../bookworm/latest/`) resolves 200 OK (~332 MB) and
  redirects to a Debian mirror that `curl -f -L` follows, so the base-image
  fetch step is verified without a full provision.

Implementation landed the eight plan steps: the `family:` map, the
`create_vm.bash` base-image and epics-dev cases plus IP bases
(`DEBIAN12_IP_BASE=15`, `DEBIAN12_EPICS_DEV_IP_BASE=45`) and help text, the
`CONFIG_SITE` `OS_TYPES`, `templates/user-data.debian12`, the inventory bare
selector, the epics-dev build allowlist, and the operator model vacua and
`bare_debian12` species rows.

<a id="m5"></a>
#### M5 - Add an extra-vars passthrough to the epics-dev build driver

Origin: 5 / M5
Identity History: none
GitHub Issue: [#38](https://github.com/jeonghanlee/cloud-provision/issues/38)
Status: Not started

##### Summary

`bin/run_epics_env_build.bash` invokes `ansible-playbook` with no `-e` /
`ANSIBLE_OPTS` passthrough, so the build flavor (`epics_env_build_flavor`, e.g.
`gz`) cannot be overridden from the driver; only the ansible-provision make
target (`ANSIBLE_OPTS="-e epics_env_build_flavor=gz"`) can. Surfaced during the
1.3.0 gz step. Minor: the make-target path already works.

##### Scope

- Add a repeatable `-e` option, or an `-O "<ANSIBLE_OPTS>"` append, to the
  driver's `ansible-playbook` invocation so extra-vars reach the run.

Out of scope: changing the default flavor or the ansible-provision make path.

##### Completion Criteria

- The driver forwards caller-supplied extra-vars, and a gz build can be driven
  through `run_epics_env_build.bash` without editing role defaults.

##### Dependencies And Decisions

- None. Tracked as issue #38.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

<a id="m6"></a>
#### M6 - Define and create the lab libvirt network in the host setup path

Origin: 6 / M6
Identity History: none
Status: Not started

##### Summary

Commit `8cc1993` (2026-08-25) isolated the lab VM model onto its own network
(`lab`), subnet (192.168.123.0/24), and MAC space (`52:54:00:01`), and pointed
`bin/create_vm.bash` at the `lab` libvirt network. No path defines or creates
that network: `bin/setup_host.bash` only ensures the libvirt-provided `default`
network is autostarted and active (it assumes `default` already exists), and the
repository ships no `lab` network definition. On a host that carries only
`default`, a provision fails at the first `virsh net-update lab` reservation
because `lab` is undefined. This surfaced attempting M3 / T2 on a default-only
host.

##### Scope

- Add a `lab` libvirt network definition (name `lab`, NAT forward, its own
  bridge, ip 192.168.123.1/24 with a DHCP range) as a file the setup path
  applies.
- Generalize `bin/setup_host.bash` so it defines the `lab` network from that
  file with `net-define` when absent, then autostarts and starts it, the same
  way `default` is ensured active, without disturbing `default`.
- Keep the per-host static reservations dynamic: `create_vm.bash` continues to
  add and remove `ip-dhcp-host` entries via `net-update` at provision time; the
  definition supplies only the subnet and a DHCP range.

Out of scope: the subnet and MAC scheme chosen by `8cc1993`; any change to the
`default` network; M3's Debian 12 wiring, which already landed.

##### Completion Criteria

- On a host that had only `default`, the setup path leaves an active `lab`
  network.
- `virsh net-dumpxml lab` shows 192.168.123.0/24 with a DHCP range compatible
  with the static reservations `create_vm.bash` adds.
- A vacuum provision reaches and passes the `net-update lab` reservation step
  without a "network not found" failure.

##### Dependencies And Decisions

- Consequence of `8cc1993`. No M or G dependencies. Completing M6 unblocks
  M3 / T2 and M3 / T3, whose real path needs the `lab` network.
- Owner decisions (2026-08-28): the network uses a fixed bridge name
  `virbr-lab` (predictable, consistent with the fixed MAC space `8cc1993`
  chose) rather than a libvirt-auto bridge; the definition lives at
  `configure/lab-network.xml`, alongside the other `configure/` inputs.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner-accepted 2026-08-28 after plan, two third-person reviews, and two second-person reviews
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Add `configure/lab-network.xml`, a libvirt network definition: `<network>`
   named `lab`, `<forward mode='nat'/>`, `<bridge name='virbr-lab' stp='on'
   delay='0'/>`, and `<ip address='192.168.123.1' netmask='255.255.255.0'>` with
   `<dhcp><range start='192.168.123.2' end='192.168.123.254'/></dhcp>`. No
   `<uuid>`, `<mac>`, or static `<host>` entries: libvirt generates the identity
   and `create_vm.bash` adds the per-host reservations at provision time. The
   DHCP range spans the static bases (`.10`-`.155`) and the fallback hash window
   (`.160`-`.254`).
2. Generalize `bin/setup_host.bash`. Factor the existing `default`
   autostart-and-start block (lines 67-83) into a helper taking a network name.
   Resolve the repository top from `${BASH_SOURCE[0]}`'s directory parent. After
   ensuring `default`, ensure `lab`: when `virsh net-info lab` reports it
   undefined, `virsh net-define "${TOP}/configure/lab-network.xml"`, then
   autostart and start it through the shared helper. Leave the `default` handling
   unchanged. The script runs under `set -e`, so probe definedness with the
   set-e-safe form `if ! virsh net-info lab >/dev/null 2>&1; then net-define; fi`,
   never a bare `status=$?` capture, which the nonzero exit of an undefined
   network would turn into an immediate script abort. The refactored helper keeps
   the existing autostart and active guards so a re-run stays idempotent.
3. Verify T1 and T2 below on this default-only host.

##### Test Plan

| Check | Method |
| --- | --- |
| M6 / T1 | On a host with only `default`, `make setup` defines and activates `lab`; `virsh net-dumpxml lab` shows 192.168.123.0/24 with the DHCP range `.2`-`.254`. |
| M6 / T2 | A vacuum provision passes the `virsh net-update lab` reservation step with no "network not found" error. The same real provision run satisfies M3 / T2 (P_common install), so `make debian12.main` covers both at once - no separate provision is scheduled for M6. |

##### Verification Results

Pending.

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EtherCAT | M4 | Validate EtherCAT use of the shared image workflow and proxy seal | Carry-forward | Deferred | No | D1 | A real EtherCAT bake, fresh consumer selection, value-redacting proxy check, and separately authorized image audit are observed on supported Libvirt/KVM; [M4 detail](#m4). |

### Backlog Details

<a id="m4"></a>
#### M4 - Validate EtherCAT use of the shared image workflow and proxy seal

Origin: 4 / M4
Identity History: none
GitHub Issue: [#35](https://github.com/jeonghanlee/cloud-provision/issues/35)
Status: Deferred

##### Summary

The EtherCAT bake and consumer share the naming, copy, creation-record, and
pair-validation code used by ioc-runner, and the shared proxy contract with a
terminal EtherCAT seal exists. No actual EtherCAT bake, fresh consumer
selection, value-redacting proxy check, or existing EtherCAT image audit has
been observed on supported Libvirt/KVM in this generation. The dedicated
EtherCAT test surfaces were removed from the current graph and must be restored
from the recorded baseline before any EtherCAT test runs; production EtherCAT
behavior is unchanged.

##### Scope

- Restore and update the deferred dedicated EtherCAT test surfaces from the
  recorded `733edf0` baseline, as source material, for the current shared
  contract; do not overwrite later IOC work with the baseline bytes.
- Apply the SIGPIPE-safe IP-resolution fix already made in the IOC bake to the
  EtherCAT bake.
- Run the shipped Debian 13 EtherCAT bake on supported Libvirt/KVM; inspect the
  produced image, manifest, and creation record for matching identity and no
  backing file.
- Boot a fresh `debian13-ethercat` consumer and confirm it selects the exact
  valid pair produced by the bake.
- Run a value-redacting verifier against the produced image and confirm no
  shared-contract proxy artifact remains.
- Audit current EtherCAT working and archived images under a separate accepted
  and authorized value-safe plan (D1); quarantine or replace every affected
  image and record any credential rotation outside the repository and GitHub.
- Verify the EtherCAT bake still installs its packages after the
  proxy-injection `packages:` strip, since it shares the same `create_vm` merge.
- Record the runtime evidence in this detail.

Species-assembly asymmetry (Keep, examined 2026-08-26).
`playbooks/species/ethercat.yml` applies only `../operators/ethercat.yml` (a
delta on the booted rtbase golden, per its own comment) while the sibling
`playbooks/species/iocrunner_nfs.yml` re-imports its base species assembly. The
`ethercat = P_ethercat |rtbase⟩` formula and P_ethercat's `After P_rt` order do
not by themselves fix which model is intended, so the two species read the ket
differently. The golden-consumer model is kept as principled and left as is;
when un-deferring EtherCAT, if a different model is chosen, reconcile
`ethercat.yml` against `iocrunner_nfs.yml`, the `ethercat.yml` comment, and the
operator-model ethercat formula and P_ethercat order.

Out of scope: changes to the shared image workflow or proxy contract unless
runtime verification exposes a defect; publishing any proxy endpoint or
credential.

##### Completion Criteria

- A real EtherCAT bake completes through the shipped entry point.
- The produced image has no backing file, and the image, manifest, and creation
  record agree on run identifier and artifact identity.
- A fresh EtherCAT consumer selects the exact verified pair.
- A value-redacting verifier reports no shared-contract proxy artifact.
- Existing EtherCAT images are audited without emitting proxy values, and every
  affected image is replaced or quarantined.
- Any required credential rotation is recorded externally.
- The deferred EtherCAT test surfaces are restored and updated before any
  EtherCAT test command runs.

##### Dependencies And Decisions

- D1 (a separate plan and authorization before any existing EtherCAT image is
  read or remediated).
- A supported Libvirt/KVM host with the EtherCAT bake prerequisites.
- Deferred by owner direction; resume as Not started when the owner obtains an
  accepted EtherCAT plan.

##### Deferred Test Restoration Record

Restoration baseline: `733edf0beca51a59ca44782ec3958b00a8fc8bc3`

| Surface | Baseline Blob | Recorded Location |
| --- | --- | --- |
| `tests/check-ethercat-bake-workflow.bash` | `2b1cf56c7f65116dac9854878d9604ad0d035c05` | lines 1-473 |
| `tests/check-proxy-lifecycle.bash` | `97d5dfa83f9fd4c9ad4550656b25588608d719eb` | lines 169-170, 201-206, 221-225, and 245-247 |
| `configure/RULES_BAKE` | `55a3cef3bbda8752b981437bc2789a8a7d508101` | lines 26-27, 33, 41-42, and 55 |
| `docs/RUNBOOK_BAKE.md` | `b4588fedf492f57c54221c40271908dc0795dfd5` | lines 348-366 |

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-27 | e260630b1ab3cb3541eb8cae7b58b2ab2ab68259 |
