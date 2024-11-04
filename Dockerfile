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
    rm -rf /var/cache/apk/*

# Remove existing clamd.conf and freshclam.conf, then download the new ones we want it to use. a script will do this latere as well
RUN rm -f /etc/clamd.conf && curl -o /etc/clamd.conf https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamd.conf
RUN rm -f /etc/freshclam.conf && curl -o /etc/freshclam.conf https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/freshclam.conf

# Copy and add the script to the container
ADD https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/Build_Freshclam_ClamD.sh /usr/local/bin/Build_Freshclam_ClamD.sh
RUN chmod +x /usr/local/bin/Build_Freshclam_ClamD.sh

# Copy clamdscan script to the container
ADD https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamdscan.sh /var/lib/clamav/clamdscan.sh
RUN chmod +x /var/lib/clamav/clamdscan.sh

# Add check_files.sh script to the container
ADD https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/check_config_files.sh /usr/local/bin/check_files.sh
RUN chmod +x /usr/local/bin/check_files.sh

# Run the script at container startup to update ClamAV and set up clamd
CMD ["/bin/sh", "-c", "/usr/local/bin/check_files.sh && /usr/local/bin/Build_Freshclam_ClamD.sh && /var/lib/clamav/clamdscan.sh"]
