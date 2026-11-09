FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable-45@sha256:b0164dfdf76f32bf6e169d4c8b7caeb67e33f2c27a1e86130aec92659cf9d3c1

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
