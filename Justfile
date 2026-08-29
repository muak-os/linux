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
push := env_var_or_default("PUSH", "false")
latest := env_var_or_default("LATEST", "false")

# Architecture

[private]
_arch_env := env_var_or_default("ARCH", "amd64")
oci_arch := if _arch_env == "arm64" { "arm64" } else { "amd64" }

# Container runtime

container_runtime := env_var_or_default("CONTAINER_RUNTIME", "podman")

# Colors

cyan := '\e[36m'
reset := '\e[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Recipes
# ─────────────────────────────────────────────────────────────────────────────

# Build (and optionally push) the Muak Linux kernel OCI image
[script]
build:
    image="{{ registry }}/linux:{{ tag }}"
    tags="--tag ${image}"
    if [ "{{ latest }}" = "true" ]; then
        tags="${tags} --tag {{ registry }}/linux:latest"
    fi

    if [ "{{ container_runtime }}" = "podman" ]; then
        cmd="podman build"
        push_flags=""
    else
        cmd="docker buildx build --provenance=false"
        if [ "{{ push }}" = "true" ]; then
            push_flags="--push"
        else
            push_flags=""
        fi
    fi

    printf "{{ cyan }}Building kernel image: {{ registry }}/linux (push={{ push }}, latest={{ latest }}){{ reset }}\n"
    ${cmd} \
        --platform=linux/{{ oci_arch }} \
        --progress=auto \
        --build-arg ALPINE_VERSION={{ alpine_version }} \
        --build-arg SOURCE_DATE_EPOCH=0 \
        ${KERNEL_SIGNING:-} \
        ${push_flags} \
        $(just _cache-from linux) $(just _cache-to linux) \
        ${tags} \
        --file Dockerfile \
        .

    if [ "{{ container_runtime }}" = "podman" ] && [ "{{ push }}" = "true" ]; then
        podman push --tls-verify=false "${image}"
        if [ "{{ latest }}" = "true" ]; then
            podman push --tls-verify=false "{{ registry }}/linux:latest"
        fi
    fi

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
