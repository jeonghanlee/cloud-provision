# Work Register

Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: review the M15 guest-only plan against the existing
ansible-provision common-role includedir task before accepting and authorizing
execution. M14 is Complete: both guests passed the live sudo checks, the
verification record was pushed in `3517a23`, and GitHub issue #45 is closed.
M15 is still Not started and its current plan has no acceptance or
implementation authorization.
The M11 D4 and PV verification records
were committed in `794eb6b`. T2 and T3 passed on fresh debian13 and
rocky8 VMs at the D4 refs: full-species re-apply, installation-state comparison,
live PV storage/retrieval and historical retrieval after appliance restart,
on 2026-09-29 UTC (2026-09-28 Pacific). T3 required an explicit host CA address
on the Rocky test VM; see its recorded configuration. M11 remains In progress on
`m11-middleware-operators` until this branch and the ansible-provision
reconciliation merge to their respective master branches (see M11 Dependencies
And Decisions). M2 is
Complete; the proxied-host live check belongs to ansible-provision. G1 is Open
and M12 is Blocked on G1; EtherCAT (M4) is assigned to Milestone and stays Deferred.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Operator model | M1 | Split the operator definition into its own normative document and add the realization-mode and produced-artifact framing | Milestone | Complete | No |  | `docs/OPERATOR_MODEL.md` carries the operator, species, and vacua definitions verbatim, `docs/IMAGE_WORKFLOW.md` points to it, and the realization-mode axis and produced-artifact node are added; committed as `e260630`; [M1 detail](#m1). |
| Operator model | M2 | Add the P_proxy precondition, landing with its ansible-provision proxy role | Milestone | Complete | No | M1 | `docs/OPERATOR_MODEL.md` defines `P_proxy` (optional, unconditionally-first precondition; `8654990`) and the matching ansible-provision `proxy` role landed (`a02298f`), one-to-one; verified 2026-09-25; [M2 detail](#m2). |
| OS coverage | M3 | Support Debian 12 as a sixth vacuum, bare and epics-dev | Milestone | Complete | No | M1 | Debian 12 is wired as a vacuum (definition, template, package source, guard) and as the `debian12-epics-dev` variant, a real bare provision installs P_common, and the epics-dev variant builds layers 1+2; [M3 detail](#m3). |
| Driver ergonomics | M5 | Add an extra-vars (ANSIBLE_OPTS) passthrough to the epics-dev build driver | Milestone | Complete | No |  | `bin/run_epics_env_build.bash` forwards extra-vars so the build flavor (e.g. gz) is selectable from the driver, not only via the ansible-provision make target; [M5 detail](#m5). Refs #38. |
| Host setup | M6 | Define and create the `lab` libvirt network in the host setup path | Milestone | Complete | No |  | `bin/setup_host.bash` defines and activates the `lab` network (192.168.123.0/24) from a shipped definition when absent, so a host with only the libvirt `default` network can provision lab vacua; unblocks M3 / T2 and M3 / T3; [M6 detail](#m6). |
| Host setup | M8 | Align the readiness self-tests with the file-based cloud-init probe | Milestone | Complete | No | M7 | `make check-cloud-init-status`, `make check-proxy-injection`, `make check-runtime-inventory`, and `make check-bake` pass on the control host with every fake ssh answering the M7 readiness probe; [M8 detail](#m8). |
| Middleware | M11 | Middleware operator/species structure and package baseline (Archiver Appliance + Phoebus) | Milestone | In progress | No | D2, D3, D4, D5 | `docs/OPERATOR_MODEL.md` defines the java/tomcat/mariadb/archiver/phoebus operators and the archiver/phoebus/middleware species in the EPICS-symmetric dual-acquisition form, and `configure/` carries the middleware package baseline (system OpenJDK 21, Tomcat 9.0.121, MariaDB) with its guard; intended to satisfy ansible-provision G2 once its deliverable text is reconciled to this plan; [M11 detail](#m11). |
| Gate | G1 | aa-distribution and phoebus-distribution repositories created and populated | External gate | Open | No |  | The two middleware distribution repositories exist and carry the built WARs and the Phoebus binary, produced by aa-env and phoebus-env; needed before the distribution-install path (P_archiver, P_phoebus) can be verified live |
| Middleware | M12 | Verify the middleware distribution-install path (P_archiver, P_phoebus) | Milestone | Blocked | No | G1 | With aa-distribution and phoebus-distribution in place, the `archiver` and `phoebus` (distribution) species install the built WARs and the Phoebus binary and a re-apply is idempotent; [M12 detail](#m12). |
| Middleware | M13 | Confirm the Phoebus source-build tool and reconcile its prerequisites | Milestone | Not started | Yes | D2, D3, D5 | Immutable source refs identify the actual Phoebus build invocation and prerequisites; the operator model and middleware package baseline agree and shipped checks pass; [M13 detail](#m13). |
| EtherCAT | M4 | Validate EtherCAT use of the shared image workflow and proxy seal | Carry-forward | Deferred | No | D1 | A real EtherCAT bake, fresh consumer selection, value-redacting proxy check, and separately authorized image audit are observed on supported Libvirt/KVM; [M4 detail](#m4). |
| VM access | M14 | Allow password-free sudo validation on the two dedicated verification VMs | Milestone | Complete | No | D1, D6 | Both guests passed uncached `sudo -n -v`, ordinary sudo, and full sudoers syntax validation; verification recorded in `3517a23` and #45 closed; [M14 detail](#m14). |
| VM access | M15 | Put the Rocky sudoers includedir after all active rules | Milestone | Not started | Yes | D1, D6 | The Rocky guest retains its existing grants and has `/etc/sudoers.d` as the final active include directive with valid sudoers syntax; [M15 detail](#m15). |

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D1 | Reading, auditing, quarantining, replacing, or deleting an existing guest, disk, image, archive, or sidecar requires a separate accepted plan and explicit authorization. | 2026-08-20 |
| D2 | Middleware server provisioning follows the EPICS-symmetric ecosystem form: source -> env (compile) -> distribution -> install operator. AA uses aa-maven (source), aa-env (compile), and a new aa-distribution repository; Phoebus uses phoebus-env and a new phoebus-distribution repository; both distribution repositories are created and populated by their env producers. cloud-provision owns the operator/species structure, the package baseline, and the base VM; the middleware server hosts the EPICS Archiver Appliance and Phoebus, each independently selectable. | 2026-09-12 |
| D3 | Middleware operator choices: system Java (distribution OpenJDK 21, not the java-env pin) with `JAVA_HOME` exported; P_epics (local EPICS C base) installed on the middleware host; Tomcat pinned to 9.0.121 (Apache tarball as the shared CATALINA_HOME; the four separate Archiver Appliance instances are created by aa-env, not P_tomcat); the Archiver Appliance config database is MariaDB now and SQLite later; service group `mid` and user `mid-srv` (parallel to `ioc`/`ioc-srv`). Maven is not installed as an operator: aa-maven pins Maven 3.9.9 through its Maven Wrapper, so the source-build species runs `./mvnw` and needs only `JAVA_HOME`, git (with an origin ref), openssh-client (scp), outbound HTTPS, and `-Dsphinx.skip=true`. | 2026-09-12 |
| D4 | M11 / T2 uses ansible-provision `b8823c1`, epicsarchiverap-env `d09dca7`, and epicsarchiverap-maven `2fc12f01` on separate fresh Debian 13 and Rocky 8 VMs. These refs select Maven Wrapper 3.9.16 and `clean package -DskipTests`; the Maven build has no Sphinx step. This replaces D3's Maven version and Sphinx-skip requirement for this verification. The full MariaDB `archiver-dev` species and a re-apply with identical inputs are required; existing application-verification VMs remain outside this test. | 2026-09-28 |
| D5 | Separate Phoebus source-build tool confirmation and prerequisite reconciliation from M11 into independent M13. M11 retains the operator/species structure and Archiver Appliance baseline and verification. M13 does not gate M11 closure or M12 distribution-install verification. | 2026-09-29 |
| D6 | Assign two independent milestones to the dedicated Debian 13 and Rocky 8.10 IOC-runner documentation-verification guests: add per-user `verifypw=any` for `vmadmin` on both, and move the Rocky sudoers includedir after the existing active rules while preserving the `rocky` grant. Templates, golden images, other guests, and application setup are outside this scope. | 2026-09-29 |

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

- Create `docs/OPERATOR_MODEL.md` and carry the Vacua, Operators, Commutation
  (later replaced by the plain-English `## Order dependencies` section),
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
Status: Complete

##### Summary

The `iocserver` species (`iocrunner` without `P_testusers`) landed in the SOT
with the operator-model document, matching the ansible-provision `iocserver`
species playbook. The `P_proxy` precondition has now landed too: defined in
`docs/OPERATOR_MODEL.md` (`8654990`) alongside the matching ansible-provision
`proxy` role (`a02298f`), completing M2.

##### Scope

- Add `P_proxy` as an optional precondition: not a member of any species
  product, and when present applied unconditionally first, before P_common and
  before every fetch. Record the single authority `bin/proxy_contract.bash`, the
  ADR-defined artifact inventory, and the per-realization fate (Golden seals it,
  Live and Instant keep it).
- Add the realization proxy-fate column and the from-vacuum walkthrough to the
  realization-mode section. Both were drafted in `work/operator-model-pending-B.md`
  but held out of the leaner section M1 shipped, since they depend on the proxy
  notation; M2 adds them now that P_proxy is defined.
- Land the matching ansible-provision `proxy` role in coordination so the
  definition and the role land together. The two live in separate repositories,
  so this is a lockstep sequence, not one change set: the role commits first,
  then the SOT definition.

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
- Role shape confirmed with the ansible-provision session (2026-08-28): the role
  is named `proxy` (`playbooks/operators/proxy.yml`), an optional precondition
  applied first before P_common and every fetch, not a species-product member; it
  applies the ADR-20260820 artifact set by calling this repository's
  `bin/proxy_contract.bash` in apply mode (the third caller of the single
  authority, no reimplementation); mode-fate is Golden seal / Live and Instant
  keep. The role is tracked on the ansible-provision side as their M4/T3 (Build
  `roles/proxy`), planned but unscheduled; my owner has requested they implement
  it so the two can land together.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner-accepted 2026-08-29 after plan, two third-person reviews, and three second-person reviews
Implementation Authorization: owner-authorized 2026-08-29 (ansible-provision `roles/proxy` landed at `a02298f`)
Superseded Plan Artifacts: none

Graft the P_proxy content from `work/operator-model-pending-B.md` onto the
current `docs/OPERATOR_MODEL.md`. draft-B predates several landed changes, so add
only the P_proxy-new material and do not regress the current surroundings
(guards below). Full working checklist: `work/m2-graft-checklist.md`.

1. Intro (defined-terms line): add `precondition` to the list of terms defined
   here.
2. Status of this pass: replace the "P_proxy remains deferred" bullet with one
   stating P_proxy is now defined and lands with its ansible-provision `proxy`
   role. Do not re-announce iocserver or the realization axis as new.
3. Operators intro: add the sentence that a precondition is not a member of any
   product.
4. Add a new `## Preconditions` section (after `## Order dependencies`, before
   `## Species`) with the P_proxy operator row (Role `proxy`), the "why first"
   rationale, the proxy-fate-by-mode bullets, and the optional-vs-first note.
   Drop draft-B's "(ansible role name pending)" qualifier from the Role field -
   the name `proxy` is confirmed (Dependencies).
5. Species intro: add that a species is defined by its operator product alone and
   P_proxy, being a precondition, never appears in a species definition.
6. Realization modes table: add a fourth column, Proxy fate - Golden seal
   (transient), Live and Instant keep (persistent).
7. Add a `### From vacuum to iocserver, without and with proxy` subsection inside
   `## Realization modes` (the with/without-proxy walkthrough).

Regression guards (keep current, ignore draft-B's older form): keep the debian12
vacua and `bare_debian12` rows; keep the plain-English `## Order dependencies`
(never restore the QM `Commutation:` block); keep the `Valid unnamed products`
heading and wording (never "Legal"/"commutation rules"); keep the current
`P_provenance`-bearing first unnamed-product row; keep the current iocserver and
Instant-realization wording.

Landing: the graft is written to match the confirmed `proxy` role one-to-one, but
the commit is held until ansible-provision `roles/proxy` lands, so definition and
implementation land together (M2 Dependencies).

##### Test Plan

| Check | Method |
| --- | --- |
| M2 / T1 | The `P_proxy` artifact inventory in the document matches `ADR-20260820`. |
| M2 / T2 | The ansible-provision `proxy` role applies the artifact set through `bin/proxy_contract.bash`. |

##### Verification Results

- Graft landed (2026-08-29): the seven plan items were added to
  `docs/OPERATOR_MODEL.md` - the `precondition` term, the Status note, the
  Operators-intro sentence, the `## Preconditions` section with the P_proxy row
  (Role `proxy`), the Species-intro sentence, the realization Proxy-fate column,
  and the from-vacuum walkthrough. The regression guards held: debian12 rows,
  the plain-English `## Order dependencies`, `Valid unnamed products`, and the
  current iocserver/Instant wording are all intact (no QM block, no "Legal").
- T1: pass. The document's P_proxy artifact list (shell profile,
  `/etc/environment`, apt/dnf, sudo, sshd, vmadmin ssh environment, pip, system
  git) matches the `ADR-20260820` inventory.
- T2: structurally verified, live apply pending. The ansible-provision `proxy`
  role (`a02298f`) consumes `bin/proxy_contract.bash` in apply mode without
  reimplementation - it stages the script to the target's `/run/cloud-provision`,
  writes the schema-1 input (schema=1/proxy_url/script_sha256), and runs
  `bash "${staged}" apply`, matching the apply-mode contract. A real apply on a
  live proxied host has not been run; it is the ansible-provision side's M4/T3
  live check, tracked there.
- One-to-one map holds: the definition's Role `proxy` and the landed
  `playbooks/operators/proxy.yml` match, both precondition-first over the same
  `proxy_contract.bash` artifact set.
- Completion re-confirmed 2026-09-25: `P_proxy` present in `docs/OPERATOR_MODEL.md`
  (`8654990`), and LAB-ansible-provision confirmed `roles/proxy` and
  `playbooks/operators/proxy.yml` at `a02298f`/`8b9339d`, name and shape matching
  (applied first when proxied, not imported by any species - consistent with the
  definition). Completion criteria 1-3 met; the live apply remains ansible-provision's
  own M4/T3, out of M2's scope.

<a id="m3"></a>
#### M3 - Support Debian 12 as a sixth vacuum

Origin: 3 / M3
Identity History: none
Status: Complete

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
- T2: pass (2026-08-28, after M6 landed the `lab` network). The first attempt
  with `debian-12-genericcloud-amd64.qcow2` failed: the VM booted but cloud-init
  never saw the SATA seed cdrom (hostname stayed `localhost`, no DHCP lease, no
  SSH), while `make debian13.main` succeeded through the identical wiring.
  Owner-directed variant experiment: switching the base image to
  `debian-12-generic-amd64.qcow2` (full driver set) made `make debian12.main`
  complete - SSH ready, cloud-init complete. In-guest readback: hostname
  `lab-debian12-main`, lease 192.168.123.15, all ten template baseline packages
  installed, `en_US.utf8` present. The plan's genericcloud image name is
  superseded by the generic variant for both the `debian12` and
  `debian12-epics-dev` cases (owner-decided 2026-08-28).
- T3: pass (2026-08-28). `make debian12-epics-dev.main` provisioned the
  `epics-dev` VM (192.168.123.45) and `bin/run_epics_env_build.bash -o
  debian12-epics-dev` ran all four operators (common, python, epics_build,
  epics_support) - PLAY RECAP `ok=15 changed=4 unreachable=0 failed=0`. In-guest
  readback confirms layer 1 (EPICS-env 1.3.0 with EPICS base 7.0.10 at
  `/opt/epics/1.3.0/debian-12/7.0.10/base`) and layer 2 (AreaDetector
  `.../modules/ADCore`). This depended on the ansible-provision counterpart: the
  build first skipped every play because `inventory/lab.ini` `[vacua:children]`
  omitted debian12 (operator plays target `hosts: vacua` under `--limit
  epics_dev`); the peer added the `[debian12]` group and the `vacua` membership
  (ansible-provision `35f00fe`), after which the build ran.
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
Status: Complete

##### Summary

`bin/run_epics_env_build.bash` invokes `ansible-playbook` with no `-e` /
`ANSIBLE_OPTS` passthrough, so the build flavor (`epics_env_build_flavor`, e.g.
`gz`) cannot be overridden from the driver; only the ansible-provision make
target (`ANSIBLE_OPTS="-e epics_env_build_flavor=gz"`) can. Surfaced during the
1.3.0 gz step. Minor: the make-target path already works.

##### Scope

- Add a repeatable `-e <key=value>` option to the driver's `ansible-playbook`
  invocation so extra-vars reach the run. (A single `-O "<ANSIBLE_OPTS>"` string
  append was the alternative; the repeatable `-e` was chosen - see Decisions.)

Out of scope: changing the default flavor or the ansible-provision make path.

##### Completion Criteria

- The driver forwards caller-supplied extra-vars, and a gz build can be driven
  through `run_epics_env_build.bash` without editing role defaults.

##### Dependencies And Decisions

- None. Tracked as issue #38.
- Decision (2026-08-29): forward extra-vars as a repeatable `-e <key=value>`
  (option A) rather than a single `-O "<ANSIBLE_OPTS>"` string append (option B).
  A passes one argv token per value with no string word-splitting and mirrors
  ansible-playbook's own flag; B's arbitrary-option generality is not needed for
  the gz flavor and adds quoting risk.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner-accepted 2026-08-29 after plan, three third-person reviews, and two second-person reviews
Implementation Authorization: owner-authorized 2026-08-29
Superseded Plan Artifacts: none

Add a repeatable `-e <key=value>` option to `bin/run_epics_env_build.bash` that
forwards each value to the `ansible-playbook` invocation as its own `-e`
argument (option A: mirrors ansible-playbook's own flag, one argv token per
value, no string word-splitting).

1. Declare `declare -ag EXTRA_VARS=()` alongside the other option variables.
2. Add `e:` to the `getopts` string (`:o:a:d:p:n:i:P:e:h`) and an
   `e) EXTRA_VARS+=("${OPTARG}") ;;` case.
3. Add a usage line: `-e <key=value>  Extra var forwarded to ansible-playbook;
   may be repeated`.
4. Before the `ansible-playbook` call, build `EXTRA_VARS_ARGS` as
   `(-e "<value>" ...)` from `EXTRA_VARS`, and add it to the invocation - before
   the `"${PLAYBOOK}"` argument, since ansible-playbook expects options ahead of
   the playbook path - with the set-u-safe expansion
   `"${EXTRA_VARS_ARGS[@]+"${EXTRA_VARS_ARGS[@]}"}"` (the same guarded form
   `create_vm.bash` uses for `boot_args`), so an empty list does not trip
   `set -u`.

##### Test Plan

| Check | Method |
| --- | --- |
| M5 / T1 | `bin/run_epics_env_build.bash -h` lists the `-e` option and `bash -n bin/run_epics_env_build.bash` is clean. |
| M5 / T2 | With a recording `ansible-playbook` shim first on `PATH` (the outermost boundary only) and a provisioned epics-dev host, the real driver run with `-e epics_env_build_flavor=gz -e foo=bar` forwards exactly `-e epics_env_build_flavor=gz -e foo=bar` into the `ansible-playbook` argv; the same run with no `-e` forwards no extra `-e`. |
| M5 / T3 | A real gz build driven through `bin/run_epics_env_build.bash -e epics_env_build_flavor=gz` against a provisioned epics-dev host produces the gz distribution without editing role defaults (the completion criterion). |

##### Verification Results

- T1: pass (2026-08-29). `bash -n bin/run_epics_env_build.bash` is clean; `-h`
  lists `-e <key=value>`; the unknown-option guard still rejects an unknown flag.
  The four plan steps landed: `EXTRA_VARS` array, `e:` in getopts with its case,
  the usage line, and the `EXTRA_VARS_ARGS` build appended before `"${PLAYBOOK}"`
  with the set-u-safe guarded expansion.
- T2: pass (2026-08-29). Against a provisioned `debian12-epics-dev` host
  (192.168.123.45), with a recording `ansible-playbook` shim first on `PATH`
  (the outermost boundary only), the real driver run with
  `-e epics_env_build_flavor=gz -e foo=bar` recorded the argv
  `... --limit epics_dev -e epics_env_build_flavor=gz -e foo=bar
  playbooks/species/epics_dev.yml` - both extra-vars forwarded verbatim and
  placed before the playbook path. The same run with no `-e` recorded no `-e`
  token. The driver's own `create_vm.bash -s` and inventory generation ran for
  real; only the ansible-playbook binary was replaced.
- T3: pass (2026-08-29). `bin/run_epics_env_build.bash -o debian12-epics-dev -e
  epics_env_build_flavor=gz` drove a real build on the host: the running
  `epics_build` task carried `flavor="gz"` (the forwarded extra-var reached
  ansible), so its `if [ "${flavor}" = "gz" ]; then make build.gz` branch ran
  `make build.gz` - defined in EPICS-env `configure/RULES_SRC` as `conf.gz.base
  build.base conf.gz.modules build.modules`, a distinct gz-configured path, not
  the internal `make build`. PLAY RECAP `ok=15 changed=4 failed=0`; the install
  completed (base, modules, AreaDetector, setEpicsEnv.bash). The flavor was
  selected from the driver without editing role defaults - the completion
  criterion.

<a id="m6"></a>
#### M6 - Define and create the lab libvirt network in the host setup path

Origin: 6 / M6
Identity History: none
Status: Complete

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
Implementation Authorization: owner-authorized 2026-08-28
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

- T1: pass. On this default-only host, `make setup` ran the real shipped path
  and reported `Network lab defined ... marked as autostarted ... started`.
  Read back with `virsh net-dumpxml lab`: `forward mode='nat'`, bridge
  `virbr-lab`, ip `192.168.123.1/24`, DHCP range `.2`-`.254`; `net-list` shows
  `lab active yes autostart yes persistent yes`.
- T2: pass. A real `make debian12.main` run reached and passed the
  `virsh net-update lab` step: the reservation `lab-debian12-main ->
  192.168.123.15` (mac `52:54:00:01:0f:00`) is present in `net-dumpxml lab`,
  with no "network not found" error. Both `make debian13.main` and (after the
  M3 base-image variant fix) `make debian12.main` then completed end to end on
  the `lab` network - SSH ready, cloud-init complete, DHCP leases visible in
  `net-dhcp-leases lab`. An initial debian12 failure past this step was the
  M3 base-image variant issue, recorded under M3 / T2, not an M6 defect.

<a id="m8"></a>

#### M8 - Align the readiness self-tests with the file-based cloud-init probe

Origin: 8 / M8
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

M7 (`690604a`) replaced the `cloud-init status` call in `bin/create_vm.bash`
with a probe that reads `/var/lib/cloud/instance/boot-finished` and
`/var/lib/cloud/data/status.json`. Four self-tests replace the ssh boundary
with a fake that still answers only the literal `cloud-init status` command:
`tests/check-cloud-init-status.bash`,
`tests/check-iocrunner-bake-provenance.bash`,
`tests/check-proxy-injection.bash`, and
`tests/check-epics-env-inventory.bash`. Each fake rejects the probe as an
unexpected command, so every readiness wait spends its full attempt budget
and every `-s` report reads `running`. At `35c859b` this fails
`make check-cloud-init-status`, `make check-bake-provenance`,
`make check-proxy-injection`, `make check-epics-env-inventory` (and so
`make check-runtime-inventory`), and `make check-proxy-lifecycle`, which has
no fake of its own but drives the provenance and proxy-injection tests; through
the last two, `make check-bake` fails. The real VM path is unaffected: M7 /
T1-T3 ran on real VMs, and the rocky8 and debian13 goldens baked on
2026-09-02, 2026-09-03, and 2026-09-06 carry cloud-provision `35c859b`, a
descendant of `690604a`. Observed 2026-09-06 on the control host; the
epics-ioc-runner session reported the check-bake half.

##### Scope

- `tests/fixtures/cloud-init-status/`: probe-output fixtures (`done`,
  `running`, `error`) that follow the parser contract M7 shipped in
  `parse_cloud_init_status` (`bin/create_vm.bash`): the `boot-finished:`
  line followed by a `status.json` body whose per-stage `"errors": [...]`
  lines and top-level `"stage"` line carry the state, with the exact
  `"errors": []` and `"stage": null` spellings that function greps for.
- `tests/check-cloud-init-status.bash`: the fake ssh answers the readiness
  probe from those fixtures; the `-s` and provision cases pin `done`,
  `running`, and `error` (the shipped parser no longer produces `unknown`);
  the eventual-success counter answers `running` until the ready count, then
  `done`; the header comment describes the three states and names
  `wait_for_vm` and its two call-site branches instead of line coordinates.
- `tests/check-iocrunner-bake-provenance.bash`,
  `tests/check-proxy-injection.bash`, `tests/check-epics-env-inventory.bash`:
  each fake ssh answers the readiness probe with the `done` fixture.
- `tests/check-proxy-lifecycle.bash` is not changed; it is expected to pass
  once the two tests it drives pass, and M8 / T2 observes that.

Out of scope: `bin/create_vm.bash` and `parse_cloud_init_status`; the
interactive operator hint in `docs/RUNBOOK_BAKE.md` that runs
`cloud-init status --long` by hand; the silent exit of
`bin/run_epics_env_build.bash` when the `-s` report is not `done`.

##### Completion Criteria

- `make check-cloud-init-status` and `make check-runtime-inventory` pass on
  the control host with the shipped `bin/create_vm.bash` and
  `bin/run_epics_env_build.bash`.
- `make check-proxy-injection` passes on the control host.
- `make check-bake` passes on the control host, including
  `check-bake-provenance` and `check-proxy-lifecycle`.
- The status cases in `check-cloud-init-status.bash` observe `done`,
  `running`, and `error` from probe-shaped input, not from `status:` lines.

##### Dependencies And Decisions

- M7 (behavioral constraint): the fixtures follow the probe and parser M7
  shipped; a later probe change must update the fixtures with it.
- The fixtures pin the parser contract, not a captured `status.json`: no
  supported VM was running when the plan was written, and M8 / T3 proves the
  fixtures drive the real parse path.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner accepted 2026-09-07
Implementation Authorization: owner authorized 2026-09-07
Superseded Plan Artifacts: none

1. Add `tests/fixtures/cloud-init-status/done.txt`, `running.txt`, and
   `error.txt` holding the probe output for a finished boot with no errors,
   an unfinished boot still in `modules-final`, and a finished boot with a
   stage error.
2. `tests/check-cloud-init-status.bash`: match the probe (a remote command
   naming `/var/lib/cloud/instance/boot-finished`) in the fake ssh, keep
   `FAKE_CLOUD_INIT_STATUS_OUTPUT` as the answer, make the ready-after counter
   answer the `running` then the `done` fixture, rewrite the status and
   rejection cases to the three fixture states, and rewrite the header
   comment to name `wait_for_vm` and its two call sites (the shut-off restart
   and fresh-provision branches of the main section) rather than line
   coordinates.
3. `tests/check-iocrunner-bake-provenance.bash`,
   `tests/check-proxy-injection.bash`, `tests/check-epics-env-inventory.bash`:
   match the probe in each fake ssh and answer with the `done` fixture,
   passing the fixture path through the environment each test already gives
   its fakes.
4. Run T1 through T4; run shellcheck on the four test scripts.

##### Test Plan

- T1: `make check-cloud-init-status` on the control host, shipped
  `bin/create_vm.bash`, fakes at the virsh, ssh, and sleep boundary as before:
  every case passes, including `done`, `running`, `error`, and the 61-attempt
  eventual-success case.
- T2: `make check-bake` on the control host: every target passes, including
  `check-bake-provenance` and `check-proxy-lifecycle`, and no failure
  workspace is retained.
- T3 (fixture pin): with `done.txt` temporarily altered to `"stage":
  "modules-final"`, T1's `status done` case fails against the shipped parser,
  proving the fixture drives the real parse path; the fixture is restored
  afterwards.
- T4: `make check-proxy-injection` and `make check-runtime-inventory` on the
  control host: every case passes with the shipped
  `bin/run_epics_env_build.bash` preflight reading `done`.

##### Verification Results

Observed 2026-09-07 on the control host, working tree on top of `35c859b`,
through the shipped make targets (fakes only at the virsh, ssh, and sleep
boundary, as each test already defines):

- T1: pass. `make check-cloud-init-status` 152 / 152, including `status done`,
  `status running`, `status error`, `provision error`, and the 61-attempt
  eventual-success case; shellcheck 0.10.0 reports nothing new on the four
  test scripts (two pre-existing info items are unchanged from `35c859b`).
- T2: pass. `make check-bake` exit 0: fresh-inputs 7 / 7, provenance
  107 / 107, proxy-lifecycle 35 / 35, package-parity 6 / 6, epics-packages
  6 / 6; no failure workspace retained.
- T3: pass. With `done.txt` altered to `"stage": "modules-final"`,
  `make check-cloud-init-status` fell to 139 / 152, and all 13 failures were
  cases that expect the `done` fixture to be read as done (`status done`,
  `provision done`, the IP, ssh, and cloud-init eventual-success cases, and
  `seed exit`), so the fixture reaches the shipped parser; the fixture was
  restored and re-verified.
- T4: pass. `make check-proxy-injection` 145 / 145,
  `make check-runtime-inventory` 2 / 2 (`check-generated-ansible-inventory`
  165 / 165, `check-epics-env-inventory` 2 / 2).

##### Closure Evidence

- Deliverable: cloud-provision `a0c1363` (the four test scripts and
  `tests/fixtures/cloud-init-status/`), verified by T1-T4 above.
- Landing: pushed with the register record `30cb62b`; observed
  2026-09-07T20:16Z that `origin/master` is `30cb62b` and equals the local
  HEAD after `git fetch origin`. All completion criteria met by the
  Verification Results above; no linked issue.

<a id="m11"></a>
#### M11 - Middleware operator/species structure and package baseline (Archiver Appliance + Phoebus)

Origin: e260630 / M11
Status: In progress

##### Summary

The middleware server (the middleware counterpart of the IOC host) hosts the
EPICS Archiver Appliance and Phoebus, each independently selectable, on a base
that carries the EPICS C base. cloud-provision defines the operator/species
structure and the package baseline for it - the normative source ansible-provision
mirrors (its G2). The three application stacks (EPICS, Archiver Appliance,
Phoebus) share one ecosystem form: source -> env (compile) -> distribution ->
install operator.

##### Scope

- Define new operators in `docs/OPERATOR_MODEL.md`: P_java (system OpenJDK 21,
  `JAVA_HOME` set to the distribution JDK path - family-specific, e.g.
  `/usr/lib/jvm/java-21-openjdk-amd64` on debian - aligned with aa-env's
  declarative package list `configure/os/<os>.pkgs` to avoid a double
  definition), P_tomcat (Tomcat 9.0.121 Apache tarball as the shared
  CATALINA_HOME only; the four-instance skeleton stays aa-env's, created by its
  `make install` from `site-template/skel`), P_mariadb (MariaDB server with the
  `archappl` database and user - kept a separable, low-investment module because
  aa-env replaces it entirely with SQLite in Phase 2), P_archiver /
  P_archiver-build (install the aa-distribution WARs, or build aa-maven at its
  freeze tag on the base VM and install), and P_phoebus / P_phoebus-build
  (phoebus-distribution binary, or source build) - each install operator paired
  with a source-build alternative as P_epics is with P_epics-build.
- Define the species: `archiver` (distribution) and `archiver-dev` (source
  build), `phoebus` and `phoebus-dev`, and `middleware` (the selectable
  combination), on a base that includes P_epics.
- Carry the middleware package baseline in `configure/` (system OpenJDK 21,
  Tomcat 9.0.121, MariaDB) as the single source with a guard.
- The middleware VM is provisionable through the existing `create_vm.bash` and
  the `lab` network. The target vacua are debian13 and rocky8 (both families),
  with family-specific handling (the `JAVA_HOME` distribution path and the
  package names differ by family).

##### Out of scope

- Creating and populating the aa-distribution and phoebus-distribution
  repositories (owned by aa-env and phoebus-env); the ansible-provision role
  implementation (its M14); the live verification of the distribution-install
  path, which needs those repositories to exist (tracked as `G1` and `M12`).
- Phoebus source-build tool confirmation and prerequisite reconciliation
  belong to `M13` under `D5`. The aa-maven source build uses its Maven Wrapper
  (`./mvnw`, verified present); Maven is not a separate operator in M11.

##### Completion Criteria

- `docs/OPERATOR_MODEL.md` defines the operators and species above with their
  order and the install/source-build alternative rule.
- `configure/` carries the middleware package baseline with a passing guard.
- The `archiver-dev` (source-build) species resolves on the base VM (structure
  check) - the path that works before the distribution repositories exist.

##### Dependencies And Decisions

- `D2` (2026-09-12): the EPICS-symmetric ecosystem form and the cross-repository
  ownership split.
- `D3` (2026-09-12): system Java, P_epics required, Tomcat 9.0.121, MariaDB
  now / SQLite later, group `mid` / user `mid-srv`, and Maven via the wrapper
  with the source-build prerequisites (`JAVA_HOME`, git, scp, outbound HTTPS,
  `-Dsphinx.skip=true`).
- The aa-maven build structure was confirmed by the aa-maven session on
  2026-09-12 (single-module pom, Maven Wrapper 3.9.9, JDK 21 + `JAVA_HOME`,
  Tomcat not a build dependency; servlet-api line Tomcat 9).
- `D4` (2026-09-28) supplies the accepted T2 verification inputs. At
  epicsarchiverap-maven `2fc12f01`, `.mvn/wrapper/maven-wrapper.properties`
  selects Maven 3.9.16 and `pom.xml` has no Sphinx step. At
  epicsarchiverap-env `d09dca7`, `configure/CONFIG_SRC` selects the source
  checkout's `mvnw`; `configure/RULES_SRC` runs `clean package -DskipTests`
  for `build.mvn`.
  This verifies installation and re-apply behavior; it does not run the
  application's skipped unit tests.
- The java/tomcat/mariadb boundary was coordinated with the aa-env session on
  2026-09-12 and matches its decisions D10-D12 (`docs/milestone-265f580.md`):
  the system JDK with `JAVA_HOME` at the distribution path and java-env dropped
  (D10); Tomcat 9.0.121 runtime, the launcher a script plus a single systemd
  service (D12); MariaDB now, fully replaced by SQLite in Phase 2 (D11). The
  instance skeleton, `server.xml` / `context.xml`, and the schema stay aa-env's;
  the three operators provide only the generic packages and services.
- Reconciliation (cross-repository): the ansible-provision session reconciled
  `G2`/`M14`/`D15` to this plan on 2026-09-13 - its `D16` supersedes the pinned
  non-system OpenJDK/Maven and Phoebus-build substance of `D15`, and `G2`/`M14`
  now name the system Java, wrapper Maven, Tomcat 9.0.121, and MariaDB plan with
  M11 as the source. The reconciliation (`D16`) is landed on the ansible-provision
  branch `m14-middleware-reconcile` (commit `372c333`), pending its merge to
  ansible master; this milestone's G2-reconciliation condition is met only when
  that reconciliation merges to ansible master (durable evidence), not against the
  branch commit. cloud-provision remains the
  source (M11); the ansible session owns that register (single-writer).
- Sub-decisions settled (2026-09-13): target vacua debian13 and rocky8 (both);
  the `mid` group GID is site-assigned (not pinned in the operator); the
  increment scope is the source-build species first (`archiver-dev` /
  `phoebus-dev`), the distribution path deferred to `M12`; repository-wrapper
  Maven (`./mvnw`) is the intended source-build path. It is confirmed for
  aa-maven; the Phoebus assumption remains unverified and belongs to `M13`.
- `D5` (2026-09-29): Phoebus source-build tool confirmation and prerequisite
  reconciliation are separated into `M13`. M11 retains the operator/species
  structure and Archiver Appliance baseline and verification; M13 is not a
  condition for M11 closure.
- Java setup reference: the ALS-U Linux OS Preparation document (`work/`,
  gitignored, kept on both sides) is the implementation-time reference for the
  rocky `alternatives` handling and the JDK package name only; it is not the
  basis for the register (owner ruling 2026-09-13).
- Proxy precondition: when the middleware host is behind the site proxy,
  `P_proxy` applies first (unconditionally, before `P_common` and every fetch),
  as it does for the other species. It is a precondition, not a product member,
  so it is not in the operator list; the source-build's outbound HTTPS (the
  Maven wrapper and dependency downloads) and every package and
  distribution fetch pass through it, and its fate follows the realization mode
  (Golden seals it, Live and Instant keep it). The svg_viewer asset is vendored
  at the D4 source ref.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner accepted 2026-09-13 after the third-person plan review and findings F1-F4; accepted the D4 verification baseline and separate fresh VMs on 2026-09-28; requested live PV storage and retrieval verification on 2026-09-28
Implementation Authorization: owner authorized 2026-09-13 (implement on branch m11-middleware-operators); authorized the checkout fast-forward, D4 update, installation and re-apply on 2026-09-28; authorized live PV storage and retrieval verification on those VMs on 2026-09-28
Superseded Plan Artifacts: none

1. Reflect the operators, species, and order into `docs/OPERATOR_MODEL.md`.
2. Add the middleware package baseline under `configure/` and a guard under
   `tests/` mirroring the existing `check-epics-packages.bash` /
   `check-package-parity.bash` pattern, wired into a `make check-*` target.
3. Structure-check the middleware species; confirm the source-build path on both
   debian13 and rocky8.
4. Verify real host IOC signals through CA, archive storage and retrieval on
   both test VMs, including retrieval of the same historical interval after
   restarting their appliances. Record any required CA address configuration.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Structure | Enumerate the new operators and species in `OPERATOR_MODEL.md`; run the middleware package-baseline guard | control host | Operators, species, and order are defined; the guard passes. |
| T2 | Integration | Apply the full `archiver-dev` species at D4 refs on a fresh VM per family; inspect the deployed source refs, build result, WARs, schema and service; capture installation state before and after the same apply | debian13 and rocky8 | The repository `./mvnw` uses Maven 3.9.16 and builds the four WARs with `clean package -DskipTests`; all four instances run and MariaDB holds the four application tables over its socket. Re-apply reports `ARCHIVER_BUILD_SKIPPED`, with no drift or repair, unchanged build sentinel, config stamp, deployed artifact hashes and service start time, and healthy instances afterwards. `changed=0` alone is insufficient. |
| T3 | Integration | Register two changing host softIoc PVs through `archivePV`; capture live CA events with `camonitor`; query the same UTC interval through `getData.json`; inspect MariaDB PVTypeInfo and nonempty PB files; restart each appliance and repeat the historical query | T2 Debian 13 and Rocky 8.10 VMs at D4 refs, with the host CA address configured where broadcast discovery is insufficient | Both PVs reach connected `Being archived` status. At least 20 events per PV and VM match the live CA values within 1e-12 and timestamps within 1 microsecond. MariaDB retains both PV configurations; archive files exist. The historical event values and full timestamps remain identical after an observed service restart. This is a bounded persistence check, not a long-term retention test. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-09-13 | control host | Passed | `docs/OPERATOR_MODEL.md` carries the 7 operators, 5 species, and 2 produced artifacts (`b2a79c8`); `make check-middleware-packages` reports 2/2 pass with its failure branches (missing coverage, duplicate, empty list, unknown OS, unparseable line) exercised, `shellcheck` clean, and `make check-bake` green (`b71af98`). |
| T2 | 2026-09-29T02:29:22Z | Fresh Debian 13 and Rocky 8.10 VMs, 2 vCPU, 4 GiB RAM and 20 GiB disk each; cloud-provision `83ca6bb`, ansible-provision `b8823c1`, application refs D4 | Passed | The shipped `create_vm.bash -F` and readiness check produced each fresh host; the shipped inventory generator supplied its address, and `make archiver_dev.<vacuum>` applied all eight operators with an exact host limit. Initial apply: Debian `ok=31 changed=11 failed=0 unreachable=0`, Rocky `ok=33 changed=14 failed=0 unreachable=0`. The build journal records Maven 3.9.16, `mvnw ... clean package -DskipTests` and `BUILD SUCCESS`. Deployed refs match D4; four WARs pass archive integrity checks and a class from each matches its deployed webapp. OpenJDK 21, Tomcat 9.0.121, four JVMs under `mid-srv`, an active appliance unit and a valid management API response are present on both. MariaDB has ArchivePVRequests, ExternalDataServers, PVAliases and PVTypeInfo over the family socket, with skip_networking=1 and no TCP 3306 listener. Same-input re-apply: Debian `ok=29 changed=0 failed=0 unreachable=0`, Rocky `ok=31 changed=0 failed=0 unreachable=0`; both report `ARCHIVER_BUILD_SKIPPED` without drift or repair. Before/after checks retain identical four WAR hashes, all 3,555 deployed webapp/config file hashes per host, sentinel/stamp metadata and content, four JVM PIDs, unit MainPID, invocation ID and start timestamps; the management API and schema checks pass again. |
| T3 | 2026-09-29T03:39:51Z | T2 VMs and D4 application refs; existing host softIoc supplies M33:CNT and M33:SIN over CA | Passed | Both PVs reached connected `Being archived` status with MONITOR and a 1-second sampling period. For the UTC query interval 03:37:14.357494-03:37:43.857445 on 2026-09-29, `getData.json` returned HTTP 200 and matched 29 real `camonitor` events per PV on each VM, within 1e-12 for values and 1 microsecond for CA timestamp formatting. Both PV names were present in MariaDB PVTypeInfo and had nonempty STS PB files. Both appliance services were restarted successfully; their MainPID and invocation ID changed. Queries of the same interval returned all 58 matched events per VM with identical full-event SHA-256 digests before and after restart. MariaDB PV registrations persisted, nonempty PB files remained, and connected PV status reported new events after restart. |

T3 configuration: Debian used the installed `EPICS_CA_ADDR_LIST=localhost`
and `EPICS_CA_AUTO_ADDR_LIST=YES`. On Rocky, that discovery configuration did
not connect to the host PVs, while a direct CA query to the host gateway did.
The Rocky test VM's installed `archappl.conf` now explicitly sets
`EPICS_CA_ADDR_LIST=192.168.123.1`; its previous file is retained alongside it
as `archappl.conf.m11-pv-before`. This is a test VM configuration change;
the provisioning inputs were not changed. The firewall configuration was
not changed. The host IOC was read only.

T3 raw CA output, API responses, DB/file observations, restart records and
the executed `verify_archive.py` are retained under the ignored
`work/m11-t2-20260928.axZaVF/` directory. The result covers a bounded interval
and graceful appliance restart; it does not establish long-term retention
or recovery from a power failure.

The control-host recheck on 2026-09-29 UTC passed
`make check-middleware-packages` (2/2) and `make check-docs` (12/12).
The application build uses its shipped `-DskipTests` path; this result is
installation and re-apply evidence, not an application unit-test result.

##### Closure Evidence

T1, T2 and T3 verification passed. The D4 and PV verification records were
committed in `794eb6b`. The cloud-provision branch and the ansible-provision
reconciliation have not merged to their respective master branches. M11 remains In progress until
those landing conditions are met. The two verification VMs remain available;
their removal is a separate action.

<a id="m12"></a>
#### M12 - Verify the middleware distribution-install path (P_archiver, P_phoebus)

Origin: e260630 / M12
Status: Blocked

##### Summary

Once the aa-distribution and phoebus-distribution repositories exist (`G1`), the
distribution-install operators defined in `M11` (`P_archiver`, `P_phoebus`) and
their `archiver` / `phoebus` species can be verified live: install the built
WARs and the Phoebus binary on the middleware host. `M11` delivers the structure
and the source-build path; this row is the deferred distribution-path
verification, which cannot run before the repositories exist.

##### Scope

- Live-apply the `archiver` (distribution) species and the `phoebus`
  (distribution) species on the middleware VM, confirming the WARs and the
  Phoebus binary install from their distribution repositories and a re-apply is
  idempotent.

Out of scope: defining the operators/species (that is `M11`); producing the
distribution repositories (owned by aa-env and phoebus-env).

##### Completion Criteria

- The `archiver` and `phoebus` distribution species install and re-apply
  idempotently on the middleware VM against real distribution repositories.

##### Dependencies And Decisions

- `G1` (Open): the two distribution repositories must exist and carry their
  artifacts. This row is Blocked until `G1` is Complete, then resumes as Not
  started.
- Depends on `M11` for the operator and species definitions.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. After `G1`, live-apply the distribution species on the middleware VM.
2. Record the per-species install and idempotency evidence.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Live-apply the `archiver` distribution species | middleware VM | The aa-distribution WARs install and deploy to the Tomcat instances; a re-apply is idempotent. |
| T2 | Integration | Live-apply the `phoebus` distribution species | middleware VM | The phoebus-distribution binary installs and configures; a re-apply is idempotent. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | pending | middleware VM | Not run | |
| T2 | pending | middleware VM | Not run | |

<a id="m13"></a>
#### M13 - Confirm the Phoebus source-build tool and reconcile its prerequisites

Origin: e260630 / M13
Identity History: none
GitHub Issue: none
Status: Not started

##### Summary

Confirm the actual build tool used by phoebus-env and its source checkout,
then align the Phoebus source-build prerequisites in `docs/OPERATOR_MODEL.md`
and the middleware package baseline with that evidence. The current model
intends a repository Maven Wrapper, but that assumption is unverified.
This work is separated from M11 under D5.

##### Scope

- Inspect phoebus-env at a recorded source ref, its `make build.phoebus`
  entry point, and the delegated Phoebus source build invocation.
- Confirm the tool, wrapper or system-package acquisition, JDK requirement,
  `JAVA_HOME` handling, and other required build prerequisites against the
  actual source and configuration.
- Reconcile the `P_phoebus-build` and `P_java` descriptions in
  `docs/OPERATOR_MODEL.md` and the relevant comments or package requirements
  in `configure/middleware-packages` with the confirmed source-build path.

Out of scope: creating or populating phoebus-distribution (`G1`), verifying
distribution installation (`M12`), implementing ansible-provision roles,
building or running the full Phoebus application, and repeating the M11
Archiver Appliance verification.

##### Completion Criteria

- An immutable phoebus-env source ref and its delegated source ref identify
  the actual build invocation and prerequisite evidence.
- The repository-wrapper assumption is confirmed or corrected; the operator
  model and middleware package baseline agree with the observed build path.
- The shipped middleware package and documentation checks pass against the
  resulting definitions.

##### Dependencies And Decisions

- `D2` and `D3` supply the ecosystem structure and system-Java baseline.
- `D5` (2026-09-29) assigns Phoebus source-build tool confirmation and
  prerequisite reconciliation to this independent milestone.
- The unresolved M11 hypothesis is retained here: aa-maven's `./mvnw` is
  confirmed present, but phoebus-env was not cloned locally when the model
  was defined. Whether Phoebus uses its intended repository wrapper or the
  site document's `maven-openjdk21` remains to be confirmed from its source.
- Source inspection does not require the M11 master merges or the G1
  distribution repositories. M11 and M12 do not depend on M13.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Record the source refs and inspect the real build entry point and tool
   configuration through the delegated source build.
2. Confirm the prerequisites and reconcile the operator model and middleware
   package baseline where the source evidence requires a change.
3. Run the shipped checks and record the source evidence and check results.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Structure | Inspect `make build.phoebus`, its delegated build invocation and tool configuration at recorded immutable refs | phoebus-env and its source checkout | The actual tool, acquisition path, JDK and other prerequisites are identified from shipped source files. |
| T2 | Structure | Compare `P_phoebus-build`, `P_java` and `configure/middleware-packages` with T1 evidence; run `make check-middleware-packages` and `make check-docs` | control host | The definitions agree with the source evidence and both shipped checks pass. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | phoebus-env and its source checkout | Pending | none |
| T2 | Not run | control host | Pending | none |

##### Closure Evidence

- None.

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

<a id="m14"></a>
#### M14 - Allow password-free sudo validation on the two dedicated verification VMs

Origin: e260630 / M14
Identity History: none
GitHub Issue: [#45](https://github.com/jeonghanlee/cloud-provision/issues/45)
Status: Complete

##### Summary

The dedicated Debian 13 and Rocky 8.10 verification guests allow
`sudo -n true` and `sudo -n id -u`, but reject `sudo -n -v` with a password
requirement. Their `vmadmin` accounts have both password-required group
grants and a cloud-init `NOPASSWD` grant. The default `verifypw=all` requires
all matching grants to be password-free for validation.

##### Scope

- Add `Defaults:vmadmin verifypw=any` in a root-owned, mode-0440 sudoers
  drop-in on the two dedicated guests.
- Verify validation without an existing sudo timestamp, ordinary sudo,
  effective grants, and the full sudoers configuration.
- Update the private guest handoff with the observed SSH and sudo behavior.

Out of scope: changing templates or golden images, other guests, SSH keys,
passwords, other users' privileges, application setup, and the Rocky include
ordering change owned by M15.

##### Completion Criteria

- Both guests pass `sudo -k` followed by `sudo -n -v` without a password.
- `sudo -n true` succeeds and `sudo -n id -u` returns 0 on both guests.
- `sudo -n visudo -c` succeeds and `sudo -n -l` retains the existing grants.
- The private handoff records dated results and the guest configuration;
  the linked issue is closed or a dated closure exception is recorded.

##### Dependencies And Decisions

- D1 requires an accepted and explicitly authorized plan for existing guests.
- D6 sets the target pair and per-user policy. M15 is independent: changing
  include ordering is not required for the drop-in to be read.
- The observation on 2026-09-30 at 02:03 UTC established ordinary sudo success,
  validation failure, and valid sudoers syntax on both guests. Exact private
  coordinates are retained in the local handoff, outside the public repository.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-09-30; the owner accepted the current guest-only M14 plan by directing its execution after the plan and issue were prepared.
Implementation Authorization: 2026-09-30; explicit owner direction to execute M14 on the two dedicated verification guests.
Superseded Plan Artifacts: none

1. Confirm the dedicated guest identities and current sudo configuration;
   retain a private baseline and check for concurrent sudoers changes.
2. Stage a single per-user directive in
   `/etc/sudoers.d/91-cloud-provision-validation`, validate the candidate,
   and install it as root with mode 0440. Do not overwrite unrelated files.
3. Validate the full configuration; restore the prior state if validation
   fails. Invalidate the sudo timestamp, run the real sudo checks, and
   record the results and refreshed handoff.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Execute `sudo -k` and then `sudo -n -v` as `vmadmin` over SSH | Dedicated Debian 13 and Rocky 8.10 verification guests | Validation succeeds without a password or cached timestamp. |
| T2 | Integration | Execute `sudo -n true`, `sudo -n id -u`, `sudo -n -l`, and `sudo -n visudo -c`; inspect drop-in ownership and mode | Same two guests | Ordinary sudo succeeds, UID is 0, existing grants remain, syntax is valid, and the drop-in is root-owned with mode 0440. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-10-01T05:22:30Z | Dedicated Debian 13 and Rocky 8.10 verification guests | Passed | Real SSH sessions ran `sudo -k` followed by `sudo -n -v` successfully on both guests. A second `sudo -k` followed by plain `sudo -v` with closed stdin also succeeded. Before the change, the actual `sudo -n -v` returned 1 with a password requirement on both guests. |
| T2 | 2026-10-01T05:22:30Z | Same two guests | Passed | `sudo -n true` succeeded, `sudo -n id -u` returned 0, and full `sudo -n visudo -c` parsed every included file. The effective grant lines are identical before and after. The new drop-in is a root-owned regular file with mode 0440 and contains exactly `Defaults:vmadmin verifypw=any`. All pre-existing sudoers files retain their SHA-256 hashes, including each main file and application drop-ins. Rocky's new file received its restored SELinux context; temporary stage files are absent. |

##### Closure Evidence

- Guest configuration and T1/T2 verification passed on 2026-10-01 at
  05:22:30 UTC. The private access handoff records the current policy and
  observations. Only the new per-user drop-in was installed; main sudoers
  and all earlier drop-ins were preserved.
- The verification record was committed as
  `3517a236a5e809ed41f103fc1c64b9d6409437b5` and pushed to
  `origin/m11-middleware-operators`; the remote branch SHA was verified.
- GitHub issue #45 received the verified results and all four completed
  acceptance criteria, then closed as completed at 2026-10-01T05:42:20Z.
  Its closed state was rechecked with `gh issue view 45` at
  2026-10-01T05:44:05Z. All M14 completion criteria are satisfied;
  the independent M15 include-order change remains outside this scope.

##### GitHub Projection

Title: Allow password-free sudo validation on verification VMs
Labels: bug
GitHub Milestone: 1 / Nimbus - Cloud Provisioning Reliability
Observed State: closed
Observed Labels: bug
Observed Milestone: 1 / Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-10-01T05:44:05Z; remote updated 2026-10-01T05:42:20Z

<a id="m15"></a>
#### M15 - Put the Rocky sudoers includedir after all active rules

Origin: e260630 / M15
Identity History: none
GitHub Issue: [#46](https://github.com/jeonghanlee/cloud-provision/issues/46)
Status: Not started

##### Summary

The dedicated Rocky 8.10 verification guest has a valid sudoers configuration,
but its `#includedir /etc/sudoers.d` directive is followed by an active
`rocky` NOPASSWD grant. IOC-runner's shipped
`verify_sudoers_includedir_order` requires that no active rule follow the
drop-in include. Moving the directive preserves the existing grant while
making the file satisfy that prerequisite.

##### Scope

- Move the existing `/etc/sudoers.d` include to the final active position in
  the dedicated Rocky guest's `/etc/sudoers`.
- Preserve every existing grant, including the `rocky` NOPASSWD grant, and
  existing drop-ins.
- Verify syntax, file integrity outside the directive movement, ordering,
  and ordinary sudo; update the private guest handoff.

Out of scope: changing templates or golden images, the Debian guest, other
guests, application setup, and the per-user validation policy owned by M14.

##### Completion Criteria

- The include appears once and no active sudoers rule follows it.
- The existing `rocky` grant and all other rules are unchanged.
- Full `visudo -c` validation succeeds, ordinary sudo succeeds, and effective
  grants remain available.
- The private handoff records the dated configuration result; the linked
  issue is closed or a dated closure exception is recorded.

##### Dependencies And Decisions

- D1 requires an accepted and explicitly authorized plan for the existing guest.
- D6 fixes the target and preserves the existing grant. M14 is independent.
- The 2026-09-30 02:03 UTC observation found the trailing active `rocky` grant
  and passing syntax validation. The ordering requirement is in the shipped
  `epics-ioc-runner/bin/setup-system-infra.bash` function
  `verify_sudoers_includedir_order`; syntax validity alone does not establish
  that prerequisite.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Confirm the dedicated Rocky guest and retain a root-owned sudoers backup
   outside the drop-in directory; check for concurrent file changes.
2. Stage the original file with only the include directive moved after all
   active rules. Compare all remaining bytes and validate the candidate.
3. Install the validated file, preserving permissions and the SELinux context;
   validate the full configuration and restore the backup on failure.
4. Inspect the actual file ordering, verify ordinary sudo and retained grants,
   and record the result and refreshed handoff. Do not run application setup.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Configuration | Compare the original and installed `/etc/sudoers` after excluding the moved include directive; inspect its final active position | Dedicated Rocky 8.10 verification guest | All other bytes are preserved, the include appears once, and no active rule follows it. |
| T2 | Integration | Execute `sudo -n visudo -c`, `sudo -n true`, `sudo -n id -u`, and `sudo -n -l`; inspect ownership, mode, and SELinux context | Same Rocky guest | Syntax is valid, ordinary sudo succeeds, UID is 0, grants remain, and file metadata is preserved. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Dedicated Rocky 8.10 verification guest | Pending | none |
| T2 | Not run | Same Rocky guest | Pending | none |

##### Closure Evidence

- None.

##### GitHub Projection

Title: Move the Rocky sudoers includedir after active rules
Labels: bug
GitHub Milestone: 1 / Nimbus - Cloud Provisioning Reliability
Observed State: open
Observed Labels: bug
Observed Milestone: 1 / Nimbus - Cloud Provisioning Reliability
Last Compared: 2026-09-30T06:03:39Z; remote updated 2026-09-30T06:03:23Z

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Host setup | M7 | Restore the VM readiness preflight against cloud-init 23.4 | Milestone | Complete | No |  | `create_vm.bash -s` and the epics-dev build driver read a post-OS-update VM as ready, not `cloud-init: unknown`; [M7 detail](#m7). |
| Documentation | M9 | Replace the unprivileged cloud-init status hint in the bake runbook | Milestone | Complete | No | M7 | The `docs/RUNBOOK_BAKE.md` slow-boot hint works unprivileged on a VM carrying the rebuilt cloud-init or states the privilege it needs; [M9 detail](#m9). |
| Driver ergonomics | M10 | Report the refused host when the epics-dev build preflight fails | Milestone | Complete | No | M8 | A not-ready VM makes `bin/run_epics_env_build.bash` exit with a message naming the OS type and showing the `-s` report instead of exiting silently; [M10 detail](#m10). |

### Backlog Details

<a id="m7"></a>
#### M7 - Restore the VM readiness preflight against cloud-init 23.4

Origin: found 2026-08-31 during the ansible-provision M5 source-build verification
Identity History: none
GitHub Issue: [#39](https://github.com/jeonghanlee/cloud-provision/issues/39)
Status: Complete

##### Summary

When a VM runs the epics_build role, its in-build `dnf update` upgrades
cloud-init to 23.4 (`cloud-init-23.4-7.el8_10.11.0.2` observed on rocky8). On
that version an unprivileged `cloud-init status` aborts with
`PermissionError: [Errno 13] Permission denied: '/run/cloud-init/cloud.cfg'`
instead of printing a status word. `bin/create_vm.bash -s` and the
`bin/run_epics_env_build.bash` preflight both parse that output; the traceback
reads as `cloud-init : unknown`, so the driver refuses the host and exits
before running any play. Fresh-VM provisioning is unaffected because the base
image ships an older cloud-init; the defect only appears when re-running a
status check or the build driver against a VM that has already taken the OS
update. Observed while verifying ansible-provision M5 on the standing rocky8
epics-dev VM.

##### Scope

- Make the readiness check tolerant of a cloud-init that cannot report status
  as the invoking user - read the status with sufficient privilege, or treat an
  unreadable `/run/cloud-init` as "already booted" rather than "unknown".
- Cover both `bin/create_vm.bash` (`-s`) and the driver preflight in
  `bin/run_epics_env_build.bash`.

Out of scope: changing what cloud-init writes, or the fresh-boot provisioning
path, which is unaffected.

##### Completion Criteria

- `create_vm.bash -s` against a VM carrying cloud-init 23.4 reports the real
  readiness, not `unknown`.
- The epics-dev build driver runs its play against such a VM instead of exiting
  at preflight.

##### Dependencies And Decisions

- No dependency on other milestones. Discovered during ansible-provision M5;
  does not block that work, whose acceptance runs use fresh VMs.
- Root cause refined (Decision Date 2026-09-01): the regression is the
  `23.4-7.el8_10.11.0.2` RHEL rebuild tightening `/run/cloud-init` to `0700`,
  not cloud-init 23.4 in general. The base image ships `23.4-7.el8_10.0.1`,
  whose unprivileged status still works; `dnf update` in the epics_build role
  installs the rebuild.
- Approach decided (Decision Date 2026-09-01): full replacement of the
  privileged `cloud-init status` call with a non-privileged read of two
  world-readable files, verified present on `23.4-7.el8_10.0.1`,
  `23.4-7.el8_10.11.0.2`, and `25.1.4`.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner accepted 2026-09-01
Implementation Authorization: owner authorized 2026-09-01
Superseded Plan Artifacts: none

Approach: full replacement of the privileged `cloud-init status` call with a
non-privileged read of two world-readable files cloud-init writes on every
supported version:

- `/var/lib/cloud/instance/boot-finished` - existence marks a finished boot.
- `/var/lib/cloud/data/status.json` - per-stage `errors` and top-level `stage`.

`parse_cloud_init_status` is rewritten to derive the status word from those two
signals in pure bash (no jq): non-empty `errors` gives `error`; `boot-finished`
present with `stage: null` gives `done`; otherwise `running`. Both call sites
(`print_status_report`, `wait_for_cloud_init`) fetch the two signals over one
`ssh_probe` command instead of running `cloud-init status`. The epics-dev build
driver consumes the `-s` report unchanged.

##### Test Plan

- T1: on the rocky8 epics-dev VM (cloud-init `23.4-7.el8_10.11.0.2`),
  `create_vm.bash -s` reports cloud-init `done`, not `unknown`.
- T2: the epics-dev build driver preflight against that VM generates the
  runtime inventory and reaches the play instead of exiting at preflight.
- T3 (regression): `-s` against fresh rocky8 (`23.4-7.el8_10.0.1`) and fresh
  debian13 (`25.1.4`) still reports `done`.

##### Verification Results

Observed 2026-09-01 on real running VMs via the shipped `create_vm.bash -s`
path (no stubs or mocks):

- T1 - rocky8 epics-dev, cloud-init `23.4-7.el8_10.11.0.2`: `-s` reports
  `cloud-init : done`, exit 0 (was `unknown` before the change).
- T2 - `run_epics_env_build.bash -o rocky8-epics-dev` run end-to-end against
  that VM: passes preflight, runs `playbooks/species/epics_dev.yml` on the
  `epics_dev` host, and the play converges - PLAY RECAP ok=15, changed=0,
  failed=0, unreachable=0, driver exit 0.
- T3 (regression) - fresh rocky8 (`23.4-7.el8_10.0.1`) and fresh debian13
  (`25.1.4`): both report `done`, exit 0.

##### Closure Evidence

Deliverable: cloud-provision `690604a` (`bin/create_vm.bash`), pushed to
origin/master. All completion criteria met by the Verification Results above,
observed 2026-09-01 on the real `create_vm.bash -s` and
`run_epics_env_build.bash` paths. GitHub issue #39 closed on this evidence.

<a id="m9"></a>

#### M9 - Replace the unprivileged cloud-init status hint in the bake runbook

Origin: 9 / M9
Identity History: none
GitHub Issue: [#40](https://github.com/jeonghanlee/cloud-provision/issues/40)
Status: Complete

##### Summary

`docs/RUNBOOK_BAKE.md` (section "Slow boot and package-manager diagnosis")
tells the operator to read the live cloud-init state with an unprivileged `ssh
... cloud-init status --long`. That is the same unprivileged call M7 replaced
in `bin/create_vm.bash`: the `23.4-7.el8_10.11.0.2` rebuild ships a tmpfiles
rule that sets `/run/cloud-init` to 0700 when the package is upgraded in place,
and until the next reboot the call aborts with a PermissionError instead of a
status word (cloud-init resets the directory to 0755 at every boot; mechanism
recorded in docs/CLOSED_DOORS.md). In this repository only the epics_dev
species upgrades cloud-init in place, so the hint works during a bake today and
fails on an epics-dev guest between its build and its next reboot. Found
2026-09-06 during the M8 review.

##### Scope

- Reword the hint to `sudo cloud-init status --long`, which keeps the
  section's convention (its dnf log commands already run under `sudo`); fall
  back to reading the two world-readable files the readiness probe reads
  (`/var/lib/cloud/instance/boot-finished` and
  `/var/lib/cloud/data/status.json`), or to keeping the command with a note
  on when it fails, only if the privileged call is not acceptable there.
- Apply the chosen wording to the runbook section and keep
  `make check-docs` passing.

Out of scope: `bin/create_vm.bash` and the readiness probe; any change to
what cloud-init writes.

##### Completion Criteria

- The runbook hint works as an unprivileged operator command on a rocky8 VM
  that carries the rebuilt cloud-init, or states the privilege it needs.
- `make check-docs` passes.

##### Dependencies And Decisions

- M7 (behavioral constraint): the readiness probe M7 shipped is the reference
  for what an unprivileged read can rely on.
- Decision Date 2026-09-07: proceed; the row moves from Open to Not started
  and a GitHub issue projects it.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner accepted 2026-09-07
Implementation Authorization: owner authorized 2026-09-07
Superseded Plan Artifacts: none

1. Confirm on a rocky8 VM with the rebuilt cloud-init (a rocky8-epics-dev
   VM after the epics_build role's `dnf update`, the VM M7 / T1 used) that
   `sudo cloud-init status --long` prints a status, then reword the runbook
   hint to that form; take one of the two fallbacks in Scope only if the
   privileged call is not acceptable.

##### Test Plan

- T1: run the reworded hint as `vmadmin` against a rocky8 VM carrying
  `cloud-init-23.4-7.el8_10.11.0.2`; it prints a status, not a traceback.
- T2: `make check-docs` passes.

##### Verification Results

Observed 2026-09-07 on the control host against the rocky8 epics-dev VM
(`cloud-init-23.4-7.el8_10.11.0.2`), through the exact runbook command run
as `vmadmin`:

- T1: pass. `ssh ... vmadmin@<vm-ip> sudo cloud-init status --long` printed
  `status: done` (exit 0) with `/run/cloud-init` at 0755 (booted state) and
  again at 0700 (after `systemd-tmpfiles --create`, the state an in-place
  upgrade leaves); in the 0700 state the previous unprivileged form exited 1
  with the PermissionError. The directory was restored to 0755 afterwards.
- T2: pass. `make check-docs`: check-doc-refs 4 / 4, check-proxy-doc-statements
  8 / 8.

##### Closure Evidence

- Deliverable: cloud-provision `bd3a6e2` (`docs/RUNBOOK_BAKE.md`), verified by
  T1-T2 above and landed on origin/master. The tmpfiles inconsistency
  behind the failure is recorded as a Closed Door (2026-09-08) and routed to
  ansible-provision.

<a id="m10"></a>

#### M10 - Report the refused host when the epics-dev build preflight fails

Origin: 10 / M10
Identity History: none
GitHub Issue: [#41](https://github.com/jeonghanlee/cloud-provision/issues/41)
Status: Complete

##### Summary

`bin/run_epics_env_build.bash` runs under `set -euo pipefail` and captures the
readiness report with `status_report="$(create_vm.bash ... -s)"`. When the VM
is not ready, `-s` returns 1, `set -e` aborts the driver at that assignment,
and the `die "failed to generate runtime inventory ..."` branch that would name
the OS type never runs: the driver exits 1 with nothing on stdout or stderr.
Observed 2026-09-06 on the control host while the M8 fake answered `cloud-init
: running` (the same path a real not-ready VM takes); the mechanism is read
from the driver source. Priority decided 2026-09-08: proceed.

##### Scope

- Make the driver print the captured `-s` status report and name the refused
  OS type before exiting when the readiness preflight fails. The change is
  confined to the runtime-inventory loop in `bin/run_epics_env_build.bash`;
  the existing `cleanup_runtime_inventories` EXIT trap already removes the
  temp inventory on the new exit path.

Out of scope: the readiness probe and `-s` report format in
`bin/create_vm.bash`; the inventory generator; the ansible play invocation.

##### Completion Criteria

- A not-ready VM makes the driver exit non-zero with a message naming the OS
  type and showing the `-s` report.
- `make check-runtime-inventory` still passes.

##### Dependencies And Decisions

- M8 (behavioral constraint): `tests/check-epics-env-inventory.bash` is the
  offline path that can pin the refusal message with a `running` fixture.
- Decision Date 2026-09-08: proceed; the row moves from Open to Not started.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner accepted 2026-09-08
Implementation Authorization: owner authorized 2026-09-08
Superseded Plan Artifacts: none

1. In the runtime-inventory loop, replace the plain
   `status_report="$(create_vm ... -s)"` assignment (which `set -e` aborts on
   a non-zero `-s`) with a captured-status form: set `rc=0`, then
   `status_report="$(create_vm ... -s)" || rc=$?`. `create_vm -s` prints the
   full readiness report to stdout even when it returns non-zero, so
   `status_report` holds the report; when `rc` is non-zero, print that report
   to stderr and `die` naming the OS type.
2. Add a refusal case to `tests/check-epics-env-inventory.bash`: invoke the
   driver with its fake ssh answering the readiness probe from the `running`
   fixture in `tests/fixtures/cloud-init-status/`, capturing both streams.
   Assert the driver exits non-zero, its output names the refused selector
   (`rocky8-epics-dev`, the first default OS type), and carries the report
   line `cloud-init : running`.

##### Test Plan

- T1: `make check-runtime-inventory` still passes on the ready path, where
  the fake ssh answers the `done` fixture and the driver reaches the play.
- T2: the new refusal case passes: with the fake answering the `running`
  fixture, the driver exits non-zero, names `rocky8-epics-dev`, and its
  captured output contains the report line `cloud-init : running`.

##### Verification Results

Observed 2026-09-08 on the control host through the shipped offline suite
(fakes only at the virsh, ssh, and sleep boundary); shellcheck 0.10.0 clean on
both edited scripts.

- T1: pass. `make check-runtime-inventory`: check-generated-ansible-inventory
  165 / 165 and check-epics-env-inventory's ready path both pass; the driver
  reaches the play with the fake answering the `done` fixture.
- T2: pass. The new refusal case: with the fake answering the `running`
  fixture, the driver exits non-zero, its captured output names
  `rocky8-epics-dev`, and it carries the report line `cloud-init : running`.
  Pinning confirmed by mutation: reverting only the driver fix makes the
  refusal assertions fail (check-epics-env-inventory exits 1); the fix was
  restored intact.

##### Closure Evidence

- Deliverable: cloud-provision `0daf2f6` (`bin/run_epics_env_build.bash` and
  `tests/check-epics-env-inventory.bash`), T1-T2 above pass on the shipped
  offline path. The commit carries `Closes #41`, so #41 auto-closes when it
  lands on origin/master.

## Assignment History

| Date | Movement | Note |
| --- | --- | --- |
| 2026-09-25 | M12: Backlog to Milestone | Assigned to the middleware line; stays Blocked on G1 and resumes as Not started when G1 completes. |
| 2026-09-29 | M4: Backlog to Milestone | Assigned with its complete row and detail in this synchronization commit; Origin, ID, Deferred status, plan and verification evidence are preserved. |

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-27 | e260630b1ab3cb3541eb8cae7b58b2ab2ab68259 |
