# Select a maintained official ClamAV base image.
#
# The _base image intentionally contains no signature database.
# This project downloads signatures during its own build and stores
# an immutable first-run/offline copy under /build/clamav-db.
#
# For a reproducible engine release, override with an exact tag:
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

# ============================================================
# Maintainer payload
# ============================================================
#
# Keep a complete image-local copy of the maintainer build payload.
#
# /build is intentionally separate from runtime bind mounts.
#
# This allows:
#
#   /build/clamd.conf
#       -> seed missing /etc/clamav/clamd.conf
#
#   /build/freshclam.conf
#       -> seed missing /etc/clamav/freshclam.conf
#
#   /build/clamav-db/
#       -> seed an empty /var/lib/clamav database volume
#
COPY build/ /build/

# ============================================================
# Install runtime files
# ============================================================
RUN set -eu; \
    mkdir -p \
        /etc/clamav \
        /var/lib/clamav \
        /var/log/clamav \
        /run/clamav \
        /build/clamav-db; \
    \
    cp /build/clamd.conf /etc/clamav/clamd.conf; \
    cp /build/freshclam.conf /etc/clamav/freshclam.conf; \
    \
    cp /build/check_files.sh /usr/local/bin/check_files.sh; \
    cp /build/apply_exclude_paths.sh /usr/local/bin/apply_exclude_paths.sh; \
    cp /build/Build_Freshclam_ClamD.sh /usr/local/bin/Build_Freshclam_ClamD.sh; \
    cp /build/clamdscan.sh /usr/local/bin/clamdscan.sh; \
    \
    chmod 0644 \
        /build/clamd.conf \
        /build/freshclam.conf \
        /etc/clamav/clamd.conf \
        /etc/clamav/freshclam.conf; \
    \
    chmod 0755 \
        /build/check_files.sh \
        /build/apply_exclude_paths.sh \
        /build/Build_Freshclam_ClamD.sh \
        /build/clamdscan.sh \
        /usr/local/bin/check_files.sh \
        /usr/local/bin/apply_exclude_paths.sh \
        /usr/local/bin/Build_Freshclam_ClamD.sh \
        /usr/local/bin/clamdscan.sh

# ============================================================
# Build-time ClamAV signature database
# ============================================================
#
# Download a complete current signature database while the image
# is being built.
#
# Runtime containers may still update this database with freshclam,
# but this build-time copy provides an offline-capable fallback.
#
# IMPORTANT:
# /var/lib/clamav may later be hidden by a host bind mount.
# Therefore the finished databases are copied to /build/clamav-db.
# The temporary build copy under /var/lib/clamav is then removed so
# the final image stores only one immutable database seed.
#
RUN set -eu; \
    echo "========================================"; \
    echo " Building ClamAV signature database"; \
    echo "========================================"; \
    \
    mkdir -p /var/lib/clamav /run/clamav /build/clamav-db; \
    chown -R clamav:clamav /var/lib/clamav /run/clamav; \
    \
    rm -f /run/clamav/freshclam.pid; \
    \
    freshclam --config-file=/etc/clamav/freshclam.conf; \
    \
    echo; \
    echo "Validating downloaded signature database..."; \
    \
    if ! { [ -f /var/lib/clamav/main.cvd ] || [ -f /var/lib/clamav/main.cld ]; }; then \
        echo "ERROR: freshclam completed but main.cvd/main.cld is missing."; \
        exit 1; \
    fi; \
    \
    if ! { [ -f /var/lib/clamav/daily.cvd ] || [ -f /var/lib/clamav/daily.cld ]; }; then \
        echo "ERROR: freshclam completed but daily.cvd/daily.cld is missing."; \
        exit 1; \
    fi; \
    \
    echo; \
    echo "Saving immutable database seed..."; \
    \
    for DB_FILE in \
        /var/lib/clamav/*.cvd \
        /var/lib/clamav/*.cld; \
    do \
        [ -f "$DB_FILE" ] || continue; \
        cp -a "$DB_FILE" /build/clamav-db/; \
    done; \
    \
    chown -R root:root /build/clamav-db; \
    chmod -R a=rX /build/clamav-db; \
    \
    echo; \
    echo "Build-time signature database:"; \
    ls -lh /build/clamav-db; \
    \
    rm -f /var/lib/clamav/*.cvd /var/lib/clamav/*.cld /var/lib/clamav/freshclam.dat

# ============================================================
# One-shot scan workflow
# ============================================================
#
# Order:
#
#   1. check_files.sh
#      - create runtime directories
#      - seed missing /etc/clamav configuration
#      - seed empty/incomplete /var/lib/clamav from /build/clamav-db
#      - preserve existing host config/database files
#      - archive previous logs
#      - enforce LOG_HISTORY_LIMIT retention
#
#   2. apply_exclude_paths.sh
#      - update only the Docker-managed ExcludePath block
#
#   3. Build_Freshclam_ClamD.sh
#      - update signatures unless SKIP_FRESHCLAM is enabled
#      - fall back to existing signatures if an online update fails
#      - start clamd and wait until it is ready
#
#   4. clamdscan.sh
#      - report scan folders and active exclusions
#      - perform scan
#      - save results
#      - exit
#
ENTRYPOINT ["/bin/sh", "-c"]

CMD ["/usr/local/bin/check_files.sh && /usr/local/bin/apply_exclude_paths.sh && /usr/local/bin/Build_Freshclam_ClamD.sh && /usr/local/bin/clamdscan.sh"]
