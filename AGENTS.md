# AGENTS.md — Karpathy-inspired guidelines for qcow2-builder

Guidelines adapted from [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills),
tailored to this disk-image builder repo.

> "The models make wrong assumptions on your behalf and just run along with
> them without checking. They don't surface inconsistencies, don't present
> tradeoffs, and don't push back when they should."

## Project context (read first)

- This repo builds bootable qcow2 images via `disk-image-create` + cloud-init
  NoCloud seed. Debian 12 is the **reference distro**; every other distro is a
  port of `images/debian-12/` + `elements/debian-12/`.
- **UEFI Secure Boot only.** Legacy BIOS is not supported. Every template must
  use `block-device-efi + grub2` and `*.secboot.fd` OVMF firmware — enforced by
  `require_uefi_secure_boot` in `scripts/common.sh`. Never "fix" build or boot
  failures by relaxing this requirement.
- Key paths:
  - `images/<name>/` — per-distro `distro.env`, `build.sh`, `boot-test.sh`, `cloud-init/`
  - `images/_template/` — skeleton for new distros (copy this, don't improvise)
  - `elements/<distro>/` — diskimage-builder custom elements
  - `scripts/` — `build-image.sh`, `make-seed.sh`, `boot-vm.sh`, `common.sh`
  - `docs/adding-new-distro.md` — the porting checklist
- Adding a new distro means: copy `images/_template/`, copy `elements/debian-12/`
  as the new element base, follow `docs/adding-new-distro.md`. Do not invent a
  new structure or a new build flow.

## The four principles

### 1. Think before coding

- **State assumptions explicitly.** If a request is ambiguous (e.g. "make boot
  faster", "build also works for arm64"), present the interpretations and ask —
  do not silently pick one.
- **Stop when confused.** If `pkg-map`, `package-installs.yaml`, or hook
  ordering semantics are unclear, say what's unclear instead of guessing.
- **Push back when warranted.** If a requested change would break the
  Secure Boot contract or deviate from the Debian-12 reference, say so.

### 2. Simplicity first

- Minimum change that solves the problem. No speculative features.
- No abstraction for single-use code. A per-distro hook script duplicated in two
  distros is fine *until* it is provably identical; then, and only then, factor
  it into `elements/common-base/`.
- No "configurability" nobody asked for. Distro-specific values belong in
  `distro.env`, not in new indirection layers.
- If a change adds more than ~50 lines where 20 would do, rewrite it.

### 3. Surgical changes

- Smallest possible diff. Do not reformat, rename variables, reorder hooks, or
  "generalize" files unrelated to the task.
- Never modify or delete code/comments you don't fully understand. This is a
  shell/systems codebase — `pkg-map` selection, `element-deps` ordering, and
  hook staging (`pre-install.d` vs `install.d` vs `post-install.d` vs
  `finalise.d`) have non-obvious semantics.
- Keep cross-distro edits symmetric: a fix in `elements/debian-12/` may also
  apply to `debian-11/`, `debian-13/`, `almalinux-9/` — but only touch those
  files if the fix genuinely applies; note it if you suspect it does.
- Delete dead code when replacing it — no `legacy-` or `old-` shims, no
  commented-out copies of the previous implementation.

### 4. Goal-driven

- Define success criteria **before** making changes: the build succeeds, the
  seed is created, the VM boots under secure-boot OVMF, `boot-test.sh` passes.
- Do not tell the process what to do and declare victory — verify. Ideally run
  the actual chain: `scripts/build-image.sh <distro>` → `scripts/make-seed.sh`
  → `scripts/boot-test.sh` (in `images/<name>/`).
- When debugging, reproduce first. Show the failing log excerpt (e.g. from
  `build/<distro>.log`) before proposing a fix.
- Don't loop until it "works" without checking logs — inspect diskimage-builder
  output, chroot hooks, and cloud-init serial output.

## Hard rules (from Karpathy's list, applied here)

- **No mocks, stubs, or fake success.** If a build step can't be tested locally,
  say so; never pretend `boot-test.sh` passed.
- **No error handling for impossible scenarios.** A script can't run its
  "secure boot check" fallback if the firmware doesn't exist — fail loudly with
  `set -euo pipefail` semantics instead.
- **No fallbacks that mask failures.** If a package is required, install it; do
  not add `|| true` to hide a broken hook.
- **No backward-compat shims.** This repo has no external API consumers.
  When you change `distro.env` naming or an element hook, update all distros
  that use it and delete the old names.
- **No new dependencies** (tools, packages, plugins) unless absolutely needed
  and stated explicitly with the reason.

## Conventions worth preserving

- Bash: `set -euo pipefail` in new scripts; quote variables; prefer
  `scripts/common.sh` helpers over ad-hoc qemu/diskimage-builder invocations.
- Elements: declare deps in `element-deps`, packages in `package-installs.yaml`
  + `pkg-map` (use `pkg-map` for distro-specific package-name differences, e.g.
  secure-boot packages).
- Every new image dir gets: `distro.env`, `build.sh`, `boot-test.sh`,
  `cloud-init/{user-data,meta-data}`, and a `docs/<name>.md`.

## Verify before saying done

For any change touching `images/` or `elements/`:

```bash
scripts/build-image.sh <affected-distro>
```

and, when the change affects boot behavior, run its `boot-test.sh`. Report
exactly what was run and its result. If you couldn't run something, state
that plainly — do not imply it was tested.
