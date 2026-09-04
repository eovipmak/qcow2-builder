# Multi-Distro Image Template Plan (Debian-first) + Repo Reorg

## Goal
Reorganize flat single-image repo into a copy-paste template supporting multiple distributions,
with Debian 12 (`bookworm`) as the reference implementation. Make builds, seeds, boot-tests,
and artifact distribution repeatable per-distro without duplicating logic.

## Current State (found)
- Flat root: `guide.md`, `debian-12.qcow2` + `.md5`/`.sha256`, `seed.iso`, `vm-serial.log`
- `seed/user-data`, `seed/meta-data` — NoCloud seed, user `debian`/`debian`, `ssh_pwauth:true`
- `debian-12.d/dib-manifests/{dib_arguments,dib_environment,dib-manifest-dpkg-debian-12}` — DIB output (`-o debian-12 -t qcow2 debian vm cloud-init --checksum`, `DIB_RELEASE=bookworm`)
- `guide.md` (127 lines) is the only doc: build + QEMU/VNC boot + custom-element + cloud-init injection patterns
- No `README.md`, no `.gitignore`, no `scripts/`, no shared `elements/`, no per-distro config

## Recommended Approach
Migrate + template (not template-only). Move existing `debian-12` into new layout as reference,
extract shared logic to `scripts/`, add copyable `images/_template/`. Keep it `disk-image-create`-native:
no new build system, just thin `build.sh` wrappers + `distro.env` per image. Generic-multi:
template covers `apt` (debian/ubuntu) and `dnf/yum` (rhel-family) via conditional element lists.

## Target Structure (to implement)
```
/
  README.md                 # index + quickstart (distills guide.md)
  plan.md                   # promoted copy of this plan = template contract in-repo
  docs/
    debian-12.md            # moved guide.md content, per-distro version
    adding-new-distro.md    # how to copy _template
  .gitignore                # *.qcow2, *.iso, *.log, build/, images/*/*.d/, seeds *.iso
  images/
    debian-12/              # migrated reference (prioritized)
      distro.env            # DIB_RELEASE=bookworm, DIB_ELEMENTS="debian vm cloud-init", OUTPUT=debian-12, TYPE=qcow2
      build.sh              # `source ../common.sh; disk-image-create ...` thin wrapper
      boot-test.sh          # parameterized QEMU cmd (ports, VNC display, seed.iso path)
      cloud-init/
        user-data           # from seed/user-data (hostname, users, chpasswd, ssh_pwauth)
        meta-data           # from seed/meta-data
    _template/              # skeleton for new distro (copy to images/<name>/)
      distro.env            # placeholders: {{DISTRO}}, {{RELEASE}}, {{ARCH}}, {{ELEMENTS}}
      build.sh
      boot-test.sh
      cloud-init/user-data
      cloud-init/meta-data
      elements/README.md    # where distro-specific DIB element overrides go
  elements/
    common-base/            # shared custom element example from guide.md §3
      package-installs.yaml
      install.d/50-common-setup
  scripts/
    common.sh               # ELEMENTS_PATH, OUTPUT/BULD_DIR resolution, set -eu -o pipefail
    build-image.sh <distro> # `scripts/build-image.sh debian-12` — loads images/<d>/distro.env, runs DIB
    make-seed.sh <distro>   # `cloud-localds build/<d>/seed.iso images/<d>/cloud-init/...`
    boot-vm.sh <distro>     # QEMU + VNC + serial log to build/<d>/
  build/                    # gitignored outputs: *.qcow2, *.md5/.sha256, *.iso, *.log, *.d/
    debian-12/
```

## Migration Map (existing → new)
- `seed/user-data` → `images/debian-12/cloud-init/user-data` (rewritten for the root-login contract: `users: [root]`, `disable_root: false`, `timezone`)
- `seed/meta-data` → `images/debian-12/cloud-init/meta-data`
- `seed.iso` → regenerated via `scripts/make-seed.sh debian-12` into `build/debian-12/seed.iso` (do not commit)
- `debian-12.qcow2{,.md5,.sha256}` → `build/debian-12/` (gitignored; keep checksum generation via `--checksum`)
- `debian-12.d/dib-manifests/*` → `build/debian-12/debian-12.d/dib-manifests/` (reference only, not committed except example `dib_arguments`)
- `vm-serial.log` → `build/debian-12/vm-serial.log` (gitignored)
- `guide.md` → `docs/debian-12.md` + slim `README.md`; `guide.md` archived to `build/legacy/` (see its README) rather than left as a stub

