# Surgical and Symmetric Changes

- Smallest possible diff. Do not reformat, rename variables, reorder hooks, or "generalize" files unrelated to the task.
- Never modify or delete code/comments you don't fully understand. This is a shell/systems codebase.
- Keep cross-distro edits symmetric: a fix in `elements/debian-12/` may also apply to `debian-11/`, `debian-13/`, `almalinux-9/` — but only touch those files if the fix genuinely applies; note it if you suspect it does.
- Delete dead code when replacing it — no `legacy-` or `old-` shims, no commented-out copies of the previous implementation.
- Expects a fix/change to be rolled out consistently across all maintained versions (e.g., if changing UEFI switch for Debian 11, apply the configuration for Debian 13 as well).
- Apply permanent fixes at the source of truth (the image build / repo config in `images/` or `elements/`), not a hand edit on the affected running host.
- No abstraction for single-use code. Wait until it is provably identical across distros before factoring into `elements/common-base/`.