#!/bin/ash

# Set permissions for directories
echo "Setting permissions for required directories..."
chmod -R 777 /var/lib/clamav
chmod -R 777 /var/log/clamav
chmod -R 777 /etc/clamav

# Function to check if a file exists, download it if it doesn't, and set permissions
check_and_download() {
  FILE_PATH=$1
  DOWNLOAD_URL=$2
  if [ ! -f "$FILE_PATH" ]; then
    echo "File $FILE_PATH not found. Downloading..."
    curl -o "$FILE_PATH" "$DOWNLOAD_URL" || {
      echo "Failed to download $FILE_PATH from $DOWNLOAD_URL"
      exit 1
    }
    chmod 777 "$FILE_PATH"
    echo "Permissions set for $FILE_PATH"
  else
    echo "File $FILE_PATH already exists. Skipping download."
  fi
}

# Check and download clamd.conf if not present
check_and_download "/etc/clamav/clamd.conf" "https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamd.conf"

# Check and download freshclam.conf if not present
check_and_download "/etc/clamav/freshclam.conf" "https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/freshclam.conf"

# Check and download clamdscan.sh if not present
check_and_download "/var/lib/clamav/clamdscan.sh" "https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamdscan.sh"

exit 0
