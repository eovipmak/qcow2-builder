# Adding a New Distro (UEFI Secure Boot only)

> This repo only generates UEFI Secure Boot templates. Legacy BIOS
> (`block-device-mbr`, empty `UEFI_CODE=`) is rejected by
> `require_uefi_secure_boot` in `scripts/common.sh`.

1. `cp -r images/_template images/<name>`
2. Edit `images/<name>/distro.env` (UEFI element set is mandatory):
    - Debian-family: `DIB_ELEMENTS="debian vm block-device-efi cloud-init grub2 dhcp-all-interfaces <custom>"` (`DIB_RELEASE=bookworm`) or
      `DIB_ELEMENTS="ubuntu vm block-device-efi cloud-init grub2 dhcp-all-interfaces <custom>"` (`DIB_RELEASE=noble`)
      - `block-device-efi` = GPT + ESP, no LVM, no swap (required; `vm` alone falls back to MBR, which is rejected)
      - `grub2` = signed `grub-efi-amd64-signed` + `shim-signed` for UEFI Secure Boot (required)
      - Keep `motd` in the element list: it writes `/etc/motd` so users see the
        Vinahost Cloud banner at login (`elements/motd/post-install.d/95-motd`).
     - `dhcp-all-interfaces` = DHCP on every NIC at boot; without it the guest has
       no IP and the SSH boot-test fails with no error on the host side
     - Keep cloud-init's network rendering **disabled**
       (`/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` →
       `network: {config: disabled}`, written by
       `elements/debian-12/post-install.d/89-debian-12-setup`). If a datasource
       supplies network config, cloud-init writes
       `/etc/network/interfaces.d/50-cloud-init` while `dhcp-all-interfaces`
       appends the same NIC to `/etc/network/interfaces`; ifupdown reads both and
       runs dhclient twice, giving one interface two IPv4 addresses. Copy that
       drop-in into any new distro's element.
    - RHEL-family: e.g. `DIB_ELEMENTS="rocky vm block-device-efi cloud-init grub2 dhcp-all-interfaces <custom>"` (`DIB_RELEASE=9-stream`),
      `DIB_ELEMENTS="almalinux vm block-device-efi cloud-init grub2 dhcp-all-interfaces <custom>"`,
      `fedora` (`DIB_RELEASE=41`), or `centos` — same UEFI set; manifest is `rpm` not `dpkg`,
      packages via `dnf/yum`, note SELinux element if needed
    - UEFI boot-test (mandatory): keep `UEFI_CODE=` (a `*.secboot.fd` image) +
      `UEFI_VARS_TEMPLATE=` (Secure Boot vars store) set — see `images/debian-12/distro.env`.
      Unset/empty values fail the build and boot-test; there is no legacy BIOS path.
3. Edit `cloud-init/user-data` + `meta-data` (hostname, password).
   Keep `users:` on `- default` (do **not** list `name: root`): cloud-init maps
   `default` to the image's `system_info.default_user` (root, written by
   `cloud.cfg.d/98_user.cfg`) and marks it as *the* default user. An explicit
   `name: root` replaces `cloud.cfg`'s `users: [default]`, nothing is marked
   default, and `set_passwords` silently drops the CloudStack datasource
   `password:` ("No default or defined user to change password for"), leaving
   root locked → no root login in CloudStack
4. Optional custom packages: copy `elements/debian-12/` to `elements/<name>/`,
   edit `package-installs.yaml` (+ `pkg-map` for virtual names), add
   `post-install.d/89-<name>-setup` (executable, AFTER cloud-init's `20-` hooks),
   append `<name>` to `DIB_ELEMENTS` in `distro.env`
5. `scripts/build-image.sh <name>` → output lands in `build/<output>/`
6. `scripts/make-seed.sh <name> && scripts/boot-vm.sh <name>` → SSH
   `ssh -p <SSH_PORT> <user>@localhost`, serial log in `build/<output>/vm-serial.log`

No-rebuild injection stays per-image in `cloud-init/user-data`
(`packages:`, `runcmd:`, `write_files:`). See `docs/debian-12.md` §3.
