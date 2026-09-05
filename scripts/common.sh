#!/bin/bash
set -eu -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_distro() {
  local name="$1"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/images/$name/distro.env"
  DISTRO_NAME="$name"
  BUILD_DIR="$REPO_ROOT/build/$OUTPUT"
  mkdir -p "$BUILD_DIR"
  export DIB_RELEASE
  export ARCH="${ARCH:-amd64}"
  # autoupdates' root.d hook reads these on the host, outside the chroot
  if [ -n "${DIB_DEB_UPDATES_CONF:-}" ]; then
    export DIB_DEB_UPDATES_CONF
  fi
  if [ -n "${DIB_YUM_UPDATES_CONF:-}" ]; then
    export DIB_YUM_UPDATES_CONF
  fi
  # Per-distro apt source override (DIB 3.29 defaults go stale: trixie
  # security moved to the -security suite path, bullseye-backports was
  # removed from the main mirror). debian-minimal's environment.d only
  # fills DIB_APT_SOURCES_CONF when unset, so an exported value wins.
  if [ -n "${DIB_APT_SOURCES_CONF:-}" ]; then
    export DIB_APT_SOURCES_CONF
  fi
}

build_image() {
  # Prepend repo elements dir so custom elements resolve alongside builtins
  # (no trailing colon: empty ELEMENTS_PATH entries abort the build).
  if [ -n "${ELEMENTS_PATH:-}" ]; then
    export ELEMENTS_PATH="$REPO_ROOT/elements:$ELEMENTS_PATH"
  else
    export ELEMENTS_PATH="$REPO_ROOT/elements"
  fi
  local args=(-o "$BUILD_DIR/$OUTPUT" -t "$TYPE" -a "$ARCH")
  read -ra elems <<< "$DIB_ELEMENTS"
  args+=("${elems[@]}")
  if [ -n "${CUSTOM_ELEMENTS:-}" ]; then
    read -ra custom <<< "$CUSTOM_ELEMENTS"
    args+=("${custom[@]}")
  fi
  if [ -n "${PACKAGES:-}" ]; then
    args+=(-p "$PACKAGES")
  fi
  args+=(--checksum)
  DIB_RELEASE="$DIB_RELEASE" disk-image-create "${args[@]}"
}

make_seed() {
  cloud-localds "$BUILD_DIR/seed.iso" \
    "$REPO_ROOT/images/$DISTRO_NAME/cloud-init/user-data" \
    "$REPO_ROOT/images/$DISTRO_NAME/cloud-init/meta-data"
}

boot_vm() {
  # Boot a throwaway overlay, never the master image. A booted guest writes
  # persistently: dhcp-all-interfaces appends its NIC stanzas into
  # /etc/network/interfaces, cloud-init creates /var/lib/cloud + a
  # /etc/network/interfaces.d/50-cloud-init, and systemd fills in /etc/machine-id.
  # Testing against the master baked all of that QEMU-specific state into the
  # published template (stale `enp0s3` entries, a pinned instance-id that makes
  # set-passwords skip, and one shared machine-id -> identical DHCPv6 DUIDs).
  local disk="$BUILD_DIR/$OUTPUT.$TYPE"
  local overlay="$BUILD_DIR/boot-test-overlay.qcow2"
  rm -f "$overlay"
  qemu-img create -f qcow2 -b "$disk" -F "$TYPE" "$overlay" >/dev/null
  local qemu_args=(-enable-kvm -m "${MEM_MB:-2048}" -smp "${SMP:-2}" -cpu host)
  if [ -n "${UEFI_CODE:-}" ] && [ -f "${UEFI_CODE:-}" ]; then
    local vars_file="$BUILD_DIR/OVMF_VARS.fd"
    if [ ! -f "$vars_file" ] || [ -n "${UEFI_VARS_TEMPLATE:-}" ] && [ "$UEFI_VARS_TEMPLATE" -nt "$vars_file" ]; then
      cp "${UEFI_VARS_TEMPLATE:-/usr/share/OVMF/OVMF_VARS_4M.fd}" "$vars_file"
    fi
    qemu_args+=(-machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on)
    qemu_args+=(-drive "if=pflash,format=raw,unit=0,file=${UEFI_CODE},readonly=on")
    qemu_args+=(-drive "if=pflash,format=raw,unit=1,file=$vars_file")
  fi
  qemu_args+=(
    -device virtio-serial-pci
    -chardev "socket,id=qga0,path=$BUILD_DIR/qga.sock,server=on,wait=off"
    -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
  )
  qemu-system-x86_64 "${qemu_args[@]}" \
    -drive "file=$overlay,if=virtio,format=qcow2" \
    -drive "file=$BUILD_DIR/seed.iso,if=virtio,format=raw,readonly=on" \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT:-2222}-:22" -device virtio-net-pci,netdev=net0 \
    -vnc "0.0.0.0${VNC_DISPLAY:-:5}" -serial "file:$BUILD_DIR/vm-serial.log" -display none -daemonize
}
