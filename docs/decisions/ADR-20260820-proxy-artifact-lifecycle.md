# ADR: Proxy Artifact Lifecycle

Date: 2026-08-20
Status: Accepted
Decision IDs: D009, D010, D011, D012, D013, D014

## Context

The cloud-init producer and golden-image bakes must agree on every proxy artifact that may reach a build disk. Separate producer and cleanup lists allow a current artifact to survive publication even when each path passes its own local checks.

## Decision

`bin/proxy_contract.bash` is the single production authority for the current profile, APT, DNF, and system Git proxy artifacts. The real `create_vm.bash` seed path renders its deterministic files and marked blocks from the already validated proxy URL. The IOC runner and EtherCAT bakes stream the same shipped file to privileged Bash in `seal` mode after manifest validation and sidecar extraction. The contract dispatches that exact `/bin/bash -p -s -- seal` stdin form while remaining source-only when loaded as a library.

Seal performs a complete applicable-set preflight before mutation. Dedicated files and shared marked blocks have fixed ownership, mode, and marker rules. Shared-target replacement preserves every byte outside the owned block. The seal then runs supported cloud-init cleanup and verifies the value-free clean state. Each bake retains in-process identity for its exact build VM and disk, then permits only immediate stop, stopped-state confirmation, and publication from that disk.

The independent fixture under `tests/fixtures/` is not a production input. Its applicable identity, path, ownership form, marker, cleanup, and remnant tuple must equal the production inventory used by the renderer and both seal consumers. Public tests execute the shipped producer and both shipped bake callers with only outer command, SSH transport, and filesystem-root boundaries replaced. Inventory, stdin dispatch, and terminal-seal omission mutations must return nonzero before stop or publication.

The deferred real gates use new run-specific identities, reject domain, disk, or creation-record collisions, and do not restore `-F`. Each fresh consumer's exact creation record must contain one `source_image` equal to the validated just-published producer basename before cleanliness evidence is accepted.

## Scope Boundary

This decision does not add issue #33 SSH, sudo, pip, vmadmin, general-environment, or direct-route behavior. It does not change Ansible, restore `-F`, inspect existing artifacts, or authorize audit or remediation.

D014 keeps the existing-artifact audit deferred. Reading, quarantining, replacing, or deleting an existing guest, disk, image, archive, or sidecar requires a separate accepted plan and explicit authorization.

D013 limits documentation to observed evidence. Local shipped-path checks do not establish the pending real Libvirt/KVM producer-consumer gates or the state of any existing artifact.

## Consequences

- Producer and bake cleanup identities cannot change independently.
- A partial, ambiguous, or malformed owned set blocks publication.
- A no-proxy build still performs cloud-init cleanup and clean-state verification.
- Local verification proves only shipped host paths under explicit outer boundaries.
- Real Libvirt/KVM producer-consumer gates and the existing-artifact audit remain separate evidence.
