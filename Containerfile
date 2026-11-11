FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable-45@sha256:a4aa291a847e318fba7a70a920e601394ba429529decd3e27fae04a3c74bf467

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/var/lib/dnf \
    /ctx/build.sh

# Fails the build if anything that keeps the machine bootable or unlockable is missing.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/verify.sh

RUN bootc container lint --fatal-warnings
