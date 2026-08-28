# Linux kernel build fobuild
#
# Prerequisites: docker/podman, just, git
# Run `just --list` for available recipes

set positional-arguments := true
set shell := ["bash", "-euo", "pipefail", "-c"]
set script-interpreter := ["bash", "-euo", "pipefail"]

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

alpine_version := "3.24"
registry := env_var_or_default("REGISTRY", "ghcr.io/muak-os")
tag := env_var_or_default("TAG", "latest")
push := env_var_or_default("PUSH", "false")
latest := env_var_or_default("LATEST", "false")
kernel_signing := env_var_or_default("KERNEL_SIGNING", "")

# Architecture
_arch_env := env_var_or_default("ARCH", "amd64")
arch := if _arch_env == "arm64" { "arm64" } else { "amd64" }
oci_arch := if arch == "arm64" { "arm64" } else { "amd64" }

# Container runtime
container_runtime := env_var_or_default("CONTAINER_RUNTIME", "podman")
build_cmd := if container_runtime == "podman" { "podman build" } else { "docker buildx build" }
push_cmd := if push == "true" {
    if container_runtime == "podman" { "podman push --tls-verify=false" } else { "docker push" }
} else {
    "true"
}

# ─────────────────────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────────────────────

cyan := '\e[36m'
reset := '\e[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Recipes
# ─────────────────────────────────────────────────────────────────────────────

# Build the Muak Linux kernel OCI image
[script]
build:
    image="{{ registry }}/linux:{{ tag }}"
    tags="--tag ${image}"
    if [ "{{ latest }}" = "true" ]; then
        tags="${tags} --tag {{ registry }}/linux:latest"
    fi
    printf "{{ cyan }}Building kernel image: {{ registry }}/linux (push={{ push }}, latest={{ latest }}){{ reset }}\n"
    {{ build_cmd }} \
        --platform=linux/{{ oci_arch }} \
        --progress=auto \
        --build-arg ALPINE_VERSION={{ alpine_version }} \
        --build-arg SOURCE_DATE_EPOCH=0 \
        {{ kernel_signing }} \
        ${tags} \
        --file Dockerfile \
        .
    {{ push_cmd }} "${image}"
    if [ "{{ latest }}" = "true" ]; then
        {{ push_cmd }} "{{ registry }}/linux:latest"
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
