# Per-distro DIB element overrides

Copy this directory to `elements/<name>/` for distro-specific customization:

- `package-installs.yaml` — declarative packages (Debian-family `apt`, RHEL-family `dnf/yum`)
  (`arch:` / `not-arch:` gate per-arch packages; see `elements/debian-12/` example)
- `pkg-map` — JSON namespace mapping virtual package names to distro packages;
  referenced via `package-installs.yaml` entries (element name = this dir name).
  See `elements/debian-12/pkg-map` (secure-boot grub/shim mapping example)
- `post-install.d/89-<name>-setup` — chrooted shell, must be executable,
  `set -eu -o pipefail`, keep <100 lines. Runs AFTER `cloud-init`'s
  `20-enable-cloud-init` so service/config overrides win.
  (`install.d/` hooks run BEFORE `-p` extra packages — prefer `post-install.d/`.)

Reference `elements/debian-12/` for the full example. `ELEMENTS_PATH` is wired
in `scripts/common.sh` (`build_image()` prepends `elements/`), so
`CUSTOM_ELEMENTS="<name>"` resolves without extra exports.
DIB hook order: `install.d` → `-p PACKAGES` → `post-install.d` → `finalise.d`.
