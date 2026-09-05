# base (shadowed builtin)

Copy of diskimage-builder 3.29's `base` element, shadowed via
`ELEMENTS_PATH=elements` (wired in `scripts/common.sh`) because the builtin's
`pre-install.d/03-baseline-tools` installs `software-properties-common`, which
Debian 13 (trixie) removed from its archives entirely — the whole build 404s
on it. Nothing else in DIB calls `add-apt-repository`.

## Local delta

`pre-install.d/03-baseline-tools`: on `DIB_RELEASE=trixie` install only
`apt-transport-https`; every other release keeps the upstream package list.
All other files are unmodified copies of the 3.29 builtin — delete this
directory once DIB itself handles trixie, the same way `autoupdates/`
documents its own removal condition.
