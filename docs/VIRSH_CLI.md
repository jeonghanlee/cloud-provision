# Virtualization Command Reference

## virsh — Status

```bash
# List all VM domains with state
virsh --connect qemu:///system list --all

# Query a specific VM state
virsh --connect qemu:///system domstate <vm>

# Dump full XML configuration of a VM
virsh --connect qemu:///system dumpxml <vm>

# List all libvirt networks
virsh --connect qemu:///system net-list --all

# Show active DHCP leases on the default network
virsh --connect qemu:///system net-dhcp-leases default
```

---

## virsh — Network (DHCP Reservation)

```bash
# Add static DHCP reservation (live + persistent)
virsh --connect qemu:///system net-update default add ip-dhcp-host \
    "<host mac='52:54:00:00:64:00' name='testbed-rocky8-server' ip='192.168.122.100'/>" \
    --live --config

# Remove static DHCP reservation (live + persistent)
virsh --connect qemu:///system net-update default delete ip-dhcp-host \
    "<host mac='52:54:00:00:64:00' name='testbed-rocky8-server' ip='192.168.122.100'/>" \
    --live --config
```

---

## virsh — VM Lifecycle

```bash
# Force stop a running VM
virsh --connect qemu:///system destroy <vm>

# Remove VM domain definition (does not delete disk)
virsh --connect qemu:///system undefine <vm>

# Attach to VM serial console  (exit: Ctrl+])
virsh --connect qemu:///system console <vm>

# Query IP address via DHCP lease (DHCP-assigned VMs only)
virsh --connect qemu:///system domifaddr <vm>
```

---

## qemu-img — Disk Image

```bash
# Inspect image format, virtual/disk size, backing file
qemu-img info <image.qcow2>

# Create a thin-provisioned qcow2 layer over a backing image
qemu-img create -f qcow2 -b <base.qcow2> -F qcow2 <target.qcow2> 20G
```

---

## virt-install — OS Variant

```bash
# List supported OS variants and filter by keyword
virt-install --os-variant list | grep <keyword>
```
