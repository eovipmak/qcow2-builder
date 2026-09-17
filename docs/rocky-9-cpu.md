# Rocky 9 — kernel panic "Attempted to kill init" on older CPU hosts

## Symptom

Rocky 8 boots fine, but the Rocky 9 template panics almost immediately after
GRUB (dracut gets a few seconds, then):

```
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00
```

exitcode `0x7f00` = init received SIGSEGV at startup → this is a userspace
binary incompatibility, not a kernel/initramfs bug.

## Root cause

The RHEL 9 family builds userland (glibc, systemd, coreutils) against the
**x86-64-v2 microarchitecture level**, which requires the CPU flags
`SSE4.2` and `POPCNT` (i.e. at least an Intel **Nehalem** /
AMD **Barcelona** class CPU). If the hypervisor presents a CPU model without
those flags, `/sbin/init` dies on its first illegal instruction and the
kernel reports the generic "Attempted to kill init" panic above.
Rocky 8 (RHEL 8) only needs x86-64-v1, which is why it boots fine on the
same host.

Verified 2026-09-17 on this repo's `rocky-9.qcow2` (local boot-test with
`-cpu host` PASSes, so the image itself is intact):

| CPU model                | flags                          | result |
|--------------------------|--------------------------------|--------|
| `host` / `Nehalem`       | x86-64-v2 present              | boots to login |
| `Penryn,+sse4.2,+popcnt` | SSE4.2 + POPCNT added          | boots to login |
| `Penryn,+sse4.2`         | only SSE4.2                    | boots to login |
| `Penryn,+popcnt`         | only POPCNT                    | PANIC (SSE4.2 missing) |
| `Penryn` (x86-64-v1)     | neither                        | PANIC |

Reproduce:

```bash
qemu-img create -f qcow2 -b build/rocky-9/rocky-9.qcow2 -F qcow2 /tmp/t.qcow2
qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -cpu Penryn \
  -machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd,readonly=on \
  -drive if=pflash,format=raw,unit=1,file=build/rocky-9/OVMF_VARS.fd \
  -drive file=/tmp/t.qcow2,if=virtio,format=qcow2 \
  -display none -serial file:/tmp/ser.log -daemonize
```

## This cannot be fixed inside the image

Rocky 9 userspace is compiled for x86-64-v2; there is no kernel
flag/package switch to run it on a v1-only CPU. The fix is on the **host /
CloudStack side** so the guest gets a v2-capable CPU model.

## CloudStack remediation

1. **Per-template detail (root admin), targeted fix:**

   ```
   update vm_template_details set name='guest.cpu.mode', value='host-passthrough'
     where template_id=<tpl-id>;   -- in the cloud DB, or via UI Details
   ```
   (equivalently `guest.cpu.mode = host-passthrough` as a template detail).
   or via UI: Template > Details > `guest.cpu.mode` = `host-passthrough`.
   With host-passthrough the guest sees the physical host CPU (requires
   uniform CPU across the host cluster — enable hyperthread matching /
   migration compatibility accordingly).

2. **Per-agent fallback (whole host),** in each
   `/etc/cloudstack/agent/agent.properties` on KVM hosts:

   ```
   guest.cpu.mode=host-passthrough
   # or: guest.cpu.mode=custom  +  guest.cpu.custom.model=Nehalem
   ```
   then `systemctl restart cloudstack-agent`.

3. If a standalone KVM/QEMU hypervisor boots the template directly (not
   CloudStack), pass `-cpu Nehalem` (or a newer model with SSE4.2+POPCNT).
   `Penryn` and QEMU's default `qemu64` custom CPU models are NOT
   sufficient for Rocky 9.
