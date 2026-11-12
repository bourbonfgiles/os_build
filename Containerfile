FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable-45@sha256:b70358b001c0ed079edf1f91de395d4f86e02479247314e196a2c5a335c45c5d

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
