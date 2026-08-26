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
from the OS selector, then adds the species group in underscore form.
The operator definition in `docs/IMAGE_WORKFLOW.md` assigns every
species to every vacuum.

| `--species` | Direct groups |
|---|---|
| `bare` | Vacuum group only |
| `iocrunner` | Vacuum group and `iocrunner` |
| `iocrunner-nfs` | Vacuum group and `iocrunner_nfs` |
| `epics-dev` | Vacuum group and `epics_dev` |
| `nfs-sim` | Vacuum group and `nfs_sim` |
| `rtbase` | Vacuum group and `rtbase` |
| `ethercat` | Vacuum group and `ethercat` |

The maintained group relationships make every generated host reachable
through the `vacua` parent group.

## Generate from a running VM

Run this section from the cloud-provision checkout root.

Create the temporary file first:

```bash
runtime_inventory=$(mktemp /tmp/cloud-provision-ansible-inventory.XXXXXX)
```

Run the VM status path and generate the host inventory. Choose the species
from the table above:

```bash
bin/create_vm.bash -o rocky8 -n main -s | bin/generate_ansible_inventory.bash --status-input --os-type rocky8 --species nfs-sim > "$runtime_inventory"
```

For an arbitrary prefix or instance label, pass the same `-p` and `-n` values
used to create the VM. The generator reads the reported identity; it does not
rebuild a host name from a fixed naming rule.

## Run Ansible

From the ansible-provision checkout, pass both inventory sources:

```bash
ansible-inventory -i inventory/lab.ini -i "$runtime_inventory" --graph
ansible-playbook -i inventory/lab.ini -i "$runtime_inventory" playbooks/species/iocrunner.yml
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

This check runs the real generator for all 35 vacuum-species pairs the
operator definition assigns plus five suffixed selectors, merges each
output through `ansible-inventory`, verifies direct and inherited groups,
and exercises the EPICS-env status-to-playbook path with only Libvirt,
SSH, and Ansible command boundaries controlled.
