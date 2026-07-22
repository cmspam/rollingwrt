---
title: Virtualization with Incus
nav_order: 4
permalink: /virtualization/
---

# Virtualization with Incus

rollingWRT ships [Incus](https://linuxcontainers.org/incus/) for system containers and
virtual machines. `incus` is installed with the base hypervisor package set. VM support
(QEMU, OVMF, and the KVM and vhost kernel modules) is a separate metapackage,
`incus-vm`; install it if you want to run virtual machines as well as containers.

## Networking

Incus instances need a bridge to attach to. On rollingWRT there are two approaches.

### Recommended: an OpenWrt-managed bridge

OpenWrt already manages your bridges, VLANs, firewall, and DHCP. The simplest and most
predictable setup is to attach instances to a bridge that OpenWrt manages, so they sit
on your LAN (or a VLAN you have configured) and get their addresses from OpenWrt's own
DHCP server. Nothing in Incus has to run a second DHCP server, and the firewall already
knows the bridge.

Point Incus at an existing OpenWrt bridge with a `nic` device of type `bridged`. For
example, to put every instance on the default LAN bridge `br-lan`:

```
incus profile device add default eth0 nic nictype=bridged parent=br-lan name=eth0
```

Use whichever OpenWrt bridge you want as the `parent`. For a router it is common to
create a dedicated bridge (for example a guest or lab bridge) in OpenWrt's network
configuration and attach instances there instead of the LAN.

### Alternative: an Incus-managed bridge

Incus can also create and manage its own bridge of any name, running its own DHCP and
DNS and its own NAT. This works on rollingWRT, but because OpenWrt already runs a
dnsmasq and a firewall, an Incus-managed bridge needs two one-time adjustments. Do them
for each Incus bridge you create, substituting your bridge's name for `INCUSBR`.

1. **Free the DHCP/DNS socket.** OpenWrt's dnsmasq runs in `bind-dynamic` mode, so it
   starts listening on any new interface the moment it appears, including a bridge Incus
   just created. Incus's own dnsmasq then cannot bind. Tell OpenWrt's dnsmasq to skip
   the Incus bridge:

   ```
   uci add_list dhcp.@dnsmasq[0].notinterface='INCUSBR'
   uci commit dhcp
   /etc/init.d/dnsmasq reload
   ```

2. **Let the firewall see it.** An Incus-managed bridge is not an OpenWrt-configured
   network, so the firewall does not know about it and will drop its traffic. Add it to
   a firewall zone. The `lan` zone accepts input and allows forwarding:

   ```
   uci add_list firewall.$(uci show firewall | sed -n "s/.*\(@zone\[[0-9]*\]\)\.name='lan'/\1/p").device='INCUSBR'
   uci commit firewall
   /etc/init.d/firewall reload
   ```

There is nothing tied to a specific bridge name; the default `incusbr0` and any other
name you choose are handled the same way.

## After installing incus-vm: restart Incus

Incus virtual machines require the KVM and vhost kernel modules (`kvm_amd` or
`kvm_intel`, `vhost_net`, `vhost_vsock`, `tun`). Installing `incus-vm` pulls them in, but
OpenWrt loads kernel modules at boot, and the Incus daemon probes for them only once,
when it starts. If Incus was already running when you installed `incus-vm`, it did not
see the new modules and will refuse to create a VM, for example:

```
Error: ... Instance type "virtual-machine" is not supported on this server:
vhost_vsock kernel module not loaded
```

Restart the daemon so it re-probes:

```
service incus restart
```

A full reboot also works, since the modules autoload at boot. The same applies to
containers: if `kmod-veth` was pulled in while Incus was already running, restart Incus
(or reboot) before launching a container.
