# Generated Ansible Inventory Runbook

## Purpose

Use this procedure when an Ansible play must target a VM created by
cloud-provision. The maintained `ansible-provision/inventory/testbed.ini` file
contains group relationships and no host rows. A temporary second inventory
contains the actual VM name, resolved IPv4 address, SSH user, and direct
workload groups.

## Inputs

| Input | Source |
|---|---|
| VM name and IPv4 address | `bin/create_vm.bash -s` output |
| OS selector | The `create_vm.bash -o` value used for the VM |
| Workload role | The table below |
| SSH user | `vmadmin` unless `--ansible-user` is supplied |

## Workload roles

| Role | Supported OS selectors | Direct groups |
|---|---|---|
| `ioc-node` | `rocky8`, `debian13`, `rocky8-iocrunner`, `debian13-iocrunner` | Base OS group |
| `nfs-sim-node` | The IOC selectors above | Base OS group and `nfs_sim_nodes` |
| `ioc-runner-build` | `rocky8`, `debian13` | Base OS group and `nfs_sim_nodes` |
| `ethercat-node` | `debian13-ethercat` | `ethercat_nodes` |
| `ethercat-build` | `debian13-rtbase` | `ethercat_build` |
| `epics-env-build` | Every `epics-env-*` selector | `epics_env_core` or `epics_env_matrix` |

The maintained group relationships make a base OS host reachable through
`ioc_nodes` and `all_nodes`, and make an EPICS-env host reachable through
`epics_env_build`.

## Generate from a running VM

Run this section from the cloud-provision checkout root.

Create the temporary file first:

```bash
runtime_inventory=$(mktemp /tmp/cloud-provision-ansible-inventory.XXXXXX)
```

Run the VM status path and generate the host inventory. Choose the role from
the table above:

```bash
bin/create_vm.bash -o rocky8 -n server -s | bin/generate_ansible_inventory.bash --status-input --os-type rocky8 --role nfs-sim-node > "$runtime_inventory"
```

For an arbitrary prefix or node ID, pass the same `-p` and `-n` values used to
create the VM. The generator reads the reported identity; it does not rebuild a
host name from a fixed naming rule.

## Run Ansible

From the ansible-provision checkout, pass both inventory sources:

```bash
ansible-inventory -i inventory/testbed.ini -i "$runtime_inventory" --graph
ansible-playbook -i inventory/testbed.ini -i "$runtime_inventory" site.yml
```

The Make workflow accepts the generated path and the actual VM name:

```bash
make 01_base RUNTIME_INVENTORY="$runtime_inventory"
make 01_base.rocky8.server RUNTIME_INVENTORY="$runtime_inventory" ANSIBLE_LIMIT=actual-vm-name
```

Remove the temporary inventory after the final Ansible command:

```bash
rm -f -- "$runtime_inventory"
```

## Automated workflows

| Entry point | Generated hosts | Ansible groups |
|---|---|---|
| `bin/bake_iocrunner_image.bash` | One run-specific build VM | Base OS, `ioc_nodes`, `all_nodes`, `nfs_sim_nodes` |
| `bin/bake_ethercat_image.bash` | One run-specific build VM | `ethercat_build` |
| `bin/run_epics_env_build.bash` | One file per selected build VM | `epics_env_core`, `epics_env_matrix`, parent `epics_env_build` |

Each automated entry point removes its generated inventory files on success or
failure. A play must receive the maintained group source and every generated
host source required by that run.

## Validation

```bash
make check-runtime-inventory
```

This check runs the real generator for every supported OS selector, merges its
output through `ansible-inventory`, verifies direct and inherited groups, and
exercises the EPICS-env status-to-playbook path with only Libvirt, SSH, and
Ansible command boundaries controlled.
