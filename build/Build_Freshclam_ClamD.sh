#!/bin/ash
#From autoscan.sh - Script to update ClamAV and Setup clamd the clamdscan system

# Update ClamAV definitions
echo "Updating ClamAV..."
freshclam || {
  echo "Initial update failed. Retrying with verbose output..."
  freshclam -v || {
    echo "Failed to update ClamAV"
    exit 1
  }
}

# Updates can Break Clamd daemon...
> /var/log/clamav/clamd.log # Clear the clamd log before beginning
# scanned files are logged in clamd.log as scan progress(This is a clamd.conf setting)

# Set up directory for clamd socket
echo "Setting up clamd socket directory..."
mkdir -p /var/run/clamav
chown nobody:users /var/run/clamav
chmod 777 /var/run/clamav

# Ensure clamd daemon is running
if ! pgrep clamd > /dev/null; then
    echo "Starting clamd daemon..."
    clamd &
    sleep 60  # Increase wait time to give clamd enough time to start and create the socket
fi

# Wait for the clamd socket to be available
SOCKET="/var/run/clamav/clamd.sock"
MAX_RETRIES=6
RETRIES=0

while [ ! -S "$SOCKET" ]; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "Error: clamd socket not found after waiting. Exiting..."
        exit 1
    fi
    echo "Waiting for clamd socket to be created..."
    sleep 10
    RETRIES=$((RETRIES + 1))
done

# Check if clamd is ready to accept connections
echo "Checking if clamd is ready to accept connections..."
READY_RETRIES=0
MAX_READY_RETRIES=6
while ! clamdscan --version > /dev/null 2>&1; do
    echo "clamd might still be initializing. Checking again..."
    if [ $READY_RETRIES -ge $MAX_READY_RETRIES ]; then
        echo "Error: clamd is not ready after waiting. Exiting..."
        exit 1
    fi
    echo "Waiting for clamd to be ready..."
    sleep 10
    READY_RETRIES=$((READY_RETRIES + 1))
done

# Display the last 50 lines of clamd log before scanning to confirm clamd and settings
echo "Displaying the last few lines of clamd log:"
tail -n 45 /var/log/clamav/clamd.log
