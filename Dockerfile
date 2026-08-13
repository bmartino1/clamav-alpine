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

# Configuration is baked into the image so runtime startup does not depend
# on downloading project files from GitHub.
COPY build/clamd.conf /etc/clamav/clamd.conf
COPY build/freshclam.conf /etc/clamav/freshclam.conf

# Preserve the tested one-shot workflow:
#   check -> freshclam/start clamd -> clamdscan -> exit
COPY build/check_files.sh /usr/local/bin/check_files.sh
COPY build/Build_Freshclam_ClamD.sh /usr/local/bin/Build_Freshclam_ClamD.sh
COPY build/clamdscan.sh /usr/local/bin/clamdscan.sh

RUN chmod 0644 \
        /etc/clamav/clamd.conf \
        /etc/clamav/freshclam.conf \
    && chmod 0755 \
        /usr/local/bin/check_files.sh \
        /usr/local/bin/Build_Freshclam_ClamD.sh \
        /usr/local/bin/clamdscan.sh \
    && mkdir -p \
        /var/lib/clamav \
        /var/log/clamav \
        /run/clamav

# Override the official image's normal long-running service behavior.
# This image performs one scan and exits when that scan is finished.
ENTRYPOINT ["/bin/sh", "-c"]
CMD ["/usr/local/bin/check_files.sh && /usr/local/bin/Build_Freshclam_ClamD.sh && /usr/local/bin/clamdscan.sh"]
