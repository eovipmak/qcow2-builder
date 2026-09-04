# autoupdates (vendored)

Vendored copy of diskimage-builder's `autoupdates` element. It is **not** in the
DIB 3.29 package this repo builds with, so the element is carried here and
resolved through `ELEMENTS_PATH=elements` (wired in `scripts/common.sh`).
`ELEMENTS_PATH` is searched before DIB's builtins, so if DIB is upgraded past
the release that introduced this element, this copy shadows the builtin — delete
this directory at that point and keep only `50unattended-upgrades` (see below).

Upstream: `diskimage_builder/elements/autoupdates` (Apache-2.0, © 2024 ECMWF) —
<https://docs.openstack.org/diskimage-builder/latest/elements/autoupdates/README.html>

## What it does

- `pkg-map` + `package-installs.yaml` → installs `unattended-upgrades`
  (Debian family) or `dnf-automatic` (Red Hat family)
- `root.d/61-create-update-config` → copies `DIB_DEB_UPDATES_CONF`
  (host-side path) to `/etc/apt/apt.conf.d/50unattended-upgrades`; RHEL uses
  `DIB_YUM_UPDATES_CONF` → `/etc/dnf/automatic.conf`. Setting neither is a
  warning, not an error, and leaves the distro default policy in place
- `post-install.d/82-enable-autoupdate` → `systemctl enable unattended-upgrades.service`

## Local delta

`post-install.d/83-enable-periodic-updates` is **not upstream**. Upstream's
`82-` hook enables a oneshot service that nothing schedules; on Debian the
schedule comes from `apt-daily.timer` / `apt-daily-upgrade.timer` calling
`/usr/lib/apt/apt.systemd.daily`, whose `APT::Periodic::*` defaults are all `0`.
So `83-` writes `/etc/apt/apt.conf.d/20auto-upgrades` and enables the two
timers. Without it the image appears to have automatic updates but never
applies one.

## Per-image policy

The actual patch policy lives with the image, not here:
`images/<distro>/50unattended-upgrades`, pointed at by `DIB_DEB_UPDATES_CONF` in
`images/<distro>/distro.env` (exported by `scripts/common.sh`).
