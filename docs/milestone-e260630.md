# Work Register

Remote tracker: `jeonghanlee/cloud-provision` GitHub milestone 1

Next session entry point: the only open milestone is M2 (the `P_proxy`
precondition) - its definition is landed and matches the ansible-provision
`proxy` role (`a02298f`) one-to-one, M2 / T1 passed, and its single remaining
check is M2 / T2's live apply on a real proxied host (the ansible-provision
side's M4/T3 live check, gated on the idev whitelist). M1, M3, M5, and M6 are
Complete; EtherCAT (M4) stays Deferred in the Backlog.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Operator model | M1 | Split the operator definition into its own normative document and add the realization-mode and produced-artifact framing | Milestone | Complete | No |  | `docs/OPERATOR_MODEL.md` carries the operator, species, and vacua definitions verbatim, `docs/IMAGE_WORKFLOW.md` points to it, and the realization-mode axis and produced-artifact node are added; committed as `e260630`; [M1 detail](#m1). |
| Operator model | M2 | Add the P_proxy precondition, landing with its ansible-provision proxy role | Milestone | In progress | No | M1 | `docs/OPERATOR_MODEL.md` defines `P_proxy` (optional, unconditionally-first precondition) and the matching ansible-provision `proxy` role exists so definition and implementation land together; the `iocserver` species already landed; [M2 detail](#m2). |
| OS coverage | M3 | Support Debian 12 as a sixth vacuum, bare and epics-dev | Milestone | Complete | No | M1 | Debian 12 is wired as a vacuum (definition, template, package source, guard) and as the `debian12-epics-dev` variant, a real bare provision installs P_common, and the epics-dev variant builds layers 1+2; [M3 detail](#m3). |
| Driver ergonomics | M5 | Add an extra-vars (ANSIBLE_OPTS) passthrough to the epics-dev build driver | Milestone | Complete | No |  | `bin/run_epics_env_build.bash` forwards extra-vars so the build flavor (e.g. gz) is selectable from the driver, not only via the ansible-provision make target; [M5 detail](#m5). Refs #38. |
| Host setup | M6 | Define and create the `lab` libvirt network in the host setup path | Milestone | Complete | No |  | `bin/setup_host.bash` defines and activates the `lab` network (192.168.123.0/24) from a shipped definition when absent, so a host with only the libvirt `default` network can provision lab vacua; unblocks M3 / T2 and M3 / T3; [M6 detail](#m6). |

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
Status: In progress

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

## Backlog

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EtherCAT | M4 | Validate EtherCAT use of the shared image workflow and proxy seal | Carry-forward | Deferred | No | D1 | A real EtherCAT bake, fresh consumer selection, value-redacting proxy check, and separately authorized image audit are observed on supported Libvirt/KVM; [M4 detail](#m4). |
| Host setup | M7 | Restore the VM readiness preflight against cloud-init 23.4 | Milestone | Not started | Yes |  | `create_vm.bash -s` and the epics-dev build driver read a post-OS-update VM as ready, not `cloud-init: unknown`; [M7 detail](#m7). |

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

<a id="m7"></a>
#### M7 - Restore the VM readiness preflight against cloud-init 23.4

Origin: found 2026-08-31 during the ansible-provision M5 source-build verification
Identity History: none
GitHub Issue: [#39](https://github.com/jeonghanlee/cloud-provision/issues/39)
Status: Not started

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

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-08-27 | e260630b1ab3cb3541eb8cae7b58b2ab2ab68259 |
