#!/bin/bash
set -euxo pipefail

IMAGE=ghcr.io/bourbonfgiles/os_build
PACKAGES=(albert ghostty bpftrace bcc-tools bpftool perf podman-docker)

cp -avf /ctx/system_files/. /

# Third-party repos exist only during the build; the image ships none.
# Albert: never Rawhide, whose builds need a newer Qt than the release ships.
cat >/etc/yum.repos.d/albert.repo <<'REPO'
[albert]
name=albert
baseurl=https://download.opensuse.org/repositories/home:/manuelschneid3r/Fedora_$releasever/
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/home:/manuelschneid3r/Fedora_$releasever/repodata/repomd.xml.key
REPO
dnf5 -y copr enable scottames/ghostty

dnf5 -y install "${PACKAGES[@]}"

dnf5 -y copr disable scottames/ghostty
rm -f /etc/yum.repos.d/albert.repo /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo

# Albert starts with every login.
install -Dm0644 /usr/share/applications/albert.desktop /etc/xdg/autostart/albert.desktop

# k3d's runtime and kube.internal DNS; config is in system_files.
systemctl enable podman.socket kube-internal-dns.service

# Updates must be signed by this repo's key; Bazzite's own policy is kept.
jq --arg img "$IMAGE" '.transports.docker[$img] = [{
    type: "sigstoreSigned",
    keyPath: "/etc/pki/containers/os_build.pub",
    signedIdentity: {type: "matchRepository"}
  }]' /etc/containers/policy.json >/tmp/policy.json
install -m0644 /tmp/policy.json /etc/containers/policy.json
printf 'docker:\n  %s:\n    use-sigstore-attachments: true\n' "$IMAGE" \
  >/etc/containers/registries.d/os_build.yaml
