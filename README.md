# Disk Images (multi-distro, Debian-first, UEFI Secure Boot only)

Build bootable qcow2 images with `disk-image-create` + cloud-init NoCloud seed,
boot-test with QEMU+VNC. Debian 12 is the reference; copy `images/_template/`
for new distros. Legacy BIOS is not supported: every template must use
`block-device-efi + grub2` and `*.secboot.fd` OVMF firmware (enforced by
`require_uefi_secure_boot` in `scripts/common.sh`).

## Quickstart

```bash
scripts/build-image.sh debian-12
scripts/make-seed.sh debian-12
scripts/boot-vm.sh debian-12
ssh -p 2222 root@localhost  # password root, UEFI Secure Boot via OVMF
```

## Layout

- `images/<name>/` — per-distro `distro.env`, `build.sh`, `boot-test.sh`, `cloud-init/`
- `images/_template/` — skeleton for new distros
- `elements/debian-12/` — reference custom element (packages, timezone, secure-boot pkg-map, setup hook)
- `elements/common-base/` — shared custom-element example
- `scripts/` — `build-image.sh`, `make-seed.sh`, `boot-vm.sh` wrappers
- `build/` — gitignored outputs (`*.qcow2`, `*.iso`, `*.log`, `*.d/`)
- `docs/debian-12.md` — full Debian 12 reference; `docs/adding-new-distro.md` — porting guide
- `plan.md` — template contract + migration map

## Adding a distro

See `docs/adding-new-distro.md`.
