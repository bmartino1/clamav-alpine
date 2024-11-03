
# Use Alpine Linux as the base image
FROM alpine:latest
LABEL maintainer="Travis Quinnelly" 
LABEL maintainer_url="https://github.com/tquizzle/"
# Let maintainer keep there settings... May update if i Have to make my own docker iamge....

#step 1 in application
# Install ClamAV and other packages
RUN apk update && \
    apk add --no-cache pv ca-certificates clamav clamav-libunrar tzdata && \
    apk add --upgrade apk-tools libcurl openssl busybox && \
    rm -rf /var/cache/apk/* && \
#    freshclam -- run later in image...

#step 2 make a script taht runs in the docker to update and setup clamd 

#ENV SCANDIR=/scan
#COPY scan.sh /scan.sh
ENTRYPOINT [ "sh", "/scan.sh" ]
