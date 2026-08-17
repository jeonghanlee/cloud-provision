# Closed Doors

## Scope

This document records examined candidates that the owner deliberately leaves
unchanged. It is not an active work register.

| Date | Verdict | Candidate | Premise | Evidence | Carrying commit |
| --- | --- | --- | --- | --- | --- |
| 2026-08-17 | Keep | The golden ioc-runner consumer's engineer home (`/home/vmadmin`, mode 0700) blocks the non-root `ioc-srv` service account from traversing to the source-mode runner binary. Investigated here; cause is not in cloud-provision. | The 0700 home is the correct OS security default. The install and operational path uses `/usr/local/bin/ioc-runner` (world-readable) and never traverses the home, so the release gate is unaffected; only source-mode system tests cross the home. The coupling originates in where the runner source is placed, not in cloud-provision, so loosening the cloud-init home mode to 0711 was excluded by the owner. | Source-mode `system-lifecycle` S22 and S27 in `epics-ioc-runner` `tests/test-system-lifecycle.bash` fail only in source mode on fresh rocky8 and debian13 consumers. Root cause is `ansible-provision` `inventory/group_vars/all.yml` `path_ioc_runner_src`, which places the source under the 0700 home; `path_ioc_runner_bin` is `/usr/local/bin/ioc-runner`. cloud-init `templates/user-data.*` create `vmadmin` without setting a home mode, so it inherits the OS default 0700. Tracking transferred to `ansible-provision` M7 / jeonghanlee/ansible-provision#15 (OPEN, bug, Backlog). | 2b77a97 |
