# Muak Linux kernel OCI image build
#
# Prerequisites: docker/podman, just, git
# Run `just --list` for available recipes

set positional-arguments := true
set shell := ["bash", "-euo", "pipefail", "-c"]
set script-interpreter := ["bash", "-euo", "pipefail"]

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

# Global settings

alpine_version := "3.24"
registry := env_var_or_default("REGISTRY", "ghcr.io/muak-os")
tag := env_var_or_default("TAG", "latest")
tools := env_var_or_default("TOOLS", registry + "/tools:latest")
push := env_var_or_default("PUSH", "true")
latest := env_var_or_default("LATEST", "false")

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

# Full local development build (oci → annotate)
dev: oci annotate

# ─────────────────────────────────────────────────────────────────────────────
# OCI Images
# ─────────────────────────────────────────────────────────────────────────────

# Build (and optionally push) the linux kernel OCI image
[script]
oci:
    image="{{ registry }}/linux:{{ tag }}"
    tags="--tag ${image}"
    if [ "{{ latest }}" = "true" ]; then
        tags="${tags} --tag {{ registry }}/linux:latest"
    fi

    if [ "{{ container_runtime }}" = "podman" ]; then
        cmd="podman build"
    else
        cmd="docker buildx build --provenance=false"
    fi

    printf "{{ cyan }}Building kernel image: {{ registry }}/linux (push={{ push }}, latest={{ latest }}){{ reset }}\n"
    ${cmd} \
        --platform=linux/{{ oci_arch }} \
        --progress=auto \
        --build-arg ALPINE_VERSION={{ alpine_version }} \
        --build-arg TOOLS={{ tools }} \
        --build-arg SOURCE_DATE_EPOCH=0 \
        ${KERNEL_SIGNING:-} \
        {{ push_arg }} \
        $(just _cache-from linux) $(just _cache-to linux) \
        ${tags} \
        --file Dockerfile \
        .

    if [ "{{ container_runtime }}" = "podman" ] && [ "{{ push }}" = "true" ]; then
        {{ container_runtime }} push "${image}"
        if [ "{{ latest }}" = "true" ]; then {{ container_runtime }} push "{{ registry }}/linux:latest"; fi
    fi

# Merge per-platform images into a multi-arch OCI index
[script]
merge *sources:
    tags=""
    if [ "{{ latest }}" = "true" ]; then
        tags="--tag latest"
    fi
    {{ container_runtime }} run --rm --network=host \
        -e KOCI_REGISTRY_USERNAME -e KOCI_REGISTRY_PASSWORD \
        {{ tools }} \
        /koci merge \
            --image "{{ registry }}/linux" \
            --tag "{{ tag }}" \
            ${tags} \
            {{ sources }}

# Annotate an OCI image in the registry with per-entry sizes.
[arg("image", long="image")]
annotate image=(registry + "/linux:" + tag):
    @printf "{{ cyan }}Annotating OCI image {{ image }}{{ reset }}\n"
    {{ container_runtime }} run --rm --network=host \
        -e KOCI_REGISTRY_USERNAME -e KOCI_REGISTRY_PASSWORD \
        {{ tools }} \
        /koci annotate \
            --image "{{ image }}" \
            --annotation dev.muak.sizes \
            --exclude lib/modules

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
