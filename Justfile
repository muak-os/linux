# Muak Linux kernel OCI image build
#
# Prerequisites: docker/podman, just, git
# Run `just --list` for available recipes

set shell := ["bash", "-euo", "pipefail", "-c"]
set script-interpreter := ["bash", "-euo", "pipefail"]
set positional-arguments

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

# Global settings

alpine_version := "3.24"
registry := env_var_or_default("REGISTRY", "ghcr.io/muak-os")
tag := env_var_or_default("TAG", kernel_version)
toolchain := env_var_or_default("TOOLCHAIN", "ghcr.io/muak-os/toolchain@sha256:b5202e06f797ab99a766617238d181fede148fa8f83a15d218b33599752de4fa")
push := env_var_or_default("PUSH", "true")
kernel_version := env_var_or_default("KERNEL_VERSION", "7.2.11")

# Architecture

[private]
_arch := env_var_or_default("ARCH", "")
oci_arch := if _arch == "arm64" { "arm64" } else { "amd64" }

# Container runtime

container_runtime := env_var_or_default("CONTAINER_RUNTIME", "podman")
push_arg := if container_runtime == "podman" { "" } else { if push == "true" { "--push" } else { "" } }

# Colors

cyan := '\e[36m'
reset := '\e[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Main Recipes
# ─────────────────────────────────────────────────────────────────────────────

# Full local development build (oci -> repack)
dev: oci repack

# ─────────────────────────────────────────────────────────────────────────────
# OCI Images
# ─────────────────────────────────────────────────────────────────────────────

# Build (and optionally push) the linux kernel OCI image
[script]
oci:
    image="{{ registry }}/linux:{{ tag }}"
    tags="--tag ${image}"

    if [ "{{ container_runtime }}" = "podman" ]; then
        cmd="podman build"
    else
        cmd="docker buildx build --provenance=false"
    fi

    printf "{{ cyan }}Building kernel image: {{ registry }}/linux (push={{ push }}){{ reset }}\n"
    ${cmd} \
        --platform=linux/{{ oci_arch }} \
        --progress=auto \
        --build-arg ALPINE_VERSION={{ alpine_version }} \
        --build-arg KERNEL_VERSION={{ kernel_version }} \
        --build-arg TOOLCHAIN={{ toolchain }} \
        --build-arg SOURCE_DATE_EPOCH=0 \
        ${KERNEL_SIGNING:-} \
        {{ push_arg }} \
        $(just _cache-from linux) $(just _cache-to linux) \
        ${tags} \
        --file Dockerfile \
        .

    if [ "{{ container_runtime }}" = "podman" ] && [ "{{ push }}" = "true" ]; then
        {{ container_runtime }} push "${image}"
    fi

# Merge per-platform images into a multi-arch OCI index
[script]
merge *sources:
    {{ container_runtime }} run --rm --network=host \
        -e KOCI_REGISTRY_USERNAME -e KOCI_REGISTRY_PASSWORD \
        {{ toolchain }} \
        /koci merge \
            --image "{{ registry }}/linux" \
            --tag "{{ tag }}" \
            {{ sources }}

# Repack an OCI image's layers into eStargz, in place.
[arg("image", long="image")]
repack image=(registry + "/linux:" + tag):
    @printf "{{ cyan }}Repacking OCI image {{ image }}{{ reset }}\n"
    {{ container_runtime }} run --rm --network=host \
        -e KOCI_REGISTRY_USERNAME -e KOCI_REGISTRY_PASSWORD \
        {{ toolchain }} \
        /koci repack \
            --image "{{ image }}"

# ─────────────────────────────────────────────────────────────────────────────
# Testing
# ─────────────────────────────────────────────────────────────────────────────

# Check kernel config, cmdline & sysctl against KSPP security hardening recommendations
[script]
kspp:
    config="configs/config-{{ oci_arch }}"
    cmdline="cmdline/cmdline-{{ oci_arch }}.txt"
    sysctl="sysctl/sysctl-{{ oci_arch }}.conf"
    printf "{{ cyan }}Checking kernel config, cmdline & sysctl against KSPP recommendations{{ reset }}\n"
    {{ container_runtime }} run --rm --network=host \
        -v {{ justfile_directory() }}/$config:/config:ro \
        -v {{ justfile_directory() }}/$cmdline:/cmdline:ro \
        -v {{ justfile_directory() }}/$sysctl:/sysctl:ro \
        docker.io/alpine:{{ alpine_version }} sh -c '\
        apk add --no-cache git python3 >/dev/null 2>&1 && \
        git clone --depth 1 --quiet https://github.com/a13xp0p0v/kernel-hardening-checker.git /tmp/khc && \
        /tmp/khc/bin/kernel-hardening-checker -c /config -l /cmdline -s /sysctl'

# ─────────────────────────────────────────────────────────────────────────────
# Private Helpers
# ─────────────────────────────────────────────────────────────────────────────

[private]
_cache-from name:
    @if [ "{{ env_var_or_default("GITHUB_ACTIONS", "false") }}" = "true" ]; then printf '%s' "--cache-from=type=registry,ref={{ registry }}/{{ name }}:buildcache-{{ oci_arch }}"; fi

[private]
_cache-to name:
    @if [ "{{ env_var_or_default("GITHUB_ACTIONS", "false") }}" = "true" ] && [ "{{ push }}" = "true" ]; then printf '%s' "--cache-to=type=registry,ref={{ registry }}/{{ name }}:buildcache-{{ oci_arch }},mode=max"; fi
