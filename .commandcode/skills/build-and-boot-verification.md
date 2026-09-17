# Verification of Builds and Boots

- Define success criteria **before** making changes: the build succeeds, the seed is created, the VM boots under secure-boot OVMF, and `boot-test.sh` passes.
- Do not tell the process what to do and declare victory — verify. Ideally run the actual chain: `scripts/build-image.sh <distro>` → `scripts/make-seed.sh` → `scripts/boot-test.sh` (in `images/<name>/`).
- Inspect diskimage-builder output, chroot hooks, and cloud-init serial output (`vm-serial.log`) to verify correctness.
- A fix is proven against the real production condition, not a convenient local one (e.g. an empty datasource seed). Verify the actual scenario.
- Carry work through to a verified result without back-and-forth confirmation. The expectation is that the change works in reality.