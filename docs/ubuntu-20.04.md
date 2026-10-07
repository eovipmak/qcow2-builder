# Ubuntu 20.04 Image — Build & Boot Test Guide

Port of `docs/debian-12.md` for Ubuntu 20.04 LTS (focal), UEFI Secure Boot only.

## 1. Build the image

```bash
scripts/build-image.sh ubuntu-20.04
```

Equivalent raw command (`ELEMENTS_PATH=elements` prepended in `scripts/common.sh`):

```bash
DIB_RELEASE=focal disk-image-create -o build/ubuntu-20.04/ubuntu-20.04 -t qcow2 -a amd64 \
  ubuntu vm block-device-efi cloud-init grub2 dhcp-all-interfaces autoupdates ubuntu-20.04 motd --checksum
```

- `ubuntu` = distro root element (focal cloud-image squashfs, `DIB_RELEASE=focal`)
- Remaining elements = same UEFI set as debian-12 (`block-device-efi`, `grub2`,
  `dhcp-all-interfaces`, `autoupdates`, `motd`)
- `ubuntu-20.04` = custom element (`elements/ubuntu-20.04/`): extra packages,
  timezone, root SSH, service enables
- Output: `build/ubuntu-20.04/ubuntu-20.04.qcow2`, plus `.md5` / `.sha256`

## 2. Deltas vs debian-12

- Root element is the Ubuntu cloud image, not debootstrap: the baked-in default
  user is `ubuntu` (not `debian`), so
  `elements/ubuntu-20.04/post-install.d/89-ubuntu-20.04-setup` removes the
  `ubuntu` user instead. Root-only template, same as debian-12.
- `50unattended-upgrades` policy is identical in shape (security-only,
  no auto-reboot); `${distro_id}:${distro_codename}-security` resolves to
  `Ubuntu:focal-security` here.
- Boot-test is unchanged: `scripts/make-seed.sh ubuntu-20.04 &&
  scripts/boot-vm.sh ubuntu-20.04`, then `ssh -p 2222 root@localhost`
  (password `root`), Secure Boot via OVMF (`*.secboot.fd` + `.ms` vars).
