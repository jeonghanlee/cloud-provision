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
