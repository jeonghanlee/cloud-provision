# Milestone Register

Next session entry point: boot `rocky8-iocrunner.server` from `/home/jeonglee/libvirt/images/iocrunner-rocky8.qcow2` and rerun the downstream ioc-runner validation that previously reported the Rocky 8 sudoers `includedir` failure.

This register tracks repository work status and handoff state. Golden qcow2
artifacts live under `IMAGE_DIR` and are not committed to this repository.

## Work Register

| Topic | Work unit | Type | Status | Evidence or next action |
| --- | --- | --- | --- | --- |
| iocrunner golden images | Rocky 8 golden refresh | Milestone | Complete | `make bake.rocky8` completed on 2026-06-03. Output `/home/jeonglee/libvirt/images/iocrunner-rocky8.qcow2` is qcow2, 20 GiB virtual, 4.43 GiB disk, and `corrupt: false`; `base_os` sudoers `includedir` ordering reported `changed` during bake. |
| iocrunner golden images | Rocky 8 post-bake validation | Carry-forward | Open | Boot with `make rocky8-iocrunner.server` and rerun the system-infra and system-lifecycle checks that previously saw one sudoers ordering failure on the 2026-05-13 Rocky 8 golden. |
| iocrunner golden images | Debian 13 current golden check | Milestone | Complete | Current Debian 13 golden was observed clean for setup 8/8 and system-infra 41/41; prior `acl` and `logrotate` omissions are not observed on this golden. |
| iocrunner golden images | 2026-05-13 Rocky 8 sudoers defect | Carry-forward | Complete | Superseded by the 2026-06-03 Rocky 8 bake that includes ansible-provision sudoers `includedir` ordering. |
| Conceptual integrity 2026-06-04 | C1 setup install vs verify mismatch | Coherence finding | Open | `setup_host.bash:25` Debian branch installs `qemu-system-x86`, but `qemu-img` (required by `create_vm.bash:283,311`) ships in `qemu-utils`, which `qemu-system-x86` only `Recommends` — verified via `apt-cache depends` on this Debian 13 host. With `--no-install-recommends`, setup completes yet `make check-tools` reports qemu-img MISSING. **Fate: Replace** — add `qemu-utils` to the Debian `PKG_LIST`. |
| Conceptual integrity 2026-06-04 | C2 cloud-init "done" decided twice | Coherence finding | Open | `create_vm.bash` decides "cloud-init done" two ways: `print_status_report:466-469` parses the `status:` field and compares `== "done"`; `wait_for_cloud_init:587` substring-matches `*"done"*` on raw output. Equivalent today, divergent logic for one concept. **Fate: Generalize** (single helper) or Keep with a note. |
| Conceptual integrity 2026-06-04 | C3 VM_NAME formula duplicated | Coherence finding | Open | `VM_NAME` formula plus `VM_PREFIX`/`IMAGE_DIR`/`LIBVIRT_URI` defaults are recomputed independently in `create_vm.bash:16,27,98,131` and `bake_iocrunner_image.bash:19,23,24,64`. All agree now; `bake` derives `SOURCE_DISK:65` from its own copy, so a naming change in `create_vm` would silently break the bake disk path. **Fate: Keep** (small tool) or Generalize — owner decision. |
| Conceptual integrity 2026-06-04 | C4 -h usage lists 2 of 4 OS types | Coherence finding | Open | `create_vm.bash` `print_usage:57,67-70` advertises only `rocky8`/`debian13`, but the script accepts four (`101-122,144-149`) and `README.md:146` documents all four — the script's own help disagrees with its behavior and the README. **Fate: Replace** — update the usage text. |
| Conceptual integrity 2026-06-04 | C5 required-group decided twice | Coherence finding | Open | The libvirt group a user must belong to is decided in two places: `create_vm.bash:29,74` via `REQUIRED_GROUP="libvirt"`, and `setup_host.bash:85,88` as the hardcoded literal `\blibvirt\b` plus the `usermod -aG libvirt` hint. They agree now; a change in one would not reach the other. **Fate: Keep** or Generalize. |
| Conceptual integrity 2026-06-04 | C6 shutdown-poll implemented twice | Coherence finding | Open | "Graceful shutdown then poll `domstate` until `shut off`" is implemented twice: `create_vm.bash:240-277` (`do_stop`, 12×5s = 60s, exposed via `-S`) and `bake_iocrunner_image.bash:117-134` (24×5s = 120s, open-coded). bake bypasses the `-S` action create_vm already exposes. Premise: bake likely wants a longer margin after applying ansible, so not a defect. **Fate: Generalize/Replace** (bake calls `create_vm -S`) or Keep (120s margin intentional). |

## Conceptual integrity review — 2026-06-04

Run via the `conceptual-integrity` skill ("The Flash of Remembering" lens). The
findings above (C1-C4) are the open seams. Seams verified **coherent** the same
day, recorded so they are not re-reviewed from scratch:

- bake output name `iocrunner-${OS_TYPE}.qcow2` (`bake_iocrunner_image.bash:66`)
  equals the `*-iocrunner` `BASE_IMAGE_NAME` (`create_vm.bash:112,117`) for both
  rocky8 and debian13 — the critical cross-script seam holds.
- `CHECK_TOOLS` (`RULES_SETUP`) equals `setup_host.bash:32` `BINARIES`.
- `ARCHITECTURE.md` IP / VM-name / template tables match `create_vm.bash`.

Second pass (same day) added C5-C6 and verified two more seams coherent:

- `OS_VARIANT` values `rocky8`/`debian13` (`create_vm.bash:102,106,111,116`) are
  valid osinfo IDs for `virt-install --os-variant` and double as the cloud-init
  template suffix `templates/user-data.${OS_VARIANT}` — both roles hold (checked
  with `virt-install --osinfo list`).
- `ARCHITECTURE.md` non-iocrunner IPs (.10/.11/.12, .100/.101/.102) match the
  code IP bases `DEBIAN13_IP_BASE=10` / `ROCKY8_IP_BASE=100`.

Ranking: C1 is latent-but-reachable; C2-C6 are latent or cosmetic and agree in
current output.
