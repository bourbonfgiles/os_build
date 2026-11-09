#!/bin/bash
# Build-time guards. Each failure names what would break on the machine.
set -uo pipefail

IMAGE=ghcr.io/bourbonfgiles/os_build
failures=0
fail() { echo "VERIFY FAILED: $*" >&2; failures=$((failures + 1)); }

kver=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -1)
initramfs=/usr/lib/modules/$kver/initramfs.img

# Encryption: the system drive is unlocked by passphrase in the initramfs.
[[ -f $initramfs ]] || fail "no initramfs for kernel $kver: the machine will not boot"
lsinitrd -m "$initramfs" >/tmp/modules 2>/dev/null
for module in crypt systemd-cryptsetup btrfs; do
  grep -qx "$module" /tmp/modules || fail "initramfs lacks dracut module '$module': the LUKS system drive cannot be unlocked"
done
lsinitrd "$initramfs" >/tmp/files 2>/dev/null
grep -q 'kernel/drivers/md/dm-crypt.ko' /tmp/files ||
  fail "initramfs lacks dm-crypt.ko: the LUKS system drive cannot be unlocked"

# Encryption: drives are only ever unlocked by hand.
[[ -s /etc/crypttab ]] && fail "image ships /etc/crypttab entries: drives must only be unlocked by hand"
compgen -G '/etc/cryptsetup-keys.d/*' >/dev/null && fail "image ships LUKS keyfiles in /etc/cryptsetup-keys.d"
compgen -G '/usr/lib/systemd/system/*.wants/systemd-cryptsetup@*' >/dev/null &&
  fail "image enables a systemd-cryptsetup unit: drives must only be unlocked by hand"

# NVIDIA: the kernel module must match the image's kernel.
rpm -q kmod-nvidia >/dev/null || fail "kmod-nvidia missing: no NVIDIA driver"
[[ -n $(find "/usr/lib/modules/$kver" -name 'nvidia.ko*' -print -quit) ]] ||
  fail "no nvidia.ko for kernel $kver: the NVIDIA module does not match the kernel"

# BCC compiles against the running kernel's headers.
[[ $(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-devel-matched 2>/dev/null) == "$kver" ]] ||
  fail "kernel-devel-matched does not match kernel $kver: BCC tools will not compile"

# Added packages, plus Steam from the base.
for package in $(</ctx/packages) steam; do
  rpm -q "$package" >/dev/null || fail "package $package missing"
done
missing=$(ldd /usr/bin/albert 2>/dev/null | grep -c 'not found')
[[ $missing -eq 0 ]] || fail "albert has $missing missing libraries"
[[ -f /etc/xdg/autostart/albert.desktop ]] || fail "albert autostart entry missing"

# No third-party build repos may leak into the image.
grep -rlsE 'manuelschneid3r|scottames' /etc/yum.repos.d && fail "build-only repo files left in /etc/yum.repos.d"

# Local cluster: k3d's rootful Podman socket, kube.internal DNS, DNS over TLS.
for unit in podman.socket kube-internal-dns.service; do
  systemctl is-enabled -q "$unit" || fail "$unit is not enabled: the k3d cluster or kube.internal will not work"
done
[[ -f /usr/lib/systemd/resolved.conf.d/dns-over-tls.conf ]] || fail "DNS-over-TLS drop-in missing"
jq -e '.name == "podman" and .dns_enabled' /etc/containers/networks/podman.json >/dev/null ||
  fail "default podman network has no DNS: rootful containers query Cloudflare in plain text"

# Updates: this image's signature policy must be valid and point at a real key.
jq -e --arg img "$IMAGE" '.transports.docker[$img][0].type == "sigstoreSigned"' \
  /etc/containers/policy.json >/dev/null || fail "policy.json has no sigstoreSigned entry for $IMAGE: updates cannot be verified"
key=$(jq -r --arg img "$IMAGE" '.transports.docker[$img][0].keyPath' /etc/containers/policy.json)
[[ -s $key ]] || fail "signing public key $key missing: updates cannot be verified"
jq -e '.default[0].type == "reject"' /etc/containers/policy.json >/dev/null ||
  fail "default image policy is no longer reject"

if ((failures)); then
  echo "$failures verify check(s) failed" >&2
  exit 1
fi
echo "verify: all checks passed (kernel $kver)"
