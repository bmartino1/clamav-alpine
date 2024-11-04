# Use Alpine Linux as the base image
FROM alpine:latest

# Maintainer Information
# Old data build from...
#LABEL maintainer="Travis Quinnelly"
#LABEL maintainer_url="https://github.com/tquizzle/"

# Install ClamAV, curl, and other packages
RUN apk update && \
    apk add --no-cache pv ca-certificates clamav clamav-libunrar tzdata curl && \
    apk add --upgrade apk-tools libcurl openssl busybox && \
    rm -rf /var/cache/apk/* && \

# Script to check and download configuration files if not present
RUN ["/bin/sh", "-c", "if [ ! -f /etc/clamd.conf ]; then curl -o /etc/clamd.conf https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamd.conf; fi"]
RUN ["/bin/sh", "-c", "if [ ! -f /etc/freshclam.conf ]; then curl -o /etc/freshclam.conf https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/freshclam.conf; fi"]

# Copy and add the script to the container
ADD https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/Build_Freshclam_ClamD.sh /usr/local/bin/Build_Freshclam_ClamD.sh
RUN chmod +x /usr/local/bin/Build_Freshclam_ClamD.sh

# Copy clamdscan script to the container
ADD https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamdscan.sh /var/lib/clamav/clamdscan.sh
RUN chmod +x /var/lib/clamav/clamdscan.sh

# Run the script at container startup to update ClamAV and set up clamd
CMD ["/bin/sh", "-c", "/usr/local/bin/Build_Freshclam_ClamD.sh && /var/lib/clamav/clamdscan.sh"]
