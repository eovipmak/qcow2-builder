# Strict UEFI Secure Boot Requirement

- **UEFI Secure Boot only.** Legacy BIOS is not supported.
- Every template must use `block-device-efi + grub2` and `*.secboot.fd` OVMF firmware (enforced by `require_uefi_secure_boot` in `scripts/common.sh`).
- Never attempt to "fix" build or boot failures by relaxing this requirement or attempting to downgrade to MBR/BIOS.
- The `distro.env` file must configure `UEFI_CODE=` and `UEFI_VARS_TEMPLATE=`.
- `block-device-efi` equals GPT + ESP, no LVM, no swap. `grub2` equals signed `grub-efi-amd64-signed` + `shim-signed` for UEFI Secure Boot.
- Debian 12 UEFI setup is the reference standard. Use it as the template/reference.