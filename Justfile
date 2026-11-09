image := "os_build"
org := "bourbonfgiles"
tag := "latest"

[private]
default:
    @just --list

# Check the Justfile's formatting
check:
    just --unstable --fmt --check

# Build the image locally
build:
    #!/usr/bin/env bash
    set -euxo pipefail
    labels=(
        --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        --label "org.opencontainers.image.description=Bazzite GNOME NVIDIA with my packages built in"
        --label "org.opencontainers.image.title={{ image }}"
        --label "org.opencontainers.image.vendor={{ org }}"
    )
    if [[ -z "$(git status -s)" ]]; then
        sha=$(git rev-parse --short HEAD)
        labels+=(
            --label "org.opencontainers.image.source=https://github.com/{{ org }}/{{ image }}/blob/${sha}/Containerfile"
            --label "org.opencontainers.image.version={{ tag }}.$(date +%Y%m%d)-${sha}"
        )
    fi
    podman build "${labels[@]}" --pull=newer --tag "{{ image }}:{{ tag }}" --file Containerfile .

# Split the image into layers by package, for smaller updates
rechunk:
    #!/usr/bin/env bash
    set -euxo pipefail
    graphroot=$(podman info --format '{{ '{{.Store.GraphRoot}}' }}')
    podman run --rm --pull=never --privileged \
      --mount=type=image,src="{{ image }}:{{ tag }}",target=/rpm-ostree \
      --mount=type=bind,src="${graphroot}",target=/run/host-container-storage,rw \
      --mount=type=tmpfs,target=/run/rpm-ostree-storage \
      --entrypoint /usr/bin/rpm-ostree \
      "localhost/{{ image }}:{{ tag }}" \
      compose build-chunked-oci \
      --max-layers 127 \
      --format-version=2 \
      --bootc \
      --rootfs /rpm-ostree \
      --output "containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]localhost/{{ image }}:{{ tag }}"

# Tags CI pushes: latest, the date, and the commit when the tree is clean
tags:
    #!/usr/bin/env bash
    set -euo pipefail
    date=$(date +%Y%m%d)
    tags=("{{ tag }}" "{{ tag }}-${date}" "${date}")
    if [[ -z "$(git status -s)" ]]; then
        sha=$(git rev-parse --short HEAD)
        tags+=("{{ tag }}-${sha}" "{{ tag }}-${date}-${sha}" "${date}-${sha}")
    fi
    echo "${tags[@]}"

# Run shellcheck on the build scripts
lint:
    shellcheck build_files/*.sh
