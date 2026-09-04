# Debian 12 Image — Build & Boot Test Guide

Test image built with `disk-image-create`: Debian 12 (bookworm), qcow2, UEFI + Secure Boot, with cloud-init.

## 1. Build the image

```bash
scripts/build-image.sh debian-12
```

Equivalent raw command (`ELEMENTS_PATH=elements` prepended in `scripts/common.sh`):

```bash
# DIB_RELEASE=bookworm pins Debian 12 (default is `stable`)
DIB_RELEASE=bookworm disk-image-create -o build/debian-12/debian-12 -t qcow2 -a amd64 \
  debian vm block-device-efi cloud-init grub2 dhcp-all-interfaces autoupdates debian-12 --checksum
```

- `debian` = distro root element (debootstrap)
- `vm` = partitionable disk image
- `block-device-efi` = GPT + ESP (`/boot/efi`), no LVM, no swap (`vm` alone falls back to MBR)
- `cloud-init` = install + enable cloud-init
- `grub2` = signed `grub-efi-amd64-signed` + `shim-signed` for UEFI Secure Boot
- `dhcp-all-interfaces` = DHCP on every NIC at boot (see "Networking" below)
- `autoupdates` = unattended security updates (see "Automatic updates" below)
- `debian-12` = custom element (`elements/debian-12/`): extra packages, timezone, root SSH, service enables
- Output: `build/debian-12/debian-12.qcow2`, plus `.md5` / `.sha256`

### Automatic updates

