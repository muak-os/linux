# muak-os/linux

The Linux kernel package for [Muak](https://github.com/muak-os/muak): a minimal,
immutable, API-driven Linux distribution for running VMs.

This repository builds a single OCI image, `ghcr.io/muak-os/linux`, containing:

- `/vmlinuz` — the signed (or unsigned) kernel image
- `/cmdline` — the kernel command line
- `/lib/modules` — compressed kernel modules (`zstd`, `depmod`-indexed)

## Kernel Signing

The kernel is PE-signed with `sbsign` when a signing key is provided.

1. Generate a key/cert pair (once):

```sh
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout certs/kernel-signing-key.pem \
  -out certs/kernel-signing-cert.pem \
  -days 3650 -subj "/CN=Muak Kernel Signing Key"
```

`certs/kernel-signing-cert.pem` is the **public** certificate and is committed.
`certs/kernel-signing-key.pem` is the **private** key and is gitignored.

2. Build with signing enabled by mounting the key as a Docker secret:

```sh
KERNEL_SIGNING="--secret id=kernel_key,src=certs/kernel-signing-key.pem" REGISTRY="localhost:5000" just build
```

## Hardening

Keep configs, cmdlines, and sysctls aligned with the KSPP recommendations:

```sh
just kspp
```
