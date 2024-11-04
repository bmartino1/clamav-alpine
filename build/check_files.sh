#Check and confirm that /etc/clamd.conf and fresclam exist. 
# Function to check if a file exists, and download it if it doesn't
check_and_download() {
  FILE_PATH=$1
  DOWNLOAD_URL=$2
  if [ ! -f "$FILE_PATH" ]; then
    echo "File $FILE_PATH not found. Downloading..."
    curl -o "$FILE_PATH" "$DOWNLOAD_URL" || {
      echo "Failed to download $FILE_PATH from $DOWNLOAD_URL"
      exit 1
    }
  else
    echo "File $FILE_PATH already exists. Skipping download."
  fi
}

# Check and download clamd.conf if not present
check_and_download "/etc/clamd.conf" "https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/clamd.conf"

# Check and download freshclam.conf if not present
check_and_download "/etc/freshclam.conf" "https://raw.githubusercontent.com/bmartino1/clamav-alpine/refs/heads/master/build/freshclam.conf"