## Template Contract (`images/_template/distro.env`)
```bash
DISTRO=debian          # debian|ubuntu|rocky|fedora|centos
DIB_RELEASE=bookworm   # bookworm|noble|9-stream|41 ...
# Debian-family (UEFI + Secure Boot reference):
#   "debian vm block-device-efi cloud-init grub2 dhcp-all-interfaces debian-12"
# `vm` alone falls back to block-device-mbr (BIOS); block-device-efi gives
# GPT + ESP, no LVM, no swap; grub2 pulls signed grub/shim;
# dhcp-all-interfaces is required or the guest never gets an IP.
DIB_ELEMENTS="debian vm block-device-efi cloud-init grub2 dhcp-all-interfaces"  # rhel-family: "fedora vm cloud-init dhcp-all-interfaces"
OUTPUT=<name>          # e.g. ubuntu-24.04
TYPE=qcow2
ARCH=amd64
PACKAGES="vim,curl,htop"  # passed as -p, or via elements/<name>/package-installs.yaml
# Boot-test firmware; set both for UEFI Secure Boot, leave "" for legacy BIOS
UEFI_CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
UEFI_VARS_TEMPLATE=/usr/share/OVMF/OVMF_VARS_4M.ms.fd
```
- `build.sh` must only `source scripts/common.sh` + invoke `disk-image-create -o build/$OUTPUT -t $TYPE $DIB_ELEMENTS ${CUSTOM_ELEMENTS} ${PACKAGES:+-p $PACKAGES} --checksum`
- New distro = `cp -r images/_template images/<name>` + edit 5 files above + `scripts/build-image.sh <name>`

## DIB Differences to Document (in `docs/adding-new-distro.md`)
- Debian/Ubuntu: root element `debian`/`ubuntu`, `DIB_RELEASE` (bookworm/noble), debootstrap, `dpkg` manifest
- RHEL-family: root element `fedora`/`centos`/`rocky`, `DIB_RELEASE` (9-stream/41), `rpm` manifest, `yum/dnf` + SELinux element notes
- Shared: `vm block-device-efi cloud-init grub2 dhcp-all-interfaces` stays constant across
  distros; custom elements via `ELEMENTS_PATH=elements` (wired in `scripts/common.sh`) +
  `package-installs.yaml` (+ optional `pkg-map`) + `post-install.d/89-*` so hooks run after
  `cloud-init`'s `20-*` and `-p` packages. Reference example: `elements/debian-12/`
  (the older `guide.md` §3 nginx sample is archived in `build/legacy/`)
- No-rebuild path stays `cloud-init/{user-data,meta-data}` per image (packages/runcmd/write_files)

## Files to Create / Modify (implementation)
1. NEW `.gitignore`, `README.md`, `plan.md` (copy of this file), `docs/debian-12.md`, `docs/adding-new-distro.md`
2. NEW `images/debian-12/{distro.env,build.sh,boot-test.sh,cloud-init/user-data,cloud-init/meta-data}`
3. NEW `images/_template/{distro.env,build.sh,boot-test.sh,cloud-init/user-data,cloud-init/meta-data,elements/README.md}`
4. NEW `elements/common-base/{package-installs.yaml,install.d/50-common-setup}` (from `guide.md` lines 82-97 nginx example)
5. NEW `scripts/{common.sh,build-image.sh,make-seed.sh,boot-vm.sh}` (extract QEMU flags from `guide.md` lines 55-60: `-m 2048 -smp 2 -cpu host -vnc :5 -serial file:... -netdev user,hostfwd=tcp::2222-:22`)
6. MOVE artifacts to `build/` as above; DELETE root `seed/`, `seed.iso`, `vm-serial.log`, `debian-12.qcow2*` from git (keep locally until verified)

## Non-Goals / Assumptions
- No CI, no image publishing registry, no Packer replacement — DIB stays the builder
- Debian-first: `debian-12` is the reference implementation, rebuilt to the UEFI/Secure Boot +
  root-login contract above; any second distro copies its element/pkg-map structure
- Ubuntu is the expected second distro (lowest delta); RHEL-family supported by template vars but not built now
- Large binaries never committed; distribution = `build/<distro>/` + checksums + docs

## Verification
1. `bash -n scripts/*.sh images/*/build.sh images/*/boot-test.sh` + `shellcheck` if available
2. `scripts/build-image.sh debian-12` produces `build/debian-12/debian-12.qcow2` with
   `dib_arguments` = `-o build/debian-12/debian-12 -t qcow2 -a amd64 debian vm
   block-device-efi cloud-init grub2 debian-12 --checksum` + `DIB_RELEASE=bookworm`
3. Image-level checks (mount ESP/root, see `docs/debian-12.md`): GPT with ESP + BIOS-boot +
   root only (no LVM, no swap); `fstab` has no swap line; `/etc/timezone` =
   `Asia/Ho_Chi_Minh`; `PermitRootLogin yes`; all 12 requested packages present in the dpkg
   manifest; `cloud-init.*` + `ssh` + `chrony` + `auditd` + `sysstat` enabled; no `debian` user
4. Secure Boot: ESP `/EFI/BOOT/BOOTX64.EFI` is byte-identical to `shimx64.efi.signed` and
   `grubx64.efi` to `grub-efi-amd64-signed`'s signed image
5. `scripts/make-seed.sh debian-12 && scripts/boot-vm.sh debian-12` → boots under OVMF with
   Secure Boot on, `ssh -p 2222 root@localhost` works, `vm-serial.log` in `build/`, VNC `:5`
6. Template test: `cp -r images/_template images/ubuntu-24.04`, edit `distro.env` (`DISTRO=ubuntu DIB_RELEASE=noble`), dry-run build parses without touching `images/debian-12`
7. `git status --ignored` shows `build/`, `*.qcow2`, `*.iso`, `*.log` ignored; no large binaries staged