The `autoupdates` element is [documented upstream](https://docs.openstack.org/diskimage-builder/latest/elements/autoupdates/README.html)
but is **not in the DIB 3.29 this repo builds with**, so it is vendored at
`elements/autoupdates/` and resolved via `ELEMENTS_PATH`. See that directory's
README for the one local addition it carries.

What lands in the image:

| Path | From | Purpose |
| --- | --- | --- |
| `unattended-upgrades` package | `pkg-map` → `package-installs.yaml` | the updater itself |
| `/etc/apt/apt.conf.d/50unattended-upgrades` | `root.d/61` copying `DIB_DEB_UPDATES_CONF` | **policy**: which origins, reboot behaviour |
| `/etc/apt/apt.conf.d/20auto-upgrades` | `post-install.d/83` (local addition) | **schedule**: the `APT::Periodic` keys |
| `apt-daily.timer`, `apt-daily-upgrade.timer` | `post-install.d/83` | fire the jobs; `Persistent=true` catches up missed runs |
| `unattended-upgrades.service` | `post-install.d/82` (upstream) | on-demand run at boot |

The `83-` hook matters more than it looks: every `APT::Periodic` knob in
`/usr/lib/apt/apt.systemd.daily` defaults to `0`, so with upstream's element
alone the timers fire, find nothing enabled, and the image quietly never
patches. `20auto-upgrades` is what turns update + upgrade on.

Policy is per-image in `images/debian-12/50unattended-upgrades`, deliberately
**security-only** (`${distro_id}:${distro_codename}-security`, i.e.
`Debian:bookworm-security` from `security.debian.org`, which the image's
`sources.list.d/security.list` already carries):

- `Automatic-Reboot "false"` — CloudStack owns stop/start; a self-initiated
  reboot inside the guest fights the platform's lifecycle and console. A patch
  needing a reboot waits for an operator reboot instead.
- `Remove-Unused-Dependencies "false"` — autoremove can pull kernels and
  hypervisor-facing packages out from under a long-lived template.
- Widening to `-updates` / main is two comments in that file; it is off by
  default so a template never silently gains a new glibc mid-service.

**Gotcha:** never put global `Acquire::` keys (e.g. `Acquire::http::Dl-Limit`)
in this policy file. `root.d/61` copies it into the target rootfs *before* the
chroot's `install.d` phase, so build-time apt reads it too — a `Dl-Limit "70"`
here capped a ~100 MB build at 70 KB/s and turned an 8-minute build into a
25-minute one. Guest-side apt tuning belongs in a `post-install.d` hook, which
runs after the packages are installed.

To confirm on a built image (`unattended-upgrades --dry-run` needs the package
plus network, so check the config instead of running it):

```bash
losetup -P /dev/loop7 <(qemu-img convert -f qcow2 -O raw build/debian-12/debian-12.qcow2 /dev/stdout)
mount -o ro /dev/loop7p3 /mnt
cat /mnt/etc/apt/apt.conf.d/20auto-upgrades          # Periodic keys present
grep Allowed-Origins -A4 /mnt/etc/apt/apt.conf.d/50unattended-upgrades
ls -l /mnt/etc/systemd/system/timers.target.wants/ | grep apt-daily
```

### Networking

A plain Debian debootstrap root only has `lo` in `/etc/network/interfaces`, so
the guest boots with **no IP address**. `dhcp-all-interfaces` installs
`dhcp-all-interfaces.sh` + `dhcp-interface@.service`, which runs a DHCP client
on every real NIC at boot — required for a template whose MACs/NIC names are
unknown (`ens3`, `enp0s2`, `eth0`, ...).

**Only one component may own interface config.** Without this the instance gets
**two IPv4 addresses on one NIC**:

| Writer | Target file | Trigger |
| --- | --- | --- |
| `dhcp-all-interfaces` | appends `auto <nic>` + `iface <nic> inet dhcp` to `/etc/network/interfaces` | `dhcp-interface@<nic>.service`, and a udev rule on every NIC add |
| cloud-init | generates `/etc/network/interfaces.d/50-cloud-init` from the datasource's network config | `cloud-init-local` / `cloud-init` |

`/etc/network/interfaces` ends with `source /etc/network/interfaces.d/*`, so
ifupdown reads both and `eth0` is declared twice — twice the `auto eth0`, twice
`dhclient`, two leases (plus a duplicate `auto lo`). CloudStack exposes this as
the interface holding up to 2 IPs.

Fix: `cloud.cfg.d/99-disable-network-config.cfg` containing
`network: {config: disabled}` — written by
`elements/debian-12/post-install.d/89-debian-12-setup`. cloud-init keeps doing
everything else (hostname, users, `set_passwords`, user-data) but stops
rendering a rival network config, leaving `dhcp-all-interfaces` the single
owner. Nothing is lost: the CloudStack virtual router's `dnsmasq` already
advertises address, DNS and domain over DHCP, which is exactly what the
rendered `50-cloud-init` was repeating.

Do **not** remove `dhcp-all-interfaces` to fix this instead — cloud-init needs a
DHCP'd interface to reach the virtual router's metadata service in the first
place, so relying on rendered config alone deadlocks a fresh instance whose NIC
name is unknown.

### Boot-testing does not touch the master image

`boot_vm()` in `scripts/common.sh` boots a throwaway
`build/<output>/boot-test-overlay.qcow2` (`qemu-img create -b`), recreated on
every run, so writes stay in the overlay.

This matters: a booted guest is not read-only. Testing directly against
`build/debian-12/debian-12.qcow2` persisted QEMU-specific state into the
published template — `auto enp0s3` stanzas from `dhcp-all-interfaces`, a
populated `/var/lib/cloud` pinned to the seed's `instance-id: debian-12-001`
(which makes per-instance modules skip on the real first boot), and a filled-in
`/etc/machine-id`. That last one is the nastiest: `dhcp-all-interfaces.sh`
builds the DHCPv6 `default-duid` from `/etc/machine-id`, so every instance
cloned from such a template would present the same DUID.

Check the master is untouched after a test:

```bash
md5sum -c /tmp/master-before.md5   # take this before scripts/boot-vm.sh
```

### Secure Boot note

The build logs `WARNING: /boot/efi/EFI/debian does not exist, UEFI secure boot
not supported` — this is **benign for Debian**. Because `grub-efi-amd64-signed`
+ `shim-signed` are installed (via `grub2` + `pkg-map`), Debian's own
`grub-install` wrapper places the *signed* binaries on the ESP fallback path,
which is the portable layout a template image wants (boots with no NVRAM entry):

| ESP file | Verifies as |
| --- | --- |
| `/EFI/BOOT/BOOTX64.EFI` | identical to `/usr/lib/shim/shimx64.efi.signed` (MS-signed) |
| `/EFI/BOOT/grubx64.efi` | identical to `/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed` (Debian-signed) |
| `/EFI/BOOT/mmx64.efi` | MokManager, for enrolling custom keys |
| `/EFI/BOOT/grub.cfg` | stub → `search.fs_uuid` → `/boot/grub/grub.cfg` (the real config) |

Chain: firmware → shim → signed grub → `/boot/grub/grub.cfg`. Confirm on a
built image with:

```bash
qemu-img convert -f qcow2 -O raw build/debian-12/debian-12.qcow2 /tmp/img.raw
losetup -P /dev/loop7 /tmp/img.raw
mkdir -p /tmp/esp && mount -o ro /dev/loop7p1 /tmp/esp
md5sum /tmp/esp/EFI/BOOT/BOOTX64.EFI        # == shimx64.efi.signed
```

The warning only means the *distro-specific* `\EFI\debian` path is absent, so
DIB additionally writes the `\EFI\BOOT` fallback. Both boot under Secure Boot.

### Custom element (`elements/debian-12/`)

- `package-installs.yaml` — `openssh-server qemu-guest-agent chrony curl git vim ncdu net-tools auditd sysstat cloud-init cloud-guest-utils dosfstools`
  (+ `grub-efi-amd64-signed` / `shim-signed` on amd64 via `pkg-map`).
  `dosfstools` provides `fsck.vfat` so the ESP (`/boot/efi`, FAT, `fsck-passno 2`)
  gets checked and its dirty bit cleared at boot instead of logging
  `Volume was not properly unmounted` on CloudStack.
- `post-install.d/89-debian-12-setup` — timezone `Asia/Ho_Chi_Minh`, `PermitRootLogin yes`,
  `disable_root: false`, writes `cloud.cfg.d/99_cloudstack.cfg`
  (`datasource_list: [ConfigDrive, CloudStack, NoCloud, None]`),
  rewrites ` - set-passwords` to ` - [set_passwords, always]` in `cloud.cfg`
  (CloudStack GUI password set/reset on every boot), enables
  `ssh cloud-init-* chrony auditd sysstat`, and deletes the
  `debian` user + NOPASSWD sudoers drop-in that DIB's `debian` element adds by default
  (`install.d/10-cloud-opinions`) so the template stays root-only.
  Numbered `89` so it runs after `cloud-init`'s `20-enable-cloud-init` and
  `openssh-server`'s `80-enable-sshd-service`.

## 2. Boot test with QEMU + UEFI + VNC

```bash
apt install -y qemu-system-x86 qemu-utils cloud-image-utils ovmf
```

The image enables **root login** — cloud-init sets the password at first boot
from a NoCloud seed. Create the seed:

```bash
scripts/make-seed.sh debian-12
```

Seed content (`images/debian-12/cloud-init/`):

```yaml
#cloud-config
hostname: debian-12
timezone: Asia/Ho_Chi_Minh
users:
  - name: root
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:root
  expire: false
```

Boot (UEFI Secure Boot via OVMF, configured in `distro.env`):

```bash
scripts/boot-vm.sh debian-12
```

Raw equivalent:

```bash
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd build/debian-12/OVMF_VARS.fd
qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -cpu host \
  -machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd,readonly=on \
  -drive if=pflash,format=raw,unit=1,file=build/debian-12/OVMF_VARS.fd \
  -drive file=build/debian-12/debian-12.qcow2,if=virtio,format=qcow2 \
  -drive file=build/debian-12/seed.iso,if=virtio,format=raw,readonly=on \
  -device virtio-serial-pci \
  -chardev socket,id=qga0,path=build/debian-12/qga.sock,server=on,wait=off \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0 \
  -vnc 0.0.0.0:5 -serial file:build/debian-12/vm-serial.log -display none -daemonize
```

- UEFI vars: `ms` template boots with Secure Boot active from the start
- Serial console: `build/debian-12/vm-serial.log`
- **Pass criteria: `vm-serial.log` ends with `debian-12 login:`** (CloudStack
  platform image — internal checks are manual, later). No SSH login required.
  Example: `grep -a "login:" build/debian-12/vm-serial.log`

### Guest agent

`qemu-guest-agent.service` reports `static` and cannot be enabled — Debian ships
it with an empty `[Install]` section and `BindsTo=dev-virtio\x2dports-org.qemu.guest_agent.0.device`,
so **starting it is the hypervisor's job**: attach a virtserialport named
`org.qemu.guest_agent.0` (as above, or `<channel type='unix'>` in libvirt) and
systemd activates the agent automatically. With the channel attached the
boot-test shows `/usr/sbin/qemu-ga` running; without it the unit stays
inactive, which is expected, not a defect.

## 3. Customize the image

### Ad-hoc packages (quick, no scaffolding)

```bash
PACKAGES="htop" scripts/build-image.sh debian-12
# or: CUSTOM_ELEMENTS="myelement" scripts/build-image.sh debian-12
```

`-p` installs extra packages once, after the `install.d` phase.

### Proper way — custom element

See `elements/debian-12/` as the reference. Create `elements/<name>/` with:

**`package-installs.yaml`** — declarative packages:

```yaml
nginx:
python3:
```

**`post-install.d/89-<name>-setup`** — arbitrary shell, runs chrooted in the image:

```bash
#!/bin/bash
set -eu -o pipefail
systemctl enable nginx                       # enable a service
```

Build with it (append to `DIB_ELEMENTS` in `distro.env`):

```bash
disk-image-create -o debian-12 -t qcow2 debian vm block-device-efi cloud-init grub2 myelement
```

`ELEMENTS_PATH=elements` is wired in `scripts/common.sh`. Note phases:
`install.d` → `-p PACKAGES` → `post-install.d` → `finalise.d`.

### No-rebuild injection via cloud-init seed (`images/debian-12/cloud-init/user-data`)

```yaml
#cloud-config
packages: [nginx, vim]
runcmd:
  - systemctl enable --now nginx
  - /usr/local/bin/my-script.sh
write_files:
  - path: /usr/local/bin/my-script.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo hello > /tmp/it-works
```

Useful for per-boot testing without rebuilding the image.

## Sources

- [diskimage-builder Elements Guide](https://docs.openstack.org/diskimage-builder/latest/user_guide/elements.html)
