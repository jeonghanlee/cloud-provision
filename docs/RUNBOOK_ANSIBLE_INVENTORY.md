# Generated Ansible Inventory Runbook

## Purpose

Use this procedure when an Ansible play must target a VM created by
cloud-provision. The maintained `ansible-provision/inventory/lab.ini` file
contains group relationships and no host rows. A temporary second inventory
contains the actual VM name, resolved IPv4 address, SSH user, and direct
species groups.

## Inputs

| Input | Source |
|---|---|
| VM name and IPv4 address | `bin/create_vm.bash -s` output |
| OS selector | The `create_vm.bash -o` value used for the VM |
| Species | The table below |
| SSH user | `vmadmin` unless `--ansible-user` is supplied |

## Species

The generator derives the vacuum group by stripping any species suffix
from the OS selector, then adds the species group in underscore form. It
does not enforce which species a vacuum may take; the species-to-vacuum
assignment is defined in `docs/OPERATOR_MODEL.md`.

| `--species` | Direct groups |
|---|---|
| `bare` | Vacuum group only |
| `iocrunner` | Vacuum group and `iocrunner` |
| `iocserver` | Vacuum group and `iocserver` |
| `iocrunner-nfs` | Vacuum group and `iocrunner_nfs` |
| `epics-dev` | Vacuum group and `epics_dev` |
| `nfs-sim` | Vacuum group and `nfs_sim` |
| `rtbase` | Vacuum group and `rtbase` |
| `ethercat` | Vacuum group and `ethercat` |
| `archiver` | Vacuum group and `archiver` |
| `archiver-dev` | Vacuum group and `archiver_dev` |
| `archiver-dev-sqlite` | Vacuum group and `archiver_dev_sqlite` |

The maintained group relationships make every generated host reachable
through the `vacua` parent group.

## Generate from a running VM

Run this section in Bash from the cloud-provision checkout root.

Create the temporary file first:

```bash
runtime_inventory=$(mktemp /tmp/cloud-provision-ansible-inventory.XXXXXX)
```

Define the VM status command and inventory command. Choose the species
from the table above:

```bash
status_command=(bin/create_vm.bash -o rocky8 -n main -s)
inventory_command=(bin/generate_ansible_inventory.bash --status-input --os-type rocky8 --species nfs-sim)
```

For an arbitrary prefix or instance label, pass the same `-p` and `-n` values
used to create the VM in `status_command`. The generator reads the reported identity; it does not
rebuild a host name from a fixed naming rule.

Generate the inventory only after the status command succeeds:

```bash
vm_status=$("${status_command[@]}") && "${inventory_command[@]}" <<< "$vm_status" > "$runtime_inventory"
```

Continue only if this command exits successfully. The status command requires
`Domain running`, `SSH ready`, and `cloud-init done`. On failure, stop before
running Ansible, inspect the report with `printf "%s\n" "$vm_status"`, and
resolve the reported VM state before retrying.

## Run Ansible

In the same shell, change to the ansible-provision checkout, pass both inventory sources, and select
the playbook for the intended species. For the `nfs-sim` example:

```bash
ansible-inventory -i inventory/lab.ini -i "$runtime_inventory" --graph
ansible-playbook -i inventory/lab.ini -i "$runtime_inventory" playbooks/species/nfs_sim.yml
```

The Make workflow accepts the generated path and the actual VM name; targets
are `<species>.<vacuum>` and `op.<operator>.<vacuum>`:

```bash
make nfs_sim.rocky8 RUNTIME_INVENTORY="$runtime_inventory"
make nfs_sim.rocky8 RUNTIME_INVENTORY="$runtime_inventory" ANSIBLE_LIMIT=actual-vm-name
```

Remove the temporary inventory after the final Ansible command:

```bash
rm -f -- "$runtime_inventory"
```

## Automated workflows

| Entry point | Generated hosts | Ansible groups |
|---|---|---|
| `bin/bake_iocrunner_image.bash` | One run-specific build VM | Vacuum group and `iocrunner` (or `iocrunner_nfs` with `-f iocrunner-nfs`) |
| `bin/bake_ethercat_image.bash` | One run-specific build VM | Vacuum group and `rtbase` |
| `bin/run_epics_env_build.bash` | One file per selected build VM | Vacuum group and `epics_dev` |

Each automated entry point removes its generated inventory files on success or
failure. A play must receive the maintained group source and every generated
host source required by that run.

## Validation

```bash
make check-runtime-inventory
```

This check runs the real generator for 44 plain-selector vacuum-species
pairs plus twelve suffixed-selector cases, merges each output through
`ansible-inventory`, verifies direct and inherited groups, and exercises
the EPICS-env status-to-playbook path with only Libvirt, SSH, and
Ansible command boundaries controlled.
