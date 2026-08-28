# muak-os/linux

The Linux kernel package for [Muak](https://github.com/muak-os/muak): a minimal,
immutable, API-driven Linux distribution for running VMs.

This repository builds a single OCI image, `ghcr.io/muak-os/linux`, containing:

- `/vmlinuz` — the signed (or unsigned) kernel image
- `/cmdline` — the kernel command line
- `/lib/modules` — compressed kernel modules (`zstd`, `depmod`-indexed)

## Architecture

The kernel is built for two architectures, selected with the `ARCH` build variable
(default `amd64`):

| `ARCH`  | Target                 | Kernel binary             |
|---------|------------------------|---------------------------|
| `amd64` | `linux/amd64` (x86_64)  | `arch/x86/boot/bzImage`   |
| `arm64` | `linux/arm64` (aarch64) | `arch/arm64/boot/Image`   |

Per-architecture inputs live under `configs/`, `cmdline/`, and `sysctl/` and are
selected by the Dockerfile via `TARGETARCH`. Build for arm64 with:

```sh
ARCH=arm64 just build
```

## Local Development

A local OCI registry makes iterative testing easy:

```sh
podman run -d -p 5000:5000 --name registry docker.io/library/registry:3

# Build and push the unsigned kernel to the local registry
REGISTRY="localhost:5000" PUSH="true" just build
```

## Secure Boot Signing

The kernel is PE-signed with `sbsign` when a signing key is provided. The signing
key is **private** and must never be committed.

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
   KERNEL_SIGNING="--secret id=kernel_key,src=certs/kernel-signing-key.pem" REGISTRY="localhost:5000" PUSH="true" just build
   ```

In CI, `KERNEL_SIGNING_KEY` is supplied as a repository secret and materialized
to `/tmp/kernel-signing-key.pem` for the duration of the build (see
`.github/workflows/build.yaml`). The temporary key is removed in a cleanup step.

To enroll the public cert in a Secure Boot setup (MOK / DB), use
`certs/kernel-signing-cert.pem` (convert to DER if your firmware requires it).

## Hardening

Keep configs, cmdlines, and sysctls aligned with the KSPP recommendations:

```sh
just kspp
```
