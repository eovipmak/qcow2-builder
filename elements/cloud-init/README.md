# cloud-init (shadowed builtin)

Copy of diskimage-builder 3.29's `cloud-init` element, shadowed via
`ELEMENTS_PATH=elements` (wired in `scripts/common.sh`) because the builtin's
`post-install.d/20-enable-cloud-init` enables `cloud-init.service`, which
cloud-init 25.x (Debian 13 trixie) split into `cloud-init-main.service` +
`cloud-init-network.service` — the old name no longer exists and the enable
fails the build.

## Local delta

`post-install.d/20-enable-cloud-init`: enable whichever unit generation is
actually shipped (file check against the target root, since this hook runs in
the chroot). `elements/debian-13/post-install.d/89-debian-13-setup` carries
the same conditional; bookworm/bullseye keep the old unit and take the
`else` branch. All other files are unmodified copies of the 3.29 builtin —
delete this directory once DIB itself handles the split unit names.
