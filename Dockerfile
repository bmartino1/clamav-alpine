# Select a maintained official ClamAV base image.
# Default tracks the current patch release in the ClamAV 1.4 line.
# For a reproducible release build, override with an exact tag such as:
#   docker build --build-arg CLAMAV_TAG=1.4.6_base ...
ARG CLAMAV_TAG=1.4_base
FROM clamav/clamav:${CLAMAV_TAG}

USER root

LABEL org.opencontainers.image.title="clamav-alpine"
LABEL org.opencontainers.image.description="One-shot ClamAV clamdscan filesystem scanner"
LABEL org.opencontainers.image.source="https://github.com/bmartino1/clamav-alpine"
LABEL org.opencontainers.image.url="https://github.com/bmartino1/clamav-alpine"
LABEL org.opencontainers.image.vendor="bmartino1"
LABEL org.opencontainers.image.licenses="MIT"

# Keep a complete, image-local copy of the maintainer build payload.
#
# This is intentionally separate from /etc/clamav. If an end user bind-mounts
# an empty host directory over /etc/clamav, Docker hides the config files that
# were baked into that path. check_files.sh can then seed ONLY the missing
# files from /build into the mounted /etc/clamav directory on first run.
# Existing end-user config files are never replaced.
COPY build/ /build/

# Install the normal runtime copies used by the one-shot workflow.
# The pristine copies under /build remain available for first-run recovery.
RUN mkdir -p \
        /etc/clamav \
        /var/lib/clamav \
        /var/log/clamav \
        /run/clamav \
    && cp /build/clamd.conf /etc/clamav/clamd.conf \
    && cp /build/freshclam.conf /etc/clamav/freshclam.conf \
    && cp /build/check_files.sh /usr/local/bin/check_files.sh \
    && cp /build/apply_exclude_paths.sh /usr/local/bin/apply_exclude_paths.sh \
    && cp /build/Build_Freshclam_ClamD.sh /usr/local/bin/Build_Freshclam_ClamD.sh \
    && cp /build/clamdscan.sh /usr/local/bin/clamdscan.sh \
    && chmod 0644 \
        /build/clamd.conf \
        /build/freshclam.conf \
        /etc/clamav/clamd.conf \
        /etc/clamav/freshclam.conf \
    && chmod 0755 \
        /build/check_files.sh \
        /build/apply_exclude_paths.sh \
        /build/Build_Freshclam_ClamD.sh \
        /build/clamdscan.sh \
        /usr/local/bin/check_files.sh \
        /usr/local/bin/apply_exclude_paths.sh \
        /usr/local/bin/Build_Freshclam_ClamD.sh \
        /usr/local/bin/clamdscan.sh

# Override the official image's normal long-running service behavior.
# This image performs one scan and exits when that scan is finished.
#
# Order is intentional:
#   1. check_files.sh
#      - create required runtime directories
#      - seed ONLY missing /etc/clamav config files from /build
#      - preserve existing end-user config files unchanged
#      - archive previous logs and prepare clean active logs
#   2. apply_exclude_paths.sh
#      - rewrite only the Docker-managed exclusion block from EXCLUDE_PATHS
#      - preserve all manual clamd.conf edits outside that block
#   3. Build_Freshclam_ClamD.sh
#      - update signatures
#      - start clamd and wait until it is ready
#   4. clamdscan.sh
#      - scan the configured folders and save/stream results
ENTRYPOINT ["/bin/sh", "-c"]
CMD ["/usr/local/bin/check_files.sh && /usr/local/bin/apply_exclude_paths.sh && /usr/local/bin/Build_Freshclam_ClamD.sh && /usr/local/bin/clamdscan.sh"]
